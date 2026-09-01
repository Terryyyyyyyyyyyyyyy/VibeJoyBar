"""Small macOS-native vertical scrolling adapter.

The right stick uses this instead of Page Up/Page Down because Codex maps
those keys to conversation navigation.  A macro invokes one bounded gesture
per stick deflection; no repeat timer is involved.
"""

from __future__ import annotations

import logging
from collections.abc import Callable

logger = logging.getLogger(__name__)

try:  # macOS; keep imports optional so config tests run elsewhere.
    from Quartz import (
        CGEventCreateScrollWheelEvent,
        CGEventPost,
        kCGEventFlagMaskNonCoalesced,
        kCGHIDEventTap,
        kCGScrollEventUnitLine,
    )
except ImportError:  # pragma: no cover - CI/non-macOS fallback
    CGEventCreateScrollWheelEvent = None
    CGEventPost = None
    kCGEventFlagMaskNonCoalesced = 0
    kCGHIDEventTap = 0
    kCGScrollEventUnitLine = 0


def emit_scroll(
    direction: str,
    amount: int = 8,
    *,
    _create_event: Callable[..., object] | None = None,
    _post_event: Callable[..., object] | None = None,
) -> bool:
    """Post one vertical scroll event, returning whether it was emitted.

    ``amount`` is deliberately bounded by the action parser.  The injectable
    hooks make the platform side deterministic in unit tests.
    """
    if direction not in ("up", "down") or amount <= 0:
        raise ValueError("scroll direction must be up/down and amount positive")
    create = _create_event or CGEventCreateScrollWheelEvent
    post = _post_event or CGEventPost
    if create is None or post is None:
        logger.warning("native scroll is unavailable on this platform")
        return False

    delta = amount if direction == "up" else -amount
    event = create(
        None,
        kCGScrollEventUnitLine,
        1,
        delta,
    )
    # Prevent macOS from coalescing this discrete gesture with an unrelated
    # trackpad event. The event still targets the current frontmost app.
    try:
        event.setIntegerValueField_(kCGEventFlagMaskNonCoalesced, 1)
    except AttributeError:
        pass
    post(kCGHIDEventTap, event)
    return True
