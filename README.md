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

## Build and run

```bash
./script/build_and_run.sh
```

The staged app bundle is written to `dist/VibeJoyBar.app`.
