import AppKit
import Foundation

struct ButtonBinding: Identifiable, Equatable {
    let button: String
    var action: String

    var id: String { button }

    var displayName: String {
        switch button {
        case "plus": "+"
        case "minus": "-"
        case "r-stick": "R 摇杆"
        case "l-stick": "L 摇杆"
        case "capture": "截图"
        case "up": "↑ (X)"
        case "down": "↓ (B)"
        case "left": "← (Y)"
        case "right": "→ (A)"
        default: button.uppercased()
        }
    }
}

struct StickBinding: Identifiable, Equatable {
    let direction: String
    var action: String

    var id: String { direction }

    var displayName: String {
        switch direction {
        case "up": "上"
        case "down": "下"
        case "left": "左"
        case "right": "右"
        default: direction.capitalized
        }
    }
}

enum ActionSummary {
    static func text(for action: String) -> String {
        let value = action.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "none" { return "已停用" }
        if value == "app_switcher:system" { return "按住 · 系统 App 切换" }
        if value == "macro:codex_page_up" { return "Codex · 当前对话向上滚动" }
        if value == "macro:codex_page_down" { return "Codex · 当前对话向下滚动" }
        if value == "macro:codex_previous_thread" { return "Codex · 上一对话" }
        if value == "macro:codex_next_thread" { return "Codex · 下一对话" }
        if value.hasPrefix("tap:") { return "按一下 · \(keyName(String(value.dropFirst(4))))" }
        if value.hasPrefix("hold:") { return "按住 · \(keyName(String(value.dropFirst(5))))" }
        if value.hasPrefix("combo:") {
            let keys = String(value.dropFirst(6)).split(separator: "+").map { keyName(String($0)) }
            return "组合键 · \(keys.joined(separator: " + "))"
        }
        if value.hasPrefix("repeat:") {
            let spec = String(value.dropFirst(7))
            let parts = spec.split(separator: "@")
            let key = keyName(String(parts[0]))
            return "连发 · \(key)"
        }
        if value.hasPrefix("window_switch:") {
            let app = String(value.dropFirst(14)).split(separator: ",").first.map(String.init) ?? "应用"
            return "聚焦 · \(app)"
        }
        if value.hasPrefix("type:") {
            let text = String(value.dropFirst(5))
            return text.isEmpty ? "输入文字" : "输入文字 · \"\(text)\""
        }
        if value.hasPrefix("shell:") { return "运行脚本" }
        if value.hasPrefix("modifier:") {
            let spec = String(value.dropFirst(9))
            let parts = spec.split(separator: "?", maxSplits: 1)
            let layer = String(parts[0])
            if parts.count > 1 {
                let fallback = String(parts[1])
                return "物理修饰层 · \(layer) (\(ActionSummary.text(for: fallback)))"
            }
            return "物理修饰层 · \(layer)"
        }
        return value
    }

    private static func keyName(_ key: String) -> String {
        switch key.lowercased() {
        case "cmd": "⌘"
        case "option", "alt": "⌥"
        case "shift": "⇧"
        case "ctrl", "control": "⌃"
        case "enter", "return": "Enter"
        case "escape", "esc": "Esc"
        default: key.uppercased()
        }
    }
}

enum MappingSelection: Hashable {
    case button(String)
    case stick(String)

    var label: String {
        switch self {
        case let .button(value): value == "plus" ? "Plus" : value.uppercased()
        case let .stick(value): "摇杆 · \(value.capitalized)"
        }
    }
}

enum MappingDefaults {
    static func action(for selection: MappingSelection) -> String {
        switch selection {
        case .button("a"), .button("right"): "tap:enter"
        case .button("b"), .button("down"): "tap:escape"
        case .button("x"), .button("up"): "combo:option+0"
        case .button("y"), .button("left"): "combo:option+1"
        case .button("r"), .button("l"): "combo:option+2"
        case .button("zr"), .button("zl"): "app_switcher:system"
        case .button("plus"), .button("minus"): "combo:cmd+s"
        case .button("home"), .button("capture"): "window_switch:com.openai.codex"
        case .stick("up"): "macro:codex_page_up"
        case .stick("down"): "macro:codex_page_down"
        case .stick("left"): "macro:codex_previous_thread"
        case .stick("right"): "macro:codex_next_thread"
        case .button("r-stick"), .button("l-stick"), .button("sl"), .button("sr"): "none"
        case .stick: "none"
        case .button: "none"
        }
    }

    static func isGlobalLockedKey(for selection: MappingSelection) -> Bool {
        switch selection {
        case .button("r"), .button("x"), .button("y"), .button("zr"), .button("a"), .button("b"),
             .button("l"), .button("up"), .button("left"), .button("zl"), .button("right"), .button("down"):
            return true
        default:
            return false
        }
    }

    static func isFreedKey(for selection: MappingSelection) -> Bool {
        switch selection {
        case .stick("up"), .stick("down"), .stick("left"), .stick("right"):
            return true
        case .button("plus"), .button("minus"), .button("home"), .button("capture"),
             .button("sl"), .button("sr"), .button("r-stick"), .button("l-stick"):
            return true
        default:
            return false
        }
    }

    static func isRecommendedGlobalKey(for selection: MappingSelection) -> Bool {
        switch selection {
        case .button("a"), .button("b"), .button("x"), .button("y"), .button("r"), .button("zr"), .button("plus"),
             .button("right"), .button("down"), .button("up"), .button("left"), .button("l"), .button("zl"), .button("minus"):
            return true
        case .stick("up"), .stick("down"):
            return true
        default:
            return false
        }
    }
}

enum KeyModifier: String, CaseIterable, Comparable, Hashable, Sendable {
    case command = "cmd"
    case option = "option"
    case control = "ctrl"
    case shift = "shift"

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    var displayName: String {
        switch self {
        case .command: return "Command"
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        }
    }

    var compactName: String {
        switch self {
        case .command: return "⌘ Cmd"
        case .option: return "⌥ Opt"
        case .control: return "⌃ Ctrl"
        case .shift: return "⇧ Shift"
        }
    }

    var standardDslName: String {
        rawValue
    }

    private var sortOrder: Int {
        switch self {
        case .command: return 0
        case .option: return 1
        case .control: return 2
        case .shift: return 3
        }
    }

    static func < (lhs: KeyModifier, rhs: KeyModifier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

enum TriggerStyle: String, CaseIterable, Identifiable, Sendable {
    case tap = "tap"
    case hold = "hold"
    case `repeat` = "repeat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tap: return "单击 (tap)"
        case .hold: return "长按 (hold)"
        case .repeat: return "连发 (repeat)"
        }
    }
}

struct ShortcutKeyModel: Equatable, Hashable, Sendable {
    var modifiers: Set<KeyModifier>
    var key: String
    var triggerStyle: TriggerStyle

    init(modifiers: Set<KeyModifier> = [], key: String = "", triggerStyle: TriggerStyle = .tap) {
        self.modifiers = modifiers
        self.key = Self.normalizeKey(key)
        self.triggerStyle = triggerStyle
    }

    static func normalizeKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "return": return "enter"
        case "esc": return "escape"
        case "del", "backspace": return "delete"
        case "opt", "alt": return "option"
        default: return trimmed
        }
    }

    var displayKeySymbol: String {
        Self.displaySymbol(for: key)
    }

    static func displaySymbol(for key: String) -> String {
        let norm = normalizeKey(key)
        switch norm {
        case "space": return "␣ Space"
        case "enter": return "⏎ Return"
        case "escape": return "⎋ Esc"
        case "tab": return "⇥ Tab"
        case "delete": return "⌫ Delete"
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        default:
            if norm.hasPrefix("f") && norm.count > 1, let num = Int(norm.dropFirst()) {
                return "F\(num)"
            }
            return norm.uppercased()
        }
    }

    var dsl: String {
        let cleanKey = Self.normalizeKey(key)
        if cleanKey.isEmpty || cleanKey == "none" {
            return "none"
        }
        if modifiers.isEmpty {
            switch triggerStyle {
            case .tap:
                return "tap:\(cleanKey)"
            case .hold:
                return "hold:\(cleanKey)"
            case .repeat:
                return "repeat:\(cleanKey)"
            }
        }
        let sortedMods = modifiers.sorted().map(\.standardDslName)
        return "combo:\((sortedMods + [cleanKey]).joined(separator: "+"))"
    }

    static func parse(dsl: String) -> ShortcutKeyModel? {
        let trimmed = dsl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "none" {
            return nil
        }
        if trimmed.hasPrefix("tap:") {
            let key = String(trimmed.dropFirst(4))
            return ShortcutKeyModel(modifiers: [], key: key, triggerStyle: .tap)
        }
        if trimmed.hasPrefix("hold:") {
            let key = String(trimmed.dropFirst(5))
            return ShortcutKeyModel(modifiers: [], key: key, triggerStyle: .hold)
        }
        if trimmed.hasPrefix("repeat:") {
            let payload = String(trimmed.dropFirst(7))
            let key = payload.split(separator: "@").first.map(String.init) ?? payload
            return ShortcutKeyModel(modifiers: [], key: key, triggerStyle: .repeat)
        }
        if trimmed.hasPrefix("combo:") {
            let payload = String(trimmed.dropFirst(6))
            let parts = payload.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            var mods: Set<KeyModifier> = []
            var mainKey = ""
            for part in parts {
                if let mod = modifierFrom(string: part) {
                    mods.insert(mod)
                } else {
                    mainKey = part
                }
            }
            return ShortcutKeyModel(modifiers: mods, key: mainKey, triggerStyle: .tap)
        }
        return nil
    }

    private static func modifierFrom(string: String) -> KeyModifier? {
        switch string.lowercased() {
        case "cmd", "command": return .command
        case "opt", "option", "alt": return .option
        case "ctrl", "control": return .control
        case "shift": return .shift
        default: return nil
        }
    }
}

enum BindingScope {
    case globalBaseline      // Currently in default.toml
    case inheritedFromGlobal // In sub-profile, value matches global default
    case profileOverride     // In sub-profile, custom value overrides global
}

struct MappingPreset: Identifiable {
    let title: String
    let action: String

    var id: String { action }

    static let common: [MappingPreset] = [
        .init(title: "不执行", action: "none"),
        .init(title: "确认 Enter", action: "tap:enter"),
        .init(title: "取消 Esc", action: "tap:escape"),
        .init(title: "保存 Cmd+S", action: "combo:cmd+s"),
        .init(title: "撤销 Cmd+Z", action: "combo:cmd+z"),
        .init(title: "重做 Cmd+Shift+Z", action: "combo:cmd+shift+z"),
        .init(title: "Type4Me 润色 Option+0", action: "combo:option+0"),
        .init(title: "Type4Me 快速 Option+1", action: "combo:option+1"),
        .init(title: "Type4Me Prompt 优化 Option+2", action: "combo:option+2"),
        .init(
            title: "系统 App 切换（按住 ZR）",
            action: "app_switcher:system"
        ),
        .init(title: "SL 修饰层 1 (按住切换第二套按键)", action: "modifier:layer1"),
        .init(title: "聚焦 Codex / ChatGPT", action: "window_switch:com.openai.codex"),
        .init(title: "Codex 对话向上翻页", action: "macro:codex_page_up"),
        .init(title: "Codex 对话向下翻页", action: "macro:codex_page_down"),
        .init(title: "Codex 上一对话", action: "macro:codex_previous_thread"),
        .init(title: "Codex 下一对话", action: "macro:codex_next_thread"),
        .init(title: "Type4Me 润色 F18", action: "tap:f18"),
        .init(title: "Type4Me 快速 F19", action: "tap:f19"),
    ]
}

/// Which Joy-Con side the control panel is currently showing.
enum ActiveControllerSide: String, CaseIterable, Hashable {
    case right = "right"
    case left  = "left"

    var displayName: String { self == .right ? "右 Joy-Con" : "左 Joy-Con" }
    var stickLabel: String  { self == .right ? "R 摇杆" : "L 摇杆" }
    var stickButtonID: String { self == .right ? "r-stick" : "l-stick" }
}

struct ControllerBattery: Equatable, Sendable {
    let level: Int
    let percentage: Int
    let isCharging: Bool

    var symbolName: String {
        if isCharging {
            return "battery.100.bolt"
        }
        switch percentage {
        case 88...100: return "battery.100"
        case 63..<88:  return "battery.75"
        case 38..<63:  return "battery.50"
        case 13..<38:  return "battery.25"
        default:       return "battery.0"
        }
    }

    var isLowBattery: Bool {
        percentage <= 20 && !isCharging
    }
}

enum VibeJoyPhase: Equatable {
    case stopped
    case starting
    case waitingForController
    case needsAccessibility
    case running(String)
    case failed(String)

    var title: String {
        switch self {
        case .stopped: "已停止"
        case .starting: "正在启动"
        case .waitingForController: "等待 Joy-Con"
        case .needsAccessibility: "需要辅助功能权限"
        case let .running(side): "运行中 · \(side)"
        case let .failed(message): "异常 · \(message)"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "gamecontroller.fill"
        case .starting, .waitingForController: "gamecontroller"
        case .needsAccessibility: "keyboard.badge.ellipsis"
        case .failed: "exclamationmark.triangle"
        case .stopped: "gamecontroller"
        }
    }

    var tintName: String {
        switch self {
        case .running: "green"
        case .starting, .waitingForController, .needsAccessibility: "orange"
        case .failed: "red"
        case .stopped: "secondary"
        }
    }
}

struct CommandResult: Sendable {
    let exitCode: Int32
    let output: String
}

struct ProfileItem: Identifiable, Hashable, Equatable, Sendable {
    let name: String
    let isDefault: Bool
    let isActive: Bool
    let fileURL: URL
    let targetApps: [String]

    var id: String { name }

    init(name: String, isDefault: Bool, isActive: Bool, fileURL: URL, targetApps: [String] = []) {
        self.name = name
        self.isDefault = isDefault
        self.isActive = isActive
        self.fileURL = fileURL
        self.targetApps = targetApps
    }
}

struct RunningAppItem: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    let bundleIdentifier: String
    let localizedName: String
    let icon: NSImage?

    init(id: String, bundleIdentifier: String, localizedName: String, icon: NSImage? = nil) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.icon = icon
    }
}
