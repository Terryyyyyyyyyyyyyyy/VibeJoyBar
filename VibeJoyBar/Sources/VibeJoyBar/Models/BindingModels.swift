import Foundation

struct ButtonBinding: Identifiable, Equatable {
    let button: String
    var action: String

    var id: String { button }

    var displayName: String {
        switch button {
        case "plus": "+"
        case "r-stick": "R 摇杆"
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
        if value.hasPrefix("window_switch:") {
            let app = String(value.dropFirst(14)).split(separator: ",").first.map(String.init) ?? "应用"
            return "聚焦 · \(app)"
        }
        if value.hasPrefix("type:") { return "输入文字" }
        if value.hasPrefix("shell:") { return "运行脚本" }
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
        case let .stick(value): "R 摇杆 · \(value.capitalized)"
        }
    }
}

enum MappingDefaults {
    static func action(for selection: MappingSelection) -> String {
        switch selection {
        case .button("a"): "tap:enter"
        case .button("b"): "tap:escape"
        case .button("x"): "combo:option+0"
        case .button("y"): "combo:option+1"
        case .button("r"): "combo:option+2"
        case .button("zr"): "app_switcher:system"
        case .button("plus"): "combo:cmd+s"
        case .button("home"): "window_switch:com.openai.codex"
        case .stick("up"): "macro:codex_page_up"
        case .stick("down"): "macro:codex_page_down"
        case .stick("left"): "macro:codex_previous_thread"
        case .stick("right"): "macro:codex_next_thread"
        case .button("r-stick"), .button("sl"), .button("sr"): "none"
        case .stick: "none"
        case .button: "none"
        }
    }
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
        .init(title: "聚焦 Codex / ChatGPT", action: "window_switch:com.openai.codex"),
        .init(title: "Codex 对话向上翻页", action: "macro:codex_page_up"),
        .init(title: "Codex 对话向下翻页", action: "macro:codex_page_down"),
        .init(title: "Codex 上一对话", action: "macro:codex_previous_thread"),
        .init(title: "Codex 下一对话", action: "macro:codex_next_thread"),
        .init(title: "Type4Me 润色 F18", action: "tap:f18"),
        .init(title: "Type4Me 快速 F19", action: "tap:f19"),
    ]
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

    var id: String { name }
}
