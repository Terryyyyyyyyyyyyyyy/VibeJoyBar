import Foundation
import Observation

enum VibeJoyConfigError: LocalizedError {
    case missingSection
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .missingSection: "配置中找不到 [profile.right.buttons]"
        case let .unreadable(message): message
        }
    }
}

@MainActor
@Observable
final class VibeJoyConfigStore {
    static let knownButtons = ["a", "b", "x", "y", "r", "zr", "plus", "home", "r-stick", "sl", "sr"]
    static let knownStickDirections = ["up", "down", "left", "right"]

    private(set) var bindings: [ButtonBinding] = []
    private(set) var stickBindings: [StickBinding] = []
    private(set) var deadzone: Double = 0.35
    private(set) var sourceText = ""
    private(set) var hasUnsavedChanges = false
    var errorMessage: String?
    var configURL: URL

    init(configURL: URL, loadImmediately: Bool = true) { self.configURL = configURL; if loadImmediately { load() } }

    func updateURL(_ url: URL) { configURL = url; load() }

    func load() {
        do {
            let originalText = try String(contentsOf: configURL, encoding: .utf8)
            // Migrate only the exact legacy defaults. Custom mappings and
            // other profiles remain byte-for-byte untouched.
            let text = Self.migrateLegacyDefaults(in: originalText)
            if text != originalText {
                try text.write(to: configURL, atomically: true, encoding: .utf8)
            }
            sourceText = text
            let buttons = Self.parseSection("profile.right.buttons", from: text)
            let sticks = Self.parseSection("profile.right.stick", from: text)
            bindings = Self.knownButtons.map { ButtonBinding(button: $0, action: buttons[$0] ?? "none") }
            stickBindings = Self.knownStickDirections.map { StickBinding(direction: $0, action: sticks[$0] ?? "none") }
            deadzone = Self.parseDeadzone(from: text) ?? 0.35
            hasUnsavedChanges = false; errorMessage = nil
        } catch {
            bindings = Self.knownButtons.map { ButtonBinding(button: $0, action: "none") }
            stickBindings = Self.knownStickDirections.map { StickBinding(direction: $0, action: "none") }
            errorMessage = "无法读取配置：\(error.localizedDescription)"
        }
    }

    func setAction(_ action: String, at index: Int) { guard bindings.indices.contains(index) else { return }; bindings[index].action = action; hasUnsavedChanges = true }
    func setStickAction(_ action: String, at index: Int) { guard stickBindings.indices.contains(index) else { return }; stickBindings[index].action = action; hasUnsavedChanges = true }
    func setDeadzone(_ value: Double) { deadzone = min(max(value, 0), 0.95); hasUnsavedChanges = true }

    func action(for selection: MappingSelection) -> String {
        switch selection {
        case let .button(button): bindings.first(where: { $0.button == button })?.action ?? "none"
        case let .stick(direction): stickBindings.first(where: { $0.direction == direction })?.action ?? "none"
        }
    }

    func setAction(_ action: String, for selection: MappingSelection) {
        switch selection {
        case let .button(button): if let index = bindings.firstIndex(where: { $0.button == button }) { setAction(action, at: index) }
        case let .stick(direction): if let index = stickBindings.firstIndex(where: { $0.direction == direction }) { setStickAction(action, at: index) }
        }
    }

    func renderedText() throws -> String {
        guard !sourceText.isEmpty else { throw VibeJoyConfigError.unreadable("当前没有可保存的配置内容") }
        var text = sourceText
        let buttons = Dictionary(uniqueKeysWithValues: bindings.map { ($0.button, normalizedAction($0.action)) })
        let sticks = Dictionary(uniqueKeysWithValues: stickBindings.map { ($0.direction, normalizedAction($0.action)) })
        text = Self.renderSection("profile.right.buttons", entries: buttons, keys: Self.knownButtons, in: text)
        text = Self.renderSection("profile.right.stick", entries: sticks, keys: Self.knownStickDirections, in: text)
        return Self.renderDeadzone(deadzone, in: text)
    }

    func commit(_ text: String) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
        sourceText = text; hasUnsavedChanges = false; errorMessage = nil
    }

    static func parseRightButtons(from text: String) -> [String: String] { parseSection("profile.right.buttons", from: text) }
    static func parseRightStick(from text: String) -> [String: String] { parseSection("profile.right.stick", from: text) }

    static func parseDeadzone(from text: String) -> Double? {
        guard let lines = sectionLines("global", from: text) else { return nil }
        for line in lines where bindingKey(in: line) == "deadzone" {
            let value = line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
            return Double(value.split(separator: "#", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        return nil
    }

    private static func migrateLegacyDefaults(in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[profile.right.buttons]" }) {
            let end = lines[(header + 1)...].firstIndex(where: { let value = $0.trimmingCharacters(in: .whitespacesAndNewlines); return value.hasPrefix("[") && value.hasSuffix("]") }) ?? lines.endIndex
            for index in (header + 1)..<end {
                guard let key = bindingKey(in: lines[index]), let value = bindingValue(in: lines[index]) else { continue }
                if key == "zr" && value == "window_switch:Codex,Google Chrome,Safari,Visual Studio Code" {
                    lines[index] = replacingValue(in: lines[index], with: "app_switcher:system")
                } else if key == "home" && value == "window_switch:Codex" {
                    lines[index] = replacingValue(in: lines[index], with: "window_switch:com.openai.codex")
                }
            }
        }

        var migratedStick = false
        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[profile.right.stick]" }) {
            let end = lines[(header + 1)...].firstIndex(where: { let value = $0.trimmingCharacters(in: .whitespacesAndNewlines); return value.hasPrefix("[") && value.hasSuffix("]") }) ?? lines.endIndex
            let defaults = [
                "up": "macro:codex_page_up",
                "down": "macro:codex_page_down",
                "left": "macro:codex_previous_thread",
                "right": "macro:codex_next_thread",
            ]
            for index in (header + 1)..<end {
                guard let key = bindingKey(in: lines[index]), let value = bindingValue(in: lines[index]), value == "none", let action = defaults[key] else { continue }
                lines[index] = replacingValue(in: lines[index], with: action)
                migratedStick = true
            }
        }

        if migratedStick {
            let macroDefinitions = [
                ("codex_page_up", "tap:page_up"),
                ("codex_page_down", "tap:page_down"),
                ("codex_previous_thread", "combo:cmd+shift+["),
                ("codex_next_thread", "combo:cmd+shift+]"),
            ]
            for (name, step) in macroDefinitions where !lines.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[macro.\(name)]" }) {
                if !lines.isEmpty, !lines.last!.isEmpty { lines.append("") }
                lines.append("[macro.\(name)]")
                lines.append("if_app = \"com.openai.codex\"")
                lines.append("steps = [\"\(step)\"]")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func normalizedAction(_ action: String) -> String { let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines); return trimmed.isEmpty ? "none" : trimmed }

    private static func parseSection(_ name: String, from text: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let lines = sectionLines(name, from: text) else { return result }
        for line in lines { if let key = bindingKey(in: line), let value = bindingValue(in: line) { result[key] = value } }
        return result
    }

    private static func sectionLines(_ name: String, from text: String) -> ArraySlice<String>? {
        let lines = text.components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[\(name)]" }) else { return nil }
        let end = lines[(header + 1)...].firstIndex(where: { let value = $0.trimmingCharacters(in: .whitespacesAndNewlines); return value.hasPrefix("[") && value.hasSuffix("]") }) ?? lines.endIndex
        return lines[(header + 1)..<end]
    }

    private static func renderSection(_ name: String, entries: [String: String], keys: [String], in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[\(name)]" }) else {
            if !lines.isEmpty, !lines.last!.isEmpty { lines.append("") }
            lines.append("[\(name)]")
            for key in keys { lines.append("\(renderedKey(key).padding(toLength: 9, withPad: " ", startingAt: 0)) = \"\(escape(entries[key] ?? "none"))\"") }
            return lines.joined(separator: "\n")
        }
        let end = lines[(header + 1)...].firstIndex(where: { let value = $0.trimmingCharacters(in: .whitespacesAndNewlines); return value.hasPrefix("[") && value.hasSuffix("]") }) ?? lines.endIndex
        var seen = Set<String>()
        for index in (header + 1)..<end {
            guard let key = bindingKey(in: lines[index]), let action = entries[key] else { continue }
            lines[index] = replacingValue(in: lines[index], with: action); seen.insert(key)
        }
        var insertAt = end
        for key in keys where !seen.contains(key) {
            lines.insert("\(renderedKey(key).padding(toLength: 9, withPad: " ", startingAt: 0)) = \"\(escape(entries[key] ?? "none"))\"", at: insertAt); insertAt += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func renderDeadzone(_ value: Double, in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[global]" }) else { return source }
        let end = lines[(header + 1)...].firstIndex(where: { let value = $0.trimmingCharacters(in: .whitespacesAndNewlines); return value.hasPrefix("[") && value.hasSuffix("]") }) ?? lines.endIndex
        for index in (header + 1)..<end where bindingKey(in: lines[index]) == "deadzone" { lines[index] = replacingScalarValue(in: lines[index], with: String(format: "%.2f", value)); return lines.joined(separator: "\n") }
        lines.insert("deadzone       = \(String(format: "%.2f", value))", at: header + 1)
        return lines.joined(separator: "\n")
    }

    private static func renderedKey(_ key: String) -> String { key.contains("-") ? "\"\(key)\"" : key }

    private static func bindingKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
        var key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
        if key.hasPrefix("\"") && key.hasSuffix("\"") { key.removeFirst(); key.removeLast() }
        return key.isEmpty ? nil : key.lowercased()
    }

    private static func bindingValue(in line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let tail = line[line.index(after: equals)...]
        guard let firstQuote = tail.firstIndex(of: "\"") else { return nil }
        var cursor = tail.index(after: firstQuote); var escaped = false
        while cursor < tail.endIndex {
            let character = tail[cursor]
            if character == "\"" && !escaped { let raw = String(tail[tail.index(after: firstQuote)..<cursor]); return raw.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
            escaped = character == "\\" && !escaped; if character != "\\" { escaped = false }; cursor = tail.index(after: cursor)
        }
        return nil
    }

    private static func replacingValue(in line: String, with action: String) -> String {
        guard let equals = line.firstIndex(of: "=") else { return line }
        guard let firstQuote = line[line.index(after: equals)...].firstIndex(of: "\"") else { return line }
        var cursor = line.index(after: firstQuote); var escaped = false
        while cursor < line.endIndex {
            let character = line[cursor]
            if character == "\"" && !escaped { var updated = line; updated.replaceSubrange(firstQuote...cursor, with: "\"\(escape(action))\""); return updated }
            escaped = character == "\\" && !escaped; if character != "\\" { escaped = false }; cursor = line.index(after: cursor)
        }
        return line
    }

    private static func replacingScalarValue(in line: String, with value: String) -> String {
        guard let equals = line.firstIndex(of: "=") else { return line }
        let prefix = String(line[..<line.index(after: equals)]); let tail = line[line.index(after: equals)...]
        let comment = tail.firstIndex(of: "#").map { String(tail[$0...]) } ?? ""
        return "\(prefix) \(value)\(comment.isEmpty ? "" : "   \(comment)")"
    }

    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}
