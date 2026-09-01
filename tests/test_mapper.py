"""Mapper tests with fake keyboard / window sinks."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any

import pytest

from vibejoy.config import Config, GlobalConfig, MacroDef, ProfileConfig
from vibejoy.events import ButtonEvent, StickEvent
from vibejoy.mapper import Mapper

# ---------- Fakes ----------


@dataclass
class FakeKeyboard:
    events: list[tuple[str, Any]] = field(default_factory=list)

    def press(self, key: str) -> None:
        self.events.append(("press", key))

    def release(self, key: str) -> None:
        self.events.append(("release", key))

    def tap(self, key: str, duration: float = 0.02) -> None:
        self.events.append(("tap", key))

    def combo(self, keys, hold: float = 0.04) -> None:
        self.events.append(("combo", tuple(keys)))

    def type_text(self, text: str) -> None:
        self.events.append(("type", text))

    def release_all(self) -> None:
        self.events.append(("release_all", None))


@dataclass
class FakeWindow:
    queries: tuple[str, ...] = ()
    steps: int = 0

    def set_queries(self, queries) -> None:
        self.queries = tuple(queries)

    def step(self):
        self.steps += 1
        return None


# ---------- Fixtures ----------


def _config(
    right_buttons: dict[str, str] | None = None,
    right_stick: dict[str, str] | None = None,
    macros: dict[str, MacroDef] | None = None,
    long_press_ms: int = 250,
) -> Config:
    return Config(
        global_=GlobalConfig(long_press_ms=long_press_ms),
        profiles={
            "right": ProfileConfig(
                buttons=right_buttons or {},
                stick=right_stick or {},
            ),
        },
        macros=macros or {},
    )


@pytest.fixture
def kbd() -> FakeKeyboard:
    return FakeKeyboard()


@pytest.fixture
def win() -> FakeWindow:
    return FakeWindow()


# ---------- Tests ----------


class TestTap:
    def test_tap_on_press(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"a": "tap:enter"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="a", pressed=True))
        mapper.on_event(ButtonEvent(side="right", button="a", pressed=False))
        assert kbd.events == [("tap", "enter")]


class TestHold:
    def test_hold_presses_and_releases(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"sl": "hold:shift"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="sl", pressed=True))
        mapper.on_event(ButtonEvent(side="right", button="sl", pressed=False))
        assert kbd.events == [("press", "shift"), ("release", "shift")]


class TestCombo:
    def test_combo_fires_once(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"plus": "combo:cmd+s"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="plus", pressed=True))
        mapper.on_event(ButtonEvent(side="right", button="plus", pressed=False))
        assert kbd.events == [("combo", ("cmd", "s"))]


class TestAuto:
    def test_short_press_becomes_tap(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"x": "auto:f2"}, long_press_ms=250), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="x", pressed=True))
        mapper.poll()  # < threshold
        mapper.on_event(ButtonEvent(side="right", button="x", pressed=False))
        assert kbd.events == [("tap", "f2")]

    def test_long_press_becomes_hold(self, kbd: FakeKeyboard, win: FakeWindow, monkeypatch) -> None:
        # Use a tiny threshold so the test completes instantly.
        mapper = Mapper(_config({"x": "auto:f2"}, long_press_ms=10), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="x", pressed=True))
        time.sleep(0.02)
        mapper.poll()
        mapper.on_event(ButtonEvent(side="right", button="x", pressed=False))
        kinds = [e[0] for e in kbd.events]
        assert kinds == ["press", "release"]
        assert kbd.events[0][1] == "f2"


class TestSequence:
    def test_hold_modifier_tap_rest(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"y": "sequence:cmd+tab"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="y", pressed=True))
        mapper.on_event(ButtonEvent(side="right", button="y", pressed=False))
        assert kbd.events == [
            ("press", "cmd"),
            ("tap", "tab"),
            ("release", "cmd"),
        ]


class TestStickRepeat:
    def test_repeat_taps_on_interval(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config(right_stick={"up": "repeat:up@10"}), kbd, win)
        mapper.on_event(StickEvent(side="right", direction="up"))
        # First tap on entering direction
        assert kbd.events == [("tap", "up")]
        time.sleep(0.02)
        mapper.poll()
        assert kbd.events[-1] == ("tap", "up")

    def test_centering_stops_repeat(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config(right_stick={"up": "repeat:up@10"}), kbd, win)
        mapper.on_event(StickEvent(side="right", direction="up"))
        mapper.on_event(StickEvent(side="right", direction=None))
        time.sleep(0.02)
        before = len(kbd.events)
        mapper.poll()
        assert len(kbd.events) == before  # no more taps


class TestNativeScroll:
    def test_scroll_macro_fires_once_per_direction_entry(self, kbd: FakeKeyboard, win: FakeWindow, monkeypatch) -> None:
        calls: list[tuple[str, int]] = []
        import vibejoy.mapper as mapper_mod

        monkeypatch.setattr(mapper_mod, "emit_scroll", lambda direction, amount: calls.append((direction, amount)))
        cfg = _config(
            right_stick={"up": "macro:codex_page_up"},
            macros={"codex_page_up": MacroDef(steps=("scroll:up@8",))},
        )
        mapper = Mapper(cfg, kbd, win)
        mapper.on_event(StickEvent(side="right", direction="up"))
        mapper.on_event(StickEvent(side="right", direction=None))
        assert calls == [("up", 8)]
        assert kbd.events == []


class TestWindowSwitch:
    def test_step_called(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"r": "window_switch:code,chrome"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="r", pressed=True))
        assert win.queries == ("code", "chrome")
        assert win.steps == 1


class TestAppSwitcher:
    def test_press_release_is_quick_system_switch(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"zr": "app_switcher:system"}, right_stick={"right": "tap:right"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=True))
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=False))
        assert kbd.events == [("press", "cmd"), ("tap", "tab"), ("release", "cmd")]

    def test_right_stick_navigates_forward_while_held(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"zr": "app_switcher:system"}, right_stick={"right": "tap:right", "left": "tap:left"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=True))
        mapper.on_event(StickEvent(side="right", direction="right"))
        mapper.on_event(StickEvent(side="right", direction=None))
        assert kbd.events == [("press", "cmd"), ("tap", "tab"), ("tap", "tab")]

    def test_left_stick_navigates_backward_and_center_is_noop(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"zr": "app_switcher:system"}, right_stick={"left": "tap:left"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=True))
        mapper.on_event(StickEvent(side="right", direction="left"))
        mapper.on_event(StickEvent(side="right", direction=None))
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=False))
        assert kbd.events == [
            ("press", "cmd"),
            ("tap", "tab"),
            ("press", "shift"),
            ("tap", "tab"),
            ("release", "shift"),
            ("release", "cmd"),
        ]

    def test_disconnect_cleanup_releases_cmd(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"zr": "app_switcher:system"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=True))
        mapper.release_all()
        assert kbd.events[-1] == ("release_all", None)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=False))


class TestReleaseAll:
    def test_clears_state(self, kbd: FakeKeyboard, win: FakeWindow) -> None:
        mapper = Mapper(_config({"sl": "hold:shift"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="sl", pressed=True))
        mapper.release_all()
        assert ("release_all", None) in kbd.events
        # Subsequent release should be a no-op on the mapper side.
        mapper.on_event(ButtonEvent(side="right", button="sl", pressed=False))


# ---------- Shell dispatch ----------


class _ShellRecorder:
    """Replaces vibejoy.mapper.run_shell to capture invocations."""

    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def __call__(self, cmd, *, extra_env=None, cwd=None, _popen=None):
        self.calls.append({"cmd": cmd, "env": dict(extra_env or {})})


@pytest.fixture
def shell_recorder(monkeypatch: pytest.MonkeyPatch) -> _ShellRecorder:
    rec = _ShellRecorder()
    import vibejoy.mapper as mapper_mod

    monkeypatch.setattr(mapper_mod, "run_shell", rec)
    # Also freeze get_frontmost_app so tests are deterministic across hosts.
    monkeypatch.setattr(mapper_mod, "get_frontmost_app", lambda: "TestApp")
    return rec


class TestShellButton:
    def test_press_and_release_both_fire(
        self,
        kbd: FakeKeyboard,
        win: FakeWindow,
        shell_recorder: _ShellRecorder,
    ) -> None:
        mapper = Mapper(_config({"zr": "shell:echo hi"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=True))
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=False))

        assert len(shell_recorder.calls) == 2
        first, second = shell_recorder.calls
        assert first["cmd"] == "echo hi"
        assert first["env"]["VIBEJOY_EVENT"] == "pressed"
        assert first["env"]["VIBEJOY_BUTTON"] == "zr"
        assert first["env"]["VIBEJOY_SIDE"] == "right"
        assert first["env"]["VIBEJOY_FRONTMOST_APP"] == "TestApp"
        assert second["env"]["VIBEJOY_EVENT"] == "released"

    def test_keyboard_untouched(
        self,
        kbd: FakeKeyboard,
        win: FakeWindow,
        shell_recorder: _ShellRecorder,
    ) -> None:
        mapper = Mapper(_config({"zr": "shell:true"}), kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=True))
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=False))
        assert kbd.events == []


class TestShellStick:
    def test_enter_and_center_fire(
        self,
        kbd: FakeKeyboard,
        win: FakeWindow,
        shell_recorder: _ShellRecorder,
    ) -> None:
        mapper = Mapper(_config(right_stick={"up": "shell:echo up"}), kbd, win)
        mapper.on_event(StickEvent(side="right", direction="up"))
        mapper.on_event(StickEvent(side="right", direction=None))

        assert len(shell_recorder.calls) == 2
        assert shell_recorder.calls[0]["env"]["VIBEJOY_EVENT"] == "pressed"
        assert shell_recorder.calls[0]["env"]["VIBEJOY_DIRECTION"] == "up"
        assert shell_recorder.calls[1]["env"]["VIBEJOY_EVENT"] == "released"
        assert shell_recorder.calls[1]["env"]["VIBEJOY_DIRECTION"] == "up"

    def test_direction_change_fires_release_then_press(
        self,
        kbd: FakeKeyboard,
        win: FakeWindow,
        shell_recorder: _ShellRecorder,
    ) -> None:
        mapper = Mapper(
            _config(right_stick={"up": "shell:A", "down": "shell:B"}),
            kbd,
            win,
        )
        mapper.on_event(StickEvent(side="right", direction="up"))
        mapper.on_event(StickEvent(side="right", direction="down"))
        # Expected: A-pressed, A-released, B-pressed.
        evs = [(c["cmd"], c["env"]["VIBEJOY_EVENT"]) for c in shell_recorder.calls]
        assert evs == [("A", "pressed"), ("A", "released"), ("B", "pressed")]


class TestShellInMacro:
    def test_shell_step_runs_with_macro_event(
        self,
        kbd: FakeKeyboard,
        win: FakeWindow,
        shell_recorder: _ShellRecorder,
    ) -> None:
        cfg = _config(
            right_buttons={"zr": "macro:hello"},
            macros={"hello": MacroDef(steps=("shell:say done",))},
        )
        mapper = Mapper(cfg, kbd, win)
        mapper.on_event(ButtonEvent(side="right", button="zr", pressed=True))

        assert len(shell_recorder.calls) == 1
        assert shell_recorder.calls[0]["cmd"] == "say done"
        assert shell_recorder.calls[0]["env"]["VIBEJOY_EVENT"] == "macro"
        assert shell_recorder.calls[0]["env"]["VIBEJOY_BUTTON"] == "zr"
