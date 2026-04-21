# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- CLI: `vibejoy run | validate | discover | doctor | init | rumble | schema`.
- `vibejoy doctor` probes Joy-Con presence, Accessibility permission, window
  access, and daemon socket health in one command.
- 104 unit tests, 0.4 s wall-clock, no physical controller required.
- GitHub Actions CI (macos-latest × Python 3.11 / 3.12 / 3.13) running lint,
  formatter check, and test suite on every push and pull request.
- Automated PyPI publishing via OIDC Trusted Publishing on `v*` tags,
  gated by the `release` environment for manual approval.

[Unreleased]: https://github.com/WEIFENG2333/vibejoy/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/WEIFENG2333/vibejoy/releases/tag/v0.1.0
