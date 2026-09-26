import AppKit
import Foundation
import SwiftUI

@MainActor
final class HUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

public enum AgentEventKind: String, Sendable, CaseIterable {
    case taskDone = "task_done"
    case taskFail = "task_fail"
    case userAttention = "user_attention"
}

@MainActor
final class HUDFeedbackService {
    static let shared = HUDFeedbackService()

    private var panel: HUDPanel?
    private var dismissTask: Task<Void, Never>?
    private var distributedObserver: NSObjectProtocol?
    private let hudModel = HUDModel()

    @Observable
    final class HUDModel {
        enum Mode {
            case profileSwitch
            case controllerWake
            case agentEvent
        }

        var mode: Mode = .profileSwitch
        var profileName: String = "default"
        var appName: String? = nil
        var appIcon: NSImage? = nil
        var isAutoSwitch: Bool = false
        var wakeTitle: String = ""
        var wakeSubtitle: String = ""
        var isVisible: Bool = false

        var agentTitle: String = ""
        var agentSubtitle: String = ""
        var agentIcon: String = "sparkles"
        var agentColor: Color = .green
        var agentTrailingIcon: String = "checkmark.circle.fill"
    }

    private init() {
        startListening()
    }

    func startListening() {
        guard distributedObserver == nil else { return }
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.vibejoy.hud_agent_event"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let kindRaw = notification.userInfo?["kind"] as? String,
                  let kind = AgentEventKind(rawValue: kindRaw) else { return }
            let message = notification.userInfo?["message"] as? String
            Task { @MainActor [weak self] in
                self?.showAgentEvent(kind: kind, message: message)
            }
        }
    }

    func show(profileName: String, appName: String? = nil, bundleId: String? = nil, isAutoSwitch: Bool = false) {
        dismissTask?.cancel()
        dismissTask = nil

        var icon: NSImage? = nil
        if let bundleId = bundleId, !bundleId.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else if let appName = appName, !appName.isEmpty {
            let possibleAppURL = URL(fileURLWithPath: "/Applications/\(appName).app")
            if FileManager.default.fileExists(atPath: possibleAppURL.path) {
                icon = NSWorkspace.shared.icon(forFile: possibleAppURL.path)
            }
        }

        hudModel.mode = .profileSwitch
        hudModel.profileName = profileName
        hudModel.appName = appName
        hudModel.appIcon = icon
        hudModel.isAutoSwitch = isAutoSwitch

        presentHUD(durationMs: 1500)
    }

    func showControllerWake(sides: Set<String>, batteries: [ActiveControllerSide: ControllerBattery]) {
        dismissTask?.cancel()
        dismissTask = nil

        let title: String
        let subtitle: String

        if sides.count > 1 {
            title = "双持手柄已唤醒"
            if let left = batteries[.left]?.percentage, let right = batteries[.right]?.percentage, left > 0 || right > 0 {
                subtitle = "左 \(left)% · 右 \(right)% · 随时可用"
            } else if let anyBat = batteries.values.first, anyBat.percentage > 0 {
                subtitle = "电量 \(anyBat.percentage)% · 随时可用"
            } else {
                subtitle = "连接就绪 · 随时可用"
            }
        } else if sides.contains("right") {
            title = "右手柄已唤醒"
            if let bat = batteries[.right], bat.percentage > 0 {
                subtitle = "电量 \(bat.percentage)% · 随时可用"
            } else if let anyBat = batteries.values.first, anyBat.percentage > 0 {
                subtitle = "电量 \(anyBat.percentage)% · 随时可用"
            } else {
                subtitle = "连接就绪 · 随时可用"
            }
        } else {
            title = "左手柄已唤醒"
            if let bat = batteries[.left], bat.percentage > 0 {
                subtitle = "电量 \(bat.percentage)% · 随时可用"
            } else if let anyBat = batteries.values.first, anyBat.percentage > 0 {
                subtitle = "电量 \(anyBat.percentage)% · 随时可用"
            } else {
                subtitle = "连接就绪 · 随时可用"
            }
        }

        hudModel.mode = .controllerWake
        hudModel.wakeTitle = title
        hudModel.wakeSubtitle = subtitle
        hudModel.appIcon = nil

        presentHUD(durationMs: 2000)
    }

    func showAgentEvent(kind: AgentEventKind, message: String? = nil) {
        dismissTask?.cancel()
        dismissTask = nil

        hudModel.mode = .agentEvent
        switch kind {
        case .taskDone:
            hudModel.agentTitle = "AI 任务执行完成"
            hudModel.agentSubtitle = message ?? "代码生成与测试完毕"
            hudModel.agentIcon = "sparkles"
            hudModel.agentColor = .green
            hudModel.agentTrailingIcon = "checkmark.circle.fill"
        case .taskFail:
            hudModel.agentTitle = "任务执行异常"
            hudModel.agentSubtitle = message ?? "遇到错误，需要人工检查"
            hudModel.agentIcon = "exclamationmark.triangle.fill"
            hudModel.agentColor = .orange
            hudModel.agentTrailingIcon = "xmark.circle.fill"
        case .userAttention:
            hudModel.agentTitle = "等待人工确认"
            hudModel.agentSubtitle = message ?? "AI 请求用户决策或审批"
            hudModel.agentIcon = "person.wave.2.fill"
            hudModel.agentColor = .accentColor
            hudModel.agentTrailingIcon = "bell.badge.fill"
        }

        presentHUD(durationMs: 2500)
    }

    private func presentHUD(durationMs: Int) {
        ensurePanelCreated()

        guard let panel = panel else { return }

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth: CGFloat = 340
            let panelHeight: CGFloat = 64
            let x = screenFrame.midX - (panelWidth / 2)
            let y = screenFrame.maxY - panelHeight - 18
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.hudModel.isVisible = true
        }

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(durationMs))
            guard !Task.isCancelled, let self = self else { return }

            withAnimation(.easeOut(duration: 0.35)) {
                self.hudModel.isVisible = false
            }

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanelCreated() {
        guard panel == nil else { return }
        let initialRect = NSRect(x: 0, y: 0, width: 340, height: 64)
        let panel = HUDPanel(contentRect: initialRect)
        let hosting = NSHostingView(rootView: HUDContainerView(model: hudModel))
        panel.contentView = hosting
        self.panel = panel
    }
}

private struct HUDContainerView: View {
    @Bindable var model: HUDFeedbackService.HUDModel

    var body: some View {
        ZStack {
            if model.isVisible {
                HUDCapsuleView(model: model)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.88).combined(with: .opacity).combined(with: .offset(y: -16)),
                        removal: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: -6))
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HUDCapsuleView: View {
    @Bindable var model: HUDFeedbackService.HUDModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        model.mode == .controllerWake ? Color.green.opacity(0.12) :
                        model.mode == .agentEvent ? model.agentColor.opacity(0.15) :
                        Color.primary.opacity(0.08)
                    )
                    .frame(width: 32, height: 32)

                if model.mode == .agentEvent {
                    Image(systemName: model.agentIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.agentColor)
                } else if model.mode == .controllerWake {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.green)
                } else if let icon = model.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model.isAutoSwitch ? Color.accentColor : Color.primary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if model.mode == .agentEvent {
                    Text(model.agentTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(model.agentSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if model.mode == .controllerWake {
                    Text(model.wakeTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(model.wakeSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 4) {
                        Text(model.isAutoSwitch ? "已自动路由" : "已切换方案")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let appName = model.appName, !appName.isEmpty {
                            Text("· \(appName)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(model.profileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if model.mode == .agentEvent {
                Image(systemName: model.agentTrailingIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(model.agentColor)
            } else if model.mode == .controllerWake {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: model.isAutoSwitch ? "bolt.horizontal.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(model.isAutoSwitch ? Color.orange : Color.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 280, maxWidth: 330, minHeight: 48, maxHeight: 48)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
    }
}
