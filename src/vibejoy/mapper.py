"""Translate Joy-Con events into keyboard and window actions.

The :class:`Mapper` is a small state machine.  On each :class:`Event` it
looks up the matching action in the config and either executes it
immediately (``tap`` / ``combo`` / ``window_switch``) or transitions
some tracked state (``hold`` presses a key now and releases it on
button-up; ``auto`` waits to see if a press becomes long).

Time-driven state (auto-promotion to hold, sequence repeat, stick
repeat) lives in :meth:`Mapper.poll`, which the runner calls once per
loop iteration.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from .actions import (
    Action,
    ActionParseError,
    AppSwitcherAction,
    AutoAction,
    ComboAction,
    DelayAction,
    HoldAction,
    MacroRef,
    NoAction,
    RepeatAction,
    ScrollAction,
    SequenceAction,
    ShellAction,
    TapAction,
    TypeAction,
    WindowSwitchAction,
    parse_action,
)
from .config import Config, MacroDef, ProfileConfig
from .events import ButtonEvent, Direction, Event, Side, StickEvent
from .keyboard import KeyboardOutput
from .scroll import emit_scroll
from .shell import ShellEventKind, build_context_env, get_frontmost_app, run_shell
from .window import WindowSwitcher

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class _RepeatState:
    """Tracks a repeating tap: the key + interval + timestamp of last fire."""

    key: str
    interval_s: float
    last_fire: float


@dataclass(slots=True)
class _AutoPending:
    key: str
    press_time: float


@dataclass(slots=True)
class _MapperState:
    """All mutable tracking state. Per-control keyed by stringified id."""

    # button-id -> key being held (for hold + auto-promoted + sequence modifier)
    holds: dict[str, str] = field(default_factory=dict)
    # button-id -> AutoAction waiting to decide tap/hold
    auto_pending: dict[str, _AutoPending] = field(default_factory=dict)
    # button-id -> all keys of an active sequence (so we can release them on up)
    sequence_keys: dict[str, tuple[str, ...]] = field(default_factory=dict)
    # button-id -> repeat of sequence's non-modifier keys
    sequence_repeat: dict[str, _RepeatState] = field(default_factory=dict)
    # stick-id -> repeat state for stick direction held down
    stick_repeat: dict[str, _RepeatState] = field(default_factory=dict)
    # stick-id -> held key (for 'hold:' on stick)
    stick_holds: dict[str, str] = field(default_factory=dict)
    # stick-id -> (shell_cmd, direction) currently "held" by a stick shell binding,
    # so we can fire a "released" event when the stick returns to center.
    stick_shell_held: dict[str, tuple[str, str]] = field(default_factory=dict)
    app_switcher_active: bool = False
    app_switcher_button_id: str | None = None


class Mapper:
    """Map events + config to side effects on keyboard / window / rumble."""

    def __init__(
        self,
        config: Config,
        keyboard_out: KeyboardOutput,
        window_switcher: WindowSwitcher,
    ) -> None:
        self._config = config
        self._keyboard = keyboard_out
        self._window = window_switcher
        self._state = _MapperState()
        self._long_press_s = config.global_.long_press_ms / 1000.0
        self._precompiled: dict[str, Action] = self._precompile(config)

    # ---------- Public API ----------

    def on_event(self, event: Event) -> None:
        try:
            if isinstance(event, ButtonEvent):
                self._on_button(event)
            elif isinstance(event, StickEvent):
                self._on_stick(event)
        except Exception:  # pragma: no cover — last-resort guard
            logger.exception("mapper crashed on event %r", event)

    def poll(self) -> None:
        """Drive time-based transitions. Call once per loop tick."""
        now = time.monotonic()
        self._promote_auto_holds(now)
        self._fire_sequence_repeats(now)
        self._fire_stick_repeats(now)

    def release_all(self) -> None:
        """Release every held key and clear all tracked state."""
        self._keyboard.release_all()
        self._state = _MapperState()

    # ---------- Button handling ----------

    def _on_button(self, event: ButtonEvent) -> None:
        button_id = _button_id(event.side, event.button)
        action = self._lookup_button(event.side, event.button)
        if action is None:
            return

        if event.pressed:
            self._do_press(button_id, action, event)
        else:
            self._do_release(button_id, action, event)

    def _do_press(self, button_id: str, action: Action, event: ButtonEvent) -> None:
        label = event.button
        if isinstance(action, NoAction):
            return

        if isinstance(action, TapAction):
            self._keyboard.tap(action.key)

        elif isinstance(action, HoldAction):
            self._keyboard.press(action.key)
            self._state.holds[button_id] = action.key

        elif isinstance(action, AutoAction):
            self._state.auto_pending[button_id] = _AutoPending(
                key=action.key, press_time=time.monotonic()
            )

        elif isinstance(action, ComboAction):
            self._keyboard.combo(action.keys)

        elif isinstance(action, SequenceAction):
            modifier, *rest = action.keys
            self._keyboard.press(modifier)
            for key in rest:
                self._keyboard.tap(key)
            self._state.holds[button_id] = modifier
            self._state.sequence_keys[button_id] = action.keys
            if action.repeat_ms > 0 and rest:
                self._state.sequence_repeat[button_id] = _RepeatState(
                    key="__sequence__",  # sentinel; actual keys in sequence_keys
                    interval_s=action.repeat_ms / 1000.0,
                    last_fire=time.monotonic(),
                )

        elif isinstance(action, WindowSwitchAction):
            self._window.set_queries(action.apps)
            self._window.step()

        elif isinstance(action, AppSwitcherAction):
            self._enter_app_switcher(button_id)

        elif isinstance(action, MacroRef):
            self._run_macro(
                action.name,
                context_env=self._button_context_env("macro", event),
            )

        elif isinstance(action, TypeAction):
            self._keyboard.type_text(action.text)

        elif isinstance(action, RepeatAction):
            # On a button this degenerates to an initial tap — repeat only
            # makes semantic sense on a stick direction which has a "while held"
            # notion. A button-down is instantaneous.
            self._keyboard.tap(action.key)

        elif isinstance(action, ShellAction):
            self._spawn_shell(action.cmd, "pressed", button=event.button, side=event.side)

        elif isinstance(action, DelayAction):
            logger.warning("button [%s]: 'delay:' is only meaningful inside macros", label)

    def _do_release(self, button_id: str, action: Action, event: ButtonEvent) -> None:
        # Shell actions fire on both edges so scripts can distinguish via
        # $VIBEJOY_EVENT. Handle this first so it's independent of any
        # hold / sequence bookkeeping the action may have (there isn't any,
        # but being explicit keeps future refactors honest).
        if isinstance(action, ShellAction):
            self._spawn_shell(action.cmd, "released", button=event.button, side=event.side)
            return

        if isinstance(action, AppSwitcherAction):
            self._exit_app_switcher(button_id)
            return

        # Sequence: release only the modifier (keys[1:] were tapped, not held).
        if button_id in self._state.sequence_keys:
            keys = self._state.sequence_keys.pop(button_id)
            self._state.sequence_repeat.pop(button_id, None)
            self._state.holds.pop(button_id, None)
            self._keyboard.release(keys[0])
            return

        # Hold: release the tracked key.
        if button_id in self._state.holds and not isinstance(action, AutoAction):
            key = self._state.holds.pop(button_id)
            self._keyboard.release(key)
            return

        # Auto: decide based on whether it was promoted to a hold.
        if isinstance(action, AutoAction):
            pending = self._state.auto_pending.pop(button_id, None)
            if pending is not None:
                # Never promoted → treat as a tap.
                self._keyboard.tap(pending.key)
                return
            key = self._state.holds.pop(button_id, None)
            if key is not None:
                self._keyboard.release(key)

    def _promote_auto_holds(self, now: float) -> None:
        to_promote: list[tuple[str, _AutoPending]] = []
        for button_id, pending in self._state.auto_pending.items():
            if now - pending.press_time >= self._long_press_s:
                to_promote.append((button_id, pending))
        for button_id, pending in to_promote:
            del self._state.auto_pending[button_id]
            self._keyboard.press(pending.key)
            self._state.holds[button_id] = pending.key

    def _fire_sequence_repeats(self, now: float) -> None:
        for button_id, repeat in self._state.sequence_repeat.items():
            if now - repeat.last_fire < repeat.interval_s:
                continue
            keys = self._state.sequence_keys.get(button_id)
            if not keys:
                continue
            for key in keys[1:]:
                self._keyboard.tap(key)
            repeat.last_fire = now

    # ---------- Stick handling ----------

    def _on_stick(self, event: StickEvent) -> None:
        stick_id = _stick_id(event.side)

        # While ZR is held, the right stick exclusively navigates the native
        # Cmd+Tab switcher. Ordinary right-stick mappings must not compete
        # with it, including on the center transition.
        if event.side == "right" and self._state.app_switcher_active:
            self._release_stick(stick_id, side=event.side)
            if event.direction == "right":
                self._keyboard.tap("tab")
            elif event.direction == "left":
                # Cmd is already held by ZR. Keep it down while briefly
                # adding Shift; KeyboardOutput.combo would temporarily
                # release Cmd, which would commit the switcher selection.
                self._keyboard.press("shift")
                self._keyboard.tap("tab")
                self._keyboard.release("shift")
            return

        # Always release previous stick hold/repeat/shell before considering the new direction.
        self._release_stick(stick_id, side=event.side)

        if event.direction is None:
            return

        action = self._lookup_stick(event.side, event.direction)
        if action is None:
            return

        if isinstance(action, NoAction):
            return

        if isinstance(action, TapAction):
            self._keyboard.tap(action.key)

        elif isinstance(action, HoldAction):
            self._keyboard.press(action.key)
            self._state.stick_holds[stick_id] = action.key

        elif isinstance(action, RepeatAction):
            self._keyboard.tap(action.key)
            self._state.stick_repeat[stick_id] = _RepeatState(
                key=action.key,
                interval_s=action.interval_ms / 1000.0,
                last_fire=time.monotonic(),
            )

        elif isinstance(action, ComboAction):
            self._keyboard.combo(action.keys)

        elif isinstance(action, TypeAction):
            self._keyboard.type_text(action.text)

        elif isinstance(action, WindowSwitchAction):
            self._window.set_queries(action.apps)
            self._window.step()

        elif isinstance(action, MacroRef):
            self._run_macro(
                action.name,
                context_env=self._stick_context_env("macro", event),
            )

        elif isinstance(action, ShellAction):
            self._spawn_shell(
                action.cmd,
                "pressed",
                side=event.side,
                direction=event.direction,
            )
            self._state.stick_shell_held[stick_id] = (action.cmd, event.direction)

        else:
            logger.warning(
                "stick [%s.%s]: action type %s is not supported on sticks",
                event.side,
                event.direction,
                type(action).__name__,
            )

    def _release_stick(self, stick_id: str, *, side: Side | None = None) -> None:
        key = self._state.stick_holds.pop(stick_id, None)
        if key is not None:
            self._keyboard.release(key)
        self._state.stick_repeat.pop(stick_id, None)
        held = self._state.stick_shell_held.pop(stick_id, None)
        if held is not None and side is not None:
            cmd, direction = held
            self._spawn_shell(cmd, "released", side=side, direction=direction)

    def _enter_app_switcher(self, button_id: str) -> None:
        if self._state.app_switcher_active:
            return
        # Clear any prior directional hold before taking ownership of the
        # right stick. Cmd remains held until ZR release.
        self._release_stick(_stick_id("right"), side="right")
        self._keyboard.press("cmd")
        self._keyboard.tap("tab")
        self._state.app_switcher_active = True
        self._state.app_switcher_button_id = button_id

    def _exit_app_switcher(self, button_id: str) -> None:
        if not self._state.app_switcher_active or self._state.app_switcher_button_id != button_id:
            return
        self._keyboard.release("cmd")
        self._state.app_switcher_active = False
        self._state.app_switcher_button_id = None

    def _fire_stick_repeats(self, now: float) -> None:
        for repeat in self._state.stick_repeat.values():
            if now - repeat.last_fire >= repeat.interval_s:
                self._keyboard.tap(repeat.key)
                repeat.last_fire = now

    # ---------- Macros ----------

    def _run_macro(self, name: str, *, context_env: dict[str, str]) -> None:
        macro = self._config.macros.get(name)
        if macro is None:
            logger.warning("macro %r is not defined", name)
            return
        if not _macro_guard_passes(macro):
            logger.debug("macro %r skipped (if_app guard)", name)
            return

        logger.info("executing macro %s (%d steps)", name, len(macro.steps))
        for i, step_spec in enumerate(macro.steps):
            try:
                step = parse_action(step_spec)
            except ActionParseError as e:  # pragma: no cover — caught by validate_config
                logger.error("macro %s step %d parse error: %s", name, i, e)
                return
            self._execute_macro_step(step, context_env=context_env)

    def _execute_macro_step(self, step: Action, *, context_env: dict[str, str]) -> None:
        if isinstance(step, NoAction):
            return
        if isinstance(step, TapAction):
            self._keyboard.tap(step.key)
        elif isinstance(step, HoldAction):
            self._keyboard.press(step.key)
        elif isinstance(step, ComboAction):
            self._keyboard.combo(step.keys)
        elif isinstance(step, TypeAction):
            self._keyboard.type_text(step.text)
        elif isinstance(step, DelayAction):
            time.sleep(step.ms / 1000.0)
        elif isinstance(step, ScrollAction):
            emit_scroll(step.direction, step.amount)
        elif isinstance(step, RepeatAction):
            self._keyboard.tap(step.key)
        elif isinstance(step, ShellAction):
            run_shell(step.cmd, extra_env=context_env)
        # macro / window_switch inside macros is blocked at config-validation time.

    # ---------- Shell helpers ----------

    def _spawn_shell(
        self,
        cmd: str,
        event: ShellEventKind,
        *,
        button: str | None = None,
        side: Side | None = None,
        direction: str | None = None,
    ) -> None:
        """Build the context env and fire off a shell command."""
        env = build_context_env(
            event=event,
            button=button,
            side=side,
            direction=direction,
            frontmost_app=get_frontmost_app(),
        )
        run_shell(cmd, extra_env=env)

    def _button_context_env(self, event: ShellEventKind, ev: ButtonEvent) -> dict[str, str]:
        return build_context_env(
            event=event,
            button=ev.button,
            side=ev.side,
            frontmost_app=get_frontmost_app(),
        )

    def _stick_context_env(self, event: ShellEventKind, ev: StickEvent) -> dict[str, str]:
        return build_context_env(
            event=event,
            side=ev.side,
            direction=ev.direction,
            frontmost_app=get_frontmost_app(),
        )

    # ---------- Lookup ----------

    def _lookup_button(self, side: Side, button: str) -> Action | None:
        profile = self._config.profiles.get(side)
        if profile is None:
            return None
        spec = profile.buttons.get(button)
        if spec is None:
            return None
        return self._precompiled.get(f"profile.{side}.buttons.{button}")

    def _lookup_stick(self, side: Side, direction: Direction) -> Action | None:
        profile = self._config.profiles.get(side)
        if profile is None:
            return None
        spec = profile.stick.get(direction)
        if spec is None:
            return None
        return self._precompiled.get(f"profile.{side}.stick.{direction}")

    def _precompile(self, config: Config) -> dict[str, Action]:
        """Parse every action spec once so hot-path lookup doesn't re-parse."""
        out: dict[str, Action] = {}
        for side, profile in config.profiles.items():
            for btn, spec in profile.buttons.items():
                out[f"profile.{side}.buttons.{btn}"] = parse_action(spec)
            for direction, spec in profile.stick.items():
                out[f"profile.{side}.stick.{direction}"] = parse_action(spec)
        return out


# ---------- Helpers ----------


def _button_id(side: Side, button: str) -> str:
    return f"{side}:btn:{button}"


def _stick_id(side: Side) -> str:
    return f"{side}:stick"


def _macro_guard_passes(macro: MacroDef) -> bool:
    """``if_app`` restricts macro execution to when that app is foreground."""
    if macro.if_app is None:
        return True

    try:
        from AppKit import NSWorkspace  # type: ignore[import-not-found]
    except ImportError:  # pragma: no cover — non-macOS hosts
        return False

    query = macro.if_app.strip().lower()
    try:
        frontmost = NSWorkspace.sharedWorkspace().frontmostApplication()
        if frontmost is None:
            return False
        name = (frontmost.localizedName() or "").lower()
        bundle = (frontmost.bundleIdentifier() or "").lower()
        return query in name or query in bundle
    except Exception:  # pragma: no cover
        logger.debug("if_app check failed", exc_info=True)
        return False


# Keep the unused imports referenced for type-checkers that prune them.
_ = ProfileConfig
