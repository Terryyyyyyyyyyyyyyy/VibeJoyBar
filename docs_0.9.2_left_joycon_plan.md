# VibeJoyBar v0.9.2: 左手 Joy-Con 硬件支持与动态插图适配方案

## 🎯 目标与范围
支持 Nintendo Switch 左手 Joy-Con（PID: 0x2006）的单持及双持使用，并在 VibeJoyBar 控制面板中实现自适应插图联动与独立按键配置。

### 核心功能需求
1. **硬件自动识别与单持/双持状态机**：
   - 仅连右手：显示右手插图与 profile.right 配置（保持现状）；
   - 仅连左手：控制面板自适应切换为左手插图，配置绑定 profile.left；
   - 左右双持：顶部提供 `[ ◖ 左手 Joy-Con | 右手 Joy-Con ◗ ]` 分段切换卡，两只手柄后台同时生效。
2. **左手物理按键定义**：
   - 摇杆在上、四个方向键（↑ ↓ ← →）在下；
   - 系统键为 `-`（减号），功能键为方形 `Capture`（截图键）；
   - 肩键为 `L` 和 `ZL`，滑轨键为 `SL` 和 `SR`。
3. **UI 插图与热区**：
   - 补充 `left-joycon-front.png` 与 `left-joycon-shoulder.png` 高清素材；
   - 精确标定左手按键与摇杆热区。
