# Changelog

## 0.9.4

- **虚拟控制器物理按键下陷弹起与摇杆 3D 偏转灵动动效 (Tactile Animations & 3D Analog Stick Deflection)**：
  - **按键物理下陷阻尼回弹 (Key Travel & Spring Bounce)**：
    - 新增 `TactileHotspotButtonStyle` 与 `TactileCapsuleButtonStyle`，模拟真实机械微动按键行程；
    - 针对大面积宽幅按键与圆形按键精准调优，按下时沉入基底槽 4.2~6.5pt，外围投影与光圈紧贴收拢，并触发系统触觉反馈（Haptic Feedback）；
    - 松开时配合 Apple Spring 阻尼弹簧（`response: 0.22, dampingFraction: 0.52`）拟真回弹复位，且具备 120ms 最小触觉停留保障，告别轻点无感。
  - **真实左手柄 4 枚独立圆形方向键形态复刻 (Joy-Con L Circular Buttons)**：
    - 严格遵循任天堂官方 Switch 真机双人分体共享设计规范，彻底纠正十字键错误，无痕重绘红色外壳基底；
    - 像素级还原 4 枚独立圆形方向键（▲、▼、◀、▶），与右手 A/B/X/Y 呈完全对称菱形布局。
  - **真实肩部硬件按键解耦与机械下陷沉入深槽 (Shoulder Mechanical Depression)**：
    - 彻底告别悬浮在按键中间的突兀小胶囊指示器，将整枚真实黑色肩部硬件按键作为独立可交互物理层；
    - 针对左手（ZL/L）与右手（ZR/R）的不同几何曲面与延伸长度进行独立像素级标定；
    - 静止状态 100% 还原官方插图且无缝贴合；点击时真实垂直下沉（ZL/ZR 下沉 6.5pt，L/R 下沉 4.8pt）沉入深黑色腔体槽。
  - **摇杆 3D 偏转与轴向拉伸 (3D Stick Deflection & Perspective Tilt)**：
    - 新增 `TactilePhysics` 物理动力学引擎，支持最大 14pt 物理偏转阻尼向量限幅、18° 3D 空间透视倾斜矩阵计算与反向光影投射；
    - 全新 `InteractiveJoyConStickView` 拟真组件：
      - **机械球窝底座**：76pt 暗黑径向底座，随推杆方向实时逆向拉伸内阴影，呈现真实物理凹窝纵深感；
      - **Joy-Con 经典摇杆帽**：52pt 哑光防滑橡胶外圈、4 方向物理凸点（Grip Nubs）、凹面指腹槽、高亮微光轮廓；
      - **手势联动与点击**：支持原生平滑拖拽手势偏转、直接下压点击（Stick Click）伴随同心光环微脉冲与触觉震动反馈；
      - **环形方向选择器**：集成上下左右 4 轴方向指示热区，按压弹性下陷与实时偏转高亮。
  - **左/右 Joy-Con 完整协同适配**：
    - 右手 R-Stick 与左手 L-Stick 自动绑定，精确定位在手柄插图对应的物理摇杆中心，与 Codex 导航映射完美统一。

## 0.9.3

- **手柄电量实时监测与状态显示 (Real-Time Controller Battery Monitoring)**：
  - Python 后端：`JoyConReader.get_battery()` 解析 Joy-Con 状态帧中的电量等级（0..4）与充电状态，准确映射为百分比（100%、75%、50%、25%、5%），并具备断连与异常安全降级机制。
  - IPC 通信层：`status` 指令返回当前各连接手柄的电量字典 `controllers`（含 `level`, `percentage`, `charging`, `battery`）。
  - CLI 工具：`vibejoy doctor` 在检测手柄时实时打印电量与充电状态（如 `right (100%)`）。
  - VibeJoyBar 前端：
    - `ControllerBattery` 数据模型与 SF Symbols 动态图标映射（`battery.100`, `battery.75`, `battery.50`, `battery.25`, `battery.0`, `battery.100.bolt`），电量 $\le 20\%$ 低电量告警。
    - Dashboard Header 显示当前手柄电量胶囊角标与充电标记，双持分段器支持左/右实时百分比显示。
    - Dashboard 侧边栏紧凑状态头集成微型电池指示。
    - macOS 菜单栏常驻图标下拉菜单显示左右 Joy-Con 实时电量及充电状态。

## 0.9.2

- **左手 Joy-Con 硬件适配 (Left Joy-Con Hardware Support)**：
  - Python 后端新增内置左手默认方案 `profiles/left_default.toml`（L-Stick 继承 Codex 导航映射，D-Pad / L / ZL / Minus / Capture 预设 `none` 供自定义）；`ensure_profiles_initialized()` 自动创建左手方案文件。
  - 硬件发现层已就绪：`discover_readers()` 与 `_rediscover_missing()` 原生支持左手，IPC `status` 命令返回实时 `sides` 列表。

- **VibeJoyBar 动态插图自适应 (Adaptive Controller Illustration)**：
  - 新增 `ActiveControllerSide` 枚举，`VibeJoyProcessService` 新增 `connectedSides: Set<String>` 可观察属性，实时追踪已连接手柄侧。
  - **三态 UI**：仅右手 → 保持原有布局；仅左手 → 控制面板自动切换为左手插图与按键分组（D-Pad / L / ZL / Minus / Capture / L-Stick）；左右双持 → Header 出现 `[ ◖ 左手 | 右手 ◗ ]` 分段切换卡，两侧配置后台同时生效。
  - `ControllerIllustrationView` 接收 `controllerSide` 参数，热区布局、肩键胶囊（R/ZR ↔ L/ZL）、摇杆图例全部跟随侧动态切换。
  - 新增左手正面与肩部插图资源（`left-joycon-front.png` / `left-joycon-shoulder.png`），朝向与真实左手 Joy-Con 物理布局一致（圆弧在左、SL/SR 轨道在右）。

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
