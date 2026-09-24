# VibeJoyBar v0.9.5: 前台 App 智能感知与方案自动路由研发方案

## 🎯 目标与范围
让 VibeJoyBar 成为随桌面场景自适应变形的生产力神器：无需手动在菜单栏切换配置，当前台窗口在 Codex、浏览器、终端或系统间切换时，手柄按键方案静默、实时、无感自动切换！

### 核心功能指标
1. **Profile 与目标应用关联 (App Association)**：
   - 每个 Profile 支持关联一个或多个目标应用（通过 Bundle ID 或 App 名称，例如 `com.openai.codex`, `com.apple.Safari`, `com.google.Chrome`）；
   - 在控制面板提供直观的应用选择器（展示当前运行的应用图标与列表供一键勾选）。
2. **系统级前台监听 (Zero-Overhead Event Listener)**：
   - 监听 macOS 原生通知 `NSWorkspace.didActivateApplicationNotification`（0% CPU，纯事件驱动）；
   - 当检测到应用前台切换，查表匹配关联的 Profile；若当前应用未绑定任何方案，自动回退到 `default` 通用方案。
3. **静默热重载与防抖保护**：
   - 切换触发已有的 `switchProfile` 与 IPC `reload`（50ms 零中断热替换映射）；
   - 增加 100ms 快速切换防抖保护，避免 Cmd+Tab 快速轮播时频繁触发文件写入与重载；
   - 提供全局自动切换开关：`[✓] 随前台应用自动切换方案`，可随时一键开启或锁定当前方案。

---

## 🛠 实现架构与交付成果

### 1. `[meta]` TOML 规范与跨语言数据契约 (`vibejoy` + `VibeJoyBar`)
- **`MetaConfig` (Python)**：
  - `[meta]` 作为合法顶层节加入 Schema，提供 `apps: tuple[str, ...]` 与 `description: str`。
  - `vibejoy validate` 与 `vibejoy profile list` 均原生识别并展示关联应用。
- **`VibeJoyConfigStore` (Swift)**：
  - 实现 `parseTargetApps(from:)` 与 `renderTargetApps(_:in:)`。
  - 支持单 Profile 针对性更新 `updateTargetApps(for:apps:)`，保持 TOML 原生结构与注释完整。
  - 优化 `switchToProfile(named:isAutoSwitch:)`，自动切换时静默跳过历史备份，避免频繁轮播造成磁盘膨胀。

### 2. `AppRouterService.swift` (系统级前台感知路由引擎)
- 纯事件驱动：监听 `NSWorkspace.didActivateApplicationNotification`（0% 待机 CPU）。
- 智能过滤：排除系统守护进程与 `VibeJoyBar` 自身 PID/Bundle ID。
- 100ms 异步防抖保护（`Task.sleep(for: .milliseconds(100))`），快速 Cmd+Tab 轮播时不卡顿、不抖动。
- 路由算法：Bundle ID 不区分大小写优先匹配 -> Localized Name 不区分大小写次优匹配 -> 未命中自动优雅回退到 `default`。

### 3. UI 交互与体验设计
- **`AppAssociationSheet.swift`**：
  - 双栏布局，左侧查看与管理当前方案的关联列表（支持删除与手动添加），右侧实时罗列 macOS 运行中前台图形 App 并附带高保真图标与 Bundle ID。
  - 跨方案冲突提醒（“已关联: xxx”）、搜索关键字过滤、从 `/Applications` 任意选取未运行 App（`NSOpenPanel`）。
- **`DashboardHeader`**：
  - 方案菜单内嵌「关联目标应用…」快捷入口。
  - 显式全局自动路由按钮：`[✓] 自动路由: 开/关`（附带动态状态颜色与悬浮提示）。
- **`MenuBarContentView`**：
  - 菜单栏下拉菜单集成「随前台应用自动切换方案」全局开关及当前匹配前台 App 的动态状态显示。
- **`SettingsView`**：
  - 设置中心加入「前台应用自动路由」配置区块，版本升级至 `0.9.5 (Build 6)`，Python 内核显示 `0.9.5`。

### 4. 自动化测试与质量验证
- Python 核心测试：`uv run pytest` 全部 185 个测试用例通过（覆盖 `[meta]` 解析、校验、CLI 格式输出）。
- Swift 单元测试：`swift test` 全部 31 个测试用例通过（覆盖 `parseTargetApps`、`renderTargetApps`、`updateTargetApps`、`testAutoSwitchDoesNotCreateBackup`、`testAppRouterMatching`）。

---

## 📌 版本状态
- **Status**: ✅ Completed (v0.9.5 / Build 6)
