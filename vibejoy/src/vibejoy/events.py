"""Input events emitted by Joy-Con readers.

Events are frozen dataclasses — cheap to compare, safe to hash, and
immutable so consumers can't accidentally mutate shared state.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, TypeAlias

Side: TypeAlias = Literal["left", "right"]
"""Which Joy-Con the event came from."""

Direction: TypeAlias = Literal[
    "up",
    "down",
    "left",
    "right",
    "up-left",
    "up-right",
    "down-left",
    "down-right",
]
"""Stick direction after deadzone + angle quantization."""

ALL_DIRECTIONS: tuple[Direction, ...] = (
    "up",
    "down",
    "left",
    "right",
    "up-left",
    "up-right",
    "down-left",
    "down-right",
)


@dataclass(frozen=True, slots=True)
class ButtonEvent:
    """A physical button transitioned between pressed and released."""

    side: Side
    button: str  # lowercase pyjoycon name: "a", "zr", "r-stick", "plus"...
    pressed: bool


@dataclass(frozen=True, slots=True)
class StickEvent:
    """The stick entered a new direction, or returned to center (direction=None)."""

    side: Side
    direction: Direction | None


Event: TypeAlias = ButtonEvent | StickEvent
