# Changelog

## 0.9.1

- **方案预设系统 (Profile System)**：
  - 固化出厂基准方案 `default.toml`，支持一键恢复与自动带时间戳物理备份 (`backups/`)。
  - 多方案生命周期自由管理：支持另存为新方案、方案克隆、切换与安全删除（保护 default 方案）。
  - **零中断热重载 (Zero-Interruption Hot Reload via IPC)**：通过 IPC 控制通道发送 `reload` 信号，原子热替换按键映射与采样参数，切换方案或保存配置时手柄不掉线、无重新校准延迟。
  - VibeJoyBar 控制面板 Header 方案切换下拉菜单与「另存为新方案」交互，macOS 菜单栏常驻图标支持全局一键秒切。

## 0.9.0

- Stick Up/Down native mouse wheel scrolling with smooth 60ms repeat.
- Display-boundary-aware scroll event targeting for edge-docked apps (Codex / ChatGPT).
- Hardened Joy-Con ADC calibration with non-empty packet polling and baseline clamping.
- Re-architected VibeJoyBar UI: exact pixel-aligned hotspots, shape-adaptive button indicators, unified directional stick compass, and hidden idle indicators.

## 0.5.3

- Correct right-stick vertical orientation and suppress snapback/cross-axis
  actions with a stable one-action-per-deflection state machine.

## 0.5.2

- Preserve Command and Shift flags on Cmd+Tab app-switcher navigation.

## 0.5.1

- Use bounded native macOS scroll gestures for Codex conversation history;
  left/right chat switching and ZR App switching are unchanged.

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] — 2026-04-22

### Changed
- **First-run UX**: `vibejoy run` now auto-creates a starter config at
  the resolved path (defaults to `~/.config/vibejoy/config.toml`) when
  none exists, printing a one-line notice that tells the user exactly
  where the file landed. Eliminates the "install → run → wall → look up
  command → retry" dance for new users.
- `vibejoy doctor`'s message about a missing config now reads
  "will be created on first `vibejoy run`" instead of pointing at
  a command that no longer exists.
- `load_config` error message now suggests `vibejoy run` or an explicit
  `--config` path when the file is missing.

### Removed
- **`vibejoy init` subcommand**. `run` handles first-time creation
  automatically; `schema` continues to print the reference example for
  AI copilots or stdout-piping. One less command, one less step.
- Dead code: `Mapper.update_window_apps()` had no callers.

### Notes
- This is a breaking CLI change. Scripts that used `vibejoy init` should
  either delete the call (if they followed it with `vibejoy run`), or
  replace it with `vibejoy schema > path/to/config.toml` if they need
  an explicit write-to-custom-path step.

## [0.1.0] — 2026-04-21

### Added
- Initial public release.
- Joy-Con HID reader via `pyjoycon` with factory-offset stick calibration on
  startup (no manual calibration step required).
- TOML configuration with strict validation: unknown fields, unknown key names,
  and unparseable action specs all produce path-scoped error messages designed
  to be actionable by AI copilots.
- Action DSL — single-string-per-binding grammar:
  `tap`, `hold`, `repeat`, `auto`, `combo`, `sequence`, `type`, `delay`,
  `macro`, `window_switch`, `shell`.
- `shell:<command>` action: non-blocking `/bin/sh -c` dispatch that receives
  context via `VIBEJOY_EVENT` / `BUTTON` / `SIDE` / `DIRECTION` /
  `FRONTMOST_APP` env variables. Fires on both press and release.
- macOS keyboard simulation (`pynput`) with a curated key-name resolver and
  held-key bookkeeping for clean `release_all()` semantics.
- macOS application focus cycling through `NSWorkspace` via `pyobjc`.
- HD-Rumble support with preset patterns (`short`, `long`, `click`, `double`,
  `ok`, `error`) and raw-byte spec (`--pattern "c8 c8 72 04"`) for custom tones.
- Unix-socket control channel (`~/.vibejoy/control.sock`): lets external
  processes trigger rumble while the daemon holds the HID handle — the
  motivating use case is Claude Code hooks buzzing your hand on `Stop` /
  `Error` events.
- CLI: `vibejoy run | validate | discover | doctor | init | rumble | schema`
  (note: `init` was removed in 0.2.0 in favor of auto-create on `run`).
- `vibejoy doctor` probes Joy-Con presence, Accessibility permission, window
  access, and daemon socket health in one command.
- 104 unit tests, 0.4 s wall-clock, no physical controller required.
- GitHub Actions CI (macos-latest × Python 3.11 / 3.12 / 3.13) running lint,
  formatter check, and test suite on every push and pull request.
- Automated PyPI publishing via OIDC Trusted Publishing on `v*` tags,
  gated by the `release` environment for manual approval.

[Unreleased]: https://github.com/WEIFENG2333/vibejoy/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/WEIFENG2333/vibejoy/releases/tag/v0.2.0
[0.1.0]: https://github.com/WEIFENG2333/vibejoy/releases/tag/v0.1.0
