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
    static let knownLeftButtons = ["right", "down", "up", "left", "l", "zl", "minus", "capture", "l-stick", "sl", "sr"]
    static let knownStickDirections = ["up", "down", "left", "right"]

    private(set) var bindings: [ButtonBinding] = []
    private(set) var stickBindings: [StickBinding] = []
    private(set) var leftBindings: [ButtonBinding] = []
    private(set) var leftStickBindings: [StickBinding] = []
    private(set) var deadzone: Double = 0.35
    private(set) var sourceText = ""
    private(set) var hasUnsavedChanges = false
    private(set) var activeProfileName: String = "default"
    private(set) var availableProfiles: [ProfileItem] = []
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

            let leftButtons = Self.parseSection("profile.left.buttons", from: text)
            let leftSticks = Self.parseSection("profile.left.stick", from: text)
            leftBindings = Self.knownLeftButtons.map { ButtonBinding(button: $0, action: leftButtons[$0] ?? "none") }
            leftStickBindings = Self.knownStickDirections.map { StickBinding(direction: $0, action: leftSticks[$0] ?? "none") }

            deadzone = Self.parseDeadzone(from: text) ?? 0.35
            hasUnsavedChanges = false; errorMessage = nil
        } catch {
            bindings = Self.knownButtons.map { ButtonBinding(button: $0, action: "none") }
            stickBindings = Self.knownStickDirections.map { StickBinding(direction: $0, action: "none") }
            leftBindings = Self.knownLeftButtons.map { ButtonBinding(button: $0, action: "none") }
            leftStickBindings = Self.knownStickDirections.map { StickBinding(direction: $0, action: "none") }
            errorMessage = "无法读取配置：\(error.localizedDescription)"
        }
        refreshProfiles()
    }

    func refreshProfiles() {
        let fileManager = FileManager.default
        let baseDir = configURL.deletingLastPathComponent()
        let activeProfileFile = baseDir.appendingPathComponent("active_profile")
        var currentActive = "default"
        if fileManager.fileExists(atPath: activeProfileFile.path),
           let content = try? String(contentsOf: activeProfileFile, encoding: .utf8) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.contains("\\") && !trimmed.contains("..") && !trimmed.hasPrefix(".") {
                currentActive = trimmed
            }
        }

        let profilesDir = baseDir.appendingPathComponent("profiles")
        var items: [ProfileItem] = []
        if let urls = try? fileManager.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension == "toml" {
                let name = url.deletingPathExtension().lastPathComponent
                let isDefault = (name == "default")
                let isActive = (name == currentActive)
                items.append(ProfileItem(name: name, isDefault: isDefault, isActive: isActive, fileURL: url))
            }
        }

        if !items.contains(where: { $0.name == "default" }) {
            let defaultURL = profilesDir.appendingPathComponent("default.toml")
            items.append(ProfileItem(name: "default", isDefault: true, isActive: currentActive == "default", fileURL: defaultURL))
        }

        items.sort { a, b in
            if a.name == "default" { return true }
            if b.name == "default" { return false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        availableProfiles = items
        activeProfileName = currentActive
    }

    func setAction(_ action: String, at index: Int) { guard bindings.indices.contains(index) else { return }; bindings[index].action = action; hasUnsavedChanges = true }
    func setStickAction(_ action: String, at index: Int) { guard stickBindings.indices.contains(index) else { return }; stickBindings[index].action = action; hasUnsavedChanges = true }
    func setLeftAction(_ action: String, at index: Int) { guard leftBindings.indices.contains(index) else { return }; leftBindings[index].action = action; hasUnsavedChanges = true }
    func setLeftStickAction(_ action: String, at index: Int) { guard leftStickBindings.indices.contains(index) else { return }; leftStickBindings[index].action = action; hasUnsavedChanges = true }
    func setDeadzone(_ value: Double) { deadzone = min(max(value, 0), 0.95); hasUnsavedChanges = true }

    func action(for selection: MappingSelection, side: ActiveControllerSide = .right) -> String {
        switch selection {
        case let .button(button):
            let list = (side == .right ? bindings : leftBindings)
            return list.first(where: { $0.button == button })?.action ?? "none"
        case let .stick(direction):
            let list = (side == .right ? stickBindings : leftStickBindings)
            return list.first(where: { $0.direction == direction })?.action ?? "none"
        }
    }

    func setAction(_ action: String, for selection: MappingSelection, side: ActiveControllerSide = .right) {
        switch selection {
        case let .button(button):
            if side == .right {
                if let index = bindings.firstIndex(where: { $0.button == button }) { setAction(action, at: index) }
            } else {
                if let index = leftBindings.firstIndex(where: { $0.button == button }) { setLeftAction(action, at: index) }
            }
        case let .stick(direction):
            if side == .right {
                if let index = stickBindings.firstIndex(where: { $0.direction == direction }) { setStickAction(action, at: index) }
            } else {
                if let index = leftStickBindings.firstIndex(where: { $0.direction == direction }) { setLeftStickAction(action, at: index) }
            }
        }
    }

    func renderedText() throws -> String {
        guard !sourceText.isEmpty else { throw VibeJoyConfigError.unreadable("当前没有可保存的配置内容") }
        var text = sourceText
        let buttons = Dictionary(uniqueKeysWithValues: bindings.map { ($0.button, normalizedAction($0.action)) })
        let sticks = Dictionary(uniqueKeysWithValues: stickBindings.map { ($0.direction, normalizedAction($0.action)) })
        text = Self.renderSection("profile.right.buttons", entries: buttons, keys: Self.knownButtons, in: text)
        text = Self.renderSection("profile.right.stick", entries: sticks, keys: Self.knownStickDirections, in: text)

        let leftButtons = Dictionary(uniqueKeysWithValues: leftBindings.map { ($0.button, normalizedAction($0.action)) })
        let leftSticks = Dictionary(uniqueKeysWithValues: leftStickBindings.map { ($0.direction, normalizedAction($0.action)) })
        text = Self.renderSection("profile.left.buttons", entries: leftButtons, keys: Self.knownLeftButtons, in: text)
        text = Self.renderSection("profile.left.stick", entries: leftSticks, keys: Self.knownStickDirections, in: text)

        return Self.renderDeadzone(deadzone, in: text)
    }

    func commit(_ text: String) throws {
        let fileManager = FileManager.default
        let baseDir = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try text.write(to: configURL, atomically: true, encoding: .utf8)

        if activeProfileName != "default" {
            let profilesDir = baseDir.appendingPathComponent("profiles")
            try fileManager.createDirectory(at: profilesDir, withIntermediateDirectories: true)
            let profileURL = profilesDir.appendingPathComponent("\(activeProfileName).toml")
            try text.write(to: profileURL, atomically: true, encoding: .utf8)
        }

        sourceText = text; hasUnsavedChanges = false; errorMessage = nil
        refreshProfiles()
    }

    private func createBackupOfCurrentConfig() throws {
        let fileManager = FileManager.default
        let existingContent: String?
        if fileManager.fileExists(atPath: configURL.path),
           let text = try? String(contentsOf: configURL, encoding: .utf8),
           !text.isEmpty {
            existingContent = text
        } else if !sourceText.isEmpty {
            existingContent = sourceText
        } else {
            existingContent = nil
        }

        if let content = existingContent {
            let backupsDir = configURL.deletingLastPathComponent().appendingPathComponent("backups")
            try fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            var backupURL = backupsDir.appendingPathComponent("config.\(formatter.string(from: Date())).bak.toml")
            if fileManager.fileExists(atPath: backupURL.path) {
                formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
                backupURL = backupsDir.appendingPathComponent("config.\(formatter.string(from: Date())).bak.toml")
            }
            try content.write(to: backupURL, atomically: true, encoding: .utf8)
        }
    }

    func saveAsNewProfile(named rawName: String) throws {
        let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !cleanName.hasPrefix("."),
              !cleanName.contains("/"),
              !cleanName.contains("\\"),
              !cleanName.contains("..") else {
            throw VibeJoyConfigError.unreadable("无效的方案名称：'\(rawName)'")
        }

        let fileManager = FileManager.default
        let baseDir = configURL.deletingLastPathComponent()
        let profilesDir = baseDir.appendingPathComponent("profiles")
        try fileManager.createDirectory(at: profilesDir, withIntermediateDirectories: true)

        let targetURL = profilesDir.appendingPathComponent("\(cleanName).toml")
        let text = try renderedText()
        try text.write(to: targetURL, atomically: true, encoding: .utf8)

        let activeProfileURL = baseDir.appendingPathComponent("active_profile")
        try cleanName.write(to: activeProfileURL, atomically: true, encoding: .utf8)

        try text.write(to: configURL, atomically: true, encoding: .utf8)
        activeProfileName = cleanName
        load()
    }

    func switchToProfile(named name: String) throws {
        let fileManager = FileManager.default
        let baseDir = configURL.deletingLastPathComponent()
        let profilesDir = baseDir.appendingPathComponent("profiles")
        let targetURL = profilesDir.appendingPathComponent("\(name).toml")

        let targetText: String
        if fileManager.fileExists(atPath: targetURL.path) {
            targetText = try String(contentsOf: targetURL, encoding: .utf8)
        } else if name == "default" {
            if fileManager.fileExists(atPath: AppPaths.defaultProfileURL.path),
               let text = try? String(contentsOf: AppPaths.defaultProfileURL, encoding: .utf8),
               !text.isEmpty {
                targetText = text
            } else {
                targetText = Self.fallbackDefaultConfig
            }
            try fileManager.createDirectory(at: profilesDir, withIntermediateDirectories: true)
            try targetText.write(to: targetURL, atomically: true, encoding: .utf8)
        } else {
            throw VibeJoyConfigError.unreadable("方案不存在：\(name)")
        }

        try createBackupOfCurrentConfig()

        try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try targetText.write(to: configURL, atomically: true, encoding: .utf8)

        let activeProfileURL = baseDir.appendingPathComponent("active_profile")
        try name.write(to: activeProfileURL, atomically: true, encoding: .utf8)

        activeProfileName = name
        load()
    }

    func deleteProfile(named name: String) throws {
        if name == "default" {
            throw VibeJoyConfigError.unreadable("出厂基准方案不可删除")
        }
        let fileManager = FileManager.default
        let baseDir = configURL.deletingLastPathComponent()
        let profilesDir = baseDir.appendingPathComponent("profiles")
        let targetURL = profilesDir.appendingPathComponent("\(name).toml")

        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw VibeJoyConfigError.unreadable("方案不存在：\(name)")
        }

        if activeProfileName == name {
            try switchToProfile(named: "default")
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        refreshProfiles()
    }

    func resetToDefaultProfile(createBackup: Bool = true) throws {
        let fileManager = FileManager.default
        if createBackup {
            try createBackupOfCurrentConfig()
        }

        let baseDir = configURL.deletingLastPathComponent()
        let defaultProfileURL = baseDir.appendingPathComponent("profiles/default.toml")
        let defaultContent: String
        if fileManager.fileExists(atPath: defaultProfileURL.path),
           let text = try? String(contentsOf: defaultProfileURL, encoding: .utf8),
           !text.isEmpty {
            defaultContent = text
        } else if fileManager.fileExists(atPath: AppPaths.defaultProfileURL.path),
                  let text = try? String(contentsOf: AppPaths.defaultProfileURL, encoding: .utf8),
                  !text.isEmpty {
            defaultContent = text
        } else {
            defaultContent = Self.fallbackDefaultConfig
        }

        let activeProfileURL = baseDir.appendingPathComponent("active_profile")
        try? "default".write(to: activeProfileURL, atomically: true, encoding: .utf8)
        activeProfileName = "default"

        try commit(defaultContent)
        load()
    }

    static let fallbackDefaultConfig = """
    # VibeJoy — Joy-Con → macOS keyboard mapping.
    # Default Profile (出厂基准方案 v0.9.0)

    [global]
    deadzone       = 0.2    # stick radial deadzone, 0..1
    poll_hz        = 100    # polling frequency
    long_press_ms  = 250    # auto:<key>'s short-vs-long threshold
    stick_mode     = "4dir" # "4dir" or "8dir"

    # ─────────── Right Joy-Con ───────────

    [profile.right.buttons]
    a       = "tap:enter"
    b       = "tap:escape"
    x       = "combo:option+0"
    y       = "combo:option+1"
    r       = "combo:option+2"           # Type4Me Prompt 优化; not app-switch mode
    zr      = "app_switcher:system"     # hold for Cmd+Tab; right stick navigates
    plus    = "combo:cmd+s"
    home    = "window_switch:com.openai.codex" # ChatGPT app bundle (Codex)
    "r-stick" = "none"
    sl      = "none"
    sr      = "none"

    [profile.right.stick]
    up      = "macro:codex_page_up"          # one page up in the current Codex chat
    down    = "macro:codex_page_down"        # one page down in the current Codex chat
    left    = "macro:codex_previous_thread"  # previous Codex chat; ZR still overrides this
    right   = "macro:codex_next_thread"      # next Codex chat; ZR still overrides this

    # ─────────── Left Joy-Con (only used if paired) ───────────

    [profile.left.buttons]
    right   = "tap:enter"
    down    = "tap:escape"
    up      = "combo:option+0"
    left    = "combo:option+1"
    l       = "combo:option+2"
    zl      = "app_switcher:system"
    minus   = "combo:cmd+s"
    capture = "window_switch:com.openai.codex"
    "l-stick" = "none"
    sl      = "none"
    sr      = "none"

    [profile.left.stick]
    up      = "macro:codex_page_up"
    down    = "macro:codex_page_down"
    left    = "macro:codex_previous_thread"
    right   = "macro:codex_next_thread"

    # ─────────── Macros ───────────

    [macro.codex_page_up]
    if_app  = "com.openai.codex"
    steps   = ["scroll:up@8"]

    [macro.codex_page_down]
    if_app  = "com.openai.codex"
    steps   = ["scroll:down@8"]

    [macro.codex_previous_thread]
    if_app  = "com.openai.codex"
    steps   = ["combo:cmd+shift+["]

    [macro.codex_next_thread]
    if_app  = "com.openai.codex"
    steps   = ["combo:cmd+shift+]"]

    [macro.claude_focus]
    if_app  = "Visual Studio Code"
    steps   = [
      "combo:cmd+shift+p",
      "delay:100",
      "type:Claude Code: Focus input",
      "delay:100",
      "tap:enter",
    ]
    """

    static func parseRightButtons(from text: String) -> [String: String] { parseSection("profile.right.buttons", from: text) }
    static func parseRightStick(from text: String) -> [String: String] { parseSection("profile.right.stick", from: text) }
    static func parseLeftButtons(from text: String) -> [String: String] { parseSection("profile.left.buttons", from: text) }
    static func parseLeftStick(from text: String) -> [String: String] { parseSection("profile.left.stick", from: text) }

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

        // The old Codex page macros sent Page Up/Down key presses. Migrate
        // only those exact one-step macro values; custom macro steps remain
        // untouched, even when their names happen to contain "page_up".
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("steps"), trimmed.contains("[\"tap:page_up\"]") || trimmed.contains("[\"tap:page_down\"]") else { continue }
            lines[index] = lines[index]
                .replacingOccurrences(of: "[\"tap:page_up\"]", with: "[\"scroll:up@8\"]")
                .replacingOccurrences(of: "[\"tap:page_down\"]", with: "[\"scroll:down@8\"]")
        }

        if migratedStick {
            let macroDefinitions = [
                ("codex_page_up", "scroll:up@8"),
                ("codex_page_down", "scroll:down@8"),
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

        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[profile.left.buttons]" }) {
            let end = lines[(header + 1)...].firstIndex(where: { let value = $0.trimmingCharacters(in: .whitespacesAndNewlines); return value.hasPrefix("[") && value.hasSuffix("]") }) ?? lines.endIndex
            let sectionLines = lines[(header + 1)..<end]
            let keys = Set(sectionLines.compactMap { bindingKey(in: $0) })
            if keys.contains("a") || keys.contains("b") {
                let defaultLeftLines = [
                    "right     = \"tap:enter\"",
                    "down      = \"tap:escape\"",
                    "up        = \"combo:option+0\"",
                    "left      = \"combo:option+1\"",
                    "l         = \"combo:option+2\"",
                    "zl        = \"app_switcher:system\"",
                    "minus     = \"combo:cmd+s\"",
                    "capture   = \"window_switch:com.openai.codex\"",
                    "\"l-stick\" = \"none\"",
                    "sl        = \"none\"",
                    "sr        = \"none\"",
                ]
                lines.replaceSubrange((header + 1)..<end, with: defaultLeftLines)
            }
        }

        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[profile.left.stick]" }) {
            let end = lines[(header + 1)...].firstIndex(where: { let value = $0.trimmingCharacters(in: .whitespacesAndNewlines); return value.hasPrefix("[") && value.hasSuffix("]") }) ?? lines.endIndex
            let leftStickDefaults = [
                "up": "macro:codex_page_up",
                "down": "macro:codex_page_down",
                "left": "macro:codex_previous_thread",
                "right": "macro:codex_next_thread",
            ]
            for index in (header + 1)..<end {
                guard let key = bindingKey(in: lines[index]), let value = bindingValue(in: lines[index]), value == "none", let action = leftStickDefaults[key] else { continue }
                lines[index] = replacingValue(in: lines[index], with: action)
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
