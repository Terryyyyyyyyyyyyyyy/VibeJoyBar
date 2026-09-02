"""Main loop glue: Joy-Con → mapper → keyboard / window / rumble.

Run with :func:`run`, which blocks until the process is signalled or
every controller disappears.  Cleans up HID handles, releases every
held key, and tears down the IPC socket on exit.
"""

from __future__ import annotations

import logging
import signal
import threading
import time
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any

from .config import Config, load_config
from .events import Side
from .ipc import ControlServer, Request, is_daemon_running
from .joycon import JoyConReader, discover_readers
from .keyboard import KeyboardOutput
from .mapper import Mapper
from .rumble import Rumbler, resolve_pattern
from .window import WindowSwitcher, WindowSwitchUnavailableError

logger = logging.getLogger(__name__)


NO_CONTROLLER_EXIT_CODE: int = 2
ALREADY_RUNNING_EXIT_CODE: int = 3


@dataclass(frozen=True, slots=True)
class RunResult:
    """Summary of a finished :func:`run` invocation."""

    exit_code: int
    message: str


def run(
    config_path: str | None = None,
    *,
    stop_event: threading.Event | None = None,
    install_signal_handlers: bool = True,
) -> RunResult:
    """Start the daemon and block until it stops.

    ``stop_event`` lets tests / embedders request a graceful shutdown.
    If ``install_signal_handlers`` is True we hook SIGINT/SIGTERM.
    """
    if is_daemon_running():
        return RunResult(
            exit_code=ALREADY_RUNNING_EXIT_CODE,
            message="another VibeJoy daemon is already running",
        )

    config = load_config(config_path)
    logger.info("loaded config from %s", config.source_path)

    readers = discover_readers(
        deadzone=config.global_.deadzone,
        stick_mode=config.global_.stick_mode,
    )
    stop_event = stop_event or threading.Event()
    if install_signal_handlers:
        _install_signal_handlers(stop_event)

    keyboard_out = KeyboardOutput()
    window = WindowSwitcher(queries=())
    mapper = Mapper(config=config, keyboard_out=keyboard_out, window_switcher=window)

    rumblers_by_side: dict[Side, Rumbler] = {}
    control_server: ControlServer | None = None

    try:
        _calibrate_available(readers)
        rumblers_by_side.update({r.side: r.rumbler for r in readers})
        control_server = _start_control_server(rumblers_by_side, readers, stop_event, mapper=mapper)
        _print_banner(readers, config)
        _main_loop(readers, mapper, config, stop_event, rumblers_by_side=rumblers_by_side)
    except KeyboardInterrupt:
        pass
    except WindowSwitchUnavailableError as e:
        logger.warning("window switching disabled: %s", e)
    finally:
        logger.info("shutting down...")
        mapper.release_all()
        for reader in readers:
            reader.close()
        if control_server is not None:
            control_server.stop()

    return RunResult(exit_code=0, message="bye")


# ---------- Subsystems ----------


def _install_signal_handlers(stop_event: threading.Event) -> None:
    def _handler(signum: int, _frame: Any) -> None:
        logger.info("received signal %d, shutting down...", signum)
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, _handler)
        except (OSError, ValueError):
            # Not main thread or platform-unsupported — ignore.
            pass


def _calibrate_all(readers: Iterable[JoyConReader]) -> None:
    for reader in readers:
        reader.calibrate()


def _calibrate_available(readers: list[JoyConReader]) -> None:
    """Calibrate connected readers, dropping any that sleep during startup."""
    for reader in list(readers):
        try:
            reader.calibrate()
        except OSError:
            reader.close()
            readers.remove(reader)
            print(f"vibejoy ▶ disconnected: {reader.side}", flush=True)


def _print_banner(readers: list[JoyConReader], config: Config) -> None:
    sides = ", ".join(r.side for r in readers)
    print(f"vibejoy ▶ connected: {sides}" if sides else "vibejoy ▶ waiting: no Joy-Con", flush=True)
    print(f"         config: {config.source_path}", flush=True)
    print(
        f"         poll: {config.global_.poll_hz} Hz, "
        f"deadzone: {config.global_.deadzone}, "
        f"stick: {config.global_.stick_mode}",
        flush=True,
    )
    print("         Ctrl+C to quit.", flush=True)


def _main_loop(
    readers: list[JoyConReader],
    mapper: Mapper,
    config: Config,
    stop_event: threading.Event,
    *,
    rumblers_by_side: dict[Side, Rumbler] | None = None,
) -> None:
    interval = 1.0 / max(1, config.global_.poll_hz)
    rediscover_after = 0.0
    rumblers_by_side = rumblers_by_side if rumblers_by_side is not None else {}
    while not stop_event.is_set():
        loop_start = time.monotonic()
        for reader in list(readers):
            if not reader.is_connected:
                _drop_reader(reader, readers, mapper, rumblers_by_side)
                continue
            for event in reader.poll():
                mapper.on_event(event)
            if not reader.is_connected:
                _drop_reader(reader, readers, mapper, rumblers_by_side)
        mapper.poll()

        now = time.monotonic()
        if now >= rediscover_after:
            rediscover_after = now + 2.0
            _rediscover_missing(readers, mapper, config, rumblers_by_side)

        elapsed = time.monotonic() - loop_start
        remaining = interval - elapsed
        if remaining > 0:
            # Event-based wait so a stop signal wakes us immediately.
            stop_event.wait(timeout=remaining)


def _drop_reader(
    reader: JoyConReader,
    readers: list[JoyConReader],
    mapper: Mapper,
    rumblers_by_side: dict[Side, Rumbler],
) -> None:
    if reader in readers:
        readers.remove(reader)
    rumblers_by_side.pop(reader.side, None)
    mapper.release_all()
    reader.close()
    print(f"vibejoy ▶ disconnected: {reader.side}; waiting for reconnect", flush=True)


def _rediscover_missing(
    readers: list[JoyConReader],
    mapper: Mapper,
    config: Config,
    rumblers_by_side: dict[Side, Rumbler],
) -> None:
    existing = {reader.side for reader in readers if reader.is_connected}
    missing = {"right", "left"} - existing
    if not missing:
        return
    discovered = discover_readers(
        deadzone=config.global_.deadzone,
        stick_mode=config.global_.stick_mode,
        sides=missing,
    )
    for reader in discovered:
        if reader.side in existing:
            reader.close()
            continue
        try:
            reader.calibrate()
        except OSError:
            reader.close()
            continue
        readers.append(reader)
        rumblers_by_side[reader.side] = reader.rumbler
        print(f"vibejoy ▶ connected: {reader.side} (reconnected)", flush=True)


# ---------- IPC ----------


def _start_control_server(
    rumblers_by_side: dict[Side, Rumbler],
    readers: list[JoyConReader],
    stop_event: threading.Event,
    *,
    mapper: Mapper | None = None,
) -> ControlServer | None:
    """Install the IPC handler. Failure to bind is non-fatal."""

    def handle(request: Request) -> dict[str, Any]:
        if request.cmd == "ping":
            from . import __version__

            return {"pong": True, "version": __version__}

        if request.cmd == "debug":
            return {
                "readers": [
                    {
                        "side": r.side,
                        "connected": r.is_connected,
                        "calibration": {
                            "baseline_x": r.calibration.baseline_x,
                            "baseline_y": r.calibration.baseline_y,
                            "half_range_x": r.calibration.half_range_x,
                            "half_range_y": r.calibration.half_range_y,
                        }
                        if r.calibration
                        else None,
                        "raw_stick": r._read_raw_stick(),
                        "locked_direction": r._state.locked_direction,
                        "candidate_direction": r._state.candidate_direction,
                    }
                    for r in readers
                ],
                "mapper": {
                    "app_switcher_active": mapper._state.app_switcher_active if mapper else None,
                    "holds": list(mapper._state.holds.keys()) if mapper else [],
                    "stick_holds": list(mapper._state.stick_holds.keys()) if mapper else [],
                    "stick_repeat": list(mapper._state.stick_repeat.keys()) if mapper else [],
                    "stick_macro_repeat": list(mapper._state.stick_macro_repeat.keys()) if mapper else [],
                },
            }

        if request.cmd == "status":
            live_readers = [r for r in readers if r.is_connected]
            return {
                "sides": sorted(r.side for r in live_readers),
                "calibration": {
                    r.side: None
                    if r.calibration is None or not r.is_connected
                    else {
                        "baseline_x": r.calibration.baseline_x,
                        "baseline_y": r.calibration.baseline_y,
                    }
                    for r in readers
                },
                "heartbeat_age": {r.side: r.heartbeat_age for r in live_readers},
            }

        if request.cmd == "stop":
            stop_event.set()
            return {"stopping": True}

        if request.cmd == "rumble":
            pattern_spec = str(request.args.get("pattern") or "short")
            side_req = str(request.args.get("side") or "any").lower()
            pulses = resolve_pattern(pattern_spec)
            targets = _resolve_rumble_targets(rumblers_by_side, side_req)
            if not targets:
                raise RuntimeError(f"no rumbler available for side={side_req!r}")
            for rumbler in targets:
                rumbler.play(pulses)
            return {
                "pattern": pattern_spec,
                "sides": sorted(t_side for t_side, _ in rumblers_by_side.items() if _ in targets),
            }

        raise ValueError(f"unknown command: {request.cmd!r}")

    server = ControlServer(handler=handle)
    try:
        server.start()
    except Exception as e:  # pragma: no cover — best-effort
        logger.warning("control socket unavailable: %s", e)
        return None
    return server


def _resolve_rumble_targets(
    rumblers_by_side: dict[Side, Rumbler],
    side: str,
) -> list[Rumbler]:
    if side in ("any", "all", ""):
        return list(rumblers_by_side.values())
    if side in ("left", "l"):
        r = rumblers_by_side.get("left")
        return [r] if r else []
    if side in ("right", "r"):
        r = rumblers_by_side.get("right")
        return [r] if r else []
    raise ValueError(f"side must be 'left', 'right', or 'any', got {side!r}")
