"""Joy-Con device reader: polls ``pyjoycon`` state and emits typed events.

Responsibilities
----------------
- Auto-calibrate the stick resting point on init (Joy-Con sticks have
  per-unit factory offset — see ``scripts/spike_joycon.py`` for why).
- Apply a circular deadzone and map the 2-D stick vector to a 4- or 8-way
  direction.
- Diff successive polls and yield only the transitions (button up/down,
  stick direction change) so callers don't see duplicate events.
- Expose the underlying HID device through a :class:`~.rumble.Rumbler`
  so the runner can drive vibration without opening a second handle.
"""

from __future__ import annotations

import logging
import math
import time
from collections.abc import Iterator
from dataclasses import dataclass, field
from typing import Literal

from pyjoycon import JoyCon, get_L_id, get_R_id

from .events import ALL_DIRECTIONS, ButtonEvent, Direction, Event, Side, StickEvent
from .rumble import Rumbler

logger = logging.getLogger(__name__)


StickMode = Literal["4dir", "8dir"]

DEFAULT_DEADZONE: float = 0.2
DEFAULT_STICK_MODE: StickMode = "4dir"
DEFAULT_STICK_RANGE: int = 1500
"""Conservative half-range (raw ADC units) used before auto-learning kicks in."""

_SNAPBACK_FRAMES: int = 2
"""Number of consecutive centered frames required to emit a 'center' event.
Prevents flicker when the stick crosses zero on fast flicks."""

_DEFAULT_CALIBRATION_SAMPLES: int = 20
_DEFAULT_CALIBRATION_INTERVAL_S: float = 0.01


@dataclass(slots=True)
class StickCalibration:
    """Center (baseline) and half-range per axis, in raw ADC units."""

    baseline_x: int
    baseline_y: int
    half_range_x: int = DEFAULT_STICK_RANGE
    half_range_y: int = DEFAULT_STICK_RANGE

    def normalize(self, raw_x: int, raw_y: int) -> tuple[float, float]:
        """Subtract baseline and scale to approximately [-1.0, 1.0]."""
        nx = (raw_x - self.baseline_x) / max(1, self.half_range_x)
        ny = (raw_y - self.baseline_y) / max(1, self.half_range_y)
        # Invert Y so up = +1 (pyjoycon reports raw ADC; higher Y raw is "up" on R-stick)
        return _clip(nx), _clip(-ny)


@dataclass
class _ReaderState:
    """Mutable per-reader state kept apart from config so ``poll()`` stays readable."""

    prev_buttons: set[str] = field(default_factory=set)
    prev_direction: Direction | None = None
    center_frames: int = 0


class JoyConReader:
    """Polls a single Joy-Con and yields :class:`Event` on state changes."""

    def __init__(
        self,
        joycon: JoyCon,
        side: Side,
        *,
        deadzone: float = DEFAULT_DEADZONE,
        stick_mode: StickMode = DEFAULT_STICK_MODE,
    ) -> None:
        if not 0.0 <= deadzone < 1.0:
            raise ValueError(f"deadzone must be in [0, 1), got {deadzone}")
        self._joycon = joycon
        self._side: Side = side
        self._deadzone = deadzone
        self._stick_mode: StickMode = stick_mode
        self._state = _ReaderState()
        self._calibration: StickCalibration | None = None
        self._rumbler = Rumbler(joycon._joycon_device, side_name=side)

    # ---------- Public API ----------

    @property
    def side(self) -> Side:
        return self._side

    @property
    def rumbler(self) -> Rumbler:
        """HID-shared rumbler so the runner can vibrate without reopening."""
        return self._rumbler

    @property
    def calibration(self) -> StickCalibration | None:
        return self._calibration

    def calibrate(
        self,
        *,
        samples: int = _DEFAULT_CALIBRATION_SAMPLES,
        interval_s: float = _DEFAULT_CALIBRATION_INTERVAL_S,
    ) -> StickCalibration:
        """Sample the stick at rest to learn its center. Call once at startup.

        Assumes the user is not touching the stick. Silently accepts any
        offset — Joy-Con factory calibration varies by unit.
        """
        sum_x = 0
        sum_y = 0
        for _ in range(samples):
            raw_x, raw_y = self._read_raw_stick()
            sum_x += raw_x
            sum_y += raw_y
            time.sleep(interval_s)

        cal = StickCalibration(
            baseline_x=sum_x // samples,
            baseline_y=sum_y // samples,
        )
        self._calibration = cal
        logger.info(
            "%s stick baseline: x=%d y=%d (half-range=%d)",
            self._side, cal.baseline_x, cal.baseline_y, cal.half_range_x,
        )
        return cal

    def poll(self) -> Iterator[Event]:
        """Read current state and yield one ``Event`` per change since last poll."""
        try:
            status = self._joycon.get_status()
        except OSError as e:
            logger.warning("%s joycon disconnected during poll: %s", self._side, e)
            return

        yield from self._diff_buttons(status)
        yield from self._diff_stick(status)

    def close(self) -> None:
        """Best-effort cleanup. Safe to call multiple times."""
        try:
            self._rumbler.stop()
        except Exception:  # pragma: no cover
            logger.debug("%s rumbler.stop failed", self._side, exc_info=True)

    # ---------- Internals ----------

    def _diff_buttons(self, status: dict) -> Iterator[ButtonEvent]:
        current = _active_buttons(status)
        pressed = current - self._state.prev_buttons
        released = self._state.prev_buttons - current

        for btn in sorted(pressed):
            yield ButtonEvent(side=self._side, button=btn, pressed=True)
        for btn in sorted(released):
            yield ButtonEvent(side=self._side, button=btn, pressed=False)

        self._state.prev_buttons = current

    def _diff_stick(self, status: dict) -> Iterator[StickEvent]:
        if self._calibration is None:
            return  # Not yet calibrated — don't emit spurious direction events.

        raw_x, raw_y = _read_stick_from_status(status, self._side)
        nx, ny = self._calibration.normalize(raw_x, raw_y)
        fx, fy = apply_circular_deadzone(nx, ny, self._deadzone)
        direction = quantize_direction(fx, fy, self._stick_mode)

        # Debounce the "centered" transition so a fast flick doesn't
        # register an extra release.
        if direction is None and self._state.prev_direction is not None:
            self._state.center_frames += 1
            if self._state.center_frames < _SNAPBACK_FRAMES:
                return
            yield StickEvent(side=self._side, direction=None)
            self._state.prev_direction = None
            self._state.center_frames = 0
            return

        if direction is not None and direction != self._state.prev_direction:
            self._state.center_frames = 0
            yield StickEvent(side=self._side, direction=direction)
            self._state.prev_direction = direction

    def _read_raw_stick(self) -> tuple[int, int]:
        status = self._joycon.get_status()
        return _read_stick_from_status(status, self._side)


# ---------- Discovery ----------


def discover_readers(
    *,
    deadzone: float = DEFAULT_DEADZONE,
    stick_mode: StickMode = DEFAULT_STICK_MODE,
) -> list[JoyConReader]:
    """Open every Joy-Con currently paired over Bluetooth and wrap as readers.

    Returns an empty list if none are found; callers decide how to react.
    """
    readers: list[JoyConReader] = []
    r_id = get_R_id()
    l_id = get_L_id()

    if r_id[0] is not None:
        try:
            joycon = JoyCon(*r_id)
            readers.append(JoyConReader(joycon, "right", deadzone=deadzone, stick_mode=stick_mode))
            logger.info("opened right Joy-Con: vid=%#06x pid=%#06x", r_id[0], r_id[1])
        except OSError as e:
            logger.error("failed to open right Joy-Con: %s", e)

    if l_id[0] is not None:
        try:
            joycon = JoyCon(*l_id)
            readers.append(JoyConReader(joycon, "left", deadzone=deadzone, stick_mode=stick_mode))
            logger.info("opened left Joy-Con: vid=%#06x pid=%#06x", l_id[0], l_id[1])
        except OSError as e:
            logger.error("failed to open left Joy-Con: %s", e)

    return readers


# ---------- Pure helpers (tested separately) ----------


def apply_circular_deadzone(x: float, y: float, deadzone: float) -> tuple[float, float]:
    """Circular deadzone — preserves analog range outside the zone.

    Inside ``deadzone`` radius → (0, 0).  Outside → linearly rescale so
    the deadzone boundary maps to 0 and the unit circle to 1.
    """
    magnitude = math.hypot(x, y)
    if magnitude < deadzone:
        return (0.0, 0.0)
    scale = min(1.0, (magnitude - deadzone) / (1.0 - deadzone))
    return (x / magnitude * scale, y / magnitude * scale)


def quantize_direction(x: float, y: float, mode: StickMode) -> Direction | None:
    """Return the quantized stick direction, or ``None`` if centered."""
    if math.hypot(x, y) < 0.1:
        return None
    angle = math.degrees(math.atan2(y, x))
    if mode == "4dir":
        return _dir_4(angle)
    return _dir_8(angle)


def _dir_4(angle: float) -> Direction:
    """Quadrant assignment: right 0°, up +90°, left 180°, down -90°."""
    if -45.0 <= angle < 45.0:
        return "right"
    if 45.0 <= angle < 135.0:
        return "up"
    if -135.0 <= angle < -45.0:
        return "down"
    return "left"


def _dir_8(angle: float) -> Direction:
    """8-way quantization with 22.5° half-sector on each cardinal direction."""
    thresholds: tuple[tuple[float, Direction], ...] = (
        (-157.5, "left"),
        (-112.5, "down-left"),
        (-67.5, "down"),
        (-22.5, "down-right"),
        (22.5, "right"),
        (67.5, "up-right"),
        (112.5, "up"),
        (157.5, "up-left"),
    )
    for boundary, direction in thresholds:
        if angle < boundary:
            return direction
    return "left"


# ---------- Status-dict extraction ----------


def _active_buttons(status: dict) -> set[str]:
    """Pull every pressed button name from a pyjoycon status dict.

    Looks in both side-specific groups and the shared group.  Button names
    are lowercased verbatim (e.g. ``'a'``, ``'r-stick'``, ``'charging-grip'``).
    """
    out: set[str] = set()
    btn_groups = status.get("buttons", {})
    for group_name in ("right", "left", "shared"):
        group = btn_groups.get(group_name) or {}
        for name, val in group.items():
            if val:
                out.add(name.lower())
    return out


def _read_stick_from_status(status: dict, side: Side) -> tuple[int, int]:
    sticks = status.get("analog-sticks") or {}
    stick = sticks.get(side) or {}
    return (
        int(stick.get("horizontal", 0) or 0),
        int(stick.get("vertical", 0) or 0),
    )


def _clip(v: float) -> float:
    if v > 1.0:
        return 1.0
    if v < -1.0:
        return -1.0
    return v


# Keep linters happy about ALL_DIRECTIONS being imported for type-checking.
_ = ALL_DIRECTIONS
