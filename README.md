# VibeJoy

[![CI](https://github.com/WEIFENG2333/vibejoy/actions/workflows/ci.yml/badge.svg)](https://github.com/WEIFENG2333/vibejoy/actions/workflows/ci.yml)
[![PyPI](https://img.shields.io/pypi/v/vibejoy.svg)](https://pypi.org/project/vibejoy/)
[![Python](https://img.shields.io/pypi/pyversions/vibejoy.svg)](https://pypi.org/project/vibejoy/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#requirements)

Map Nintendo Switch **Joy-Con** inputs to **macOS keyboard shortcuts** — configured via a single TOML file, controllable from the command line, and designed to be edited by humans *or* AI copilots.

Bonus: expose the Joy-Con's **HD Rumble** as a CLI, so your Claude Code / any-AI hook can buzz your hand when a task finishes.

```bash
# after `vibejoy run` is running in the background:
vibejoy rumble --pattern ok       # a gentle double-click
vibejoy rumble --pattern error    # a long angry buzz
```

## Why

The existing Joy-Con → keyboard projects are Windows-first, GUI-heavy, and don't play well with an AI-driven workflow. VibeJoy is the opposite:

- **macOS-native** — reads Joy-Con directly over HID (`joycon-python`), simulates keys via `pynput`, switches apps via Quartz/AppKit.
- **TOML is the API** — one human-readable file, one DSL per binding (`tap:enter`, `combo:cmd+c`, `repeat:up@100`). AIs can edit it; `vibejoy validate` catches typos.
- **CLI first** — no GUI, no system tray. Every operation is a subcommand.
- **AI-reachable rumble** — the daemon exposes a Unix-socket control channel; any script can trigger haptics.

## Requirements

- macOS 13+ (Quartz + AppKit pyobjc frameworks).
- Python 3.11+ (uses the built-in `tomllib`).
- `uv` (recommended) or `pip`.
- Joy-Con paired over Bluetooth.

## Install

```bash
# end-user install (once 0.1.0 lands on PyPI)
pip install vibejoy

# or with uv for a fully isolated tool
uv tool install vibejoy

# from source, for development
git clone https://github.com/WEIFENG2333/vibejoy.git
cd vibejoy
uv sync
```

Grant **Accessibility** permission to your terminal the first time you run anything that simulates keys — otherwise pynput silently does nothing.

> System Settings → Privacy & Security → Accessibility → add Terminal / iTerm / VS Code.

## Quick Start

```bash
# 1. Pair Joy-Con via Bluetooth (see `vibejoy doctor` for guidance)
vibejoy doctor

# 2. Generate a starter config
vibejoy init                       # writes ~/.config/vibejoy/config.toml

# 3. Edit config.toml — or let an AI edit it
$EDITOR ~/.config/vibejoy/config.toml
vibejoy validate                   # catches typos

# 4. Start the daemon
vibejoy run
```

The daemon autodetects whichever Joy-Cons are paired and applies the matching profile (`profile.right` / `profile.left`).

## Configuration

Everything lives in one TOML file. The full DSL:

| Verb | Form | Meaning |
|---|---|---|
| `none` | `none` | explicit no-op |
| `tap` | `tap:<key>` | press + release once |
| `hold` | `hold:<key>` | press on input-down, release on input-up |
| `repeat` | `repeat:<key>[@<ms>]` | re-tap every N ms while held (sticks) |
| `auto` | `auto:<key>[@<ms>]` | short press = tap, long press (≥ ms) = hold |
| `combo` | `combo:<k1>+<k2>+…` | one-shot chord |
| `sequence` | `sequence:<mod>+<k>[@<ms>]` | hold mod, tap rest (optionally repeat) |
| `type` | `type:<text>` | type a literal string |
| `delay` | `delay:<ms>` | wait (inside macros only) |
| `macro` | `macro:<name>` | run a `[macro.<name>]` block |
| `window_switch` | `window_switch:<a>,<b>,…` | cycle focus between apps |
| `shell` | `shell:<command>` | run `/bin/sh -c <command>`, non-blocking |

Minimal example:

```toml
[global]
deadzone       = 0.2
poll_hz        = 100
long_press_ms  = 250
stick_mode     = "4dir"

[profile.right.buttons]
a    = "tap:enter"
b    = "tap:escape"
x    = "combo:cmd+w"
r    = "window_switch:code,chrome,terminal"
zr   = "macro:claude_focus"
plus = "combo:cmd+s"

[profile.right.stick]
up    = "repeat:up@100"
down  = "repeat:down@100"
left  = "repeat:left@100"
right = "repeat:right@100"

[macro.claude_focus]
if_app = "Visual Studio Code"    # run only when VS Code is frontmost
steps  = [
  "combo:cmd+shift+p",
  "delay:100",
  "type:Claude Code: Focus input",
  "delay:100",
  "tap:enter",
]
```

Run `vibejoy schema` to print the full annotated example.

## Shell Actions

Bind any button or stick direction to a shell command:

```toml
[profile.right.buttons]
home    = "shell:open -a Calculator"
capture = "shell:say done"
plus    = "shell:osascript -e 'display notification \"buzzed\"'"
```

**Semantics**

- Runs `/bin/sh -c <command>` in a new session — **non-blocking** (the daemon never waits).
- Fires on **both** press and release.  Your script gets `$VIBEJOY_EVENT` = `pressed` or `released` so it can tell which edge it's handling.
- Inside a macro step, `$VIBEJOY_EVENT` = `macro`.

**Injected environment variables**

Every shell invocation receives these in addition to the daemon's env:

| Variable | When set | Example |
|---|---|---|
| `VIBEJOY_EVENT` | always | `pressed` \| `released` \| `macro` |
| `VIBEJOY_BUTTON` | button triggers | `zr` |
| `VIBEJOY_SIDE` | buttons + sticks | `left` \| `right` |
| `VIBEJOY_DIRECTION` | stick triggers | `up-right` |
| `VIBEJOY_FRONTMOST_APP` | macOS only | `Visual Studio Code` |

Scripts that only want to act on press:

```bash
[ "$VIBEJOY_EVENT" = "pressed" ] || exit 0
```

**Output handling**

Stdout/stderr inherit from `vibejoy run` — so you see your script's output in the same terminal.  For noisy commands, redirect in the command itself:

```toml
home = "shell:long-running.sh >> ~/vibejoy.log 2>&1"
```

**Security**

Binding a button to `shell:` gives `config.toml` the same authority as a shell script under your account.  VibeJoy already requires macOS Accessibility permission (arbitrary keystrokes), so the trust boundary doesn't change — but treat `config.toml` with dotfile-level care.  If an AI is rewriting your config, review its edits the same way you'd review a PR.

## CLI Reference

```
vibejoy run           start the mapping daemon
vibejoy validate      parse + type-check config, exit non-zero on error
vibejoy discover      live dump of button / stick events (for authoring)
vibejoy doctor        probe environment: Joy-Con, permissions, IPC
vibejoy init          write starter config.toml
vibejoy rumble        trigger rumble (via daemon if running, else direct HID)
vibejoy schema        print the annotated starter config
```

Each subcommand has `--help`.

## Rumble from AI Hooks

The daemon listens on a Unix domain socket at `~/.vibejoy/control.sock`. `vibejoy rumble` prefers this channel (so it works even while the daemon holds the HID handle) and falls back to opening HID directly when no daemon is running.

Built-in patterns: `short`, `long`, `click`, `double`, `ok`, `error`.

Custom patterns: pass raw bytes with `--pattern "c8 c8 72 04"` (4 bytes shared across sides, or 8 bytes for left / right).

### Claude Code example

`.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "vibejoy rumble --pattern ok" }] }
    ],
    "Error": [
      { "hooks": [{ "type": "command", "command": "vibejoy rumble --pattern error" }] }
    ]
  }
}
```

Your Joy-Con becomes a tactile notification channel.

## Architecture

```
┌───────────────┐  events   ┌──────────┐  actions   ┌────────────────┐
│  joycon.py    │──────────▶│ mapper.py│───────────▶│ keyboard.py    │
│  (pyjoycon +  │           │ (state   │            │ window.py      │
│  baseline cal)│           │  machine)│            │ (rumble via    │
└───────────────┘           └──────────┘            │  shared HID)   │
       ▲                         ▲                  └────────────────┘
       │              config.py  │
       └── discover ──────── cli.py ──▶ runner.py ──▶ ipc.py
                                                     (control socket)
```

Nine source files, each a single responsibility:

```
src/vibejoy/
├── __init__.py
├── __main__.py           # python -m vibejoy
├── cli.py                # argparse subcommands
├── config.py             # TOML load / validate / paths
├── events.py             # ButtonEvent, StickEvent dataclasses
├── actions.py            # Action DSL + parser
├── keyboard.py           # pynput wrapper + key-name resolver
├── window.py             # macOS app switcher (Quartz/AppKit)
├── joycon.py             # pyjoycon wrapper + baseline calibration
├── mapper.py             # event → action state machine
├── shell.py              # non-blocking shell dispatch + env context
├── rumble.py             # HD-Rumble primitives + presets
├── ipc.py                # Unix-socket control channel
├── runner.py             # main loop + signal handling
└── config.example.toml   # bundled starter config
```

## Development

```bash
uv sync --all-groups
uv run pytest             # 81 tests, ~0.4s
uv run ruff check .
uv run vibejoy doctor     # sanity check
```

## Known Caveats

- `joycon-python` 0.2.4 forgot to declare `pyglm` as a dependency; `pyproject.toml` pins it explicitly until upstream fixes that.
- Rumble byte presets are derived from published reverse-engineering docs. They vibrate reliably but the exact tone isn't Nintendo-accurate — use raw bytes if you need a specific frequency.
- macOS sleeps Bluetooth Joy-Cons after ~30 min idle. Press any button to wake.

## License

MIT
