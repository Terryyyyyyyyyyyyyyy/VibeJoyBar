from __future__ import annotations

import pytest

import vibejoy.joycon as joycon_mod
import vibejoy.runner as runner_mod
from vibejoy.config import Config, GlobalConfig, ProfileConfig
from vibejoy.joycon import JoyConReader, StickCalibration


class FakeDevice:
    def __init__(self) -> None:
        self.closed = False

    def close(self) -> None:
        self.closed = True


class FakeRumbler:
    def __init__(self, device, *, side_name: str) -> None:
        self.device = device

    def stop(self) -> None:
        return None

    def close(self) -> None:
        self.device.close()


class FakeJoyCon:
    def __init__(self) -> None:
        self._joycon_device = FakeDevice()
        self.fail = True

    def get_status(self) -> dict:
        if self.fail:
            self.fail = False
            raise OSError("device asleep")
        return {
            "buttons": {"right": {"a": True}},
            "analog-sticks": {"right": {"horizontal": 0, "vertical": 0}},
        }


def test_poll_marks_disconnect_closes_hid_and_reconnect_reader_resumes(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(joycon_mod, "Rumbler", FakeRumbler)
    sleeping = FakeJoyCon()
    reader = JoyConReader(sleeping, "right")
    assert list(reader.poll()) == []
    assert not reader.is_connected
    assert sleeping._joycon_device.closed

    reconnected = FakeJoyCon()
    reconnected.fail = False
    replacement = JoyConReader(reconnected, "right")
    replacement._calibration = StickCalibration(0, 0)
    events = list(replacement.poll())
    assert replacement.is_connected
    assert any(getattr(event, "button", None) == "a" for event in events)
    replacement.close()
    assert reconnected._joycon_device.closed


class FakeReconnectReader:
    def __init__(self) -> None:
        self.side = "right"
        self.is_connected = True
        self.rumbler = object()
        self.calibrated = False
        self.closed = False

    def calibrate(self) -> None:
        self.calibrated = True

    def close(self) -> None:
        self.closed = True


class FakeMapper:
    def release_all(self) -> None:
        return None


def test_runner_rediscovery_adds_and_calibrates_missing_side(monkeypatch: pytest.MonkeyPatch) -> None:
    replacement = FakeReconnectReader()
    monkeypatch.setattr(runner_mod, "discover_readers", lambda **_: [replacement])
    config = Config(global_=GlobalConfig(), profiles={"right": ProfileConfig()}, macros={})
    readers: list[FakeReconnectReader] = []
    rumblers: dict[str, object] = {}
    runner_mod._rediscover_missing(readers, FakeMapper(), config, rumblers)  # type: ignore[arg-type]
    assert readers == [replacement]
    assert replacement.calibrated
    assert rumblers["right"] is replacement.rumbler


def test_runner_rediscovery_never_reopens_live_side(monkeypatch: pytest.MonkeyPatch) -> None:
    live = FakeReconnectReader()
    replacement = FakeReconnectReader()
    replacement.side = "left"
    calls: list[set[str]] = []

    def discover(**kwargs):
        calls.append(set(kwargs["sides"]))
        return [replacement]

    monkeypatch.setattr(runner_mod, "discover_readers", discover)
    config = Config(global_=GlobalConfig(), profiles={"right": ProfileConfig()}, macros={})
    readers = [live]
    rumblers: dict[str, object] = {"right": live.rumbler}
    runner_mod._rediscover_missing(readers, FakeMapper(), config, rumblers)  # type: ignore[arg-type]
    assert calls == [{"left"}]
    assert live.closed is False
    assert readers == [live, replacement]


class HeartbeatClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


class HeartbeatJoyCon(FakeJoyCon):
    def __init__(self) -> None:
        super().__init__()
        self._input_report = bytearray(b"\x01\x00\x00")
        self.fail = False


def test_raw_report_heartbeat_detects_sleep_without_oserror(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(joycon_mod, "Rumbler", FakeRumbler)
    clock = HeartbeatClock()
    fake = HeartbeatJoyCon()
    reader = JoyConReader(fake, "right", heartbeat_timeout_s=2.0, clock=clock)
    list(reader.poll())
    assert reader.is_connected
    clock.now = 1.9
    list(reader.poll())
    assert reader.is_connected
    clock.now = 2.1
    list(reader.poll())
    assert not reader.is_connected
    assert fake._joycon_device.closed


def test_changing_or_missing_raw_report_never_false_disconnects(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(joycon_mod, "Rumbler", FakeRumbler)
    clock = HeartbeatClock()
    changing = HeartbeatJoyCon()
    reader = JoyConReader(changing, "right", heartbeat_timeout_s=1.0, clock=clock)
    list(reader.poll())
    clock.now = 5.0
    changing._input_report[0] = 2
    list(reader.poll())
    assert reader.is_connected

    without_report = FakeJoyCon()
    without_report.fail = False
    fallback = JoyConReader(without_report, "left", heartbeat_timeout_s=1.0, clock=clock)
    clock.now = 50.0
    list(fallback.poll())
    assert fallback.is_connected
