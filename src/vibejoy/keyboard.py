"""pynput-based keyboard output with a key-name resolver tuned for macOS.

Maintains an internal ``_held`` set so we never double-press a key and can
unconditionally release everything on shutdown or disconnect.

Key-name vocabulary
-------------------
- Modifiers: ``cmd``, ``shift``, ``ctrl``, ``alt``, ``fn``
  (``option`` aliases ``alt``, ``command`` aliases ``cmd``)
- Navigation: ``up``, ``down``, ``left``, ``right``, ``home``, ``end``,
  ``page_up``, ``page_down``
- Editing: ``enter``, ``return``, ``tab``, ``space``, ``backspace``,
  ``delete``, ``escape`` (alias ``esc``)
- Function: ``f1`` through ``f20``
- Media: ``media_play_pause``, ``media_volume_up``, ``media_volume_down``,
  ``media_volume_mute``, ``media_next``, ``media_previous``
- Single characters: any one-letter/digit/punct like ``a`` or ``/``

Callers pass lowercase names. Resolution is strict — unknown names raise
``UnknownKeyError`` so config validation catches typos early.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Sequence

from pynput.keyboard import Controller, Key, KeyCode

logger = logging.getLogger(__name__)


class UnknownKeyError(KeyError):
    """Raised when a key name can't be resolved to a pynput key."""


# Symbolic key table. Aliases share the same Key value.
_SYMBOLS: dict[str, Key] = {
    # Modifiers
    "cmd": Key.cmd, "command": Key.cmd,
    "shift": Key.shift,
    "ctrl": Key.ctrl, "control": Key.ctrl,
    "alt": Key.alt, "option": Key.alt, "opt": Key.alt,
    # Navigation
    "up": Key.up, "down": Key.down, "left": Key.left, "right": Key.right,
    "home": Key.home, "end": Key.end,
    "page_up": Key.page_up, "page_down": Key.page_down,
    "pageup": Key.page_up, "pagedown": Key.page_down,
    # Editing
    "enter": Key.enter, "return": Key.enter,
    "tab": Key.tab,
    "space": Key.space,
    "backspace": Key.backspace,
    "delete": Key.delete, "del": Key.delete,
    "escape": Key.esc, "esc": Key.esc,
    "caps_lock": Key.caps_lock,
    # Media
    "media_play_pause": Key.media_play_pause,
    "media_volume_up": Key.media_volume_up,
    "media_volume_down": Key.media_volume_down,
    "media_volume_mute": Key.media_volume_mute,
    "media_next": Key.media_next,
    "media_previous": Key.media_previous,
}
# Function keys
for _i in range(1, 21):
    _SYMBOLS[f"f{_i}"] = getattr(Key, f"f{_i}")


_ResolvedKey = Key | KeyCode | str


def resolve_key(name: str) -> _ResolvedKey:
    """Convert a human key name into something ``pynput.Controller`` accepts."""
    if not isinstance(name, str):
        raise UnknownKeyError(f"key name must be a string, got {type(name).__name__}")
    k = name.strip().lower()
    if not k:
        raise UnknownKeyError("empty key name")
    if k in _SYMBOLS:
        return _SYMBOLS[k]
    if len(k) == 1:
        # Single character: letter / digit / punctuation.
        return k
    raise UnknownKeyError(f"unknown key name: {name!r}")


def is_known_key(name: str) -> bool:
    """Cheap probe for config validation — True iff ``resolve_key`` would succeed."""
    try:
        resolve_key(name)
    except UnknownKeyError:
        return False
    return True


class KeyboardOutput:
    """High-level keyboard output with safe ``release_all`` cleanup.

    All methods are idempotent w.r.t. double-press: pressing an already-held
    key is a no-op; releasing a non-held key is a no-op. ``tap`` temporarily
    releases a held key so the tap doesn't corrupt the ``_held`` bookkeeping.
    """

    def __init__(self, controller: Controller | None = None) -> None:
        self._kbd = controller or Controller()
        self._held: set[_ResolvedKey] = set()

    # -- primitive operations --

    def press(self, key: str) -> None:
        resolved = resolve_key(key)
        if resolved in self._held:
            return
        self._kbd.press(resolved)
        self._held.add(resolved)
        logger.debug("press %s", key)

    def release(self, key: str) -> None:
        resolved = resolve_key(key)
        if resolved not in self._held:
            return
        self._kbd.release(resolved)
        self._held.discard(resolved)
        logger.debug("release %s", key)

    def tap(self, key: str, duration: float = 0.02) -> None:
        resolved = resolve_key(key)
        was_held = resolved in self._held
        if was_held:
            self._kbd.release(resolved)
            self._held.discard(resolved)

        self._kbd.press(resolved)
        time.sleep(duration)
        self._kbd.release(resolved)

        if was_held:
            self._kbd.press(resolved)
            self._held.add(resolved)
        logger.debug("tap %s", key)

    # -- higher-level --

    def combo(self, keys: Sequence[str], hold: float = 0.04) -> None:
        """Chord: press all, hold briefly, release in reverse order.

        Any of the requested keys currently in ``_held`` are temporarily
        released and restored afterwards so background holds stay coherent.
        """
        resolved = [resolve_key(k) for k in keys]
        restore = [r for r in resolved if r in self._held]
        for r in restore:
            self._kbd.release(r)
            self._held.discard(r)

        for r in resolved:
            self._kbd.press(r)
            time.sleep(0.008)
        time.sleep(hold)
        for r in reversed(resolved):
            self._kbd.release(r)

        for r in restore:
            self._kbd.press(r)
            self._held.add(r)
        logger.debug("combo %s", "+".join(keys))

    def type_text(self, text: str) -> None:
        """Type a literal string using pynput's ``type``."""
        self._kbd.type(text)
        logger.debug("type %r", text)

    def release_all(self) -> None:
        """Release every tracked key. Called on shutdown / disconnect."""
        for resolved in list(self._held):
            try:
                self._kbd.release(resolved)
            except Exception:  # pragma: no cover — best-effort cleanup
                logger.warning("release_all: failed to release %r", resolved, exc_info=True)
        self._held.clear()

    @property
    def held(self) -> frozenset[_ResolvedKey]:
        """Snapshot of currently-held keys. For diagnostics only."""
        return frozenset(self._held)
