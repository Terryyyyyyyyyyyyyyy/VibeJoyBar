import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Label(model.processService.phase.title, systemImage: model.processService.phase.symbolName)

        if !model.processService.batteries.isEmpty {
            Divider()
            if let left = model.processService.battery(for: .left) {
                Label("左 Joy-Con: \(left.percentage)%" + (left.isCharging ? " (充电中)" : ""),
                      systemImage: left.symbolName)
            }
            if let right = model.processService.battery(for: .right) {
                Label("右 Joy-Con: \(right.percentage)%" + (right.isCharging ? " (充电中)" : ""),
                      systemImage: right.symbolName)
            }
        }

        Divider()

        Button(model.processService.desiredRunning ? "停止 VibeJoy" : "启动 VibeJoy") {
            if model.processService.desiredRunning {
                model.processService.stop()
            } else {
                model.processService.start()
            }
        }

        if model.processService.phase == .needsAccessibility {
            Button("打开辅助功能设置…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        Button("打开控制器面板…") {
            activateAndOpen(id: "mapper")
        }

        Menu("方案预设 (\(model.configStore.activeProfileName))") {
            ForEach(model.configStore.availableProfiles) { profile in
                Button {
                    model.switchToProfile(named: profile.name)
                } label: {
                    if profile.isActive {
                        Label(profile.name + (profile.isDefault ? " (出厂基准)" : ""), systemImage: "checkmark")
                    } else {
                        Text(profile.name + (profile.isDefault ? " (出厂基准)" : ""))
                    }
                }
            }
        }

        Button("查看日志…") {
            activateAndOpen(id: "logs")
        }

        Button("运行诊断") {
            model.runDoctor()
        }
        .disabled(model.isBusy)

        Divider()

        Toggle(
            "登录时启动",
            isOn: Binding(
                get: { model.loginItemService.isEnabled },
                set: { model.loginItemService.setEnabled($0) }
            )
        )

        Button("设置…") {
            activateAndOpenSettings()
        }

        Divider()

        Button("退出 VibeJoy Bar") {
            model.processService.stop()
            NSApplication.shared.terminate(nil)
        }
    }

    private func activateAndOpen(id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func activateAndOpenSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeMain || window.canBecomeKey {
                if window.title.contains("设置") || window.title.contains("Settings") {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}
