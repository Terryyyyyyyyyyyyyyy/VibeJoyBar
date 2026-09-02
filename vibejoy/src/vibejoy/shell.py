"""Fire-and-forget shell command execution for :class:`ShellAction`.

Design
------
- **Non-blocking.**  The daemon polls at 100 Hz and cannot afford to wait
  on a child process.  Every command is spawned with ``subprocess.Popen``
  in a new session and we never ``wait()`` — exit codes and output are
  the user's responsibility.
- **Inherits stdio.**  When the user runs ``vibejoy run`` in their
  terminal they see the script's output inline.  For noisy scripts,
  redirect in the command itself (``shell:my.sh >> ~/out.log 2>&1``).
- **Detached.**  ``start_new_session=True`` means a Ctrl+C on the daemon
  doesn't SIGINT the child, and long-running spawns survive daemon
  restarts (deliberate — ``say "bye"`` should finish speaking).

Context environment
-------------------
Every spawn receives the daemon's environment plus these variables:

- ``VIBEJOY_EVENT``       — ``pressed`` / ``released`` / ``macro``
- ``VIBEJOY_BUTTON``      — button name, for button triggers only
- ``VIBEJOY_SIDE``        — ``left`` / ``right``
- ``VIBEJOY_DIRECTION``   — stick direction, for stick triggers only
- ``VIBEJOY_FRONTMOST_APP`` — localized name of the foreground app
                              (``None`` when ``AppKit`` is unavailable)

Security
--------
Binding a button to ``shell:<cmd>`` is equivalent to giving the config
file shell-script privileges.  ``vibejoy`` already requires macOS
Accessibility permission (arbitrary keystrokes), so the trust boundary
is identical — treat ``config.toml`` with the same care as a dotfile
under your home directory.
"""

from __future__ import annotations

import logging
import os
import subprocess
from collections.abc import Mapping
from typing import Literal

from .events import Side

logger = logging.getLogger(__name__)


ShellEventKind = Literal["pressed", "released", "macro"]
"""Why the shell command was invoked. Scripts may inspect ``$VIBEJOY_EVENT``
to behave differently per phase."""


def build_context_env(
    *,
    event: ShellEventKind,
    button: str | None = None,
    side: Side | None = None,
    direction: str | None = None,
    frontmost_app: str | None = None,
) -> dict[str, str]:
    """Build the ``VIBEJOY_*`` env overlay for one shell invocation.

    ``None`` fields are simply omitted so scripts can detect absence
    with ``[ -z "$VIBEJOY_BUTTON" ]``.
    """
    env: dict[str, str] = {"VIBEJOY_EVENT": event}
    if button is not None:
        env["VIBEJOY_BUTTON"] = button
    if side is not None:
        env["VIBEJOY_SIDE"] = side
    if direction is not None:
        env["VIBEJOY_DIRECTION"] = direction
    if frontmost_app:
        env["VIBEJOY_FRONTMOST_APP"] = frontmost_app
    return env


def run_shell(
    cmd: str,
    *,
    extra_env: Mapping[str, str] | None = None,
    cwd: str | None = None,
    _popen: type = subprocess.Popen,  # injectable for tests
) -> subprocess.Popen[bytes] | None:
    """Spawn ``cmd`` in ``/bin/sh -c``, non-blocking.

    Returns the ``Popen`` handle on success, or ``None`` if the spawn
    failed (e.g. ``/bin/sh`` missing, which shouldn't happen on macOS).
    The daemon never awaits the child; callers should treat the return
    value as opaque bookkeeping.
    """
    if not cmd or not cmd.strip():
        logger.warning("shell: refusing to spawn empty command")
        return None

    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)

    try:
        proc = _popen(
            ["/bin/sh", "-c", cmd],
            env=env,
            cwd=cwd,
            start_new_session=True,
            # stdio inherits — user sees output in their `vibejoy run` terminal.
        )
    except OSError as e:
        logger.error("shell spawn failed for %r: %s", cmd, e)
        return None

    logger.info("shell pid=%s: %s", getattr(proc, "pid", "?"), _truncate(cmd, 80))
    return proc


def get_frontmost_app() -> str | None:
    """Return the localized name of the current foreground app.

    Returns ``None`` on non-macOS hosts or when nothing is focused.
    Uses the ``NSWorkspace`` shared singleton — cheap enough to call on
    every shell invocation.
    """
    try:
        from AppKit import NSWorkspace  # type: ignore[import-not-found]
    except ImportError:
        return None
    try:
        app = NSWorkspace.sharedWorkspace().frontmostApplication()
    except Exception:  # pragma: no cover — pyobjc bridge quirks
        return None
    if app is None:
        return None
    try:
        return app.localizedName() or None
    except Exception:  # pragma: no cover
        return None


# ---------- internal ----------


def _truncate(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"
