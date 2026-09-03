from __future__ import annotations

import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

import vibejoy.joycon as joycon_mod
from vibejoy.actions import TapAction
from vibejoy.cli import main
from vibejoy.config import Config, GlobalConfig, MacroDef, ProfileConfig, load_config
from vibejoy.events import ButtonEvent, Direction, Side, StickEvent
from vibejoy.ipc import IPCError, call as ipc_call
from vibejoy.joycon import JoyConReader, StickCalibration
from vibejoy.mapper import Mapper
from vibejoy.runner import _start_control_server


@dataclass
class FakeKeyboard:
    events: list[tuple[str, Any]] = field(default_factory=list)

    def press(self, key: str) -> None:
        self.events.append(("press", key))

    def release(self, key: str) -> None:
        self.events.append(("release", key))

    def tap(self, key: str, duration: float = 0.02) -> None:
        self.events.append(("tap", key))

    def tap_with_modifiers(self, key: str, modifiers: tuple[str, ...], duration: float = 0.02) -> bool:
        self.events.append(("modified_tap", (key, tuple(modifiers))))
        return True

    def combo(self, keys, hold: float = 0.04) -> None:
        self.events.append(("combo", tuple(keys)))

    def type_text(self, text: str) -> None:
        self.events.append(("type", text))

    def release_all(self) -> None:
        self.events.append(("release_all", None))


@dataclass
class FakeWindow:
    queries: tuple[str, ...] = ()
    steps: int = 0

    def set_queries(self, queries) -> None:
        self.queries = tuple(queries)

    def step(self):
        self.steps += 1
        return None


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

    def get_status(self) -> dict:
        return {
            "buttons": {"right": {}},
            "analog-sticks": {"right": {"horizontal": 2048, "vertical": 2048}},
        }


def _make_config(a_action: str = "tap:enter", up_action: str = "tap:up", deadzone: float = 0.2, stick_mode: str = "4dir") -> Config:
    return Config(
        global_=GlobalConfig(deadzone=deadzone, stick_mode=stick_mode, long_press_ms=300),
        profiles={
            "right": ProfileConfig(
                buttons={"a": a_action},
                stick={"up": up_action},
            )
        },
        macros={"macro1": MacroDef(steps=("tap:a",))},
    )


# ---------- 1. Mapper reload_config tests ----------


def test_mapper_reload_config_action_switching():
    kb = FakeKeyboard()
    win = FakeWindow()
    cfg1 = _make_config(a_action="tap:enter", up_action="tap:up")
    mapper = Mapper(cfg1, kb, win)

    mapper.on_event(ButtonEvent("right", "a", pressed=True))
    assert kb.events[-1] == ("tap", "enter")

    cfg2 = _make_config(a_action="tap:space", up_action="tap:pageup")
    mapper.reload_config(cfg2)

    mapper.on_event(ButtonEvent("right", "a", pressed=True))
    assert kb.events[-1] == ("tap", "space")


def test_mapper_reload_config_releases_active_holds():
    kb = FakeKeyboard()
    win = FakeWindow()
    cfg1 = _make_config(a_action="hold:shift")
    mapper = Mapper(cfg1, kb, win)

    mapper.on_event(ButtonEvent("right", "a", pressed=True))
    assert ("press", "shift") in kb.events
    assert mapper._state.holds.get("right:btn:a") == "shift"

    cfg2 = _make_config(a_action="tap:enter")
    mapper.reload_config(cfg2)

    assert ("release_all", None) in kb.events
    assert mapper._state.holds == {}


# ---------- 2. JoyConReader deadzone & stick_mode setter tests ----------


def test_joycon_reader_properties_and_setters(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(joycon_mod, "Rumbler", FakeRumbler)
    reader = JoyConReader(FakeJoyCon(), "right", deadzone=0.2, stick_mode="4dir")

    assert reader.deadzone == 0.2
    assert reader.stick_mode == "4dir"

    reader.deadzone = 0.35
    assert reader.deadzone == 0.35

    reader.stick_mode = "8dir"
    assert reader.stick_mode == "8dir"

    # Invalid deadzones
    with pytest.raises(ValueError, match="deadzone must be in \\[0, 1\\)"):
        reader.deadzone = -0.05

    with pytest.raises(ValueError, match="deadzone must be in \\[0, 1\\)"):
        reader.deadzone = 1.0

    with pytest.raises(ValueError, match="deadzone must be in \\[0, 1\\)"):
        reader.deadzone = 1.5

    # Invalid stick modes
    with pytest.raises(ValueError, match="stick_mode must be '4dir' or '8dir'"):
        reader.stick_mode = "16dir"  # type: ignore

    with pytest.raises(ValueError, match="stick_mode must be '4dir' or '8dir'"):
        reader.stick_mode = "any"  # type: ignore


# ---------- 3. IPC Server reload command test ----------


def test_ipc_server_reload_flow(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    import json
    import socket
    from vibejoy.ipc import ControlServer

    monkeypatch.setattr(joycon_mod, "Rumbler", FakeRumbler)
    cfg_file = tmp_path / "config.toml"

    cfg_file.write_text(
        """
        [global]
        deadzone = 0.25
        stick_mode = "4dir"
        poll_hz = 100

        [profile.right.buttons]
        a = "tap:enter"

        [macro.test_macro]
        steps = ["tap:a"]
        """,
        encoding="utf-8",
    )

    kb = FakeKeyboard()
    win = FakeWindow()
    initial_config = load_config(cfg_file)
    mapper = Mapper(initial_config, kb, win)
    reader = JoyConReader(FakeJoyCon(), "right", deadzone=0.25, stick_mode="4dir")
    readers = [reader]
    stop_event = threading.Event()
    config_holder = [initial_config]

    with patch.object(ControlServer, "start"):
        server = _start_control_server(
            {},
            readers,
            stop_event,
            mapper=mapper,
            config_holder=config_holder,
        )
        assert server is not None

        # Update config on disk
        cfg_file.write_text(
            """
            [global]
            deadzone = 0.40
            stick_mode = "8dir"
            poll_hz = 100

            [profile.right.buttons]
            a = "tap:space"

            [profile.left.buttons]
            minus = "combo:cmd+z"

            [macro.new_macro]
            steps = ["tap:b"]
            """,
            encoding="utf-8",
        )

        client_sock, server_sock = socket.socketpair()
        try:
            client_sock.sendall(json.dumps({"cmd": "reload"}).encode("utf-8") + b"\n")
            server._handle_connection(server_sock)

            data = client_sock.recv(4096)
            response = json.loads(data.decode("utf-8").strip())

            assert response.get("ok") is True
            assert response.get("reloaded") is True
            assert response.get("source_path") == str(cfg_file)
            assert "right" in response.get("profiles", [])
            assert "left" in response.get("profiles", [])
            assert "new_macro" in response.get("macros", [])

            # Verify reader in-memory updates
            assert reader.deadzone == 0.40
            assert reader.stick_mode == "8dir"

            # Verify mapper in-memory updates
            mapper.on_event(ButtonEvent("right", "a", pressed=True))
            assert kb.events[-1] == ("tap", "space")

            # Verify config_holder updated
            assert config_holder[0].global_.deadzone == 0.40
        finally:
            client_sock.close()
            server_sock.close()


def test_ipc_server_reload_custom_config_path(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    import json
    import socket
    from vibejoy.ipc import ControlServer

    monkeypatch.setattr(joycon_mod, "Rumbler", FakeRumbler)
    cfg1 = tmp_path / "config1.toml"
    cfg2 = tmp_path / "config2.toml"

    cfg1.write_text(
        """
        [global]
        deadzone = 0.20
        stick_mode = "4dir"
        [profile.right.buttons]
        a = "tap:enter"
        """,
        encoding="utf-8",
    )
    cfg2.write_text(
        """
        [global]
        deadzone = 0.30
        stick_mode = "8dir"
        [profile.right.buttons]
        a = "tap:escape"
        """,
        encoding="utf-8",
    )

    kb = FakeKeyboard()
    win = FakeWindow()
    initial_config = load_config(cfg1)
    mapper = Mapper(initial_config, kb, win)
    reader = JoyConReader(FakeJoyCon(), "right", deadzone=0.20, stick_mode="4dir")
    readers = [reader]
    stop_event = threading.Event()
    config_holder = [initial_config]

    with patch.object(ControlServer, "start"):
        server = _start_control_server(
            {},
            readers,
            stop_event,
            mapper=mapper,
            config_holder=config_holder,
        )
        assert server is not None

        client_sock, server_sock = socket.socketpair()
        try:
            client_sock.sendall(json.dumps({"cmd": "reload", "config_path": str(cfg2)}).encode("utf-8") + b"\n")
            server._handle_connection(server_sock)

            data = client_sock.recv(4096)
            response = json.loads(data.decode("utf-8").strip())

            assert response.get("ok") is True
            assert response.get("source_path") == str(cfg2)
            assert reader.deadzone == 0.30
            assert reader.stick_mode == "8dir"

            mapper.on_event(ButtonEvent("right", "a", pressed=True))
            assert kb.events[-1] == ("tap", "escape")
        finally:
            client_sock.close()
            server_sock.close()


# ---------- 4. CLI vibejoy reload command tests ----------


def test_cli_reload_command_success():
    mock_reply = {
        "ok": True,
        "reloaded": True,
        "source_path": "/path/to/config.toml",
        "profiles": ["right", "left"],
        "macros": ["codex_up", "codex_down"],
    }
    with patch("vibejoy.cli.ipc_call", return_value=mock_reply) as mock_ipc:
        ret = main(["reload"])
        assert ret == 0
        mock_ipc.assert_called_once_with({"cmd": "reload"})

    with patch("vibejoy.cli.ipc_call", return_value=mock_reply) as mock_ipc:
        ret = main(["reload", "-c", "/custom/config.toml"])
        assert ret == 0
        mock_ipc.assert_called_once_with({"cmd": "reload", "config_path": "/custom/config.toml"})


def test_cli_reload_command_unreachable():
    with patch("vibejoy.cli.ipc_call", side_effect=IPCError("daemon not running")):
        ret = main(["reload"])
        assert ret == 2
