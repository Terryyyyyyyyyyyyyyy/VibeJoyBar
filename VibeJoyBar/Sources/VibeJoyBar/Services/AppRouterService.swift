import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppRouterService {
    private(set) var currentFrontApp: String?
    private(set) var currentFrontBundleId: String?
    private(set) var matchedProfileName: String?

    private var debounceTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    weak var model: AppModel?

    init(model: AppModel? = nil) {
        self.model = model
    }


    func startObserving() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleApplicationActivated(app)
            }
        }

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            handleApplicationActivated(frontApp)
        }
    }

    func stopObserving() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
    }

    func handleApplicationActivated(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundle = Bundle.main.bundleIdentifier
        if app.processIdentifier == currentPID || (currentBundle != nil && app.bundleIdentifier == currentBundle) {
            return
        }

        debounceTask?.cancel()
        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? ""

        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.routeApp(bundleId: bundleId, appName: appName)
        }
    }

    func routeApp(bundleId: String, appName: String) {
        guard let model, model.autoSwitchEnabled else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundle = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication {
            if front.processIdentifier == currentPID || (currentBundle != nil && front.bundleIdentifier == currentBundle) {
                return
            }
        }
        if currentBundle != nil && bundleId == currentBundle {
            return
        }

        currentFrontApp = appName
        currentFrontBundleId = bundleId

        let targetProfile = Self.matchProfile(
            bundleId: bundleId,
            appName: appName,
            in: model.configStore.availableProfiles
        )
        matchedProfileName = targetProfile

        if targetProfile != model.configStore.activeProfileName {
            model.switchToProfile(named: targetProfile, isAutoSwitch: true)
        }
    }

    static func matchProfile(bundleId: String, appName: String, in profiles: [ProfileItem]) -> String {
        let cleanBundle = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = appName.trimmingCharacters(in: .whitespacesAndNewlines)

        let nonDefaultProfiles = profiles.filter { !$0.isDefault }

        if !cleanBundle.isEmpty {
            if let match = nonDefaultProfiles.first(where: { profile in
                profile.targetApps.contains { $0.caseInsensitiveCompare(cleanBundle) == .orderedSame }
            }) {
                return match.name
            }
        }

        if !cleanName.isEmpty {
            if let match = nonDefaultProfiles.first(where: { profile in
                profile.targetApps.contains { $0.caseInsensitiveCompare(cleanName) == .orderedSame }
            }) {
                return match.name
            }
        }

        if let defaultProfile = profiles.first(where: { $0.isDefault }) {
            if !cleanBundle.isEmpty, defaultProfile.targetApps.contains(where: { $0.caseInsensitiveCompare(cleanBundle) == .orderedSame }) {
                return defaultProfile.name
            }
            if !cleanName.isEmpty, defaultProfile.targetApps.contains(where: { $0.caseInsensitiveCompare(cleanName) == .orderedSame }) {
                return defaultProfile.name
            }
        }

        return "default"
    }
}
