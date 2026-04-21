"""Action DSL — the vocabulary users (and AIs) bind to Joy-Con inputs.

Config files store every action as a single human-readable string
(e.g. ``"combo:cmd+c"``). ``parse_action`` turns that string into a
typed ``Action`` dataclass for the mapper to execute.

Grammar
-------
    none                       # no-op, explicit "do nothing"
    tap:<key>                  # press and release once
    hold:<key>                 # press on input-down, release on input-up
    repeat:<key>[@<ms>]        # tap repeatedly while input is held
    auto:<key>[@<ms>]          # short press = tap, long press (>= ms) = hold
    combo:<key1>+<key2>+...    # one-shot chord (modifier-ordered first)
    sequence:<mod>+<k1>+...[@<ms>]  # hold mod, tap rest; optional repeat
    type:<text>                # type literal text (macro use)
    delay:<ms>                 # wait N ms (macro use only)
    macro:<name>               # invoke a [macro.<name>] from config
    window_switch:<app1>,<app2>,...  # cycle focus between apps
    shell:<command>            # run shell command, non-blocking, fires on both press and release

Key names are lowercase; modifiers are ``cmd`` / ``shift`` / ``ctrl`` /
``alt`` / ``fn``. Exact list lives in ``keyboard.py``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TypeAlias


class ActionParseError(ValueError):
    """Raised when an action DSL string can't be parsed."""


# ---------- Action dataclasses ----------


@dataclass(frozen=True, slots=True)
class NoAction:
    """Explicit no-op. Useful to override an inherited mapping with nothing."""


@dataclass(frozen=True, slots=True)
class TapAction:
    key: str


@dataclass(frozen=True, slots=True)
class HoldAction:
    key: str


@dataclass(frozen=True, slots=True)
class RepeatAction:
    key: str
    interval_ms: int = 100


@dataclass(frozen=True, slots=True)
class AutoAction:
    key: str
    long_press_ms: int = 250


@dataclass(frozen=True, slots=True)
class ComboAction:
    keys: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class SequenceAction:
    """Hold first key as modifier, tap the rest once (optionally on an interval)."""

    keys: tuple[str, ...]
    repeat_ms: int = 0


@dataclass(frozen=True, slots=True)
class TypeAction:
    text: str


@dataclass(frozen=True, slots=True)
class DelayAction:
    ms: int


@dataclass(frozen=True, slots=True)
class MacroRef:
    name: str


@dataclass(frozen=True, slots=True)
class WindowSwitchAction:
    apps: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class ShellAction:
    """Run a shell command via ``/bin/sh -c``. Fires on both press and release."""

    cmd: str


Action: TypeAlias = (
    NoAction
    | TapAction
    | HoldAction
    | RepeatAction
    | AutoAction
    | ComboAction
    | SequenceAction
    | TypeAction
    | DelayAction
    | MacroRef
    | WindowSwitchAction
    | ShellAction
)


# ---------- Parser ----------


def parse_action(spec: str) -> Action:
    """Parse a DSL string into an ``Action``. Raises ``ActionParseError``."""
    if not isinstance(spec, str):
        raise ActionParseError(f"action must be a string, got {type(spec).__name__}")

    s = spec.strip()
    if not s or s.lower() == "none":
        return NoAction()

    if ":" not in s:
        raise ActionParseError(
            f"missing ':' separator in {spec!r}. Expected <verb>:<payload> (e.g. 'tap:enter')."
        )

    verb, _, payload = s.partition(":")
    verb = verb.strip().lower()
    payload = payload.strip()

    if not payload:
        raise ActionParseError(f"empty payload after ':' in {spec!r}")

    handler = _PARSERS.get(verb)
    if handler is None:
        known = ", ".join(sorted(_PARSERS))
        raise ActionParseError(f"unknown action verb {verb!r}. Known: {known}")
    return handler(payload, spec)


def _split_at(payload: str) -> tuple[str, int | None]:
    """Split 'key@500' into ('key', 500). Returns (payload, None) if no '@'."""
    if "@" not in payload:
        return payload, None
    left, _, right = payload.rpartition("@")
    try:
        ms = int(right)
    except ValueError as e:
        raise ActionParseError(f"'@{right}' is not an integer millisecond value") from e
    if ms < 0:
        raise ActionParseError(f"'@{ms}' must be non-negative")
    return left.strip(), ms


def _parse_tap(payload: str, _raw: str) -> Action:
    return TapAction(key=_clean_key(payload))


def _parse_hold(payload: str, _raw: str) -> Action:
    return HoldAction(key=_clean_key(payload))


def _parse_repeat(payload: str, _raw: str) -> Action:
    key, ms = _split_at(payload)
    return RepeatAction(key=_clean_key(key), interval_ms=ms if ms is not None else 100)


def _parse_auto(payload: str, _raw: str) -> Action:
    key, ms = _split_at(payload)
    return AutoAction(key=_clean_key(key), long_press_ms=ms if ms is not None else 250)


def _parse_combo(payload: str, _raw: str) -> Action:
    keys = _split_combo_keys(payload)
    if not keys:
        raise ActionParseError("combo requires at least one key")
    return ComboAction(keys=keys)


def _parse_sequence(payload: str, raw: str) -> Action:
    body, ms = _split_at(payload)
    keys = _split_combo_keys(body)
    if len(keys) < 2:
        raise ActionParseError(f"sequence needs at least 2 keys (modifier + tapped), got {raw!r}")
    return SequenceAction(keys=keys, repeat_ms=ms or 0)


def _parse_type(payload: str, _raw: str) -> Action:
    # Leading/trailing whitespace is trimmed in parse_action; inner kept verbatim.
    return TypeAction(text=payload)


def _parse_delay(payload: str, _raw: str) -> Action:
    try:
        ms = int(payload)
    except ValueError as e:
        raise ActionParseError(
            f"delay requires an integer millisecond value, got {payload!r}"
        ) from e
    if ms < 0:
        raise ActionParseError(f"delay must be non-negative, got {ms}")
    return DelayAction(ms=ms)


def _parse_macro(payload: str, _raw: str) -> Action:
    name = payload.strip()
    if not name:
        raise ActionParseError("macro name is empty")
    return MacroRef(name=name)


def _parse_window_switch(payload: str, _raw: str) -> Action:
    apps = tuple(a.strip() for a in payload.split(",") if a.strip())
    if not apps:
        raise ActionParseError("window_switch needs at least one app identifier")
    return WindowSwitchAction(apps=apps)


def _parse_shell(payload: str, _raw: str) -> Action:
    # Preserve internal whitespace verbatim — users may have meaningful spaces
    # inside quoted arguments. Only strip surrounding whitespace (already done
    # by parse_action before the handler is invoked).
    if not payload:
        raise ActionParseError("shell command is empty")
    return ShellAction(cmd=payload)


_PARSERS: dict[str, callable] = {
    "tap": _parse_tap,
    "hold": _parse_hold,
    "repeat": _parse_repeat,
    "auto": _parse_auto,
    "combo": _parse_combo,
    "sequence": _parse_sequence,
    "type": _parse_type,
    "delay": _parse_delay,
    "macro": _parse_macro,
    "window_switch": _parse_window_switch,
    "shell": _parse_shell,
}


def _clean_key(key: str) -> str:
    key = key.strip().lower()
    if not key:
        raise ActionParseError("empty key name")
    if "+" in key or "," in key:
        raise ActionParseError(f"key name {key!r} contains a combo separator; use 'combo:' verb")
    return key


def _split_combo_keys(payload: str) -> tuple[str, ...]:
    return tuple(_clean_key(k) for k in payload.split("+") if k.strip())
