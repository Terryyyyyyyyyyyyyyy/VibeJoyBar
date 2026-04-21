# VibeJoy — notes for future Claude sessions

## What this project is

Maps Nintendo Switch Joy-Con inputs to macOS keyboard shortcuts. Config
is TOML, everything is CLI-driven, and the daemon exposes a Unix socket
so AI hooks can trigger rumble. Target platform is macOS only (pyobjc +
pynput). Python 3.11+, packaged with uv + hatchling.

## Module map (`src/vibejoy/`)

Each file is one responsibility — don't spread logic across modules.

| File | Owns |
|---|---|
| `cli.py` | argparse subcommands (run / validate / discover / doctor / rumble / schema); `run` auto-creates missing config |
| `config.py` | TOML loading, path resolution, strict validation |
| `events.py` | `ButtonEvent` / `StickEvent` frozen dataclasses |
| `actions.py` | Action DSL types + `parse_action` (the vocabulary users bind) |
| `keyboard.py` | pynput wrapper with key-name resolver and held-key bookkeeping |
| `window.py` | macOS app cycling via `NSWorkspace` |
| `joycon.py` | pyjoycon wrapper, baseline stick calibration, event diffing |
| `mapper.py` | Event + config → side effects. State machine for hold/auto/sequence/repeat/shell |
| `shell.py` | Non-blocking `/bin/sh -c` dispatch + VIBEJOY_* env injection |
| `rumble.py` | HD-Rumble primitives, presets, `Rumbler` class |
| `ipc.py` | Unix-socket control server + client (used for rumble-while-daemon-holds-HID) |
| `runner.py` | Main loop glue, signal handling, IPC hookup |

## Common commands

```bash
uv sync                          # install deps
uv run pytest                    # 104 tests, ~0.4s
uv run ruff check src tests
uv run ruff format src tests     # auto-format
uv run vibejoy doctor            # Joy-Con + permissions + daemon status
uv run vibejoy validate          # check config.toml
uv run vibejoy run               # start daemon (needs a paired Joy-Con)
uv run scripts/spike_joycon.py   # low-level device probe
```

## Code conventions

- **Types everywhere.** `from __future__ import annotations` at the top; dataclasses for structures (`frozen=True, slots=True` unless mutability is required).
- **`Side`, `Direction`, `ShellEventKind`** are `Literal` aliases in `events.py` / `shell.py` — reuse, don't redefine.
- **Validation is strict.** Unknown TOML fields, unknown key names, unparseable actions all raise `ConfigError` with a precise path like `profile.right.buttons.a: unknown key 'explode'`. Keep it that way — AI agents rely on clear errors.
- **Actions are precompiled** once at `Mapper.__init__` via `_precompile()`. Hot path doesn't re-parse DSL strings.
- **Mapper state lives in `_MapperState`**, not sprinkled across `Mapper`. Helps reset on `release_all()`.
- **Ruff config** is in `pyproject.toml` under `[tool.ruff]`. Ignored: `E501` (line length), `B008` (func call default), `SIM105` (`contextlib.suppress` slower than try/except pass).

## Non-obvious things

- **Stick baseline calibration is required.** Joy-Con factory offset puts rest at ~(2207, 1773) instead of (0, 0). `JoyConReader.calibrate()` samples 20 frames at startup. Tests that exercise the stick must either call `.calibrate()` or pre-populate `_calibration`.
- **HID is exclusive.** `pyjoycon.JoyCon(...)` opens the handle; a second process can't open the same path. That's why `ipc.py` exists — `vibejoy rumble` talks to the daemon instead of opening HID directly when a daemon is running.
- **Shell commands are fire-and-forget.** `subprocess.Popen(start_new_session=True)` with stdio inherited. Never `.wait()` on user commands — the 100Hz polling loop can't block.
- **pyjoycon 0.2.4 forgets to declare `pyglm`.** We pin it explicitly in `pyproject.toml`. If the upstream fixes it, drop the pin.
- **`get_frontmost_app` uses `NSWorkspace.frontmostApplication()`**, not AppleScript. Keep it that way — AppleScript adds ~100ms per call.
- **Rumble byte patterns are approximations.** Derived from published reverse-engineering; exact Nintendo tone encoding isn't implemented. If someone needs precise tones, they pass raw bytes (`--pattern "c8 c8 72 04"`).

## Adding new features

- **New action verb:** add dataclass to `actions.py`, add parser to `_PARSERS`, handle in `mapper._do_press` / `_do_release` / `_on_stick` / `_execute_macro_step`, add validation skip in `config._check_action_keys` if it doesn't take key names, write tests.
- **New IPC command:** extend the handler in `runner._start_control_server`, add a client helper if needed, document in `ipc.py`'s module docstring.
- **New CLI subcommand:** add parser in `cli._build_parser`, handler `cmd_*`, register in `_HANDLERS`.
- **Don't introduce abstract base classes, plugin registries, or mixins.** The project philosophy is "add a file, not an abstraction."

## Testing philosophy

- Mapper tests use `FakeKeyboard` / `FakeWindow` / `_ShellRecorder` — never pynput or subprocess directly. Keeps tests fast and deterministic.
- `test_shell.py` has one real-subprocess smoke test to catch API drift in `subprocess.Popen`. If that test fails, shell spawning is actually broken; don't stub it harder.
- Joy-Con hardware-dependent code isn't unit-tested. Exercise it via `scripts/spike_joycon.py` or `vibejoy discover`.

## Publish / release

- Semantic version in `src/vibejoy/__init__.py` and `pyproject.toml`.
- Bump both when releasing.
- GitHub repo: `WEIFENG2333/vibejoy`.
