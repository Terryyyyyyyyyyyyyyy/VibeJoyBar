"""Unix-socket control channel for the running ``vibejoy run`` daemon.

Why
---
HID devices are opened exclusively.  When ``vibejoy run`` holds the
Joy-Con, a second process (``vibejoy rumble ...`` triggered from a
Claude Code hook, for example) can't open the same handle to send a
vibration.  The daemon exposes a tiny control socket that any client can
poke for side effects — rumble being the motivating use case.

Protocol
--------
Single JSON object per connection, followed by a newline.  Reply is a
single JSON object with at least ``ok: bool`` and on failure ``error``.

::

    {"cmd": "ping"}                         -> {"ok": true, "version": "..."}
    {"cmd": "status"}                       -> {"ok": true, "sides": ["right"]}
    {"cmd": "rumble",
     "pattern": "short",                    # preset or bytes spec
     "side": "right"}                       -> {"ok": true}

``side`` may be ``"left"``, ``"right"``, or ``"any"`` (default).
"""

from __future__ import annotations

import json
import logging
import os
import socket
import stat
import threading
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


DEFAULT_SOCKET_DIR = Path.home() / ".vibejoy"
DEFAULT_SOCKET_FILE = "control.sock"
CONNECT_TIMEOUT_S: float = 1.5
RECV_TIMEOUT_S: float = 2.0
MAX_MESSAGE_BYTES: int = 4096


class IPCError(RuntimeError):
    """Raised on any failure of the client/server exchange."""


def default_socket_path() -> Path:
    """Return the canonical socket path; callers may override it."""
    return DEFAULT_SOCKET_DIR / DEFAULT_SOCKET_FILE


@dataclass(frozen=True, slots=True)
class Request:
    """Parsed request payload — handlers see this, not raw bytes."""

    cmd: str
    args: dict[str, Any]


Handler = Callable[[Request], dict[str, Any]]


# ---------- Server ----------


class ControlServer:
    """Run a Unix-socket listener in a background thread.

    Usage::

        server = ControlServer(handler=dispatch)
        server.start()
        ...
        server.stop()
    """

    def __init__(
        self,
        handler: Handler,
        *,
        path: Path | None = None,
    ) -> None:
        self._handler = handler
        self._path: Path = (path or default_socket_path()).expanduser()
        self._sock: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    @property
    def path(self) -> Path:
        return self._path

    def start(self) -> None:
        if self._thread is not None:
            raise RuntimeError("ControlServer already started")
        self._path.parent.mkdir(parents=True, exist_ok=True)
        # Remove stale socket so bind() succeeds.
        if self._path.exists():
            try:
                self._path.unlink()
            except OSError as e:
                raise IPCError(f"cannot remove stale socket {self._path}: {e}") from e

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.bind(str(self._path))
            sock.listen(4)
            # Permission 0600 — only the owner can talk to the daemon.
            os.chmod(self._path, stat.S_IRUSR | stat.S_IWUSR)
            sock.settimeout(0.5)  # Wake periodically to check _stop.
        except OSError as e:
            sock.close()
            raise IPCError(f"cannot bind control socket {self._path}: {e}") from e

        self._sock = sock
        self._thread = threading.Thread(
            target=self._serve_forever, name="vibejoy-ipc", daemon=True
        )
        self._thread.start()
        logger.info("control socket listening at %s", self._path)

    def stop(self) -> None:
        self._stop.set()
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None
        if self._thread is not None and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        # Best-effort unlink.
        try:
            if self._path.exists():
                self._path.unlink()
        except OSError:
            pass

    def _serve_forever(self) -> None:
        assert self._sock is not None
        while not self._stop.is_set():
            try:
                conn, _ = self._sock.accept()
            except TimeoutError:
                continue
            except OSError:
                # Socket was closed during shutdown.
                break
            try:
                self._handle_connection(conn)
            except Exception:  # pragma: no cover — handler crashes shouldn't kill server
                logger.exception("control socket handler failed")
            finally:
                try:
                    conn.close()
                except OSError:
                    pass

    def _handle_connection(self, conn: socket.socket) -> None:
        conn.settimeout(RECV_TIMEOUT_S)
        data = _recv_message(conn)
        response: dict[str, Any]
        try:
            raw = json.loads(data.decode("utf-8"))
            if not isinstance(raw, dict) or "cmd" not in raw:
                raise ValueError("payload must be a JSON object with 'cmd'")
            cmd = str(raw["cmd"])
            args = {k: v for k, v in raw.items() if k != "cmd"}
            response = self._handler(Request(cmd=cmd, args=args))
            response.setdefault("ok", True)
        except Exception as e:
            response = {"ok": False, "error": f"{type(e).__name__}: {e}"}
        _send_message(conn, response)


# ---------- Client ----------


def call(
    payload: dict[str, Any],
    *,
    path: Path | None = None,
    connect_timeout_s: float = CONNECT_TIMEOUT_S,
) -> dict[str, Any]:
    """Send ``payload`` to the daemon and return its reply.

    Raises :class:`IPCError` if the socket is absent or the daemon
    replies with ``ok: false``.
    """
    socket_path = (path or default_socket_path()).expanduser()
    if not socket_path.exists():
        raise IPCError(f"no vibejoy daemon is running (socket {socket_path} missing)")

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(connect_timeout_s)
    try:
        try:
            sock.connect(str(socket_path))
        except OSError as e:
            raise IPCError(
                f"cannot connect to vibejoy daemon at {socket_path}: {e}"
            ) from e

        _send_message(sock, payload)
        reply_bytes = _recv_message(sock)
    finally:
        try:
            sock.close()
        except OSError:
            pass

    try:
        reply = json.loads(reply_bytes.decode("utf-8"))
    except json.JSONDecodeError as e:
        raise IPCError(f"invalid JSON from daemon: {e}") from e
    if not isinstance(reply, dict):
        raise IPCError(f"daemon reply not a JSON object: {reply!r}")
    if not reply.get("ok", False):
        raise IPCError(reply.get("error", "unknown daemon error"))
    return reply


def is_daemon_running(path: Path | None = None) -> bool:
    """Cheap probe: does the control socket exist AND respond to ``ping``?"""
    socket_path = (path or default_socket_path()).expanduser()
    if not socket_path.exists():
        return False
    try:
        call({"cmd": "ping"}, path=socket_path, connect_timeout_s=0.5)
    except IPCError:
        return False
    return True


# ---------- Wire helpers ----------


def _send_message(conn: socket.socket, payload: dict[str, Any]) -> None:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n"
    if len(data) > MAX_MESSAGE_BYTES:
        raise IPCError(f"message too large ({len(data)} bytes)")
    conn.sendall(data)


def _recv_message(conn: socket.socket) -> bytes:
    buf = bytearray()
    while True:
        chunk = conn.recv(MAX_MESSAGE_BYTES)
        if not chunk:
            break
        buf.extend(chunk)
        if b"\n" in chunk or len(buf) >= MAX_MESSAGE_BYTES:
            break
    if not buf:
        raise IPCError("connection closed without a message")
    return bytes(buf).split(b"\n", 1)[0]
