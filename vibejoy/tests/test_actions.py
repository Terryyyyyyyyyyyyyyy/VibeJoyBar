from __future__ import annotations

import pytest

from vibejoy.actions import (
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


class TestBasicVerbs:
    def test_tap(self) -> None:
        assert parse_action("tap:enter") == TapAction(key="enter")

    def test_hold(self) -> None:
        assert parse_action("hold:shift") == HoldAction(key="shift")

    def test_type_preserves_inner_whitespace(self) -> None:
        assert parse_action("type:hello  world") == TypeAction(text="hello  world")

    def test_delay(self) -> None:
        assert parse_action("delay:150") == DelayAction(ms=150)

    def test_macro(self) -> None:
        assert parse_action("macro:claude_focus") == MacroRef(name="claude_focus")

    def test_none_variants(self) -> None:
        assert parse_action("none") == NoAction()
        assert parse_action("NONE") == NoAction()
        assert parse_action("") == NoAction()


class TestAtModifier:
    def test_repeat_default_interval(self) -> None:
        assert parse_action("repeat:down") == RepeatAction(key="down", interval_ms=100)

    def test_repeat_custom_interval(self) -> None:
        assert parse_action("repeat:down@75") == RepeatAction(key="down", interval_ms=75)

    def test_auto_default_threshold(self) -> None:
        assert parse_action("auto:f2") == AutoAction(key="f2", long_press_ms=250)

    def test_auto_custom_threshold(self) -> None:
        assert parse_action("auto:f2@500") == AutoAction(key="f2", long_press_ms=500)

    def test_scroll_defaults_to_one_bounded_gesture(self) -> None:
        assert parse_action("scroll:up") == ScrollAction(direction="up", amount=8)

    def test_scroll_custom_amount_and_direction(self) -> None:
        assert parse_action("scroll:DOWN@12") == ScrollAction(direction="down", amount=12)

    def test_scroll_rejects_invalid_amount_or_direction(self) -> None:
        with pytest.raises(ActionParseError):
            parse_action("scroll:left@8")
        with pytest.raises(ActionParseError):
            parse_action("scroll:up@0")


class TestCombo:
    def test_combo_single_key(self) -> None:
        assert parse_action("combo:space") == ComboAction(keys=("space",))

    def test_combo_multi(self) -> None:
        assert parse_action("combo:cmd+shift+p") == ComboAction(
            keys=("cmd", "shift", "p"),
        )

    def test_combo_normalizes_case(self) -> None:
        assert parse_action("combo:CMD+C") == ComboAction(keys=("cmd", "c"))


class TestSequence:
    def test_sequence_no_repeat(self) -> None:
        assert parse_action("sequence:alt+tab") == SequenceAction(
            keys=("alt", "tab"),
            repeat_ms=0,
        )

    def test_sequence_with_repeat(self) -> None:
        assert parse_action("sequence:cmd+tab@400") == SequenceAction(
            keys=("cmd", "tab"),
            repeat_ms=400,
        )

    def test_sequence_needs_two_keys(self) -> None:
        with pytest.raises(ActionParseError, match="at least 2 keys"):
            parse_action("sequence:tab")


class TestWindowSwitch:
    def test_single_app(self) -> None:
        assert parse_action("window_switch:code") == WindowSwitchAction(apps=("code",))

    def test_multiple_apps(self) -> None:
        assert parse_action("window_switch:code, chrome ,terminal") == WindowSwitchAction(
            apps=("code", "chrome", "terminal"),
        )

    def test_empty_list_rejected(self) -> None:
        with pytest.raises(ActionParseError):
            parse_action("window_switch:")


class TestAppSwitcher:
    def test_system_mode(self) -> None:
        assert parse_action("app_switcher:system") == AppSwitcherAction(mode="system")

    def test_only_system_mode_is_supported(self) -> None:
        with pytest.raises(ActionParseError):
            parse_action("app_switcher:other")


class TestShell:
    def test_simple(self) -> None:
        assert parse_action("shell:say hello") == ShellAction(cmd="say hello")

    def test_preserves_internal_spaces_and_colons(self) -> None:
        # Only first ':' is the verb separator — everything else is the command.
        assert parse_action("shell:osascript -e 'set x to 1:2'") == ShellAction(
            cmd="osascript -e 'set x to 1:2'",
        )

    def test_preserves_shell_operators(self) -> None:
        assert parse_action("shell:ls ~ | wc -l") == ShellAction(cmd="ls ~ | wc -l")

    def test_empty_rejected(self) -> None:
        with pytest.raises(ActionParseError):
            parse_action("shell:")


class TestErrors:
    def test_unknown_verb(self) -> None:
        with pytest.raises(ActionParseError, match="unknown action verb"):
            parse_action("explode:world")

    def test_missing_colon(self) -> None:
        with pytest.raises(ActionParseError, match="missing ':'"):
            parse_action("tap enter")

    def test_bad_at_ms(self) -> None:
        with pytest.raises(ActionParseError, match="integer millisecond"):
            parse_action("repeat:down@oops")

    def test_non_string_input(self) -> None:
        with pytest.raises(ActionParseError):
            parse_action(None)  # type: ignore[arg-type]
