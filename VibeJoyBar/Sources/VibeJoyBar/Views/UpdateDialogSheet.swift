import AppKit
import SwiftUI

/// Sheet displaying release highlights and providing a direct update download action.
struct UpdateDialogSheet: View {
    @Bindable var updateService: UpdateCheckerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("发现 VibeJoy Bar 新版本")
                        .font(.title2.weight(.bold))

                    HStack(spacing: 8) {
                        Text("当前: v\(AppPaths.appVersion)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text("最新: \(updateService.latestVersion ?? "v\(AppPaths.appVersion)")")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            // Release title & notes
            VStack(alignment: .leading, spacing: 10) {
                if let title = updateService.releaseTitle, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .padding(.top, 4)
                }

                Text("更新说明")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(updateService.releaseNotes ?? "暂无详细更新说明")
                        .font(.system(.body, design: .default))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Action footer
            HStack {
                Spacer()

                Button("稍后提醒") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if let url = updateService.releaseURL {
                    Button {
                        NSWorkspace.shared.open(url)
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text("前往下载更新")
                            Image(systemName: "arrow.up.forward.app")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 520, height: 460)
    }
}
