"""macOS application switching via pyobjc.

Users list apps by any of:
- bundle identifier (``com.apple.Safari``)
- localized name (``Safari``, ``Visual Studio Code``)
- executable hint (``code``, ``safari``)

Matching is case-insensitive and substring-tolerant, with exact bundle ID,
localized name, and executable matches preferred over substring aliases. Apps
that aren't running are skipped silently — users
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
        """Case-insensitive match against bundle id/name/executable."""
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
    """Best ranked running app matching ``query``, or None."""
    return _first_match(list_running_apps(), query)


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
        """Replace the cycle list, resetting only when the list changed.

        The mapper supplies the binding's app list on every button press. If
        an unchanged list reset the cursor each time, every press would focus
        its first live app instead of advancing through the cycle.
        """
        updated = tuple(queries)
        if updated == self._queries:
            return
        self._queries = updated
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
    q = query.strip().casefold()
    if not q:
        return None

    # Do not let NSWorkspace enumeration order decide which similarly named
    # app receives focus. Exact identifiers are the strongest user intent,
    # followed by exact display/executable names, then a conservative alias
    # for Codex (whose localized name is ChatGPT).
    def rank(app: AppInfo) -> tuple[int, int]:
        bundle = app.bundle_id.casefold()
        name = app.name.casefold()
        executable = app.executable.casefold()
        if q == bundle:
            return (0, 0)
        if q == name:
            return (1, 0)
        if q == executable:
            return (2, 0)
        if q == "codex" and bundle == "com.openai.codex":
            return (3, 0)
        if q in bundle or q in name or q in executable:
            return (4, 0)
        return (99, 0)

    matches = [(rank(app), index, app) for index, app in enumerate(apps)]
    matches = [item for item in matches if item[0][0] < 99]
    if not matches:
        return None
    _, _, result = min(matches, key=lambda item: (item[0], item[1]))
    return result
