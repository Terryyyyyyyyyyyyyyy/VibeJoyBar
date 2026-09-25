# VibeJoyBar v0.9.7: 原生快捷键录制器 + Type4Me 全局锁定核心 + 自由释放应用定制

## 🎯 目标与交付
针对用户日常高频的 **Type4Me 语音输入（两段式：按一下开始，按一下停止优化并上屏，再按确认发送）** 与 **肩键程序切换（按住调出 App Switcher，摇杆选择）** 核心习惯，彻底解决旧版本在多应用配置和按键自定义上的痛点：

### 核心亮点

#### 1. Type4Me 核心按钮“全局锁定” (Global Protected Core)
- **保护范围**：
  - Type4Me 录音与优化：`R` / `L` (`combo:option+2`)
  - Type4Me 快速润色：`X` / `Up` (`combo:option+0`)、`Y` / `Left` (`combo:option+1`)
  - 系统 App 切换器：`ZR` / `ZL` (`app_switcher:system`)
  - 确认与取消：`A` / `Right` (`tap:enter`)、`B` / `Down` (`tap:escape`)
- **级联继承机制**：
  - 在所有 App 子方案中强制保持全局锁定状态，随 `default.toml` 动态同步；
  - 彻底杜绝方案间“伪继承”与配置脱节（Config Drift）。

#### 2. 其余按键“自由释放” (Freed App Overrides)
- **释放范围**：摇杆 4 个方向（Up/Down/Left/Right）、Plus/Minus (`+`/`-`)、Home/Capture、导轨键 (`SL`/`SR`)、摇杆下压。
- **差异化覆盖**：
  - 允许在特定程序（如 Safari、Codex、VS Code）中单独设计专属动作（例如 Safari 下 Plus 设为 `Cmd+T` 新建标签，摇杆左右设为历史后退前进）；
  - 未定制时优雅自动回退至全局基准。

#### 3. 原生快捷键录制器与多维动作设计器 (Interactive Shortcut Recorder)
- **键盘直录**：点击「开始录制快捷键」，按下键盘上任意物理键或组合键（如 `⌘ + ⇧ + P`、`Space`、`Escape`、`F12`），自动实时捕捉并编译为 VibeJoy DSL。
- **4 大分类设计面板**：
  1. `⌨️ 快捷键录制`：物理按键录制 + 修饰键勾选 (⌘ ⌥ ⌃ ⇧) + 常用按键下拉选单；
  2. `⭐️ 常用预设`：复制、粘贴、剪切、撤销、重做、保存、关闭标签、全选、查找、刷新等高频操作；
  3. `🎙️ Type4Me 专区`：Prompt 优化、快速润色、极速输出、F18、F19；
  4. `🖥️ 系统与扩展`：系统 App 切换器、聚焦应用、SL 修饰层 1、安全停用。

#### 4. 未保存编辑防丢保护 (Unsaved Edit Protection)
- 当用户在 `VibeJoyBar` 面板中编辑且未保存（`hasUnsavedChanges == true`）时，切前台窗口自动挂起路由切换，彻底杜绝辛辛苦苦配的按键被冲掉。
