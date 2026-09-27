import Foundation
import Observation

/// Service responsible for querying GitHub Releases and comparing semantic versions
/// to determine if a newer version of VibeJoyBar is available.
@MainActor
@Observable
final class UpdateCheckerService {
    private(set) var isChecking = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String? = nil
    private(set) var releaseTitle: String? = nil
    private(set) var releaseNotes: String? = nil
    private(set) var releaseURL: URL? = nil
    private(set) var lastCheckedDate: Date? = nil
    private(set) var checkStatusMessage: String? = nil

    var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: "autoCheckUpdates")
        }
    }

    private let session: URLSession
    private static let repoLatestReleaseURL = URL(
        string: "https://api.github.com/repos/Terryyyyyyyyyyyyyyy/VibeJoyBar/releases/latest"
    )!

    init(session: URLSession = .shared) {
        self.session = session
        self.autoCheckEnabled = (UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool) ?? true
    }

    /// Compares two version strings numerically by component (SemVer).
    ///
    /// Drops leading "v" or "V", trims whitespace, pads shorter component lists with 0.
    /// Returns `.orderedAscending` when current < remote (meaning remote is newer).
    nonisolated static func compareVersions(current: String, remote: String) -> ComparisonResult {
        let currentComponents = parseVersionComponents(current)
        let remoteComponents = parseVersionComponents(remote)

        let maxCount = max(currentComponents.count, remoteComponents.count)
        for i in 0..<maxCount {
            let cur = i < currentComponents.count ? currentComponents[i] : 0
            let rem = i < remoteComponents.count ? remoteComponents[i] : 0

            if cur < rem {
                return .orderedAscending
            } else if cur > rem {
                return .orderedDescending
            }
        }
        return .orderedSame
    }

    nonisolated private static func parseVersionComponents(_ version: String) -> [Int] {
        var cleaned = version.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        if let dashOrPlus = cleaned.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            cleaned = String(cleaned[..<dashOrPlus])
        }
        return cleaned.split(separator: ".").map { Int($0.trimmingCharacters(in: CharacterSet.whitespaces)) ?? 0 }
    }

    /// Asynchronously queries GitHub API for the latest release and evaluates update status.
    func checkForUpdates(manual: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        checkStatusMessage = manual ? "正在检查新版本…" : nil

        defer {
            isChecking = false
            lastCheckedDate = Date()
        }

        do {
            var request = URLRequest(url: Self.repoLatestReleaseURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("VibeJoyBar/\(AppPaths.appVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 404 {
                        hasUpdate = false
                        checkStatusMessage = "当前已是最新版本 (v\(AppPaths.appVersion))"
                        return
                    }
                    checkStatusMessage = "检查更新失败 (HTTP \(httpResponse.statusCode))"
                    return
                }
            }

            struct GitHubRelease: Decodable {
                let tagName: String
                let name: String?
                let body: String?
                let htmlUrl: String
                let publishedAt: String?

                enum CodingKeys: String, CodingKey {
                    case tagName = "tag_name"
                    case name
                    case body
                    case htmlUrl = "html_url"
                    case publishedAt = "published_at"
                }
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let comparison = Self.compareVersions(current: AppPaths.appVersion, remote: remoteVersion)
            if comparison == .orderedAscending {
                hasUpdate = true
                latestVersion = remoteVersion
                releaseTitle = release.name
                releaseNotes = release.body
                releaseURL = URL(string: release.htmlUrl)
                checkStatusMessage = "发现新版本 \(remoteVersion)"
            } else {
                hasUpdate = false
                checkStatusMessage = "当前已是最新版本 (v\(AppPaths.appVersion))"
            }
        } catch {
            checkStatusMessage = "检查更新失败：\(error.localizedDescription)"
        }
    }
}
