import SwiftUI

enum ActionModeTab: String, CaseIterable, Identifiable {
    case custom = "custom"
    case presets = "presets"
    case type4me = "type4me"
    case system = "system"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom: "🎯 自定义设计"
        case .presets: "⭐️ 常用推荐"
        case .type4me: "🎙️ Type4Me"
        case .system: "🖥️ 系统与扩展"
        }
    }
}

struct CuratedPreset: Identifiable {
    let title: String
    let subtitle: String
    let action: String
    let icon: String

    var id: String { action }

    static let commonProductivity: [CuratedPreset] = [
        .init(title: "复制", subtitle: "Command + C", action: "combo:cmd+c", icon: "doc.on.doc"),
        .init(title: "粘贴", subtitle: "Command + V", action: "combo:cmd+v", icon: "doc.on.clipboard"),
        .init(title: "剪切", subtitle: "Command + X", action: "combo:cmd+x", icon: "scissors"),
        .init(title: "撤销", subtitle: "Command + Z", action: "combo:cmd+z", icon: "arrow.uturn.backward"),
        .init(title: "重做", subtitle: "Shift + Command + Z", action: "combo:cmd+shift+z", icon: "arrow.uturn.forward"),
        .init(title: "保存", subtitle: "Command + S", action: "combo:cmd+s", icon: "square.and.arrow.down"),
        .init(title: "关闭标签", subtitle: "Command + W", action: "combo:cmd+w", icon: "xmark.circle"),
        .init(title: "查找", subtitle: "Command + F", action: "combo:cmd+f", icon: "magnifyingglass"),
        .init(title: "全选", subtitle: "Command + A", action: "combo:cmd+a", icon: "selection.pin.in.out"),
        .init(title: "刷新", subtitle: "Command + R", action: "combo:cmd+r", icon: "arrow.clockwise"),
    ]

    static let type4meSuite: [CuratedPreset] = [
        .init(title: "Type4Me Prompt 优化", subtitle: "Option + 2 · 录音长按转写并重构 Prompt", action: "combo:option+2", icon: "waveform.and.mic"),
        .init(title: "Type4Me 快速润色", subtitle: "Option + 0 · 纠错语病与学术/口语润色", action: "combo:option+0", icon: "sparkles"),
        .init(title: "Type4Me 极速输出", subtitle: "Option + 1 · 原汁原味纯净转写", action: "combo:option+1", icon: "bolt.fill"),
        .init(title: "Type4Me 润色模式", subtitle: "F18 · 单键直发 Type4Me 润色", action: "tap:f18", icon: "function"),
        .init(title: "Type4Me 快速模式", subtitle: "F19 · 单键直发 Type4Me 快速转写", action: "tap:f19", icon: "function"),
    ]

    static let systemAndLayers: [CuratedPreset] = [
        .init(title: "系统 App 切换器", subtitle: "app_switcher:system · 按住后摇杆左右轮选", action: "app_switcher:system", icon: "arrow.left.arrow.right"),
        .init(title: "聚焦 Codex / ChatGPT", subtitle: "com.openai.codex · 快速呼出并聚焦", action: "window_switch:com.openai.codex", icon: "macwindow"),
        .init(title: "SL 修饰层 1", subtitle: "modifier:layer1 · 按住切换至第二套扩展动作", action: "modifier:layer1", icon: "square.2.layers.3d"),
        .init(title: "Codex 向上翻页", subtitle: "macro:codex_page_up · 向上滚动一页", action: "macro:codex_page_up", icon: "chevron.up.circle"),
        .init(title: "Codex 向下翻页", subtitle: "macro:codex_page_down · 向下滚动一页", action: "macro:codex_page_down", icon: "chevron.down.circle"),
        .init(title: "Codex 上一对话", subtitle: "macro:codex_previous_thread · 切换到上一对话", action: "macro:codex_previous_thread", icon: "arrow.backward.circle"),
        .init(title: "Codex 下一对话", subtitle: "macro:codex_next_thread · 切换到下一对话", action: "macro:codex_next_thread", icon: "arrow.forward.circle"),
        .init(title: "安全停用", subtitle: "none · 不发送任何输入", action: "none", icon: "nosign"),
    ]
}

struct MappingInspector: View {
    @Bindable var model: AppModel
    @Binding var selection: MappingSelection?
    @Binding var showingStickEditor: Bool

    @State private var activeTab: ActionModeTab = .custom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let selection {
                    inspector(selection)
                } else {
                    ContentUnavailableView("选择一个控制", systemImage: "cursorarrow.click")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18))
    }

    @ViewBuilder private func inspector(_ selected: MappingSelection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("控制检查器").font(.caption.weight(.bold)).foregroundStyle(.tertiary).tracking(1)
                if let layer = model.selectedLayer {
                    Text(layer == "layer1" ? "SL 修饰层 ◖" : "\(layer) ◖")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            Text(selectionTitle(selected)).font(.title2.weight(.bold))
            Text(purpose(for: selected)).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        let isGlobalLocked = MappingDefaults.isGlobalLockedKey(for: selected)
        let isFreed = MappingDefaults.isFreedKey(for: selected)
        let scope = model.configStore.bindingScope(for: selected, layer: model.selectedLayer, side: model.activeControllerSide)
        let isDefaultProfile = model.configStore.activeProfileName == "default"
        let baseAction = model.configStore.globalBaselineAction(for: selected, layer: model.selectedLayer, side: model.activeControllerSide)
        let currentAction = model.configStore.action(for: selected, layer: model.selectedLayer, side: model.activeControllerSide)

        // MARK: - Scope & Inheritance Box
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if model.selectedLayer != nil {
                    HStack(spacing: 6) {
                        Text(scope == .profileOverride ? "⚡️ 修饰层专属动作" : "🔒 继承自基础层")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(scope == .profileOverride ? Color.accentColor : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((scope == .profileOverride ? Color.accentColor : Color.secondary).opacity(0.12), in: Capsule())

                        Spacer()

                        if scope == .profileOverride {
                            Button("移除修饰覆盖") {
                                model.configStore.resetToGlobalDefault(selection: selected, layer: model.selectedLayer, side: model.activeControllerSide)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    Text(scope == .profileOverride
                        ? "此按键在修饰层 (\(model.selectedLayer!)) 中配置了专属动作，按住修饰键时生效。"
                        : "修饰层未单独覆盖该按键，触发时将回退执行基础层动作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isGlobalLocked {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("🔒 全局锁定键 · Type4Me 与核心操作跨方案一致生效")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    if isDefaultProfile {
                        Text("当前为全局出厂基准方案 (default)。此处的配置作为核心基准，在所有应用中统一生效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Type4Me 与系统核心按键在所有方案中默认锁定并贯穿生效，彻底杜绝配置割裂。如需调整，请前往 default 基准方案统一配置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if scope == .profileOverride {
                            HStack {
                                Text("当前检测到子方案专属定制")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("恢复全局锁定基准") {
                                    model.configStore.resetToGlobalDefault(selection: selected, layer: model.selectedLayer, side: model.activeControllerSide)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                } else if isFreed {
                    HStack(spacing: 6) {
                        Text("📱 自由释放键")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())

                        Spacer()

                        if !isDefaultProfile {
                            HStack(spacing: 4) {
                                if scope == .inheritedFromGlobal {
                                    Button {
                                        model.configStore.resetToGlobalDefault(selection: selected, layer: model.selectedLayer, side: model.activeControllerSide)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "checkmark")
                                            Text("继承全局基准")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                } else {
                                    Button {
                                        model.configStore.resetToGlobalDefault(selection: selected, layer: model.selectedLayer, side: model.activeControllerSide)
                                    } label: {
                                        Text("继承全局基准")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if scope == .profileOverride {
                                    Button {
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "checkmark")
                                            Text("为当前应用专属定制")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                } else {
                                    Button {
                                        model.configStore.setAction(currentAction, for: selected, layer: model.selectedLayer, side: model.activeControllerSide)
                                    } label: {
                                        Text("为当前应用专属定制")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    if isDefaultProfile {
                        Text("当前为全局基准方案。此处配置全局基准动作，各 App 子方案若未单独定制将默认继承此动作。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if scope == .inheritedFromGlobal {
                        Text("当前继承全局基准 (\(ActionSummary.text(for: baseAction)))，随全局方案实时同步更新。点击右侧按钮可为本应用专属定制。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("此按键已为当前方案 (\(model.configStore.activeProfileName)) 单独定制，不受全局默认值变动影响。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    if isDefaultProfile {
                        Text("当前正在配置全局基准方案。此处的改动将作为所有子方案的默认底座。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(scope == .inheritedFromGlobal ? "当前按键继承自全局基准方案。" : "已在当前方案中专属覆盖。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        } label: {
            Text("按键归属与作用域").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }

        // MARK: - Current Action Summary
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .foregroundStyle(Color.accentColor)
                    Text(ActionSummary.text(for: currentAction))
                        .font(.body.weight(.semibold))
                }
                if currentAction == "none" {
                    Text("安全停用 · 不会发送输入").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        } label: {
            Text("当前动作").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }

        // MARK: - Action Mode Tab Selector
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $activeTab) {
                ForEach(ActionModeTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch activeTab {
            case .custom:
                ShortcutRecorderView(action: actionBinding(for: selected))
            case .presets:
                presetGridView(presets: CuratedPreset.commonProductivity, selected: selected)
            case .type4me:
                presetGridView(presets: CuratedPreset.type4meSuite, selected: selected)
            case .system:
                presetGridView(presets: CuratedPreset.systemAndLayers, selected: selected)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // MARK: - Advanced Raw DSL
        DisclosureGroup("高级设置") {
            VStack(alignment: .leading, spacing: 7) {
                Text("支持原始 DSL 动作字符串").font(.caption).foregroundStyle(.secondary)
                TextField("例如 combo:cmd+s", text: actionBinding(for: selected), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

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
            Button("设为不执行") { model.configStore.setAction("none", for: selected, layer: model.selectedLayer, side: model.activeControllerSide) }
                .buttonStyle(.bordered)
            Spacer()
            Button("恢复默认") { model.configStore.setAction(MappingDefaults.action(for: selected), for: selected, layer: model.selectedLayer, side: model.activeControllerSide) }
                .buttonStyle(.bordered)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func presetGridView(presets: [CuratedPreset], selected: MappingSelection) -> some View {
        let current = model.configStore.action(for: selected, layer: model.selectedLayer, side: model.activeControllerSide)
        VStack(spacing: 6) {
            ForEach(presets) { preset in
                let isCurrent = current == preset.action
                Button {
                    model.configStore.setAction(preset.action, for: selected, layer: model.selectedLayer, side: model.activeControllerSide)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: preset.icon)
                            .font(.body)
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(preset.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isCurrent ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectionTitle(_ selected: MappingSelection) -> String {
        switch selected {
        case let .button(value):
            switch value {
            case "plus": return "+"
            case "minus": return "-"
            case "r-stick": return "R 摇杆按下"
            case "l-stick": return "L 摇杆按下"
            case "home": return "Home"
            case "capture": return "Capture"
            case "up": return model.activeControllerSide == .left ? "D-Pad ↑" : "UP"
            case "down": return model.activeControllerSide == .left ? "D-Pad ↓" : "DOWN"
            case "left": return model.activeControllerSide == .left ? "D-Pad ←" : "LEFT"
            case "right": return model.activeControllerSide == .left ? "D-Pad →" : "RIGHT"
            default: return value.uppercased()
            }
        case let .stick(value):
            return "\(model.activeControllerSide.stickLabel) · \(value.capitalized)"
        }
    }

    private func presetBinding(for selected: MappingSelection) -> Binding<String> {
        Binding(
            get: { model.configStore.action(for: selected, layer: model.selectedLayer, side: model.activeControllerSide) },
            set: { model.configStore.setAction($0, for: selected, layer: model.selectedLayer, side: model.activeControllerSide) }
        )
    }
    private func actionBinding(for selected: MappingSelection) -> Binding<String> {
        Binding(
            get: { model.configStore.action(for: selected, layer: model.selectedLayer, side: model.activeControllerSide) },
            set: { model.configStore.setAction($0, for: selected, layer: model.selectedLayer, side: model.activeControllerSide) }
        )
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
        case .button("r-stick"), .button("l-stick"): "摇杆按下"
        case .button("sl"), .button("sr"): "侧边滑轨按键"
        case .button("minus"): "减号键 (-)"
        case .button("capture"): "截图键 (Capture)"
        case .button("l"): "L 肩键"
        case .button("zl"): "ZL 扳机键"
        case .button("up"): model.activeControllerSide == .left ? "方向键上 (D-Pad Up)" : "方向键上"
        case .button("down"): model.activeControllerSide == .left ? "方向键下 (D-Pad Down)" : "方向键下"
        case .button("left"): model.activeControllerSide == .left ? "方向键左 (D-Pad Left)" : "方向键左"
        case .button("right"): model.activeControllerSide == .left ? "方向键右 (D-Pad Right)" : "方向键右"
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
            let stickList = model.activeControllerSide == .right ? model.configStore.stickBindings : model.configStore.leftStickBindings
            ForEach(Array(stickList.enumerated()), id: \.element.id) { index, binding in
                HStack {
                    Text(binding.displayName).frame(width: 35, alignment: .leading)
                    TextField("none", text: Binding(
                        get: { binding.action },
                        set: {
                            if model.activeControllerSide == .right {
                                model.configStore.setStickAction($0, at: index)
                            } else {
                                model.configStore.setLeftStickAction($0, at: index)
                            }
                        }
                    ))
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
