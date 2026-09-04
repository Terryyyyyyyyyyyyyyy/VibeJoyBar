import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("启动") {
                Toggle(
                    "打开菜单栏 App 时自动运行 VibeJoy",
                    isOn: Binding(
                        get: { model.autoRunOnLaunch },
                        set: { model.setAutoRun($0) }
                    )
                )
                Toggle(
                    "登录 Mac 时启动菜单栏 App",
                    isOn: Binding(
                        get: { model.loginItemService.isEnabled },
                        set: { model.loginItemService.setEnabled($0) }
                    )
                )
                if !model.loginItemService.statusMessage.isEmpty {
                    Text(model.loginItemService.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("路径") {
                TextField("VibeJoy 项目", text: $model.projectPath)
                TextField("配置文件", text: $model.configPath)
                TextField("uv 可执行文件", text: $model.uvPath)
                Button("应用路径") {
                    model.applyPaths()
                }
            }

            Section("说明") {
                Text("菜单栏 App 会在后台管理 VibeJoy，不需要保留终端窗口。手柄未连接时会每 8 秒自动重试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("应用版本") {
                    Text("v\(appVersion) (\(appBuild))")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Python 内核") {
                    Text("vibejoy 0.9.3")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 460)
        .padding()
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.3"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
    }
}
