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
        VStack(alignment: .leading, spacing: 5) {
            Text("控制检查器").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(selected.label).font(.title2.weight(.semibold))
            Text(purpose(for: selected)).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        GroupBox("当前动作") {
            VStack(alignment: .leading, spacing: 8) {
                Label(ActionSummary.text(for: model.configStore.action(for: selected)), systemImage: "command")
                    .font(.body.weight(.medium))
                if model.configStore.action(for: selected) == "none" { Text("安全停用 · 不会发送输入").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

        if case .stick = selected {
            Button("打开摇杆高级设置") { showingStickEditor = true }
                .buttonStyle(.bordered)
        }

        if selected == .button("zr") {
            Label("按住 ZR 保持 Cmd+Tab；右摇杆向右前进，向左后退。松开 ZR 提交选择。", systemImage: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack {
            Button("设为不执行") { model.configStore.setAction("none", for: selected) }
            Spacer()
            Button("恢复默认") { model.configStore.setAction(MappingDefaults.action(for: selected), for: selected) }
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
        case .button("zr"): "按住进入系统 App 切换 · 摇杆左右导航"
        case .button("plus"): "保存 / Cmd+S"
        case .button("home"): "聚焦 Codex"
        case .button("r-stick"): "摇杆按下"
        case .button("sl"), .button("sr"): "侧边肩键"
        case .button: "自定义按键动作"
        case .stick("up"): "Codex 当前对话 · 向上翻一页"
        case .stick("down"): "Codex 当前对话 · 向下翻一页"
        case .stick("left"): "Codex · 切换到上一对话"
        case .stick("right"): "Codex · 切换到下一对话"
        case .stick: "摇杆方向动作"
        }
    }
}

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
            Text("上 / 下每次翻动当前对话一页；左 / 右切换上一或下一对话。按住 ZR 时，左右方向仍优先用于系统 App 切换。所有 Codex 导航都只在 Codex 位于前台时生效。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("全局死区")
                Slider(value: Binding(get: { model.configStore.deadzone }, set: { model.configStore.setDeadzone($0) }), in: 0...0.8, step: 0.01)
                Text(model.configStore.deadzone, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().frame(width: 40, alignment: .trailing)
            }
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
