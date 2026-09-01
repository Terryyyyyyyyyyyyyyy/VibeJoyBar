from __future__ import annotations

import pytest

from vibejoy.keyboard import KeyboardOutput, UnknownKeyError, is_known_key, resolve_key


class TestResolveKey:
    def test_single_char(self) -> None:
        assert resolve_key("a") == "a"
        assert resolve_key("5") == "5"
        assert resolve_key("/") == "/"

    def test_special_keys(self) -> None:
        from pynput.keyboard import Key

        assert resolve_key("enter") == Key.enter
        assert resolve_key("cmd") == Key.cmd
        assert resolve_key("shift") == Key.shift

    def test_aliases(self) -> None:
        from pynput.keyboard import Key

        assert resolve_key("return") == Key.enter
        assert resolve_key("option") == Key.alt
        assert resolve_key("esc") == Key.esc
        assert resolve_key("command") == Key.cmd

    def test_function_keys(self) -> None:
        from pynput.keyboard import Key

        assert resolve_key("f1") == Key.f1
        assert resolve_key("f20") == Key.f20

    def test_case_insensitive(self) -> None:
        from pynput.keyboard import Key

        assert resolve_key("ENTER") == Key.enter
        assert resolve_key("Cmd") == Key.cmd

    def test_unknown(self) -> None:
        with pytest.raises(UnknownKeyError):
            resolve_key("explode")


class TestIsKnownKey:
    def test_true_cases(self) -> None:
        assert is_known_key("enter")
        assert is_known_key("a")
        assert is_known_key("f5")

    def test_false_cases(self) -> None:
        assert not is_known_key("explode")
        assert not is_known_key("")


class _FakeController:
    def __init__(self) -> None:
        self._mapping = {}
        self.events: list[tuple[str, object]] = []

    def press(self, key: object) -> None:
        self.events.append(("press", key))

    def release(self, key: object) -> None:
        self.events.append(("release", key))


def test_option_zero_uses_native_keycode_and_modifier_flags(monkeypatch) -> None:
    import vibejoy.keyboard as keyboard_mod

    posted: list[tuple[int, bool, int]] = []
    monkeypatch.setattr(keyboard_mod, "CGEventCreateKeyboardEvent", object())
    monkeypatch.setattr(
        keyboard_mod,
        "_post_macos_key_event",
        lambda keycode, pressed, flags: posted.append((keycode, pressed, flags)) or True,
    )

    output = KeyboardOutput(controller=_FakeController())
    output.combo(("option", "0"), hold=0)

    alt_flag = keyboard_mod._MODIFIER_FLAGS[keyboard_mod.Key.alt]
    assert posted == [
        (0x3A, True, alt_flag),
        (0x1D, True, alt_flag),
        (0x1D, False, alt_flag),
        (0x3A, False, 0),
    ]


def test_flagged_tab_preserves_held_cmd_and_sets_command_flag(monkeypatch) -> None:
    import vibejoy.keyboard as keyboard_mod

    posted: list[tuple[int, bool, int]] = []
    monkeypatch.setattr(keyboard_mod, "CGEventCreateKeyboardEvent", object())
    monkeypatch.setattr(
        keyboard_mod,
        "_post_macos_key_event",
        lambda keycode, pressed, flags: posted.append((keycode, pressed, flags)) or True,
    )

    output = KeyboardOutput(controller=_FakeController())
    output.press("cmd")
    assert output.tap_with_modifiers("tab", ("cmd",), duration=0)

    command = keyboard_mod._MODIFIER_FLAGS[keyboard_mod.Key.cmd]
    assert posted == [(0x30, True, command), (0x30, False, command)]
    assert keyboard_mod.Key.cmd in output.held


def test_flagged_tab_sets_command_and_shift_flags(monkeypatch) -> None:
    import vibejoy.keyboard as keyboard_mod

    posted: list[tuple[int, bool, int]] = []
    monkeypatch.setattr(keyboard_mod, "CGEventCreateKeyboardEvent", object())
    monkeypatch.setattr(
        keyboard_mod,
        "_post_macos_key_event",
        lambda keycode, pressed, flags: posted.append((keycode, pressed, flags)) or True,
    )

    output = KeyboardOutput(controller=_FakeController())
    output.press("cmd")
    assert output.tap_with_modifiers("tab", ("cmd", "shift"), duration=0)

    expected = keyboard_mod._MODIFIER_FLAGS[keyboard_mod.Key.cmd] | keyboard_mod._MODIFIER_FLAGS[keyboard_mod.Key.shift]
    assert posted == [(0x30, True, expected), (0x30, False, expected)]
    assert keyboard_mod.Key.cmd in output.held
    assert keyboard_mod.Key.shift not in output.held


def test_flagged_tap_fallback_preserves_cmd_and_transient_shift(monkeypatch) -> None:
    import vibejoy.keyboard as keyboard_mod

    monkeypatch.setattr(keyboard_mod, "CGEventCreateKeyboardEvent", None)
    controller = _FakeController()
    output = KeyboardOutput(controller=controller)
    output.press("cmd")

    assert not output.tap_with_modifiers("tab", ("cmd", "shift"), duration=0)
    assert controller.events == [
        ("press", keyboard_mod.Key.cmd),
        ("press", keyboard_mod.Key.shift),
        ("press", keyboard_mod.Key.tab),
        ("release", keyboard_mod.Key.tab),
        ("release", keyboard_mod.Key.shift),
    ]
    assert output.held == frozenset({keyboard_mod.Key.cmd})
