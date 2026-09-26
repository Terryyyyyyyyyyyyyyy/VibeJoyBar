import Foundation

enum AppPaths {
    static let projectKey = "vibejoyProjectPath"
    static let configKey = "vibejoyConfigPath"
    static let uvKey = "uvExecutablePath"
    static let autoRunKey = "autoRunVibeJoy"
    static let autoSwitchKey = "auto_switch_profiles"
    static let hudFeedbackKey = "showHUDFeedbackOnSwitch"

    static let legacyProjectPath = "/Users/terry/Documents/Codex/2026-08-30/referenced-chatgpt-conversation-this-is-an/work/vibejoy"
    static let defaultProjectPath = "/Users/terry/Library/CloudStorage/SynologyDrive-Home/Data/Codex/VibeJoy/vibejoy"
    static let defaultConfigPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vibejoy/config.toml").path
    static let profilesDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vibejoy/profiles")
    static let defaultProfileURL = profilesDirectoryURL.appendingPathComponent("default.toml")
    static let activeProfileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vibejoy/active_profile")
    static let backupsDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vibejoy/backups")
    static let defaultUVPath = "/opt/homebrew/bin/uv"

    static func expandedURL(_ path: String) -> URL {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    static var appVersion: String {
        guard Bundle.main.bundleIdentifier == "com.terry.vibejoybar" else { return "1.1.0" }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }

    static var appBuild: String {
        guard Bundle.main.bundleIdentifier == "com.terry.vibejoybar" else { return "12" }
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "12"
    }

    static var versionString: String {
        "v\(appVersion)"
    }
}
