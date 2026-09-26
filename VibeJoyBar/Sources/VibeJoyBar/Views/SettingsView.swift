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

            Section("前台应用自动路由") {
                Toggle(
                    "随前台应用自动切换方案",
                    isOn: Binding(
                        get: { model.autoSwitchEnabled },
                        set: { model.setAutoSwitchEnabled($0) }
                    )
                )
                Toggle(
                    "切换方案时显示 HUD 胶囊提示",
                    isOn: Binding(
                        get: { model.hudFeedbackEnabled },
                        set: { model.setHudFeedbackEnabled($0) }
                    )
                )
                Text("当切换前台窗口时，VibeJoy 将自动激活与该应用关联的配置方案；未关联的应用将自动回退到出厂基准方案。开启 HUD 胶囊后，方案切换时将在屏幕顶部呈现优雅的灵动岛风格指示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("📳 具身触感与 Agent 协同") {
                Text("利用 Joy-Con 线性马达（HD Rumble）作为 AI Agent 执行进度的物理触感指示器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            _ = await model.processService.runOneShot(arguments: ["rumble", "task_done"])
                        }
                        HUDFeedbackService.shared.showAgentEvent(kind: .taskDone)
                    } label: {
                        Label("测试：任务完成 (task_done)", systemImage: "sparkles")
                    }

                    Button {
                        Task {
                            _ = await model.processService.runOneShot(arguments: ["rumble", "task_fail"])
                        }
                        HUDFeedbackService.shared.showAgentEvent(kind: .taskFail)
                    } label: {
                        Label("测试：任务报错 (task_fail)", systemImage: "exclamationmark.triangle.fill")
                    }

                    Button {
                        Task {
                            _ = await model.processService.runOneShot(arguments: ["rumble", "user_attention"])
                        }
                        HUDFeedbackService.shared.showAgentEvent(kind: .userAttention)
                    } label: {
                        Label("测试：人工确认 (user_attention)", systemImage: "person.wave.2.fill")
                    }
                }
                .controlSize(.regular)

                DisclosureGroup("命令行别名与 Claude Code Hook 配置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(shellAliasesText)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack {
                            Button("复制 Shell 别名") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(shellAliasesText, forType: .string)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Spacer()
                        }
                    }
                    .padding(.top, 4)
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
                    Text("vibejoy \(AppPaths.appVersion)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 680)
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

    private let shellAliasesText = """
# 快速别名配置（可在 ~/.zshrc 中添加）：
alias agy-done="vibejoy rumble task_done"
alias agy-fail="vibejoy rumble task_fail"
alias agy-ask="vibejoy rumble user_attention"
"""

    private var appVersion: String {
        AppPaths.appVersion
    }

    private var appBuild: String {
        AppPaths.appBuild
    }
}
