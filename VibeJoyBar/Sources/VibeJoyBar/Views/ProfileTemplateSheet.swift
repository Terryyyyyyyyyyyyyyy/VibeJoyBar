import SwiftUI

struct ProfileTemplateSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("官方开发者方案库")
                            .font(.title2.weight(.bold))
                    }
                    Text("开箱即用的大厂与开发环境方案，自动锁定 Type4Me 语音三件套与应用切换器")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            // Templates List
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(ProfileTemplate.allTemplates) { template in
                        templateCard(template)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 680, height: 580)
    }

    @ViewBuilder
    private func templateCard(_ template: ProfileTemplate) -> some View {
        let isActive = model.configStore.activeProfileName == template.id
        let exists = model.configStore.availableProfiles.contains(where: { $0.name == template.id })

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(template.tintColor.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: template.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(template.tintColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(template.title)
                            .font(.headline)
                        if isActive {
                            Text("当前启用")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(template.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Action Button
                if isActive {
                    Button {
                        // Already active
                    } label: {
                        Label("正在使用中", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                } else if exists {
                    Button {
                        model.importTemplate(template)
                        dismiss()
                    } label: {
                        Text("导入并启用")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        model.importTemplate(template)
                        dismiss()
                    } label: {
                        Text("一键导入并启用")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // Badges
            HStack(spacing: 6) {
                // Highlights
                ForEach(template.highlights, id: \.self) { hl in
                    let isLock = hl.contains("锁定") || hl.contains("全局锁")
                    Text(hl)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            isLock
                                ? Color.orange.opacity(0.12)
                                : template.tintColor.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .foregroundStyle(
                            isLock
                                ? Color.orange
                                : template.tintColor
                        )
                }

                Spacer()

                // Target App Chips
                HStack(spacing: 4) {
                    Text("目标:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(displayAppNames(for: template.targetApps), id: \.self) { appName in
                        Text(appName)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: isActive ? 1.5 : 1)
        )
    }

    private func displayAppNames(for bundleIds: [String]) -> [String] {
        bundleIds.compactMap { bundleId in
            switch bundleId {
            case "com.microsoft.VSCode": return "VS Code"
            case "com.microsoft.VSCodeInsiders": return "VS Code Insiders"
            case "com.cursor.Cursor", "com.todesktop.230313mzl4w4u92": return "Cursor"
            case "com.apple.dt.Xcode": return "Xcode"
            case "com.apple.Terminal": return "Terminal"
            case "com.googlecode.iterm2": return "iTerm2"
            case "com.mitchellh.ghostty": return "Ghostty"
            case "net.kovidgoyal.kitty": return "Kitty"
            case "com.google.antigravity": return "Antigravity"
            case "com.openai.codex": return "Codex"
            case "com.apple.Safari": return "Safari"
            case "com.google.Chrome": return "Chrome"
            case "company.thebrowser.Browser": return "Arc"
            case "com.microsoft.edgemac": return "Edge"
            default:
                return bundleId.components(separatedBy: ".").last
            }
        }
        // Deduplicate
        .reduce(into: [String]()) { res, name in
            if !res.contains(name) { res.append(name) }
        }
    }
}
