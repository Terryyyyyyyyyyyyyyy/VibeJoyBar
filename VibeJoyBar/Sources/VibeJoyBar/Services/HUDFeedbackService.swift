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

@MainActor
final class HUDFeedbackService {
    static let shared = HUDFeedbackService()

    private var panel: HUDPanel?
    private var dismissTask: Task<Void, Never>?
    private let hudModel = HUDModel()

    @Observable
    final class HUDModel {
        var profileName: String = "default"
        var appName: String? = nil
        var appIcon: NSImage? = nil
        var isAutoSwitch: Bool = false
        var isVisible: Bool = false
    }

    private init() {}

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

        hudModel.profileName = profileName
        hudModel.appName = appName
        hudModel.appIcon = icon
        hudModel.isAutoSwitch = isAutoSwitch

        ensurePanelCreated()

        guard let panel = panel else { return }

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth: CGFloat = 320
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
            try? await Task.sleep(for: .milliseconds(1500))
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
        let initialRect = NSRect(x: 0, y: 0, width: 320, height: 64)
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
                HUDCapsuleView(
                    profileName: model.profileName,
                    appName: model.appName,
                    appIcon: model.appIcon,
                    isAutoSwitch: model.isAutoSwitch
                )
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
    let profileName: String
    let appName: String?
    let appIcon: NSImage?
    let isAutoSwitch: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 32, height: 32)

                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isAutoSwitch ? Color.accentColor : Color.primary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(isAutoSwitch ? "已自动路由" : "已切换方案")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let appName = appName, !appName.isEmpty {
                        Text("· \(appName)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(profileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: isAutoSwitch ? "bolt.horizontal.fill" : "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isAutoSwitch ? Color.orange : Color.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 280, height: 48)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
    }
}
