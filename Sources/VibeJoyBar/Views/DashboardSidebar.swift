import SwiftUI

struct DashboardSidebar: View {
    @Bindable var model: AppModel
    @Binding var selection: MappingSelection?
    @Binding var showingStickEditor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactHeader
            Divider().padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    mappingGroup("FACE", icon: "circle.grid.2x2.fill", buttons: ["a", "b", "x", "y"])
                    mappingGroup("SHOULDER", icon: "rectangle.topthird.inset.filled", buttons: ["r", "zr", "sl", "sr"])
                    mappingGroup("SYSTEM", icon: "command", buttons: ["plus", "home", "r-stick"])
                    VStack(alignment: .leading, spacing: 7) {
                        sectionTitle("CODEX NAVIGATION", icon: "circle.dotted")
                        ForEach(model.configStore.stickBindings) { binding in
                            stickRow(binding)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            // Pinned footer — always visible regardless of scroll position
            Divider()
            Button { showingStickEditor = true } label: {
                Label("摇杆灵敏度与高级设置", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 21)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.bar)
    }

    private func stickRow(_ binding: StickBinding) -> some View {
        let selected = selection == .stick(binding.direction)
        return Button {
            selection = .stick(binding.direction)
            showingStickEditor = false
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 16)

                Image(systemName: stickSymbol(binding.direction))
                    .font(.system(size: 11, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .frame(width: 18)

                Text(ActionSummary.text(for: binding.action))
                    .font(.caption)
                    .foregroundStyle(selected ? Color.primary.opacity(0.85) : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func stickSymbol(_ direction: String) -> String {
        switch direction {
        case "up": "arrow.up"
        case "down": "arrow.down"
        case "left": "arrow.left"
        default: "arrow.right"
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 30, height: 30)
                .background(statusColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("右 Joy-Con").font(.headline)
                Text(model.processService.phase.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 18)
    }

    @ViewBuilder private func mappingGroup(_ title: String, icon: String, buttons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle(title, icon: icon)
            ForEach(buttons, id: \.self) { button in
                mappingRow(button)
            }
        }
    }

    private func mappingRow(_ button: String) -> some View {
        let item = model.configStore.bindings.first(where: { $0.button == button })
        let selected = selection == .button(button)
        return Button {
            selection = .button(button)
            showingStickEditor = false
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 16)

                Text(item?.displayName ?? button.uppercased())
                    .font(.body.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .frame(width: 50, alignment: .leading)

                Text(ActionSummary.text(for: item?.action ?? "none"))
                    .font(.caption)
                    .foregroundStyle(selected ? Color.primary.opacity(0.85) : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("编辑 \(item?.displayName ?? button.uppercased())")
        .accessibilityValue(ActionSummary.text(for: item?.action ?? "none"))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 9)
    }

    private var statusColor: Color {
        switch model.processService.phase {
        case .running: .green
        case .failed: .red
        case .stopped: .secondary
        default: .orange
        }
    }
}
