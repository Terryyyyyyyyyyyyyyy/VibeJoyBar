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

            // Action footer / Stage view
            Group {
                switch updateService.stage {
                case .ready:
                    HStack {
                        Button("稍后提醒") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Spacer()

                        if updateService.canInAppUpdate {
                            if let url = updateService.releaseURL {
                                Link("前往网页下载", destination: url)
                                    .font(.body)
                                    .padding(.trailing, 6)
                            }

                            Button {
                                Task {
                                    await updateService.startInAppUpdate()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("🚀 立即在应用内自动更新")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        } else if let url = updateService.releaseURL {
                            Link("前往网页下载更新", destination: url)
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                        }
                    }

                case .downloading(let progress, let written, let total):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text("正在高速下载新版本，请勿退出应用…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            let totalBytes = total > 0 ? total : updateService.assetSize
                            Text("\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) (\(Int(progress * 100))%)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                case .extracting:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在解压并验证安装包…")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                case .restarting:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("更新完成，正在重启 VibeJoy Bar…")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }

                case .failed(let msg):
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("更新失败：\(msg)")
                                .foregroundStyle(.red)
                                .font(.caption)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("重试") {
                            updateService.resetStage()
                        }

                        if let url = updateService.releaseURL {
                            Link("改去网页下载", destination: url)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 520, height: 460)
        .interactiveDismissDisabled(isUpdating)
    }

    private var isUpdating: Bool {
        switch updateService.stage {
        case .downloading, .extracting, .restarting:
            return true
        case .ready, .failed:
            return false
        }
    }
}
