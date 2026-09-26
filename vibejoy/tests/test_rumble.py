from __future__ import annotations

import pytest

from vibejoy.rumble import (
    PRESETS,
    RumblePulse,
    parse_bytes_spec,
    preset_names,
    resolve_pattern,
)


class TestParseBytesSpec:
    def test_hex_string(self) -> None:
        assert parse_bytes_spec("c8c87204") == b"\xc8\xc8\x72\x04"

    def test_hex_with_spaces(self) -> None:
        assert parse_bytes_spec("c8 c8 72 04") == b"\xc8\xc8\x72\x04"

    def test_hex_with_0x_prefix(self) -> None:
        assert parse_bytes_spec("0xc8, 0xc8, 0x72, 0x04") == b"\xc8\xc8\x72\x04"

    def test_decimal_values(self) -> None:
        assert parse_bytes_spec("200, 200, 114, 4") == b"\xc8\xc8\x72\x04"

    def test_eight_bytes(self) -> None:
        out = parse_bytes_spec("c8 c8 72 04 c8 c8 72 04")
        assert len(out) == 8

    def test_rejects_wrong_count(self) -> None:
        with pytest.raises(ValueError, match="4 or 8"):
            parse_bytes_spec("c8 c8 72")

    def test_rejects_out_of_range(self) -> None:
        with pytest.raises(ValueError, match="0..255"):
            parse_bytes_spec("300, 200, 114, 4")


class TestPresets:
    @pytest.mark.parametrize("name", preset_names())
    def test_preset_is_a_tuple_of_pulses(self, name: str) -> None:
        pulses = PRESETS[name]
        assert len(pulses) >= 1
        for p in pulses:
            assert isinstance(p, RumblePulse)
            assert len(p.data) in (4, 8)


class TestResolvePattern:
    def test_preset_name(self) -> None:
        assert resolve_pattern("short") == PRESETS["short"]

    def test_raw_bytes_single_pulse(self) -> None:
        pulses = resolve_pattern("c8c87204")
        assert len(pulses) == 1
        assert pulses[0].data == b"\xc8\xc8\x72\x04"

    def test_unknown_spec(self) -> None:
        with pytest.raises(ValueError):
            resolve_pattern("explode")


class TestRumblePulseValidation:
    def test_wrong_length(self) -> None:
        with pytest.raises(ValueError, match="4 or 8 bytes"):
            RumblePulse(b"\x00\x01", duration_ms=10)

    def test_negative_duration(self) -> None:
        with pytest.raises(ValueError, match="duration_ms"):
            RumblePulse(b"\x00\x01\x40\x40", duration_ms=-1)

    def test_to_sides_four_bytes(self) -> None:
        p = RumblePulse(b"\xaa\xbb\xcc\xdd", duration_ms=10)
        left, right = p.to_sides()
        assert left == right == b"\xaa\xbb\xcc\xdd"

    def test_to_sides_eight_bytes(self) -> None:
        p = RumblePulse(b"\x01\x02\x03\x04\x05\x06\x07\x08", duration_ms=10)
        left, right = p.to_sides()
        assert left == b"\x01\x02\x03\x04"
        assert right == b"\x05\x06\x07\x08"


class TestAgentPresetsAndCLI:
    @pytest.mark.parametrize(
        "name",
        ["task_done", "task_fail", "user_attention", "voice_pulse"],
    )
    def test_agent_preset_resolution(self, name: str) -> None:
        assert name in PRESETS
        pulses = resolve_pattern(name)
        assert len(pulses) >= 1
        for pulse in pulses:
            assert isinstance(pulse, RumblePulse)
            assert len(pulse.data) in (4, 8)
            assert pulse.duration_ms > 0

    def test_cli_positional_and_hud_parsing(self) -> None:
        from vibejoy.cli import _build_parser

        parser = _build_parser()
        args = parser.parse_args(["rumble", "task_done"])
        assert args.pos_pattern == "task_done"
        assert args.hud is False

        args_hud = parser.parse_args(["rumble", "task_fail", "--hud"])
        assert args_hud.pos_pattern == "task_fail"
        assert args_hud.hud is True

        args_legacy = parser.parse_args(["rumble", "-p", "user_attention"])
        assert args_legacy.pos_pattern is None
        assert args_legacy.pattern == "user_attention"
        assert args_legacy.hud is False

    def test_cmd_rumble_with_pos_pattern(self, monkeypatch: pytest.MonkeyPatch) -> None:
        from vibejoy.cli import _build_parser, cmd_rumble

        played_pulses: list[object] = []

        class DummyRumbler:
            def __enter__(self) -> DummyRumbler:
                return self

            def __exit__(self, *args: object) -> None:
                pass

            def play(self, pulses: object) -> None:
                played_pulses.append(pulses)

        monkeypatch.setattr("vibejoy.cli.default_socket_path", lambda: pytest.MonkeyPatch())
        monkeypatch.setattr("vibejoy.rumble.Rumbler.from_side", lambda _side: DummyRumbler())

        parser = _build_parser()
        args = parser.parse_args(["rumble", "task_done", "--direct"])
        code = cmd_rumble(args)
        assert code == 0
        assert len(played_pulses) == 1
        assert played_pulses[0] == PRESETS["task_done"]
