# VibeJoy Bar

A native macOS menu bar companion for VibeJoy.

## Features

- Start, stop, and automatically retry the VibeJoy daemon without a terminal window.
- Edit right Joy-Con button mappings while preserving the existing TOML configuration.
- Validate mappings before saving and restart VibeJoy after successful changes.
- View daemon logs and run VibeJoy diagnostics.
- Register the menu bar app to launch at login.

The controller artwork in `Sources/VibeJoyBar/Resources/ControllerAssets` is
from JoyType (MIT licensed). The included `JOYTYPE-LICENSE.txt` is shipped
with the app as the third-party notice.

## 致谢与致敬 (Acknowledgments & Credits)

VibeJoy Bar 能够在 macOS 上呈现优雅的原生菜单栏与控制器视觉体验，离不开两位先驱开拓者的开源贡献：

1. **[JoyType](https://github.com/0xDarcyJ/JoyType)** by **[@0xDarcyJ](https://github.com/0xDarcyJ)**:
   - 感谢 DarcyJ 与 JoyType 贡献者打造的精湛手柄图形素材与视觉映射灵感。本项目中高清 Joy-Con 控制器视图与材质均源自 JoyType 的 MIT 开源成果。

2. **[vibejoy](https://github.com/WEIFENG2333/vibejoy)** by **[@WEIFENG2333](https://github.com/WEIFENG2333)** (liangweifeng):
   - 感谢梁炜峰创造的 VibeJoy 底层服务。其清晰的 TOML 映射语义、低延迟事件调度与 IPC 控制协议，使得 VibeJoy Bar 能以极高品质与系统深度集成。

## Build and run

```bash
./script/build_and_run.sh
```

The staged app bundle is written to `dist/VibeJoyBar.app`.

