from __future__ import annotations

import pytest

from vibejoy.scroll import emit_scroll


def test_emit_scroll_posts_signed_line_delta() -> None:
    created: list[tuple[object, ...]] = []
    posted: list[tuple[object, ...]] = []
    event = FakeEvent()

    def create(*args):
        created.append(args)
        return event

    def post(*args):
        posted.append(args)

    assert emit_scroll("up", 8, _create_event=create, _post_event=post, _frontmost_pid=lambda: None)
    assert created[0][-1] == 8
    assert posted == [(0, event)]  # kCGHIDEventTap is 0 on macOS


def test_emit_scroll_targets_frontmost_pid_when_available() -> None:
    event = FakeEvent()
    targeted: list[tuple[int, object]] = []
    fallback: list[tuple[object, ...]] = []

    assert emit_scroll(
        "down",
        1,
        _create_event=lambda *args: event,
        _post_to_pid=lambda pid, value: targeted.append((pid, value)),
        _post_event=lambda *args: fallback.append(args),
        _frontmost_pid=lambda: 4242,
    )
    assert targeted == [(4242, event)]
    assert fallback == []


def test_emit_scroll_falls_back_when_foreground_pid_is_unavailable() -> None:
    event = FakeEvent()
    fallback: list[tuple[object, ...]] = []
    assert emit_scroll(
        "up",
        1,
        _create_event=lambda *args: event,
        _post_event=lambda *args: fallback.append(args),
        _post_to_pid=lambda _pid, _value: pytest.fail("PID poster should not be used"),
        _frontmost_pid=lambda: None,
    )
    assert fallback == [(0, event)]


def test_emit_scroll_rejects_unbounded_values() -> None:
    with pytest.raises(ValueError):
        emit_scroll("sideways", 8, _create_event=lambda *args: None, _post_event=lambda *args: None)


class FakeEvent:
    pass
