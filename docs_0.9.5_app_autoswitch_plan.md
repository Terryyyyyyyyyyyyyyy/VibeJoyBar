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
