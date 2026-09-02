# VibeJoyBar 🎮

> 将 Nintendo Switch Joy-Con 打造为 macOS 下极致顺手的随身编程、AI 协作与桌面生产力菜单栏伴侣套件。

**VibeJoyBar** 是一套专为 macOS 打造的高性能手柄生产力套件。通过极低延迟的 HID 原生驱动与精致的 Swift 菜单栏伴侣，让你的单手 Joy-Con 摇身一变成为控制终端、AI 助手（Codex / ChatGPT / Claude Code）、文本润色与窗口切换的效率神器。

---

## 🌟 核心特性 (v0.9.0)

- **原生滚轮平滑滚动**：摇杆上/下推击即为原生 macOS 鼠标滚轮，60ms 极低延迟平滑连击；内置智能屏幕边界求交检测，完美解决右侧贴边窗口（如 Codex / ChatGPT）的滚动穿透问题。
- **对话切换与系统 App 调度**：摇杆左/右轻拨快速切换 AI 会话历史；按住 ZR 肩键即可激活系统级应用切换器（Cmd+Tab）。
- **精准像素级控制器面板 (`VibeJoyBar`)**：macOS 原生 Swift 菜单栏常驻应用，采用实机提取的几何对齐技术，按键形态自适应高亮（圆形面键、长条滑轨键、微光 Home 圈、一体化摇杆罗盘），未选中时纯净整洁，交互时弹性发光。
- **开机防死锁硬件校准**：加固的 Joy-Con ADC 采样滤波器，开机与蓝牙自动重连零基线漂移。
- **TOML 即 API & AI 友好**：单一人类可读的 TOML 配置文件，支持严谨语法校验；后台驱动常驻 Unix Socket IPC，毫秒级热重载。

---

## 🏗️ 架构组成

本项目由两大部分深度协同构成：

```
VibeJoyBar/
├── vibejoy/        # Python 3.11+ 底层核心驱动 (HID 通信、事件调度、滚轮平滑、IPC 服务)
└── VibeJoyBar/     # macOS 原生 Swift 6 菜单栏应用 (可视化控制器面板、映射检查器)
```

1. **`vibejoy` (核心驱动服务)**
   - 依赖 `hidapi` 与 `pyjoycon` 直接读取蓝牙手柄原生 HID 报告；
   - 模拟按键与原生 CoreGraphics HID 滚轮事件分发；
   - 提供 Unix Domain Socket IPC 控制通道，实现零中断配置热重载。

2. **`VibeJoyBar` (控制面板伴侣)**
   - 纯粹的 macOS 菜单栏常驻体验，启动不弹窗打扰；
   - 提供直观的 Joy-Con 正面与肩部映射配置器，支持一键校验并热重启后台服务。

---

## ❤️ 致谢与致敬 (Acknowledgments & Credits)

VibeJoyBar 项目在诞生与演进过程中，深深吸纳并受益于开源社区先行者的优秀设计与卓越开拓。特向以下两位作者及其项目致以最诚挚的敬意：

1. **[vibejoy](https://github.com/WEIFENG2333/vibejoy)** by **[@WEIFENG2333](https://github.com/WEIFENG2333)** (liangweifeng):
   - 奠定了本项目极为优秀的 Unix 哲学底层基石——基于 macOS 原生 HID 通信驱动、直观优雅的 TOML DSL 映射规范、低延迟的按键状态机以及轻量高效的 Unix Socket IPC 架构。感谢梁炜峰的开拓性贡献！

2. **[JoyType](https://github.com/0xDarcyJ/JoyType)** by **[@0xDarcyJ](https://github.com/0xDarcyJ)** (DarcyJ & contributors):
   - 开创了将 Joy-Con 与迷你手柄转化为现代极简桌面输入、语音听写与 AI 协同的标杆；项目中所包含的极致精致的 Joy-Con 控制器原画设计（MIT 授权）赋予了本项目视觉面板最坚实的艺术基础。感谢 DarcyJ 与 JoyType 贡献者的开源馈赠！

---

## 📄 开源许可证

本项目采用 MIT 许可证发布。
第三方控制器资产版权归 [JoyType contributors](VibeJoyBar/Sources/VibeJoyBar/Resources/ControllerAssets/JOYTYPE-LICENSE.txt) 所有。
