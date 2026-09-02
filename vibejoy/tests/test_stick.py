"""Pure-math helpers for stick processing."""

from __future__ import annotations

import pytest

from vibejoy.joycon import (
    StickCalibration,
    apply_circular_deadzone,
    quantize_direction,
)


class TestCircularDeadzone:
    def test_inside_is_zero(self) -> None:
        assert apply_circular_deadzone(0.1, 0.1, 0.2) == (0.0, 0.0)

    def test_outside_rescaled(self) -> None:
        x, y = apply_circular_deadzone(1.0, 0.0, 0.2)
        assert x == pytest.approx(1.0)
        assert y == 0.0

    def test_boundary_maps_to_zero(self) -> None:
        x, y = apply_circular_deadzone(0.2, 0.0, 0.2)
        assert x == pytest.approx(0.0, abs=1e-9)
        assert y == 0.0


class TestQuantizeDirection:
    def test_center_returns_none(self) -> None:
        assert quantize_direction(0.0, 0.0, "4dir") is None

    def test_4dir_cardinals(self) -> None:
        assert quantize_direction(1.0, 0.0, "4dir") == "right"
        assert quantize_direction(-1.0, 0.0, "4dir") == "left"
        assert quantize_direction(0.0, 1.0, "4dir") == "up"
        assert quantize_direction(0.0, -1.0, "4dir") == "down"

    def test_8dir_diagonals(self) -> None:
        # exactly diagonal
        assert quantize_direction(0.7, 0.7, "8dir") == "up-right"
        assert quantize_direction(-0.7, 0.7, "8dir") == "up-left"
        assert quantize_direction(0.7, -0.7, "8dir") == "down-right"
        assert quantize_direction(-0.7, -0.7, "8dir") == "down-left"


class TestStickCalibration:
    def test_normalize_preserves_physical_up_as_positive_y(self) -> None:
        cal = StickCalibration(
            baseline_x=2000, baseline_y=1800, half_range_x=1000, half_range_y=1000
        )
        nx, ny = cal.normalize(3000, 2800)  # dx=+1000, dy=+1000 (physical up)
        assert nx == pytest.approx(1.0)
        assert ny == pytest.approx(1.0)

    def test_clip_at_unit_circle(self) -> None:
        cal = StickCalibration(baseline_x=0, baseline_y=0, half_range_x=100, half_range_y=100)
        nx, ny = cal.normalize(9999, -9999)
        assert nx == 1.0
        assert ny == -1.0
