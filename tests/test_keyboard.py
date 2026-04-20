from __future__ import annotations

import pytest

from vibejoy.keyboard import UnknownKeyError, is_known_key, resolve_key


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
