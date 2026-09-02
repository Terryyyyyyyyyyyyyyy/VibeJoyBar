import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(model.processService.phase.title, systemImage: model.processService.phase.symbolName)

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

        SettingsLink {
            Text("设置…")
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
}
