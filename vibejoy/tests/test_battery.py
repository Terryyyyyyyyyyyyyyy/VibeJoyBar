from __future__ import annotations

import threading
from typing import Any
from unittest.mock import patch

import pytest

import vibejoy.joycon as joycon_mod
from vibejoy.ipc import Request
from vibejoy.joycon import JoyConReader
from vibejoy.runner import _start_control_server


class MockDevice:
    def __init__(self) -> None:
        self.closed = False

    def close(self) -> None:
        self.closed = True


class MockRumbler:
    def __init__(self, device: Any, *, side_name: str) -> None:
        self.device = device

    def stop(self) -> None:
        pass

    def close(self) -> None:
        self.device.close()


class MockJoyCon:
    def __init__(self, status: dict[str, Any] | Exception | None = None) -> None:
        self._joycon_device = MockDevice()
        self.status = status if status is not None else {}

    def get_status(self) -> dict[str, Any]:
        if isinstance(self.status, Exception):
            raise self.status
        return self.status


def test_battery_mapping_levels(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(joycon_mod, "Rumbler", MockRumbler)

    # 4 -> 100%
    jc4 = MockJoyCon({"battery": {"level": 4, "charging": 0}})
    reader4 = JoyConReader(jc4, "right")
    assert reader4.get_battery() == {"level": 4, "percentage": 100, "charging": False}

    # 3 -> 75%
    jc3 = MockJoyCon({"battery": {"level": 3, "charging": 1}})
    reader3 = JoyConReader(jc3, "right")
    assert reader3.get_battery() == {"level": 3, "percentage": 75, "charging": True}

    # 2 -> 50%
    jc2 = MockJoyCon({"battery": {"level": 2, "charging": 0}})
    reader2 = JoyConReader(jc2, "left")
    assert reader2.get_battery() == {"level": 2, "percentage": 50, "charging": False}

    # 1 -> 25%
    jc1 = MockJoyCon({"battery": {"level": 1, "charging": 0}})
    reader1 = JoyConReader(jc1, "right")
    assert reader1.get_battery() == {"level": 1, "percentage": 25, "charging": False}

    # 0 -> 5%
    jc0 = MockJoyCon({"battery": {"level": 0, "charging": 0}})
    reader0 = JoyConReader(jc0, "left")
    assert reader0.get_battery() == {"level": 0, "percentage": 5, "charging": False}


def test_battery_abnormal_levels(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(joycon_mod, "Rumbler", MockRumbler)

    # level > 4 clamped to 4 -> 100%
    jc_high = MockJoyCon({"battery": {"level": 9, "charging": 1}})
    reader_high = JoyConReader(jc_high, "right")
    assert reader_high.get_battery() == {"level": 4, "percentage": 100, "charging": True}

    # level < 0 clamped to 0 -> 5%
    jc_low = MockJoyCon({"battery": {"level": -2, "charging": 0}})
    reader_low = JoyConReader(jc_low, "right")
    assert reader_low.get_battery() == {"level": 0, "percentage": 5, "charging": False}

    # None or missing battery dict
    jc_empty = MockJoyCon({})
    reader_empty = JoyConReader(jc_empty, "right")
    assert reader_empty.get_battery() == {"level": 0, "percentage": 5, "charging": False}


def test_battery_error_and_disconnected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(joycon_mod, "Rumbler", MockRumbler)

    # JoyCon raises OSError
    jc_err = MockJoyCon(OSError("device lost"))
    reader_err = JoyConReader(jc_err, "right")
    assert reader_err.get_battery() == {"level": 0, "percentage": 0, "charging": False}

    # Reader marked disconnected
    jc_ok = MockJoyCon({"battery": {"level": 4, "charging": 0}})
    reader_disc = JoyConReader(jc_ok, "left")
    reader_disc.close()
    assert reader_disc.get_battery() == {"level": 0, "percentage": 0, "charging": False}


def test_ipc_status_controllers(monkeypatch: pytest.MonkeyPatch) -> None:
    from vibejoy.ipc import ControlServer

    monkeypatch.setattr(joycon_mod, "Rumbler", MockRumbler)

    jc_right = MockJoyCon({"battery": {"level": 4, "charging": 0}})
    reader_right = JoyConReader(jc_right, "right")

    jc_left = MockJoyCon({"battery": {"level": 2, "charging": 1}})
    reader_left = JoyConReader(jc_left, "left")

    readers = [reader_right, reader_left]
    stop_event = threading.Event()

    with patch.object(ControlServer, "start"):
        server = _start_control_server({}, readers, stop_event)
        assert server is not None
        reply = server._handler(Request("status", {}))

    assert reply["sides"] == ["left", "right"]
    assert "controllers" in reply
    controllers = reply["controllers"]
    assert "right" in controllers
    assert "left" in controllers
    assert controllers["right"] == {
        "level": 4,
        "percentage": 100,
        "charging": False,
        "battery": {"level": 4, "percentage": 100, "charging": False},
    }
    assert controllers["left"] == {
        "level": 2,
        "percentage": 50,
        "charging": True,
        "battery": {"level": 2, "percentage": 50, "charging": True},
    }
