# VibeJoyBar 方案预设系统 (Profile System) 研发方案

## 🎯 目标与范围
在保持当前 v0.9.0 卓越稳定性的前提下，为 VibeJoyBar 打造多套配置方案（Profile）的创建、保存、切换与恢复默认机制。

### 核心功能指标
1. **出厂基准方案 (Default Profile)**：
   - 现有的 0.9.0 配置（包括滚轮平滑滚动、吸附窗口求交、Codex 导航等）固化为 `default.toml`，支持一键恢复。
2. **多方案自由创建与切换**：
   - 用户可新建方案（例如 `profile_one.toml`, `profile_two.toml`，支持自定义命名如“编程模式”、“浏览模式”）；
   - 方案存储在 `~/.config/vibejoy/profiles/`。
3. **UI 交互与零中断热重载**：
   - 控制面板顶部与 macOS 菜单栏下拉菜单提供方案选择器；
   - 切换方案时，通过 IPC 发送 `reload` 信号，底层驱动毫秒级静默切换按键映射，手柄无需重新连接。

---

## 🏛 总体架构设计 (System Architecture)

### 1. 目录结构规范
```text
~/.config/vibejoy/
├── config.toml                 # 当前生效运行的配置（保持向后兼容）
├── active_profile              # 当前激活的方案名称（如 "default"）
├── profiles/                   # 方案预设目录
│   ├── default.toml            # 官方固化的出厂基准方案 (只读基准/模板)
│   ├── coding.toml             # 用户自定义方案 1
│   └── browsing.toml           # 用户自定义方案 2
└── backups/                    # 历史配置自动备份目录
    └── config.20260902_225010.bak.toml
```

### 2. 双端交互拓扑 (vibejoy ↔ VibeJoyBar)
- **vibejoy (Python Core)**:
  - 维护基准资产 `default.toml`（随 Python 包分发）。
  - 提供 Profile 管理核心命令：`vibejoy profile list/reset-default/export-default`。
  - 维持 `~/.config/vibejoy/profiles/` 与 `~/.config/vibejoy/config.toml` 的一致性。
  - 自动在恢复/修改前落盘备份到 `backups/`。
- **VibeJoyBar (Swift UI)**:
  - `VibeJoyConfigStore`: 扩展对 Profiles 目录、出厂默认文件及备份逻辑的支持。
  - `DashboardHeader` / `MenuBarContentView`: 暴露方案状态与「恢复出厂默认」安全交互入口（带二次防误触确认弹窗）。

---

## 📝 需求 1 详细设计：出厂基准方案 (Default Profile)

### 1.1 0.9.0 基准配置固化规范 (`default.toml`)
将 v0.9.0 实测稳定、经过人体工学验证的按键映射、滚轮宏及窗口吸附配置正式固化为 `default.toml`：
- **全局参数 (`[global]`)**：
  - `deadzone = 0.20`（UI 预览默认 35% 防漂移区间）
  - `poll_hz = 100` (10ms 高响应轮询)
  - `long_press_ms = 250` (长短按阈值)
  - `stick_mode = "4dir"` (十字精准导航)
- **右手柄按键 (`[profile.right.buttons]`)**：
  - `a`: `tap:enter` (确认)
  - `b`: `tap:escape` (取消)
  - `x`: `combo:option+0` (Type4Me 润色)
  - `y`: `combo:option+1` (Type4Me 快速)
  - `r`: `combo:option+2` (Type4Me Prompt 优化)
  - `zr`: `app_switcher:system` (macOS 原生 Cmd+Tab 系统应用切换器)
  - `plus`: `combo:cmd+s` (保存)
  - `home`: `window_switch:com.openai.codex` (Codex / ChatGPT 快速聚焦)
  - `r-stick / sl / sr`: `none` (安全停用)
- **右手柄摇杆 (`[profile.right.stick]`)**：
  - `up`: `macro:codex_page_up` (向上原生平滑滚动 8 档)
  - `down`: `macro:codex_page_down` (向下原生平滑滚动 8 档)
  - `left`: `macro:codex_previous_thread` (`combo:cmd+shift+[` 上一对话)
  - `right`: `macro:codex_next_thread` (`combo:cmd+shift+]` 下一对话)
- **左手柄按键与摇杆 (`[profile.left.*]`)**：
  - 保留标准系统控制（截屏 `combo:cmd+shift+3`，撤销 `combo:cmd+z`，全选/Tab 等）。
- **预设宏定义 (`[macro.*]`)**：
  - 完整包含 `codex_page_up`, `codex_page_down`, `codex_previous_thread`, `codex_next_thread` (限定 `if_app = "com.openai.codex"`) 以及 `claude_focus`。

### 1.2 Python 核心层实现 (`vibejoy`)
1. **静态资产固化与打包**：
   - 新增 `vibejoy/src/vibejoy/profiles/default.toml`，并在 `pyproject.toml` 的 wheel 打包包含列表中声明。
   - `config.py` 新增 `read_default_profile() -> str` 与 `ensure_profiles_dir() -> tuple[Path, Path]`。
2. **初始化与自愈机制**：
   - 当检测到 `~/.config/vibejoy/profiles/default.toml` 不存在时，自动从包内固化模板释放生成。
3. **CLI 子命令扩展 (`vibejoy profile`)**：
   - `vibejoy profile reset-default [--force]`：
     - 若未指定 `--force`，终端交互提示确认；
     - 自动将当前生效配置归档备份至 `~/.config/vibejoy/backups/config.<ISO8601>.bak.toml`；
     - 将 `default.toml` 覆写写入当前激活配置（`config.toml`），返回 0。
   - `vibejoy profile export-default`：
     - 输出出厂基准配置内容到标准输出或指定路径。

### 1.3 macOS 客户端层实现 (`VibeJoyBar`)
1. **路径与文件支撑 (`AppPaths.swift`)**：
   - 增加 `profilesDirectoryURL` (`~/.config/vibejoy/profiles/`)。
   - 增加 `defaultProfileURL` (`~/.config/vibejoy/profiles/default.toml`)。
   - 增加 `backupsDirectoryURL` (`~/.config/vibejoy/backups/`)。
2. **配置管理器扩展 (`VibeJoyConfigStore.swift`)**：
   - 新增 `func resetToDefaultProfile(createBackup: Bool = true) throws` 方法：
     - 执行配置备份（保留毫秒时间戳）；
     - 读取出厂 `default.toml` 内容；
     - 解析并更新内存模型，标记 `hasUnsavedChanges = true` 并提供即时写入重载能力；
     - 支持恢复后的即时校验与回滚兜底。
3. **UI 交互增强 (`MapperView.swift` & `DashboardHeader.swift`)**：
   - 在 `DashboardHeader` 的「重新读取」按钮旁新增「恢复默认」按钮（带 `arrow.counterclockwise` 图标）。
   - 触发时弹出二次确认弹窗：
     > **确认恢复出厂基准方案？**
     > 将重置所有按键、摇杆与 Codex 导航映射为官方默认配置。您当前的配置将自动备份。
   - 用户确认后执行重置，并在底部状态栏展示「已恢复出厂基准方案，原配置已备份至 backups/」。

### 1.4 容错与安全机制 (Safety & Rollback)
- **非破坏性优先**：任何重置动作必须在物理覆写前完成备份。
- **配置合法性拦截**：恢复写入后立即通过 `vibejoy validate` 校验，若校验未通过则阻断覆盖并报警。

---

## 📝 需求 2 详细设计：多方案自由创建、保存与切换 (Multi-Profile Management)

### 2.1 方案生命周期与存储规范
1. **方案存储体系**：
   - 存储目录：`~/.config/vibejoy/profiles/<name>.toml`
   - 活跃方案指示器：`~/.config/vibejoy/active_profile`（纯文本，存储活跃方案名称，如 `default`、`coding`、`browsing`）
   - 运行时生效配置：`~/.config/vibejoy/config.toml`（保持当前活跃方案的副本，驱动底层与现有脚本无需改动即可生效）
2. **只读保护与隔离机制**：
   - `default.toml` 为只读基准方案，禁止直接删除或重命名。
   - 当活跃方案为 `default` 且用户修改了映射保存时，更新 `config.toml` 运行时副本；点击「另存为新方案」可将其永久化为独立方案文件。
   - 当活跃方案为自定义方案 `<name>` 时，用户点击「保存」将同步写回 `profiles/<name>.toml` 与 `config.toml`。
3. **命名规则规范**：
   - 支持中英文命名（如 `coding`, `browsing`, `游戏手柄`, `快速测试`）。
   - 严格拦截路径穿越字符（禁止包含 `/`, `\`, `..` 等非法字符）。

### 2.2 Python 核心层设计 (`vibejoy`)
1. **API 模块扩充 (`config.py`)**：
   - `active_profile_path() -> Path`: 指向 `~/.config/vibejoy/active_profile`。
   - `get_active_profile() -> str`: 获取当前活跃方案名（默认 `default`）。
   - `set_active_profile(name: str) -> None`: 原子写入活跃方案名。
   - `list_profiles() -> list[dict[str, Any]]`: 列出 profiles 目录下所有 `.toml`，包含名称、路径、是否出厂基准、是否当前激活。
   - `create_profile(name: str, from_profile: str | None = None, content: str | None = None) -> Path`:
     - 校验名称合法性。
     - 若指定 `content` 则直接写入；若指定 `from_profile` 则复制源方案；缺省时从当前活跃配置复制。
   - `switch_profile(name: str) -> Path`:
     - 检查 `profiles/<name>.toml` 存在性与语法有效性。
     - 自动归档当前 `config.toml` 至 `backups/`。
     - 复制目标方案至 `config.toml`，并更新 `active_profile`。
   - `delete_profile(name: str) -> None`:
     - 拒绝删除 `default` 方案。
     - 若删除的是当前激活方案，安全切回 `default` 方案后再行删除。
2. **CLI 命令组扩展 (`vibejoy profile`)**：
   - `vibejoy profile list`: 格式化输出所有方案，当前活跃方案标星（如 `* default (active)`）。
   - `vibejoy profile current`: 快速输出当前激活方案名。
   - `vibejoy profile create <name> [--from <source>] [--switch]`: 基于源方案创建新方案，可选即时切换。
   - `vibejoy profile switch <name>`: 切换当前激活方案（自动备份旧配置并重置生效）。
   - `vibejoy profile delete <name> [--force]`: 删除指定自定义方案。

### 2.3 macOS 客户端层设计 (`VibeJoyBar`)
1. **模型与路径支撑**：
   - `AppPaths.swift`: 新增 `activeProfileURL`。
   - `BindingModels.swift`: 新增 `ProfileItem` 模型（`id`, `name`, `isDefault`, `isActive`, `fileURL`）。
2. **配置管理器扩展 (`VibeJoyConfigStore.swift`)**：
   - 暴露 `@Observable` 属性 `activeProfile: String` 与 `availableProfiles: [ProfileItem]`。
   - `func refreshProfiles()`: 扫描 `profiles/` 目录与 `active_profile` 状态，更新方案列表。
   - `func saveAsNewProfile(named name: String) throws`: 将当前编辑器的按键映射保存为新方案 `profiles/<name>.toml`，并切为当前激活。
   - `func switchToProfile(named name: String) throws`: 切换方案，执行自动备份，覆写 `config.toml` 并重新加载模型。
   - `func deleteProfile(named name: String) throws`: 安全删除方案（受保护方案不可删，删激活方案自动切回 default）。
3. **UI 交互设计 (`DashboardHeader.swift` & `MenuBarContentView.swift`)**：
   - **控制面板 Header 方案切换器**：
     - 在 Header 中间增加方案选择器下拉菜单（Menu），清晰展示当前方案：`[方案: 默认基准 ▾]`。
     - 列表中列出所有已检测到的方案（当前项带 checkmark 标记）。
     - 提供「＋ 另存为新方案…」入口，弹出自定义命名 Sheet 弹窗。
     - 提供「删除当前方案」入口（出厂默认方案灰显禁用）。
   - **macOS 菜单栏快捷切换**：
     - 在菜单栏下拉列表中新增 `方案预设 ▹` 子菜单，用户无需打开面板，即可在菜单栏点击秒级切换方案。

---

## 📝 需求 3 详细设计：零中断热重载 (Zero-Interruption Hot Reload via IPC)

### 3.1 核心痛点与解决思路
- **痛点**：过去在保存配置或切换方案时，客户端通过销毁 Python 进程并重新启动（`restart()`）使配置生效。这导致 Joy-Con 物理 HID 连接断开、摇杆重新校准、按键状态闪烁，且有 1-2 秒的操作断连延迟。
- **目标**：实现毫秒级“零中断”静默切换——手柄保持连接、蓝牙不重连、物理通道不释放，仅在驱动内存中原子替换配置树与按键映射状态机。

### 3.2 Python 核心层架构设计 (`vibejoy`)
1. **Mapper 状态机热替换 (`mapper.py`)**：
   - 增加 `Mapper.reload_config(new_config: Config) -> None`：
     - 调用 `self.release_all()`，安全释放当前所有处于 hold / auto / macro / app_switcher 的按键，防止因按键映射变更导致按键“卡住”（stuck key）。
     - 更新 `self._config = new_config` 与长短按阈值。
     - 重新预编译所有按键动作表：`self._precompiled = self._precompile(new_config)`。
2. **手柄采样参数动态同步 (`joycon.py`)**：
   - 为 `JoyConReader` 增加 `deadzone` 与 `stick_mode` 属性的 setter，支持在手柄连接运行中动态调整死区与摇杆模式（无需重新校准中位点）。
3. **IPC 守护进程控制服务扩展 (`ipc.py` & `runner.py`)**：
   - 扩充 IPC 命令字：`{"cmd": "reload", "config_path": ...}`。
   - `ControlServer` 收到 `reload` 请求时：
     - 读取并验证目标配置；
     - 触发 `mapper.reload_config(new_config)`；
     - 动态同步当前在线 readers 的 `deadzone` 与 `stick_mode`；
     - 响应 JSON：`{"ok": true, "reloaded": true, "source_path": "...", "profiles": [...]}`。
4. **CLI 命令扩展 (`cli.py`)**：
   - 新增 `vibejoy reload [-c <path>]` 命令：通过 Unix socket 向运行中的守护进程发出热重载信号。

### 3.3 macOS 客户端层架构设计 (`VibeJoyBar`)
1. **进程服务扩展 (`VibeJoyProcessService.swift`)**：
   - 新增 `func reload() async -> Bool`：
     - 若当前守护进程正在运行，调用 `runOneShot(arguments: ["reload"])`；
     - 若返回 0，记录日志并返回 `true`（零中断）；
     - 若返回非 0，自动回退到 `restart()` 安全兜底。
2. **全局业务调度改造 (`AppModel.swift`)**：
   - 改造 `saveMappings()`：保存后优先调用 `await processService.reload()`，展示“映射已保存，已完成零中断热重载”。
   - 改造 `switchToProfile(named:)`：切换后优先调用 `await processService.reload()`，展示“已切换至方案 [名称]（零中断生效）”。
   - 改造 `resetToDefaultProfile()`：恢复默认后优先调用 `await processService.reload()`，展示“已恢复出厂基准方案（零中断生效）”。



