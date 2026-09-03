# VibeJoyBar v0.9.3: 手柄实时电量监控与状态指示方案

## 🎯 目标与范围
为 VibeJoyBar 引入实时电量监控机制，让用户随时在控制面板和 macOS 菜单栏掌握手柄（左手、右手或双持）的剩余电量与充电状态，消除手柄突然断电的焦虑。

### 核心功能规划
1. **硬件电量数据提取 (`vibejoy`)**：
   - 通过 `pyjoycon` 提取 HID 输入报告中的电量等级（0..4）与充电状态标志（`charging: bool`）；
   - 在后台守护进程的 IPC `status` 返回中，分别挂载 `controllers.left` 和 `controllers.right` 的电池状态数据字典：
     ```json
     {
       "level": 4,          // 0~4
       "percentage": 100,    // 估算百分比: 100%, 75%, 50%, 25%, 5%
       "charging": false
     }
     ```
2. **原生质感 UI 呈现 (`VibeJoyBar`)**：
   - **控制面板 Header**：动态电池图标（`battery.100`, `battery.75`, `battery.50`, `battery.25`, `battery.0`, `battery.100.bolt`）与百分比；
   - **双持分段胶囊**：双持模式下，左/右手分段切换卡各自带上专属电量指示；
   - **macOS 菜单栏下拉**：常驻项展示手柄实时电量，无需展开大窗口即可一目了然；
   - **低电量保护**：当电量 $\le 20\%$ 时显示橙红色高亮警示。
