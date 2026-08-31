import Foundation

enum AppPaths {
    static let projectKey = "vibejoyProjectPath"
    static let configKey = "vibejoyConfigPath"
    static let uvKey = "uvExecutablePath"
    static let autoRunKey = "autoRunVibeJoy"

    static let legacyProjectPath = "/Users/terry/Documents/Codex/2026-08-30/referenced-chatgpt-conversation-this-is-an/work/vibejoy"
    static let defaultProjectPath = "/Users/terry/Library/CloudStorage/SynologyDrive-Home/Data/Codex/VibeJoy/vibejoy"
    static let defaultConfigPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vibejoy/config.toml").path
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
}
