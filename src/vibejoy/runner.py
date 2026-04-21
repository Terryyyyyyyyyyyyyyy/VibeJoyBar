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
from .ipc import ControlServer, Request
from .joycon import JoyConReader, discover_readers
from .keyboard import KeyboardOutput
from .mapper import Mapper
from .rumble import Rumbler, resolve_pattern
from .window import WindowSwitcher, WindowSwitchUnavailableError

logger = logging.getLogger(__name__)


NO_CONTROLLER_EXIT_CODE: int = 2


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
    config = load_config(config_path)
    logger.info("loaded config from %s", config.source_path)

    readers = discover_readers(
        deadzone=config.global_.deadzone,
        stick_mode=config.global_.stick_mode,
    )
    if not readers:
        return RunResult(
            exit_code=NO_CONTROLLER_EXIT_CODE,
            message="no Joy-Con is currently paired/connected — run `vibejoy doctor`",
        )

    stop_event = stop_event or threading.Event()
    if install_signal_handlers:
        _install_signal_handlers(stop_event)

    keyboard_out = KeyboardOutput()
    window = WindowSwitcher(queries=())
    mapper = Mapper(config=config, keyboard_out=keyboard_out, window_switcher=window)

    rumblers_by_side: dict[Side, Rumbler] = {r.side: r.rumbler for r in readers}
    control_server = _start_control_server(rumblers_by_side, readers)

    try:
        _calibrate_all(readers)
        _print_banner(readers, config)
        _main_loop(readers, mapper, config, stop_event)
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


def _print_banner(readers: list[JoyConReader], config: Config) -> None:
    sides = ", ".join(r.side for r in readers)
    print(f"vibejoy ▶ connected: {sides}")
    print(f"         config: {config.source_path}")
    print(
        f"         poll: {config.global_.poll_hz} Hz, "
        f"deadzone: {config.global_.deadzone}, "
        f"stick: {config.global_.stick_mode}"
    )
    print("         Ctrl+C to quit.")


def _main_loop(
    readers: list[JoyConReader],
    mapper: Mapper,
    config: Config,
    stop_event: threading.Event,
) -> None:
    interval = 1.0 / max(1, config.global_.poll_hz)
    while not stop_event.is_set():
        loop_start = time.monotonic()
        for reader in readers:
            for event in reader.poll():
                mapper.on_event(event)
        mapper.poll()

        elapsed = time.monotonic() - loop_start
        remaining = interval - elapsed
        if remaining > 0:
            # Event-based wait so a stop signal wakes us immediately.
            stop_event.wait(timeout=remaining)


# ---------- IPC ----------


def _start_control_server(
    rumblers_by_side: dict[Side, Rumbler],
    readers: list[JoyConReader],
) -> ControlServer | None:
    """Install the IPC handler. Failure to bind is non-fatal."""

    def handle(request: Request) -> dict[str, Any]:
        if request.cmd == "ping":
            from . import __version__

            return {"pong": True, "version": __version__}

        if request.cmd == "status":
            return {
                "sides": sorted(r.side for r in readers),
                "calibration": {
                    r.side: None
                    if r.calibration is None
                    else {
                        "baseline_x": r.calibration.baseline_x,
                        "baseline_y": r.calibration.baseline_y,
                    }
                    for r in readers
                },
            }

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
