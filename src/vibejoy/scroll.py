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
        CGEventPostToPid,
        CGEventSetLocation,
        CGPoint,
        CGWindowListCopyWindowInfo,
        kCGHIDEventTap,
        kCGNullWindowID,
        kCGScrollEventUnitLine,
        kCGWindowListExcludeDesktopElements,
        kCGWindowListOptionOnScreenOnly,
    )
except ImportError:  # pragma: no cover - CI/non-macOS fallback
    CGEventCreateScrollWheelEvent = None
    CGEventPost = None
    CGEventPostToPid = None
    CGEventSetLocation = None
    CGPoint = None
    CGWindowListCopyWindowInfo = None
    kCGHIDEventTap = 0
    kCGNullWindowID = 0
    kCGScrollEventUnitLine = 0
    kCGWindowListExcludeDesktopElements = 0
    kCGWindowListOptionOnScreenOnly = 0


def emit_scroll(
    direction: str,
    amount: int = 8,
    *,
    _create_event: Callable[..., object] | None = None,
    _post_event: Callable[..., object] | None = None,
    _post_to_pid: Callable[[int, object], object] | None = None,
    _frontmost_pid: Callable[[], int | None] | None = None,
    _window_center: Callable[[int | None], tuple[float, float] | None] | None = None,
) -> bool:
    """Post one vertical scroll event, returning whether it was emitted.

    ``amount`` is deliberately bounded by the action parser.  The injectable
    hooks make the platform side deterministic in unit tests.
    """
    if direction not in ("up", "down") or amount <= 0:
        raise ValueError("scroll direction must be up/down and amount positive")
    create = _create_event or CGEventCreateScrollWheelEvent
    post = _post_event or CGEventPost
    if create is None or (post is None and _post_to_pid is None):
        logger.warning("native scroll is unavailable on this platform")
        return False

    delta = amount if direction == "up" else -amount
    event = create(
        None,
        kCGScrollEventUnitLine,
        1,
        delta,
    )
    pid = (_frontmost_pid or _frontmost_process_id)()

    target = (_window_center or _target_window_center)(pid)
    if target is not None and CGEventSetLocation is not None and CGPoint is not None and event is not None:
        try:
            CGEventSetLocation(event, CGPoint(target[0], target[1]))
        except Exception:
            pass

    # When running under unit tests with _post_to_pid injected, target that mock.
    # In real macOS execution, always post to kCGHIDEventTap so WindowServer delivers
    # the scroll wheel event to whatever is focused or under the cursor.
    if _post_to_pid is not None and pid and pid > 0:
        _post_to_pid(pid, event)
    elif post is not None:
        post(kCGHIDEventTap, event)
    else:
        logger.warning("cannot target native scroll: no event poster")
        return False
    return True


def _frontmost_process_id() -> int | None:
    """Return the current foreground app PID, or None off macOS."""
    try:
        from AppKit import NSWorkspace  # type: ignore[import-not-found]

        app = NSWorkspace.sharedWorkspace().frontmostApplication()
        pid = int(app.processIdentifier()) if app is not None else 0
        return pid if pid > 0 else None
    except (ImportError, AttributeError, TypeError, ValueError):
        return None


def _target_window_center(pid: int | None) -> tuple[float, float] | None:
    """Return (x, y) coordinates of the content area of the frontmost window for pid."""
    if pid is None or pid <= 0 or CGWindowListCopyWindowInfo is None:
        return None
    try:
        from AppKit import NSScreen

        main_screen = NSScreen.mainScreen()
        screen_w = float(main_screen.frame().size.width) if main_screen is not None else 1920.0
        screen_h = float(main_screen.frame().size.height) if main_screen is not None else 1080.0

        windows = CGWindowListCopyWindowInfo(
            kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
            kCGNullWindowID,
        )
        for w in (windows or []):
            if w.get("kCGWindowOwnerPID") == pid:
                b = w.get("kCGWindowBounds")
                if b and float(b.get("Width", 0)) > 150 and float(b.get("Height", 0)) > 150:
                    wx = float(b.get("X", 0))
                    wy = float(b.get("Y", 0))
                    ww = float(b.get("Width", 0))
                    wh = float(b.get("Height", 0))

                    # Intersect with the visible display boundaries so coordinates
                    # never fall off the edge of the monitor (e.g. side-docked apps like ChatGPT)
                    vis_x1 = max(0.0, wx)
                    vis_y1 = max(0.0, wy)
                    vis_x2 = min(screen_w, wx + ww)
                    vis_y2 = min(screen_h, wy + wh)

                    if vis_x2 > vis_x1 and vis_y2 > vis_y1:
                        # Target the center of the visible area horizontally, and the upper 42%
                        # vertically to land squarely in chat/document history and stay well above
                        # bottom prompt input bars or toolbars.
                        cx = vis_x1 + (vis_x2 - vis_x1) * 0.5
                        cy = vis_y1 + (vis_y2 - vis_y1) * 0.42
                        return (cx, cy)
    except Exception:
        pass
    return None
