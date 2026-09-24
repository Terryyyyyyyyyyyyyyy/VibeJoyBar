# VibeJoyBar v0.9.6: 系统级灵动 HUD 胶囊提示与物理修饰层 (Modifiers & HUD) 研发方案

## 🎯 目标与范围
1. **视觉无感反馈**：引入 macOS 原生无焦点轻量灵动 HUD 悬浮胶囊，在自动/手动切键时以 0 侵入姿态提示当前激活方案，消除“切没切”的心智疑虑；
2. **硬件按键翻倍**：引入物理修饰层（Modifier / Chord Layer），通过组合键（如按住 SL + 点击正面键）使单手手柄可用按键数量从 11 个翻倍至 20+ 个，彻底释放单手生产力上限！

### 核心功能规划

#### 1. Dynamic HUD 悬浮胶囊提示 (`HUDFeedbackService.swift`)
- **原生无焦点设计**：
  - 基于 `NSPanel`（`styleMask: .nonactivatingPanel`, `canBecomeKey: false`, `level: .floating`），绝对不抢夺正在编辑的窗口焦点；
  - 屏幕顶部居中或角落半透明毛玻璃材质（`.ultraThinMaterial`），呈现高保真 App 图标与当前方案名称；
  - 弹簧动效进入（Spring Bounce），静止展示 1.5s 后优雅淡出，支持连切防抖复用；
  - 设置中心提供开关：`[✓] 切换方案时显示 HUD 胶囊提示`。

#### 2. 物理修饰层与组合键扩展 (`vibejoy` 核心驱动 + `VibeJoyBar`)
- **TOML 规范扩展**：
  - 支持将按键动作设为 `modifier:layer1`（如 `sl = "modifier:layer1"`）；
  - 支持修饰层映射表：`[profile.right.layers.layer1.buttons]` 与 `[profile.right.layers.layer1.stick]`；
- **状态机与分发引擎**：
  - 当修饰键被按住时，按键事件优先路由至对应 layer；松开修饰键立刻恢复基础层；
  - 若修饰键单独按下并松开且未组合其他按键，可支持回退触发原本的基础 tap 动作（可选）。
- **Swift 界面面板联动**：
  - 控制面板侧边栏或插图上方增加 `[ 基础层 | SL 修饰层 ◖]` 视图切换，用户可直观配置第二套按键；
  - 实机长按手柄 SL 键时，界面插图同步动态切换高亮修饰层按键！
