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
