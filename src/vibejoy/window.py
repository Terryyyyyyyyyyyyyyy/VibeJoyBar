"""macOS application switching via pyobjc.

Users list apps by any of:
- bundle identifier (``com.apple.Safari``)
- localized name (``Safari``, ``Visual Studio Code``)
- executable hint (``code``, ``safari``)

Matching is case-insensitive and substring-tolerant; the first running app
that matches wins. Apps that aren't running are skipped silently — users
can launch them separately.

The single entry point ``WindowSwitcher.step()`` cycles focus through the
configured app list in order, wrapping around.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

logger = logging.getLogger(__name__)

try:
    from AppKit import (  # type: ignore[import-not-found]
        NSApplicationActivateIgnoringOtherApps,
        NSWorkspace,
    )
    _HAS_APPKIT = True
except ImportError:  # pragma: no cover — always available on macOS with pyobjc
    _HAS_APPKIT = False


class WindowSwitchUnavailableError(RuntimeError):
    """Raised when the current platform can't switch windows (non-macOS or no pyobjc)."""


@dataclass(frozen=True, slots=True)
class AppInfo:
    """Lightweight snapshot of a running macOS application."""

    pid: int
    bundle_id: str
    name: str
    executable: str

    def matches(self, query: str) -> bool:
        """Case-insensitive substring match against bundle_id / name / executable."""
        q = query.strip().lower()
        if not q:
            return False
        return (
            q == self.bundle_id.lower()
            or q in self.name.lower()
            or q in self.executable.lower()
            or q in self.bundle_id.lower()
        )


def _require_appkit() -> None:
    if not _HAS_APPKIT:
        raise WindowSwitchUnavailableError(
            "AppKit (pyobjc) is unavailable — window switching only works on macOS."
        )


def list_running_apps() -> list[AppInfo]:
    """Return every app currently registered with NSWorkspace."""
    _require_appkit()
    workspace = NSWorkspace.sharedWorkspace()
    out: list[AppInfo] = []
    for app in workspace.runningApplications():
        bundle = app.bundleIdentifier() or ""
        name = app.localizedName() or ""
        # executableURL().path() may be None for some system services.
        try:
            exe_path = app.executableURL().path() if app.executableURL() else ""
        except Exception:
            exe_path = ""
        executable = exe_path.rsplit("/", 1)[-1] if exe_path else ""
        out.append(
            AppInfo(
                pid=int(app.processIdentifier()),
                bundle_id=bundle,
                name=name,
                executable=executable,
            )
        )
    return out


def find_app(query: str) -> AppInfo | None:
    """First running app matching ``query``, or None."""
    for app in list_running_apps():
        if app.matches(query):
            return app
    return None


def activate_app(app: AppInfo) -> bool:
    """Bring ``app`` to the foreground. Returns False if activation failed."""
    _require_appkit()
    workspace = NSWorkspace.sharedWorkspace()
    for running in workspace.runningApplications():
        if int(running.processIdentifier()) == app.pid:
            ok = bool(running.activateWithOptions_(NSApplicationActivateIgnoringOtherApps))
            logger.info("activate %s pid=%d -> %s", app.name, app.pid, ok)
            return ok
    logger.warning("activate_app: pid %d no longer running", app.pid)
    return False


class WindowSwitcher:
    """Cycle focus through a configured list of apps.

    State is minimal: an index into ``queries``. Each ``step()`` moves
    forward, skipping queries whose app isn't currently running.
    """

    def __init__(self, queries: list[str] | tuple[str, ...]) -> None:
        self._queries = tuple(queries)
        self._index = -1

    @property
    def queries(self) -> tuple[str, ...]:
        return self._queries

    def set_queries(self, queries: list[str] | tuple[str, ...]) -> None:
        """Replace the cycle list. Resets the cursor."""
        self._queries = tuple(queries)
        self._index = -1

    def step(self) -> AppInfo | None:
        """Advance to the next matching app and activate it."""
        if not self._queries:
            logger.debug("WindowSwitcher: no queries configured")
            return None

        apps = list_running_apps()
        # Walk forward up to len(queries) times, returning the first live match.
        for offset in range(1, len(self._queries) + 1):
            idx = (self._index + offset) % len(self._queries)
            match = _first_match(apps, self._queries[idx])
            if match is not None:
                self._index = idx
                activate_app(match)
                return match
        logger.info("WindowSwitcher: none of %s are running", self._queries)
        return None


def _first_match(apps: list[AppInfo], query: str) -> AppInfo | None:
    for a in apps:
        if a.matches(query):
            return a
    return None
