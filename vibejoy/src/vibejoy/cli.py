"""vibejoy command-line interface.

Subcommands
-----------
- ``run``        Start the mapping daemon. On first run, auto-creates a
                 starter config at the resolved path if none exists.
- ``validate``   Parse + type-check a config file, exit non-zero on error.
- ``discover``   Live dump of button / stick events (for config authoring).
- ``doctor``     Probe the environment: Joy-Con presence, pynput permissions, IPC.
- ``permission`` Check or request keyboard-event posting permission.
- ``stop``       Gracefully stop the running mapping daemon.
- ``rumble``     Trigger a rumble (goes through the running daemon if present,
                 otherwise opens HID directly).
- ``schema``     Print the config's reference example — useful for AI copilots.
- ``profile``    Manage mapping profiles (list, reset-default, export-default).
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time

from . import __version__
from .config import (
    ConfigError,
    backup_config,
    create_profile,
    default_config_path,
    default_profiles_dir,
    delete_profile,
    ensure_profiles_initialized,
    get_active_profile,
    list_profiles,
    load_config,
    read_default_profile,
    read_example_config,
    resolve_config_path,
    set_active_profile,
    switch_profile,
)
from .events import ButtonEvent, StickEvent
from .ipc import IPCError, default_socket_path, is_daemon_running
from .ipc import call as ipc_call
from .joycon import discover_readers
from .rumble import PRESETS, Rumbler, preset_names, resolve_pattern

# ---------- Entry ----------


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    _setup_logging(verbose=getattr(args, "verbose", False))

    handler = _HANDLERS[args.cmd]
    try:
        return handler(args)
    except ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print()
        return 130


# ---------- Parser ----------


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vibejoy",
        description="Map Joy-Con to macOS keyboard shortcuts, driven by TOML and/or AI.",
    )
    parser.add_argument("--version", action="version", version=f"vibejoy {__version__}")
    parser.add_argument("-v", "--verbose", action="store_true", help="enable DEBUG logging")
    sub = parser.add_subparsers(dest="cmd", required=True, metavar="<command>")

    p_run = sub.add_parser(
        "run",
        help="start the mapping daemon (auto-creates starter config on first run)",
    )
    p_run.add_argument("-c", "--config", help="path to config.toml")

    p_val = sub.add_parser("validate", help="validate a config file")
    p_val.add_argument("path", nargs="?", help="path to config.toml (default: auto-discovered)")

    sub.add_parser("discover", help="live dump of button / stick events")

    sub.add_parser("doctor", help="probe environment + Joy-Con + daemon health")

    p_permission = sub.add_parser(
        "permission",
        help="check the current Python process keyboard-event permission",
    )
    p_permission.add_argument(
        "--request",
        action="store_true",
        help="ask macOS to show its permission prompt when access is missing",
    )

    sub.add_parser("stop", help="gracefully stop the running mapping daemon")

    sub.add_parser("status", help="query running mapping daemon status via IPC")

    p_reload = sub.add_parser(
        "reload",
        help="hot-reload mapping configuration in running daemon via IPC",
    )
    p_reload.add_argument("-c", "--config", help="path to config.toml")

    p_rumble = sub.add_parser("rumble", help="trigger rumble")
    p_rumble.add_argument(
        "--pattern",
        "-p",
        default="short",
        help=f"preset name or bytes spec (presets: {', '.join(preset_names())})",
    )
    p_rumble.add_argument(
        "--side",
        "-s",
        default="any",
        choices=("any", "left", "right", "l", "r"),
        help="which controller (default: any connected)",
    )
    p_rumble.add_argument(
        "--direct",
        action="store_true",
        help="skip the daemon and open HID directly",
    )

    sub.add_parser("schema", help="print the starter config example")

    p_profile = sub.add_parser("profile", help="manage mapping profiles")
    p_profile_sub = p_profile.add_subparsers(
        dest="profile_cmd", required=True, metavar="<profile-action>"
    )
    p_profile_sub.add_parser("list", help="list available profiles")
    p_profile_sub.add_parser("current", help="print active profile name")

    p_profile_create = p_profile_sub.add_parser("create", help="create a new profile")
    p_profile_create.add_argument("name", help="profile name")
    p_profile_create.add_argument(
        "--from",
        dest="from_profile",
        help="source profile to clone from",
    )
    p_profile_create.add_argument(
        "--switch",
        "-s",
        action="store_true",
        help="switch to the new profile immediately",
    )

    p_profile_switch = p_profile_sub.add_parser("switch", help="switch to another profile")
    p_profile_switch.add_argument("name", help="profile name")

    p_profile_delete = p_profile_sub.add_parser("delete", help="delete a profile")
    p_profile_delete.add_argument("name", help="profile name")
    p_profile_delete.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="skip confirmation prompt",
    )

    p_profile_reset = p_profile_sub.add_parser(
        "reset-default", help="reset active config to factory default profile"
    )
    p_profile_reset.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="skip confirmation prompt",
    )
    p_profile_sub.add_parser("export-default", help="print factory default profile to stdout")

    return parser


def _setup_logging(*, verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


# ---------- Subcommand handlers ----------


def cmd_run(args: argparse.Namespace) -> int:
    _ensure_config_exists(args.config)
    from .runner import run

    result = run(config_path=args.config)
    if result.exit_code != 0:
        print(result.message, file=sys.stderr)
    return result.exit_code


def cmd_validate(args: argparse.Namespace) -> int:
    resolved = resolve_config_path(args.path)
    config = load_config(args.path)
    print(f"✅ {resolved} is valid")
    print(f"   profiles: {', '.join(sorted(config.profiles)) or '(none)'}")
    print(f"   macros:   {len(config.macros)}")
    return 0


def cmd_discover(_args: argparse.Namespace) -> int:
    readers = discover_readers()
    if not readers:
        print("no Joy-Con detected — run `vibejoy doctor` for diagnostics", file=sys.stderr)
        return 1
    for reader in readers:
        reader.calibrate()
        print(f"✓ calibrated {reader.side} (baseline={reader.calibration})")

    print("press buttons / move sticks — Ctrl+C to stop")
    print()
    try:
        while True:
            for reader in readers:
                for event in reader.poll():
                    _print_event(event)
            time.sleep(0.02)
    except KeyboardInterrupt:
        return 0


def cmd_doctor(_args: argparse.Namespace) -> int:
    problems = 0
    print(f"vibejoy {__version__}")

    # 1. Config file
    cfg_path = default_config_path()
    if cfg_path.is_file():
        try:
            load_config(cfg_path)
            print(f"✓ config  {cfg_path}")
        except ConfigError as e:
            problems += 1
            print(f"✗ config  {cfg_path}\n    {e}")
    else:
        print(f"  config  {cfg_path} (not yet created — will be on first `vibejoy run`)")

    # 2. Joy-Con presence
    readers = discover_readers()
    if readers:
        details: list[str] = []
        for r in readers:
            bat = r.get_battery()
            pct = bat.get("percentage")
            chg = ", charging" if bat.get("charging") else ""
            if pct is not None and pct > 0:
                details.append(f"{r.side} ({pct}%{chg})")
            else:
                details.append(r.side)
        print(f"✓ joycon  connected: {', '.join(details)}")
        for r in readers:
            r.close()
    else:
        problems += 1
        print("✗ joycon  none detected (pair via System Settings → Bluetooth)")

    # 3. pynput permissions probe
    try:
        from pynput.keyboard import Controller, Key

        Controller().press(Key.shift)
        Controller().release(Key.shift)
        print("✓ pynput  keyboard simulation works")
    except Exception as e:
        problems += 1
        print(f"✗ pynput  {type(e).__name__}: {e}")
        print("    grant Accessibility permission to your terminal:")
        print("    System Settings → Privacy & Security → Accessibility")

    # 4. Window switching
    try:
        from .window import list_running_apps

        n = len(list_running_apps())
        print(f"✓ window  {n} apps visible via NSWorkspace")
    except Exception as e:
        problems += 1
        print(f"✗ window  {type(e).__name__}: {e}")

    # 5. IPC
    sock = default_socket_path()
    if is_daemon_running(sock):
        print(f"✓ daemon  running at {sock}")
    else:
        print(f"  daemon  not running (socket {sock} absent)")

    print()
    if problems == 0:
        print("all good.")
        return 0
    print(f"{problems} problem(s) found.")
    return 1


def cmd_stop(_args: argparse.Namespace) -> int:
    try:
        reply = ipc_call({"cmd": "stop"})
    except IPCError as e:
        print(f"no controllable VibeJoy daemon: {e}", file=sys.stderr)
        return 2
    if reply.get("stopping"):
        print("VibeJoy daemon is stopping")
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    try:
        reply = ipc_call({"cmd": "status"})
    except IPCError as e:
        print(f"no controllable VibeJoy daemon: {e}", file=sys.stderr)
        return 2
    print(json.dumps(reply, ensure_ascii=False))
    return 0


def cmd_reload(args: argparse.Namespace) -> int:
    payload: dict[str, Any] = {"cmd": "reload"}
    if args.config:
        payload["config_path"] = args.config
    try:
        reply = ipc_call(payload)
    except IPCError as e:
        print(f"reload failed: {e}", file=sys.stderr)
        return 2

    source = reply.get("source_path", "active config")
    profiles = reply.get("profiles", [])
    macros = reply.get("macros", [])
    prof_str = ", ".join(profiles) if isinstance(profiles, list) else str(profiles)
    macro_count = len(macros) if isinstance(macros, list) else macros
    print(f"✓ vibejoy reloaded successfully ({source})")
    print(f"   profiles: {prof_str or '(none)'}")
    print(f"   macros:   {macro_count}")
    return 0


def cmd_permission(args: argparse.Namespace) -> int:
    from ApplicationServices import AXIsProcessTrusted
    from Quartz import CGPreflightPostEventAccess, CGRequestPostEventAccess

    trusted = bool(AXIsProcessTrusted()) and bool(CGPreflightPostEventAccess())
    if not trusted and args.request:
        trusted = bool(CGRequestPostEventAccess())
    if trusted:
        print("keyboard-event permission granted")
        return 0
    print(f"keyboard-event permission missing for: {sys.executable}", file=sys.stderr)
    print(
        "enable this Python executable in System Settings → Privacy & Security → Accessibility",
        file=sys.stderr,
    )
    return 4


def cmd_rumble(args: argparse.Namespace) -> int:
    # Parse pattern eagerly so we surface bad input regardless of delivery path.
    try:
        resolve_pattern(args.pattern)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    # Prefer IPC when the daemon is up — otherwise open HID directly.
    socket_path = default_socket_path()
    if not args.direct and socket_path.exists():
        try:
            reply = ipc_call(
                {
                    "cmd": "rumble",
                    "pattern": args.pattern,
                    "side": args.side,
                }
            )
            print(f"rumble via daemon: {json.dumps(reply, ensure_ascii=False)}")
            return 0
        except IPCError as e:
            print(f"daemon unreachable ({e}); falling back to direct HID", file=sys.stderr)

    pulses = resolve_pattern(args.pattern)
    side_req = "right" if args.side in ("any", "right", "r") else "left"
    try:
        with Rumbler.from_side(side_req) as rumbler:
            rumbler.play(pulses)
    except RuntimeError as e:
        # Try the other side when the user asked for "any".
        if args.side in ("any",):
            alt = "left" if side_req == "right" else "right"
            try:
                with Rumbler.from_side(alt) as rumbler:
                    rumbler.play(pulses)
                return 0
            except RuntimeError:
                pass
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


def cmd_schema(_args: argparse.Namespace) -> int:
    print(read_example_config(), end="")
    return 0


def cmd_profile(args: argparse.Namespace) -> int:
    if args.profile_cmd == "list":
        profiles = list_profiles()
        pdir = default_profiles_dir()
        if not profiles:
            print(f"no profiles found in {pdir}")
            return 0
        print(f"Profiles in {pdir}:")
        for item in profiles:
            bullet = "*" if item["is_active"] else "•"
            baseline = " (factory baseline)" if item["is_default"] else ""
            active = " (active)" if item["is_active"] else ""
            print(f"  {bullet} {item['name']}{baseline}{active} -> {item['path']}")
        return 0

    if args.profile_cmd == "current":
        print(get_active_profile())
        return 0

    if args.profile_cmd == "create":
        target = create_profile(args.name, from_profile=args.from_profile)
        print(f"✓ created profile '{args.name}' at {target}")
        if args.switch:
            switch_profile(args.name)
            print(f"✓ switched active profile to '{args.name}'")
        return 0

    if args.profile_cmd == "switch":
        target = switch_profile(args.name)
        print(f"✓ switched active profile to '{args.name}' ({target})")
        return 0

    if args.profile_cmd == "delete":
        if not args.force:
            try:
                ans = input(f"Delete profile '{args.name}'? [y/N]: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print("\naborted.")
                return 1
            if ans not in ("y", "yes"):
                print("aborted.")
                return 1
        delete_profile(args.name)
        print(f"✓ deleted profile '{args.name}'")
        return 0

    if args.profile_cmd == "reset-default":
        if not args.force:
            try:
                ans = input("Reset active config to default profile? [y/N]: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print("\naborted.")
                return 1
            if ans not in ("y", "yes"):
                print("aborted.")
                return 1

        active_path = resolve_config_path(None)
        backup_path = backup_config(active_path)
        print(f"✓ backed up active config to {backup_path}")

        default_content = read_default_profile()
        active_path.parent.mkdir(parents=True, exist_ok=True)
        active_path.write_text(default_content, encoding="utf-8")

        set_active_profile("default")
        load_config(active_path)
        print(f"✓ restored default profile to {active_path}")
        return 0

    if args.profile_cmd == "export-default":
        print(read_default_profile(), end="")
        return 0

    return 1


# ---------- Helpers ----------


def _ensure_config_exists(explicit: str | None) -> None:
    """Write the starter config at the resolved path if it doesn't already exist.

    First-run UX: a user fresh off ``pip install vibejoy`` should be able to
    type ``vibejoy run`` once and have it Just Work with sensible defaults,
    while seeing exactly where the file landed so they can edit it.
    """
    resolved = resolve_config_path(explicit)
    if resolved.is_file():
        return

    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(read_example_config(), encoding="utf-8")
    # Flush so the notice shows before the runner's logging output (which
    # goes to stderr and is unbuffered), especially when stdout is piped.
    print(f"first run: wrote starter config to {resolved}", flush=True)
    print("           edit to customize, then `vibejoy validate` to re-check", flush=True)


def _print_event(event: ButtonEvent | StickEvent) -> None:
    if isinstance(event, ButtonEvent):
        arrow = "↓" if event.pressed else "↑"
        print(f"  {event.side:5s} btn {arrow} {event.button}")
    else:
        if event.direction is None:
            print(f"  {event.side:5s} stick ○ center")
        else:
            print(f"  {event.side:5s} stick → {event.direction}")


_HANDLERS: dict[str, callable] = {
    "run": cmd_run,
    "validate": cmd_validate,
    "discover": cmd_discover,
    "doctor": cmd_doctor,
    "permission": cmd_permission,
    "stop": cmd_stop,
    "status": cmd_status,
    "reload": cmd_reload,
    "rumble": cmd_rumble,
    "schema": cmd_schema,
    "profile": cmd_profile,
}


# Keep a symbol accessible in case anyone imports it.
_ = PRESETS


if __name__ == "__main__":
    sys.exit(main())
