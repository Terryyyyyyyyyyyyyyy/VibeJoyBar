import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let processService: VibeJoyProcessService
    let configStore: VibeJoyConfigStore
    let loginItemService = LoginItemService()

    var projectPath: String
    var configPath: String
    var uvPath: String
    var autoRunOnLaunch: Bool
    var activityMessage = ""
    var isBusy = false

    private let defaults = UserDefaults.standard

    private init() {
        let persistedProjectPath = defaults.string(forKey: AppPaths.projectKey)
        let savedProjectPath: String
        if persistedProjectPath == AppPaths.legacyProjectPath,
           FileManager.default.fileExists(atPath: AppPaths.defaultProjectPath) {
            // Migrate the known prior default only when the new checkout is
            // present. Any user-selected custom path is preserved.
            savedProjectPath = AppPaths.defaultProjectPath
            defaults.set(savedProjectPath, forKey: AppPaths.projectKey)
        } else {
            savedProjectPath = persistedProjectPath ?? AppPaths.defaultProjectPath
        }
        let savedConfigPath = defaults.string(forKey: AppPaths.configKey) ?? AppPaths.defaultConfigPath
        let savedUVPath = defaults.string(forKey: AppPaths.uvKey) ?? AppPaths.defaultUVPath
        let savedAutoRun = defaults.object(forKey: AppPaths.autoRunKey) as? Bool ?? true

        projectPath = savedProjectPath
        configPath = savedConfigPath
        uvPath = savedUVPath
        autoRunOnLaunch = savedAutoRun

        processService = VibeJoyProcessService(
            projectURL: AppPaths.expandedURL(savedProjectPath),
            uvURL: AppPaths.expandedURL(savedUVPath)
        )
        configStore = VibeJoyConfigStore(configURL: AppPaths.expandedURL(savedConfigPath))
    }

    func startOnLaunchIfNeeded() {
        if autoRunOnLaunch {
            processService.start()
        }
    }

    func saveMappings() {
        guard !isBusy else { return }
        isBusy = true
        activityMessage = "正在校验映射…"

        Task {
            do {
                let rendered = try configStore.renderedText()
                let previewURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vibejoybar-preview-\(UUID().uuidString).toml")
                try rendered.write(to: previewURL, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(at: previewURL) }

                let result = await processService.runOneShot(
                    arguments: ["run", "vibejoy", "validate", previewURL.path]
                )
                if result.exitCode == 0 {
                    try configStore.commit(rendered)
                    activityMessage = "映射已保存，VibeJoy 正在重启"
                    processService.restart()
                } else {
                    activityMessage = "校验失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            } catch {
                activityMessage = "保存失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func validateCurrentConfig() {
        guard !isBusy else { return }
        isBusy = true
        activityMessage = "正在校验当前配置…"
        Task {
            let result = await processService.runOneShot(arguments: ["run", "vibejoy", "validate"])
            activityMessage = result.exitCode == 0
                ? "配置有效"
                : "配置异常：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
            isBusy = false
        }
    }

    func runDoctor() {
        guard !isBusy else { return }
        isBusy = true
        activityMessage = "正在运行诊断…"
        Task {
            let result = await processService.runOneShot(arguments: ["run", "vibejoy", "doctor"])
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            activityMessage = output.isEmpty ? "诊断完成（退出码 \(result.exitCode)）" : output
            isBusy = false
        }
    }

    func applyPaths() {
        defaults.set(projectPath, forKey: AppPaths.projectKey)
        defaults.set(configPath, forKey: AppPaths.configKey)
        defaults.set(uvPath, forKey: AppPaths.uvKey)
        defaults.set(autoRunOnLaunch, forKey: AppPaths.autoRunKey)

        processService.projectURL = AppPaths.expandedURL(projectPath)
        processService.uvURL = AppPaths.expandedURL(uvPath)
        configStore.updateURL(AppPaths.expandedURL(configPath))
        activityMessage = "路径设置已应用"
        if processService.desiredRunning {
            processService.restart()
        }
    }

    func setAutoRun(_ enabled: Bool) {
        autoRunOnLaunch = enabled
        defaults.set(enabled, forKey: AppPaths.autoRunKey)
    }
}
