"""Config loading, validation, and path resolution.

Config is a plain TOML file (Python 3.11+ ``tomllib`` reads it, no deps).
Every action is stored as a DSL string so humans and AIs can edit the
file directly without learning a nested-dict schema.

Path resolution (in order)
--------------------------
1. explicit ``--config PATH`` argument
2. ``$VIBEJOY_CONFIG`` environment variable
3. ``./config.toml`` in the current directory
4. ``$XDG_CONFIG_HOME/vibejoy/config.toml``
   (default ``~/.config/vibejoy/config.toml``)

Validation
----------
:func:`load_config` raises :class:`ConfigError` if the file is missing,
malformed TOML, fails schema checks, or contains an unparseable action
spec. Unknown fields are flagged — we prefer strict over lenient so AIs
get immediate feedback on typos.
"""

from __future__ import annotations

import os
import re
import tomllib
from dataclasses import dataclass, field
from datetime import datetime
from importlib import resources
from pathlib import Path
from typing import Any, Literal

from .actions import (
    Action,
    ActionParseError,
    AppSwitcherAction,
    MacroRef,
    WindowSwitchAction,
    parse_action,
)
from .events import ALL_DIRECTIONS, Side
from .keyboard import is_known_key

StickMode = Literal["4dir", "8dir"]


DEFAULT_CONFIG_FILENAME = "config.toml"
ENV_CONFIG_PATH = "VIBEJOY_CONFIG"
EXAMPLE_CONFIG_RESOURCE = "config.example.toml"
DEFAULT_PROFILES_DIR_NAME = "profiles"
DEFAULT_PROFILE_FILENAME = "default.toml"
ACTIVE_PROFILE_FILENAME = "active_profile"
DEFAULT_BACKUPS_DIR_NAME = "backups"
DEFAULT_PROFILE_RESOURCE = "profiles/default.toml"


class ConfigError(ValueError):
    """Raised when a config file can't be loaded or fails validation."""


# ---------- Data types ----------


@dataclass(frozen=True, slots=True)
class GlobalConfig:
    deadzone: float = 0.2
    poll_hz: int = 100
    long_press_ms: int = 250
    stick_mode: StickMode = "4dir"


@dataclass(frozen=True, slots=True)
class ProfileConfig:
    buttons: dict[str, str] = field(default_factory=dict)
    """Button name (lowercase) → action DSL string."""
    stick: dict[str, str] = field(default_factory=dict)
    """Stick direction (``up`` / ``down`` / ... ) → action DSL string."""


@dataclass(frozen=True, slots=True)
class MacroDef:
    steps: tuple[str, ...]
    if_app: str | None = None


@dataclass(frozen=True, slots=True)
class Config:
    """Fully parsed and validated configuration."""

    global_: GlobalConfig
    profiles: dict[Side, ProfileConfig]
    macros: dict[str, MacroDef]
    source_path: Path | None = None
    """The TOML path this config was loaded from (None if synthesized)."""


# ---------- Public API ----------


def default_config_path() -> Path:
    """Return the platform default, even if the file doesn't exist."""
    xdg = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(xdg) / "vibejoy" / DEFAULT_CONFIG_FILENAME


def default_profiles_dir() -> Path:
    """Return the user profiles directory ($XDG_CONFIG_HOME/vibejoy/profiles)."""
    return default_config_path().parent / DEFAULT_PROFILES_DIR_NAME


def default_backups_dir() -> Path:
    """Return the configuration backups directory ($XDG_CONFIG_HOME/vibejoy/backups)."""
    return default_config_path().parent / DEFAULT_BACKUPS_DIR_NAME


def resolve_config_path(explicit: str | Path | None) -> Path:
    """Return the path we'll actually read, following the documented order.

    Does **not** check existence — callers should, so that :func:`load_config`
    can produce a precise error with the resolved path.
    """
    if explicit is not None:
        return Path(explicit).expanduser()
    env = os.environ.get(ENV_CONFIG_PATH)
    if env:
        return Path(env).expanduser()
    cwd_cfg = Path.cwd() / DEFAULT_CONFIG_FILENAME
    if cwd_cfg.is_file():
        return cwd_cfg
    return default_config_path()


def load_config(path: str | Path | None = None) -> Config:
    """Parse + validate the config at ``path`` (or the default location)."""
    resolved = resolve_config_path(path)
    if not resolved.is_file():
        raise ConfigError(
            f"config file not found: {resolved}\n"
            f"Run `vibejoy run` to auto-create one with defaults, "
            f"or pass an explicit --config path that exists."
        )
    try:
        with resolved.open("rb") as f:
            raw = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"invalid TOML in {resolved}: {e}") from e
    except OSError as e:
        raise ConfigError(f"cannot read {resolved}: {e}") from e

    cfg = _build_config(raw, source_path=resolved)
    errors = validate_config(cfg)
    if errors:
        formatted = "\n".join(f"  - {e}" for e in errors)
        raise ConfigError(f"config {resolved} has errors:\n{formatted}")
    return cfg


def validate_config(cfg: Config) -> list[str]:
    """Return a list of human-readable error messages (empty = valid)."""
    errors: list[str] = []

    g = cfg.global_
    if not 0.0 <= g.deadzone < 1.0:
        errors.append(f"global.deadzone must be in [0.0, 1.0), got {g.deadzone}")
    if not 1 <= g.poll_hz <= 1000:
        errors.append(f"global.poll_hz must be in [1, 1000], got {g.poll_hz}")
    if g.long_press_ms <= 0:
        errors.append(f"global.long_press_ms must be > 0, got {g.long_press_ms}")
    if g.stick_mode not in ("4dir", "8dir"):
        errors.append(f"global.stick_mode must be '4dir' or '8dir', got {g.stick_mode!r}")

    macro_names = set(cfg.macros)
    for side, profile in cfg.profiles.items():
        _validate_profile(side, profile, macro_names, errors)

    for name, macro in cfg.macros.items():
        _validate_macro(name, macro, errors)

    return errors


def read_example_config() -> str:
    """Return the bundled ``config.example.toml`` as text.

    Used by ``vibejoy schema`` and by the first-run auto-create path so
    there's one source of truth for the default configuration.
    """
    try:
        return resources.files("vibejoy").joinpath(EXAMPLE_CONFIG_RESOURCE).read_text("utf-8")
    except (FileNotFoundError, ModuleNotFoundError):
        # Fallback — when running from a source checkout without the file packaged.
        here = Path(__file__).resolve().parent
        return (here / EXAMPLE_CONFIG_RESOURCE).read_text("utf-8")


def read_default_profile() -> str:
    """Return the bundled default profile (profiles/default.toml) as text.

    Falls back to `read_example_config()` if not found.
    """
    try:
        return resources.files("vibejoy").joinpath(DEFAULT_PROFILE_RESOURCE).read_text("utf-8")
    except (FileNotFoundError, ModuleNotFoundError, TypeError):
        here = Path(__file__).resolve().parent
        profile_path = here / DEFAULT_PROFILES_DIR_NAME / DEFAULT_PROFILE_FILENAME
        if profile_path.is_file():
            return profile_path.read_text("utf-8")
        return read_example_config()


def read_default_left_profile() -> str:
    """Return the bundled left-hand Joy-Con default profile as text."""
    try:
        return resources.files("vibejoy").joinpath("profiles/left_default.toml").read_text("utf-8")
    except (FileNotFoundError, ModuleNotFoundError, TypeError):
        here = Path(__file__).resolve().parent
        profile_path = here / DEFAULT_PROFILES_DIR_NAME / "left_default.toml"
        if profile_path.is_file():
            return profile_path.read_text("utf-8")
        # Minimal inline fallback so left-hand config always loads cleanly
        return (
            "[profile.left.stick]\n"
            "up = \"macro:codex_page_up\"\n"
            "down = \"macro:codex_page_down\"\n"
            "left = \"macro:codex_previous_thread\"\n"
            "right = \"macro:codex_next_thread\"\n"
            "[profile.left.buttons]\n"
        )


def ensure_profiles_initialized() -> Path:
    """Ensure the user profiles directory and default profiles exist.

    Creates ~/.config/vibejoy/profiles/default.toml and
    ~/.config/vibejoy/profiles/left_default.toml if missing.
    Returns the Path to default.toml.
    """
    pdir = default_profiles_dir()
    pdir.mkdir(parents=True, exist_ok=True)
    default_file = pdir / DEFAULT_PROFILE_FILENAME
    if not default_file.exists():
        default_file.write_text(read_default_profile(), encoding="utf-8")
    left_default_file = pdir / "left_default.toml"
    if not left_default_file.exists():
        left_default_file.write_text(read_default_left_profile(), encoding="utf-8")
    return default_file


def backup_config(target_path: Path | None = None) -> Path:
    """Back up the specified (or resolved active) config file.

    Saves to ~/.config/vibejoy/backups/config.<timestamp>.bak.toml.
    Returns the path of the created backup file.
    """
    src = target_path if target_path is not None else resolve_config_path(None)
    backups_dir = default_backups_dir()
    backups_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = backups_dir / f"config.{timestamp}.bak.toml"
    if backup_file.exists():
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        backup_file = backups_dir / f"config.{timestamp}.bak.toml"

    content = src.read_text(encoding="utf-8") if src.is_file() else read_default_profile()
    backup_file.write_text(content, encoding="utf-8")
    return backup_file


def validate_profile_name(name: str) -> str:
    """Validate and normalize a profile name.

    Disallows empty names, leading dots, path separators, traversal characters,
    or characters outside unicode letters/digits/underscores/hyphens.
    Raises ConfigError on invalid input.
    """
    cleaned = name.strip()
    if not cleaned:
        raise ConfigError(f"invalid profile name: '{name}'")
    if cleaned.startswith(".") or "/" in cleaned or "\\" in cleaned or ".." in cleaned:
        raise ConfigError(f"invalid profile name: '{name}'")
    if not re.match(r"^[\w\-]+$", cleaned, re.UNICODE):
        raise ConfigError(f"invalid profile name: '{name}'")
    return cleaned


def active_profile_path() -> Path:
    """Return the path to the active_profile marker file."""
    return default_config_path().parent / ACTIVE_PROFILE_FILENAME


def get_active_profile() -> str:
    """Return the name of the active profile (defaults to 'default')."""
    p = active_profile_path()
    if not p.is_file():
        return "default"
    try:
        content = p.read_text(encoding="utf-8").strip()
        if not content:
            return "default"
        return validate_profile_name(content)
    except (ConfigError, OSError):
        return "default"


def set_active_profile(name: str) -> None:
    """Set the active profile name in the marker file."""
    valid_name = validate_profile_name(name)
    p = active_profile_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(valid_name, encoding="utf-8")


def list_profiles() -> list[dict[str, Any]]:
    """Scan and list available profiles with metadata."""
    ensure_profiles_initialized()
    pdir = default_profiles_dir()
    active_name = get_active_profile()
    profiles: list[dict[str, Any]] = []
    for p in pdir.glob("*.toml"):
        name = p.stem
        profiles.append(
            {
                "name": name,
                "path": p,
                "is_default": name == "default",
                "is_active": name == active_name,
            }
        )
    profiles.sort(key=lambda item: (0 if item["is_default"] else 1, item["name"].lower()))
    return profiles


def create_profile(
    name: str,
    from_profile: str | None = None,
    content: str | None = None,
) -> Path:
    """Create a new profile file in the profiles directory."""
    valid_name = validate_profile_name(name)
    ensure_profiles_initialized()
    target = default_profiles_dir() / f"{valid_name}.toml"
    if target.is_file():
        raise ConfigError(f"profile '{valid_name}' already exists: {target}")

    if content is not None:
        text = content
    elif from_profile is not None:
        from_name = validate_profile_name(from_profile)
        src_file = default_profiles_dir() / f"{from_name}.toml"
        if not src_file.is_file():
            raise ConfigError(f"source profile '{from_profile}' not found: {src_file}")
        text = src_file.read_text(encoding="utf-8")
    else:
        active_cfg = resolve_config_path(None)
        text = active_cfg.read_text(encoding="utf-8") if active_cfg.is_file() else read_default_profile()

    try:
        raw = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"invalid TOML content for profile '{valid_name}': {e}") from e

    cfg = _build_config(raw, source_path=target)
    errors = validate_config(cfg)
    if errors:
        formatted = "\n".join(f"  - {e}" for e in errors)
        raise ConfigError(f"profile '{valid_name}' has errors:\n{formatted}")

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    return target


def switch_profile(name: str) -> Path:
    """Switch active config to the named profile, creating a backup first."""
    valid_name = validate_profile_name(name)
    ensure_profiles_initialized()
    target = default_profiles_dir() / f"{valid_name}.toml"
    if not target.is_file():
        raise ConfigError(f"profile '{valid_name}' not found: {target}")

    load_config(target)  # Validates target profile syntax & schema

    active_cfg = resolve_config_path(None)
    backup_config(active_cfg)
    active_cfg.parent.mkdir(parents=True, exist_ok=True)
    active_cfg.write_text(target.read_text(encoding="utf-8"), encoding="utf-8")
    set_active_profile(valid_name)
    return target


def delete_profile(name: str) -> None:
    """Delete a custom profile. Cannot delete the factory default profile."""
    valid_name = validate_profile_name(name)
    if valid_name == "default":
        raise ConfigError("cannot delete factory default profile 'default'")
    target = default_profiles_dir() / f"{valid_name}.toml"
    if not target.is_file():
        raise ConfigError(f"profile '{valid_name}' not found: {target}")
    if get_active_profile() == valid_name:
        switch_profile("default")
    target.unlink()



# ---------- Construction ----------


def _build_config(raw: dict[str, Any], *, source_path: Path | None) -> Config:
    unknown_top = set(raw) - {"global", "profile", "macro"}
    if unknown_top:
        raise ConfigError(
            f"unknown top-level section(s): {sorted(unknown_top)}. Known: global, profile, macro"
        )

    global_cfg = _build_global(raw.get("global") or {})
    profiles = _build_profiles(raw.get("profile") or {})
    macros = _build_macros(raw.get("macro") or {})

    return Config(
        global_=global_cfg,
        profiles=profiles,
        macros=macros,
        source_path=source_path,
    )


def _build_global(raw: dict[str, Any]) -> GlobalConfig:
    known = {"deadzone", "poll_hz", "long_press_ms", "stick_mode"}
    unknown = set(raw) - known
    if unknown:
        raise ConfigError(f"unknown key(s) in [global]: {sorted(unknown)}")

    kwargs: dict[str, Any] = {}
    if "deadzone" in raw:
        kwargs["deadzone"] = float(raw["deadzone"])
    if "poll_hz" in raw:
        kwargs["poll_hz"] = int(raw["poll_hz"])
    if "long_press_ms" in raw:
        kwargs["long_press_ms"] = int(raw["long_press_ms"])
    if "stick_mode" in raw:
        kwargs["stick_mode"] = raw["stick_mode"]
    return GlobalConfig(**kwargs)


def _build_profiles(raw: dict[str, Any]) -> dict[Side, ProfileConfig]:
    profiles: dict[Side, ProfileConfig] = {}
    for side_name, body in raw.items():
        if side_name not in ("right", "left"):
            raise ConfigError(f"unknown profile {side_name!r} (use 'right' or 'left')")
        if not isinstance(body, dict):
            raise ConfigError(f"[profile.{side_name}] must be a table, got {type(body).__name__}")
        unknown = set(body) - {"buttons", "stick"}
        if unknown:
            raise ConfigError(f"unknown key(s) in [profile.{side_name}]: {sorted(unknown)}")

        buttons_raw = body.get("buttons") or {}
        stick_raw = body.get("stick") or {}
        if not isinstance(buttons_raw, dict):
            raise ConfigError(f"[profile.{side_name}.buttons] must be a table")
        if not isinstance(stick_raw, dict):
            raise ConfigError(f"[profile.{side_name}.stick] must be a table")

        profiles[side_name] = ProfileConfig(
            buttons={k.lower(): v for k, v in buttons_raw.items()},
            stick={k.lower(): v for k, v in stick_raw.items()},
        )
    return profiles


def _build_macros(raw: dict[str, Any]) -> dict[str, MacroDef]:
    macros: dict[str, MacroDef] = {}
    for name, body in raw.items():
        if not isinstance(body, dict):
            raise ConfigError(f"[macro.{name}] must be a table, got {type(body).__name__}")
        unknown = set(body) - {"steps", "if_app"}
        if unknown:
            raise ConfigError(f"unknown key(s) in [macro.{name}]: {sorted(unknown)}")

        steps_raw = body.get("steps") or []
        if not isinstance(steps_raw, list) or not all(isinstance(s, str) for s in steps_raw):
            raise ConfigError(f"[macro.{name}].steps must be a list of DSL strings")
        macros[name] = MacroDef(
            steps=tuple(steps_raw),
            if_app=body.get("if_app"),
        )
    return macros


# ---------- Validation helpers ----------


def _validate_profile(
    side: Side,
    profile: ProfileConfig,
    macro_names: set[str],
    errors: list[str],
) -> None:
    for btn, spec in profile.buttons.items():
        _validate_action_spec(f"profile.{side}.buttons.{btn}", spec, macro_names, errors)

    for direction, spec in profile.stick.items():
        if direction not in ALL_DIRECTIONS:
            errors.append(
                f"profile.{side}.stick.{direction}: unknown direction "
                f"(known: {', '.join(ALL_DIRECTIONS)})"
            )
            continue
        _validate_action_spec(
            f"profile.{side}.stick.{direction}",
            spec,
            macro_names,
            errors,
            allow_in_stick=True,
        )


def _validate_macro(name: str, macro: MacroDef, errors: list[str]) -> None:
    if not macro.steps:
        errors.append(f"macro.{name}.steps is empty")
        return
    for i, step in enumerate(macro.steps):
        try:
            action = parse_action(step)
        except ActionParseError as e:
            errors.append(f"macro.{name}.steps[{i}]: {e}")
            continue
        # Macros can't invoke other macros or app/window switchers.
        if isinstance(action, MacroRef):
            errors.append(f"macro.{name}.steps[{i}]: nested macro: is not allowed")
        elif isinstance(action, WindowSwitchAction):
            errors.append(f"macro.{name}.steps[{i}]: window_switch not allowed inside macros")
        elif isinstance(action, AppSwitcherAction):
            errors.append(f"macro.{name}.steps[{i}]: app_switcher not allowed inside macros")
        _check_action_keys(f"macro.{name}.steps[{i}]", action, errors)


def _validate_action_spec(
    label: str,
    spec: str,
    macro_names: set[str],
    errors: list[str],
    *,
    allow_in_stick: bool = False,
) -> None:
    try:
        action = parse_action(spec)
    except ActionParseError as e:
        errors.append(f"{label}: {e}")
        return

    from .actions import AppSwitcherAction, AutoAction, DelayAction, ScrollAction, TypeAction

    if isinstance(action, DelayAction):
        errors.append(f"{label}: 'delay:' only makes sense inside a macro")
    if isinstance(action, ScrollAction) and not allow_in_stick:
        errors.append(f"{label}: 'scroll:' is only supported on sticks or inside a macro")
    if isinstance(action, TypeAction) and not allow_in_stick:
        # 'type' is allowed anywhere but it's generally a macro building-block.
        pass
    if isinstance(action, AutoAction) and allow_in_stick:
        errors.append(f"{label}: 'auto:' is for buttons; sticks should use 'tap:' or 'repeat:'")
    if isinstance(action, AppSwitcherAction) and allow_in_stick:
        errors.append(f"{label}: 'app_switcher:' is only supported on a button")
    if isinstance(action, MacroRef) and action.name not in macro_names:
        errors.append(f"{label}: macro {action.name!r} is not defined")

    _check_action_keys(label, action, errors)


def _check_action_keys(label: str, action: Action, errors: list[str]) -> None:
    """Verify every key name used by an action is resolvable by pynput."""
    from .actions import (
        AutoAction,
        ComboAction,
        HoldAction,
        RepeatAction,
        SequenceAction,
        TapAction,
    )

    keys: tuple[str, ...] = ()
    if isinstance(action, (TapAction, HoldAction, RepeatAction, AutoAction)):
        keys = (action.key,)
    elif isinstance(action, (ComboAction, SequenceAction)):
        keys = action.keys

    for k in keys:
        if not is_known_key(k):
            errors.append(f"{label}: unknown key {k!r}")
