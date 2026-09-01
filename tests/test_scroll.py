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

    assert emit_scroll("up", 8, _create_event=create, _post_event=post)
    assert created[0][-1] == 8
    assert posted == [(0, event)]  # kCGHIDEventTap is 0 on macOS


def test_emit_scroll_rejects_unbounded_values() -> None:
    with pytest.raises(ValueError):
        emit_scroll("sideways", 8, _create_event=lambda *args: None, _post_event=lambda *args: None)


class FakeEvent:
    def setIntegerValueField_(self, _field, _value) -> None:
        pass
