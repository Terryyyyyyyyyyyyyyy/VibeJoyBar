import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var action: String

    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var livePressedModifiers: Set<KeyModifier> = []
    @State private var pulseAnimation = false

    private let commonLetterKeys = (65...90).map { String(UnicodeScalar($0)) }
    private let commonDigitKeys = (0...9).map(String.init)
    private let commonSpecialKeys: [(name: String, id: String)] = [
        ("Return ⏎", "enter"),
        ("Escape ⎋", "escape"),
        ("Space ␣", "space"),
        ("Tab ⇥", "tab"),
        ("Delete ⌫", "delete"),
        ("↑ 上", "up"),
        ("↓ 下", "down"),
        ("← 左", "left"),
        ("→ 右", "right"),
    ]
    private let commonSymbols: [String] = ["[", "]", "/", "\\", "-", "=", ",", ".", "`"]
    private let commonFKeys: [String] = (1...20).map { "f\($0)" }

    private var currentModel: ShortcutKeyModel? {
        ShortcutKeyModel.parse(dsl: action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Main recording / preview card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        if isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 9, height: 9)
                                .opacity(pulseAnimation ? 1.0 : 0.3)
                                .animation(
                                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                                    value: pulseAnimation
                                )
                                .onAppear { pulseAnimation = true }
                                .onDisappear { pulseAnimation = false }

                            Text("正在录制：按下键盘任意按键或组合键…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)

                            Spacer()

                            Button("取消录制") {
                                stopRecording()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Image(systemName: "keyboard")
                                .foregroundStyle(Color.accentColor)
                            Text("按键录制与预览")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            if action != "none" && !action.isEmpty {
                                Button("清除", systemImage: "xmark.circle") {
                                    clearShortcut()
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .controlSize(.small)
                            }
                        }
                    }

                    // Key Badges display
                    HStack(spacing: 6) {
                        if isRecording {
                            if !livePressedModifiers.isEmpty {
                                ForEach(livePressedModifiers.sorted(), id: \.self) { mod in
                                    KeyBadgeView(symbol: mod.symbol, text: mod.compactName, isHighlighted: true)
                                }
                                Text("+")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("等待主键…")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 4)
                        } else if action.hasPrefix("type:") {
                            let text = String(action.dropFirst(5))
                            HStack(spacing: 6) {
                                Image(systemName: "text.cursor")
                                    .foregroundStyle(Color.accentColor)
                                Text("文本短语: \"\(text)\"")
                                    .font(.callout.weight(.medium))
                            }
                            .padding(.vertical, 4)
                        } else if let model = currentModel, !model.key.isEmpty {
                            ForEach(model.modifiers.sorted(), id: \.self) { mod in
                                KeyBadgeView(symbol: mod.symbol, text: mod.compactName)
                            }
                            if !model.modifiers.isEmpty {
                                Text("+")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            KeyBadgeView(symbol: "", text: model.displayKeySymbol, isMainKey: true)

                            if model.modifiers.isEmpty {
                                Text(model.triggerStyle.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        } else {
                            Text("未设置按键或已停用 (none)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    // Record button
                    if !isRecording {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                startRecording()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "record.circle")
                                        .font(.title3)
                                        .foregroundStyle(Color.red)
                                    Text("点击开始录制快捷键")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Text("按下键盘任意单键或组合键（如 ⌘C、⌥Space、F19 等），自动捕获并完成配置。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            } label: {
                Text("快捷键捕获").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }

            // MARK: - Trigger Style Selector
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hand.tap")
                            .foregroundStyle(Color.accentColor)
                        Text("按键触发模式")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Picker("触发方式", selection: Binding(
                        get: { currentModel?.triggerStyle ?? .tap },
                        set: { newStyle in
                            if var model = currentModel {
                                model.triggerStyle = newStyle
                                action = model.dsl
                            } else {
                                action = "\(newStyle.rawValue):enter"
                            }
                        }
                    )) {
                        ForEach(TriggerStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let model = currentModel, !model.modifiers.isEmpty {
                        Text("说明：组合键（含 ⌘/⌥/⌃/⇧）默认即时触发；长按/连发适用于单键（如 Space、Enter、方向键等）。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            } label: {
                Text("触发方式").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }

            // MARK: - Point-and-click Tuning Section
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "slider.horizontal.2.square")
                            .foregroundStyle(Color.accentColor)
                        Text("手动调节修饰键与按键")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    // Modifier Toggles in 2x2 Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(KeyModifier.allCases, id: \.self) { mod in
                            let isSelected = currentModel?.modifiers.contains(mod) ?? false
                            Toggle(isOn: Binding(
                                get: { isSelected },
                                set: { toggleModifier(mod, active: $0) }
                            )) {
                                HStack {
                                    Text(mod.compactName)
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .tint(isSelected ? Color.accentColor : Color.secondary)
                        }
                    }

                    Divider().padding(.vertical, 2)

                    // Common Key Picker
                    HStack(spacing: 10) {
                        Text("选择主键")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Menu {
                            Menu("常用功能键") {
                                ForEach(commonSpecialKeys, id: \.id) { item in
                                    Button(item.name) { selectKey(item.id) }
                                }
                            }
                            Menu("字母 (A-Z)") {
                                ForEach(commonLetterKeys, id: \.self) { char in
                                    Button(char) { selectKey(char.lowercased()) }
                                }
                            }
                            Menu("数字 (0-9)") {
                                ForEach(commonDigitKeys, id: \.self) { digit in
                                    Button(digit) { selectKey(digit) }
                                }
                            }
                            Menu("标点符号") {
                                ForEach(commonSymbols, id: \.self) { sym in
                                    Button(sym) { selectKey(sym) }
                                }
                            }
                            Menu("F 功能键 (F1-F20)") {
                                ForEach(commonFKeys, id: \.self) { fkey in
                                    Button(fkey.uppercased()) { selectKey(fkey) }
                                }
                            }
                        } label: {
                            HStack {
                                Text(currentModel?.displayKeySymbol ?? "选择按键…")
                                    .font(.caption.monospaced())
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)

                        Spacer()

                        if let dsl = currentModel?.dsl, dsl != "none" {
                            Text(dsl)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            } label: {
                Text("手动微调").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }

            // MARK: - Text Phrase Section
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.cursor")
                            .foregroundStyle(Color.accentColor)
                        Text("文本短语直发")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if action.hasPrefix("type:") {
                            Text("当前生效中")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }

                    Text("按压此按键时直接打出一串预设文本或常用短语（如邮箱、问候语、代码模板等）：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        TextField("输入要直发的文本内容…", text: Binding(
                            get: {
                                if action.hasPrefix("type:") {
                                    return String(action.dropFirst(5))
                                }
                                return ""
                            },
                            set: { newText in
                                if newText.isEmpty {
                                    action = "none"
                                } else {
                                    action = "type:\(newText)"
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        if action.hasPrefix("type:") && action != "type:" {
                            Button("清除") {
                                action = "none"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            } label: {
                Text("文本直发").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        livePressedModifiers = []

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            DispatchQueue.main.async {
                handleKeyEvent(event)
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isRecording = false
        livePressedModifiers = []
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let mods = event.vibejoyModifiers
        livePressedModifiers = mods

        if event.type == .keyDown {
            if let keyName = event.vibejoyKeyName {
                let currentStyle = currentModel?.triggerStyle ?? .tap
                let model = ShortcutKeyModel(modifiers: mods, key: keyName, triggerStyle: currentStyle)
                action = model.dsl
                stopRecording()
            }
        }
    }

    private func toggleModifier(_ modifier: KeyModifier, active: Bool) {
        var mods = currentModel?.modifiers ?? []
        let key = currentModel?.key.isEmpty == false ? currentModel!.key : "enter"
        let currentStyle = currentModel?.triggerStyle ?? .tap
        if active {
            mods.insert(modifier)
        } else {
            mods.remove(modifier)
        }
        let updated = ShortcutKeyModel(modifiers: mods, key: key, triggerStyle: currentStyle)
        action = updated.dsl
    }

    private func selectKey(_ key: String) {
        let mods = currentModel?.modifiers ?? []
        let currentStyle = currentModel?.triggerStyle ?? .tap
        let updated = ShortcutKeyModel(modifiers: mods, key: key, triggerStyle: currentStyle)
        action = updated.dsl
    }

    private func clearShortcut() {
        action = "none"
        stopRecording()
    }
}

// MARK: - Key Badge Component

struct KeyBadgeView: View {
    let symbol: String
    let text: String
    var isMainKey: Bool = false
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if !symbol.isEmpty {
                Text(symbol)
                    .font(.body.weight(.bold))
            }
            Text(text)
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted
                    ? Color.accentColor.opacity(0.2)
                    : (isMainKey ? Color.primary.opacity(0.12) : Color.primary.opacity(0.08)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isHighlighted
                    ? Color.accentColor
                    : Color.primary.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}

// MARK: - NSEvent Key Helpers

extension NSEvent {
    var vibejoyModifiers: Set<KeyModifier> {
        var mods: Set<KeyModifier> = []
        if modifierFlags.contains(.command) { mods.insert(.command) }
        if modifierFlags.contains(.option) { mods.insert(.option) }
        if modifierFlags.contains(.control) { mods.insert(.control) }
        if modifierFlags.contains(.shift) { mods.insert(.shift) }
        return mods
    }

    var vibejoyKeyName: String? {
        switch keyCode {
        case 36, 76: return "enter"
        case 48: return "tab"
        case 49: return "space"
        case 51, 117: return "delete"
        case 53: return "escape"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 115: return "home"
        case 119: return "end"
        case 116: return "page_up"
        case 121: return "page_down"
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        case 105: return "f13"
        case 107: return "f14"
        case 113: return "f15"
        case 106: return "f16"
        case 64: return "f17"
        case 79: return "f18"
        case 80: return "f19"
        case 90: return "f20"
        default: break
        }

        guard let chars = charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return nil
        }
        let first = chars.first!
        if first.isASCII && !first.isWhitespace && first.asciiValue! >= 33 && first.asciiValue! <= 126 {
            return String(first)
        }
        return nil
    }
}
