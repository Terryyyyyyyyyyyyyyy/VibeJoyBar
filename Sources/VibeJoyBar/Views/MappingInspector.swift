import SwiftUI

struct MappingInspector: View {
    @Bindable var model: AppModel
    @Binding var selection: MappingSelection?
    @Binding var showingStickEditor: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let selection {
                    inspector(selection)
                } else {
                    ContentUnavailableView("选择一个控制", systemImage: "cursorarrow.click")
                }
            }
            .padding(22)
        }
        .background(.quaternary.opacity(0.18))
    }

    @ViewBuilder private func inspector(_ selected: MappingSelection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("控制检查器").font(.caption.weight(.bold)).foregroundStyle(.tertiary).tracking(1)
            Text(selected.label).font(.title2.weight(.bold))
            Text(purpose(for: selected)).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .foregroundStyle(Color.accentColor)
                    Text(ActionSummary.text(for: model.configStore.action(for: selected)))
                        .font(.body.weight(.semibold))
                }
                if model.configStore.action(for: selected) == "none" {
                    Text("安全停用 · 不会发送输入").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        } label: {
            Text("当前动作").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("常用预设").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("选择预设", selection: presetBinding(for: selected)) {
                ForEach(MappingPreset.common) { preset in Text(preset.title).tag(preset.action) }
            }
            .labelsHidden()
        }

        DisclosureGroup("高级设置") {
            VStack(alignment: .leading, spacing: 7) {
                Text("支持原始 DSL 动作字符串").font(.caption).foregroundStyle(.secondary)
                TextField("例如 combo:cmd+s", text: actionBinding(for: selected), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .font(.system(.body, design: .monospaced))
            }
            .padding(.top, 5)
        }

        // Stick-specific: deadzone visualizer + editor shortcut
        if case .stick = selected {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.secondary)
                        Text("摇杆死区预览")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "死区 %.0f%%", model.configStore.deadzone * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    DeadzonePreviewView(deadzone: model.configStore.deadzone)
                        .frame(height: 110)
                    Text("红色区域内的摇杆偏移不会触发动作。在\u{201C}摇杆设置\u{201D}中可调节死区大小。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("打开摇杆设置") { showingStickEditor = true }
                .buttonStyle(.bordered)
        }

        if selected == .button("zr") {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("App 切换器操作说明", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("按住 ZR 保持 Cmd+Tab；右摇杆向右前进、向左后退。持续推杆自动步进（首次 350 ms，后续每 200 ms 连发）。松开 ZR 提交选择。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        HStack {
            Button("设为不执行") { model.configStore.setAction("none", for: selected) }
                .buttonStyle(.bordered)
            Spacer()
            Button("恢复默认") { model.configStore.setAction(MappingDefaults.action(for: selected), for: selected) }
                .buttonStyle(.bordered)
        }
        .font(.caption)
    }

    private func presetBinding(for selected: MappingSelection) -> Binding<String> {
        Binding(get: { model.configStore.action(for: selected) }, set: { model.configStore.setAction($0, for: selected) })
    }
    private func actionBinding(for selected: MappingSelection) -> Binding<String> {
        Binding(get: { model.configStore.action(for: selected) }, set: { model.configStore.setAction($0, for: selected) })
    }
    private func purpose(for selected: MappingSelection) -> String {
        switch selected {
        case .button("a"): "确认 / Enter"
        case .button("b"): "取消 / Escape"
        case .button("x"): "Type4Me 润色"
        case .button("y"): "Type4Me 快速"
        case .button("r"): "Type4Me Prompt 优化"
        case .button("zr"): "按住进入系统 App 切换 · 摇杆左右导航（支持连发）"
        case .button("plus"): "保存 / Cmd+S"
        case .button("home"): "聚焦 Codex"
        case .button("r-stick"): "摇杆按下"
        case .button("sl"), .button("sr"): "侧边肩键"
        case .button: "自定义按键动作"
        case .stick("up"): "Codex 当前对话 · 原生向上滚动约一页"
        case .stick("down"): "Codex 当前对话 · 原生向下滚动约一页"
        case .stick("left"): "Codex · 切换到上一对话"
        case .stick("right"): "Codex · 切换到下一对话"
        case .stick: "摇杆方向动作"
        }
    }
}

// MARK: - Deadzone Preview

struct DeadzonePreviewView: View {
    let deadzone: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 4
            let dz = CGFloat(deadzone)
            // Engage threshold: deadzone + 5% of remaining range
            let engageThreshold = dz + 0.05 * (1.0 - dz)

            // Outer background circle
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(.primary.opacity(0.06))
            )

            // Deadzone fill (red-tinted)
            let dzRadius = radius * dz
            if dzRadius > 0 {
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - dzRadius, y: center.y - dzRadius,
                                           width: dzRadius * 2, height: dzRadius * 2)),
                    with: .color(.red.opacity(0.18))
                )
                // Deadzone boundary ring
                var dzPath = Path()
                dzPath.addEllipse(in: CGRect(x: center.x - dzRadius, y: center.y - dzRadius,
                                              width: dzRadius * 2, height: dzRadius * 2))
                context.stroke(dzPath, with: .color(.red.opacity(0.55)), lineWidth: 1.5)
            }

            // Engage threshold ring
            let engRadius = radius * CGFloat(engageThreshold)
            var engPath = Path()
            engPath.addEllipse(in: CGRect(x: center.x - engRadius, y: center.y - engRadius,
                                           width: engRadius * 2, height: engRadius * 2))
            context.stroke(engPath, with: .color(.orange.opacity(0.6)), lineWidth: 1.0)

            // Outer boundary
            var outerPath = Path()
            outerPath.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2))
            context.stroke(outerPath, with: .color(.primary.opacity(0.18)), lineWidth: 1.0)

            // Center dot
            let dotR: CGFloat = 3
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - dotR, y: center.y - dotR,
                                       width: dotR * 2, height: dotR * 2)),
                with: .color(.primary.opacity(0.5))
            )
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.red.opacity(0.5)).frame(width: 8, height: 8)
                    Text("死区").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().strokeBorder(Color.orange.opacity(0.7), lineWidth: 1.5).frame(width: 8, height: 8)
                    Text("触发").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 2)
        }
    }
}

// MARK: - Joystick Editor Sheet

struct JoystickEditorView: View {
    @Bindable var model: AppModel
    @Binding var selection: MappingSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Codex 摇杆导航", systemImage: "circle.dotted")
                    .font(.headline)
                Spacer()
                Text("仅 Codex 前台生效").font(.caption).foregroundStyle(.secondary)
            }
            Text("上 / 下每次滚动当前对话约一页；左 / 右切换上一或下一对话。按住 ZR 时，左右方向优先用于系统 App 切换，持续推杆自动步进（首次 350 ms，后续 200 ms 连发）。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("全局死区")
                Slider(value: Binding(get: { model.configStore.deadzone }, set: { model.configStore.setDeadzone($0) }), in: 0...0.8, step: 0.01)
                Text(model.configStore.deadzone, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            DeadzonePreviewView(deadzone: model.configStore.deadzone)
                .frame(height: 120)
            ForEach(Array(model.configStore.stickBindings.enumerated()), id: \.element.id) { index, binding in
                HStack {
                    Text(binding.displayName).frame(width: 35, alignment: .leading)
                    TextField("none", text: Binding(get: { model.configStore.stickBindings[index].action }, set: { model.configStore.setStickAction($0, at: index) }))
                        .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    Button("选择") { selection = .stick(binding.direction) }.buttonStyle(.bordered)
                }
            }
            Label("自动震动未启用。此控制器不会因映射编辑产生长时间震动。", systemImage: "speaker.slash")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
