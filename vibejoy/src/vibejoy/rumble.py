"""Joy-Con HD Rumble control.

The Joy-Con vibration actuator is driven by a 4-byte pattern per side,
sent in an HID output report with report id ``0x10``.  The 4 bytes encode
high-frequency + low-frequency tones with independent amplitudes.  See
https://github.com/dekuNukem/Nintendo_Switch_Reverse_Engineering for the
full spec.

We expose three layers:

1. :data:`PRESETS` — byte patterns for short / long / double / ok / error / click.
2. :class:`RumblePulse` — a single pulse (4 bytes + duration_ms).
3. :class:`Rumbler`      — sends one or more pulses to an open ``hid.device``.

The byte patterns are derived from published reverse-engineering tables;
fine-tuning is possible by passing custom 4- or 8-byte hex sequences.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass

import hid

logger = logging.getLogger(__name__)


# ---------- Constants ----------

NINTENDO_VID: int = 0x057E
PID_JOYCON_L: int = 0x2006
PID_JOYCON_R: int = 0x2007

REPORT_ID_RUMBLE_ONLY: int = 0x10
NEUTRAL_SIDE: bytes = b"\x00\x01\x40\x40"
"""4-byte pattern meaning 'no rumble'."""


# ---------- Data types ----------


@dataclass(frozen=True, slots=True)
class RumblePulse:
    """One pulse: 4-byte pattern per side + duration in milliseconds.

    If ``data`` is 4 bytes it applies to both actuators; if 8 bytes the
    first 4 go to the left actuator and the next 4 to the right.
    """

    data: bytes
    duration_ms: int

    def __post_init__(self) -> None:
        if len(self.data) not in (4, 8):
            raise ValueError(f"RumblePulse.data must be 4 or 8 bytes, got {len(self.data)}")
        if self.duration_ms < 0:
            raise ValueError(f"duration_ms must be >= 0, got {self.duration_ms}")

    def to_sides(self) -> tuple[bytes, bytes]:
        """Return (left_4bytes, right_4bytes)."""
        if len(self.data) == 4:
            return (self.data, self.data)
        return (self.data[:4], self.data[4:])


# Tested byte patterns from Joy-Con reverse-engineering references.  These
# are approximations — for tone-accurate rumble use the raw-bytes form.
_STRONG_CLICK = b"\xc8\xc8\x72\x04"
_MEDIUM_BUZZ = b"\xa8\xc8\x62\x04"
_LOW_BUZZ = b"\x88\xa0\x52\x04"
_HIGH_DING = b"\xc8\xe8\x72\x08"


PRESETS: dict[str, tuple[RumblePulse, ...]] = {
    "short": (RumblePulse(_STRONG_CLICK, 120),),
    "long": (RumblePulse(_MEDIUM_BUZZ, 400),),
    "click": (RumblePulse(_HIGH_DING, 40),),
    "double": (
        RumblePulse(_STRONG_CLICK, 80),
        RumblePulse(NEUTRAL_SIDE, 60),
        RumblePulse(_STRONG_CLICK, 80),
    ),
    "ok": (
        RumblePulse(_STRONG_CLICK, 60),
        RumblePulse(NEUTRAL_SIDE, 30),
        RumblePulse(_HIGH_DING, 90),
    ),
    "error": (
        RumblePulse(_LOW_BUZZ, 150),
        RumblePulse(NEUTRAL_SIDE, 70),
        RumblePulse(_LOW_BUZZ, 220),
    ),
}
"""Named rumble patterns. Each is a tuple of pulses played back-to-back."""


def preset_names() -> tuple[str, ...]:
    """Names of every bundled preset, in insertion order."""
    return tuple(PRESETS)


# ---------- Raw byte parsing ----------


def parse_bytes_spec(spec: str) -> bytes:
    """Parse a user-supplied bytes specifier.

    Accepts:
      * ``"c8c872 04"`` — 4 or 8 hex bytes, spaces/commas/0x ignored
      * ``"0xc8,0xc8,0x72,0x04"``
      * ``"200,120,114,4"`` — decimal integers (single-byte each)

    Returns 4- or 8-byte ``bytes`` suitable for ``RumblePulse.data``.
    """
    cleaned = spec.replace("0x", "").replace("0X", "").replace(",", " ").replace(":", " ")
    tokens = cleaned.split()
    if not tokens:
        raise ValueError(f"empty bytes spec: {spec!r}")

    hex_chars = set("0123456789abcdefABCDEF")

    # Single-token hex string: "c8c87204"
    if len(tokens) == 1 and all(c in hex_chars for c in tokens[0]):
        raw = tokens[0]
        if len(raw) not in (8, 16):
            raise ValueError(f"hex bytes spec must be 4 or 8 bytes (8 or 16 hex chars): {spec!r}")
        return bytes.fromhex(raw)

    # Hex-tuple path: every token is exactly two hex digits.
    if all(len(t) == 2 and all(c in hex_chars for c in t) for t in tokens):
        raw = "".join(tokens)
        if len(raw) not in (8, 16):
            raise ValueError(
                f"hex bytes spec must yield 4 or 8 bytes, got {len(raw) // 2}: {spec!r}"
            )
        return bytes.fromhex(raw)

    # Decimal path.
    values: list[int] = []
    for tok in tokens:
        try:
            values.append(int(tok, 10))
        except ValueError as e:
            raise ValueError(f"can't parse token {tok!r} in bytes spec {spec!r}") from e

    if any(v < 0 or v > 0xFF for v in values):
        raise ValueError(f"byte values must be in 0..255, got {values}")
    if len(values) not in (4, 8):
        raise ValueError(f"bytes spec must yield 4 or 8 bytes, got {len(values)}: {spec!r}")
    return bytes(values)


# ---------- Rumbler ----------


class Rumbler:
    """Sends rumble pulses to a Joy-Con over HID.

    Two ways to use it:

    A. Persistent device (daemon scenario) —
       ``Rumbler(device=my_hid_handle)``. Keeps the handle; callers own
       opening/closing.  Safe to call :meth:`play` from any thread
       (serialized by an internal lock).

    B. Ephemeral (one-shot CLI) —
       ``Rumbler.from_side('right').play(preset)``. Opens the HID device,
       plays, then closes. Uses its own HID handle so a daemon holding
       the device will make this path fail — check for a running daemon
       first and use the IPC socket in that case.
    """

    def __init__(self, device: hid.device, *, side_name: str = "?") -> None:
        self._device = device
        self._side_name = side_name
        self._packet_num = 0
        self._lock = threading.Lock()

    @classmethod
    def from_side(cls, side: str) -> Rumbler:
        """Open whichever Joy-Con ('left' / 'right') is currently connected."""
        side_norm = side.strip().lower()
        if side_norm not in ("left", "right", "l", "r"):
            raise ValueError(f"side must be 'left' or 'right', got {side!r}")
        pid = PID_JOYCON_L if side_norm.startswith("l") else PID_JOYCON_R
        devices = hid.enumerate(NINTENDO_VID, pid)
        if not devices:
            raise RuntimeError(
                f"no Joy-Con ({side_norm}) currently connected — is Bluetooth paired and active?"
            )
        dev = hid.device()
        dev.open_path(devices[0]["path"])
        return cls(dev, side_name=side_norm)

    # ---- core send ----

    def _write_rumble(self, left: bytes, right: bytes) -> None:
        """Low-level: send one 0x10 rumble-only report."""
        if len(left) != 4 or len(right) != 4:
            raise ValueError("each side needs exactly 4 bytes")
        packet = bytes([REPORT_ID_RUMBLE_ONLY, self._packet_num & 0x0F]) + left + right
        self._packet_num = (self._packet_num + 1) & 0x0F
        self._device.write(packet)

    # ---- high-level ----

    def play(self, pulses: tuple[RumblePulse, ...] | list[RumblePulse]) -> None:
        """Play a sequence of pulses, blocking until done.

        Always ends with a neutral frame so the actuator stops cleanly
        even if the last pulse was non-neutral.
        """
        if not pulses:
            return
        with self._lock:
            for pulse in pulses:
                left, right = pulse.to_sides()
                self._write_rumble(left, right)
                if pulse.duration_ms > 0:
                    time.sleep(pulse.duration_ms / 1000.0)
            # Stop frame
            self._write_rumble(NEUTRAL_SIDE, NEUTRAL_SIDE)
        logger.debug("rumble %s played %d pulses", self._side_name, len(pulses))

    def stop(self) -> None:
        """Immediately silence the actuator."""
        with self._lock:
            self._write_rumble(NEUTRAL_SIDE, NEUTRAL_SIDE)

    def close(self) -> None:
        try:
            self._device.close()
        except OSError:
            pass

    def __enter__(self) -> Rumbler:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


# ---------- Convenience ----------


def resolve_pattern(spec: str) -> tuple[RumblePulse, ...]:
    """Turn a user-supplied pattern spec into pulses.

    - Preset name (``"short"``, ``"ok"``, ...) → bundled pattern.
    - Bytes spec (parseable by :func:`parse_bytes_spec`) → single 100ms pulse.
    """
    if spec in PRESETS:
        return PRESETS[spec]
    try:
        data = parse_bytes_spec(spec)
    except ValueError as e:
        known = ", ".join(preset_names())
        raise ValueError(
            f"pattern {spec!r} is neither a known preset ({known}) nor a valid bytes spec: {e}"
        ) from e
    return (RumblePulse(data=data, duration_ms=150),)
