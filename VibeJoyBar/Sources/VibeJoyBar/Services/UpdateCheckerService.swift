import AppKit
import Foundation
import Observation

/// The lifecycle stage of an in-app software update.
enum UpdateStage: Equatable, Sendable {
    case ready
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case extracting
    case restarting
    case failed(String)
}

enum UpdateError: LocalizedError {
    case downloadFailed(String)
    case extractionFailed(String)
    case bundleNotFound(String)
    case invalidBundle(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg):
            return msg
        case .extractionFailed(let msg):
            return msg
        case .bundleNotFound(let msg):
            return msg
        case .invalidBundle(let msg):
            return msg
        }
    }
}

/// Service responsible for querying GitHub Releases, comparing semantic versions,
/// and performing in-place auto-updates with download progress and relaunch.
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

    private(set) var downloadAssetURL: URL? = nil
    private(set) var assetSize: Int64 = 0
    private(set) var stage: UpdateStage = .ready

    var canInAppUpdate: Bool {
        downloadAssetURL != nil
    }

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

    /// Resets the update lifecycle stage to `.ready`.
    func resetStage() {
        stage = .ready
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
                        downloadAssetURL = nil
                        assetSize = 0
                        stage = .ready
                        checkStatusMessage = "当前已是最新版本 (v\(AppPaths.appVersion))"
                        return
                    }
                    checkStatusMessage = "检查更新失败 (HTTP \(httpResponse.statusCode))"
                    return
                }
            }

            struct GitHubAsset: Decodable {
                let name: String
                let size: Int64
                let browserDownloadUrl: String

                enum CodingKeys: String, CodingKey {
                    case name
                    case size
                    case browserDownloadUrl = "browser_download_url"
                }
            }

            struct GitHubRelease: Decodable {
                let tagName: String
                let name: String?
                let body: String?
                let htmlUrl: String
                let publishedAt: String?
                let assets: [GitHubAsset]?

                enum CodingKeys: String, CodingKey {
                    case tagName = "tag_name"
                    case name
                    case body
                    case htmlUrl = "html_url"
                    case publishedAt = "published_at"
                    case assets
                }
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if let zipAsset = release.assets?.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
               let url = URL(string: zipAsset.browserDownloadUrl) {
                downloadAssetURL = url
                assetSize = zipAsset.size
            } else {
                downloadAssetURL = nil
                assetSize = 0
            }

            let comparison = Self.compareVersions(current: AppPaths.appVersion, remote: remoteVersion)
            if comparison == .orderedAscending {
                hasUpdate = true
                latestVersion = remoteVersion
                releaseTitle = release.name
                releaseNotes = release.body
                releaseURL = URL(string: release.htmlUrl)
                stage = .ready
                checkStatusMessage = "发现新版本 \(remoteVersion)"
            } else {
                hasUpdate = false
                downloadAssetURL = nil
                assetSize = 0
                stage = .ready
                checkStatusMessage = "当前已是最新版本 (v\(AppPaths.appVersion))"
            }
        } catch {
            checkStatusMessage = "检查更新失败：\(error.localizedDescription)"
        }
    }

    /// Downloads the update package, extracts and verifies the new app bundle,
    /// and invokes the detached relaunch script to perform atomic replacement and restart.
    func startInAppUpdate() async {
        guard let assetURL = downloadAssetURL else { return }

        stage = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: assetSize)

        do {
            let downloader = UpdateDownloader()
            _ = try await downloader.download(from: assetURL, expectedSize: assetSize) { [weak self] p, written, total in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stage = .downloading(progress: p, bytesWritten: written, totalBytes: total)
                }
            }

            stage = .extracting

            let stagedDir = URL(fileURLWithPath: "/tmp/vibejoy_update_staged")
            try? FileManager.default.removeItem(at: stagedDir)
            try FileManager.default.createDirectory(at: stagedDir, withIntermediateDirectories: true)

            // Extract using macOS ditto
            let dittoProcess = Process()
            dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProcess.arguments = ["-xk", "/tmp/vibejoy_update.zip", "/tmp/vibejoy_update_staged"]
            try dittoProcess.run()
            dittoProcess.waitUntilExit()
            guard dittoProcess.terminationStatus == 0 else {
                throw UpdateError.extractionFailed("解压更新包失败，ditto 返回码: \(dittoProcess.terminationStatus)")
            }

            // Locate app bundle in staged folder
            let directApp = stagedDir.appendingPathComponent("VibeJoyBar.app")
            let stagedAppURL: URL
            if FileManager.default.fileExists(atPath: directApp.path) {
                stagedAppURL = directApp
            } else {
                let items = (try? FileManager.default.contentsOfDirectory(at: stagedDir, includingPropertiesForKeys: nil)) ?? []
                if let found = items.first(where: { $0.pathExtension == "app" }) {
                    stagedAppURL = found
                } else {
                    throw UpdateError.bundleNotFound("未在更新包中找到有效的 VibeJoyBar.app")
                }
            }

            // Verify Info.plist & CFBundleIdentifier
            let infoPlistURL = stagedAppURL.appendingPathComponent("Contents/Info.plist")
            guard FileManager.default.fileExists(atPath: infoPlistURL.path),
                  let plistData = try? Data(contentsOf: infoPlistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let bundleId = plist["CFBundleIdentifier"] as? String,
                  bundleId == "com.terry.vibejoybar" else {
                throw UpdateError.invalidBundle("更新包 Info.plist 校验失败或 Bundle ID 不匹配")
            }

            // Strip quarantine attribute
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", stagedAppURL.path]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            stage = .restarting

            let relaunchScript = #"""
            #!/bin/bash
            PARENT_PID="$1"
            STAGED_APP="$2"
            TARGET_APP="$3"

            # Wait for old app process to terminate
            while kill -0 "$PARENT_PID" 2>/dev/null; do
                sleep 0.1
            done

            # Atomic swap
            rm -rf "$TARGET_APP"
            /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"
            /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true

            # Clean staging
            rm -rf "/tmp/vibejoy_update_staged" "/tmp/vibejoy_update.zip"

            # Relaunch
            /usr/bin/open -n "$TARGET_APP"
            rm -- "$0"
            """#

            let scriptURL = URL(fileURLWithPath: "/tmp/vibejoy_relaunch.sh")
            try relaunchScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let targetAppPath: String
            let mainBundlePath = Bundle.main.bundleURL.path
            if mainBundlePath.hasSuffix(".app") && FileManager.default.fileExists(atPath: mainBundlePath) {
                targetAppPath = mainBundlePath
            } else {
                targetAppPath = "/Applications/VibeJoyBar.app"
            }

            let relaunchProcess = Process()
            relaunchProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            relaunchProcess.arguments = [
                scriptURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                stagedAppURL.path,
                targetAppPath
            ]
            try relaunchProcess.run()

            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}

/// Download helper utilizing `URLSessionDownloadDelegate` for stream progress updates.
private final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, any Error>?
    private var onProgress: (@Sendable (Double, Int64, Int64) -> Void)?
    private var expectedSize: Int64 = 0
    private var session: URLSession?

    func download(
        from url: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Double, Int64, Int64) -> Void
    ) async throws -> URL {
        self.expectedSize = expectedSize
        self.onProgress = progress

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let config = URLSessionConfiguration.default
            let downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = downloadSession
            let task = downloadSession.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let fraction = total > 0 ? min(1.0, max(0.0, Double(totalBytesWritten) / Double(total))) : 0.0
        onProgress?(fraction, totalBytesWritten, total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            continuation?.resume(throwing: UpdateError.downloadFailed("下载失败 (HTTP \(http.statusCode))"))
            continuation = nil
            return
        }

        let destination = URL(fileURLWithPath: "/tmp/vibejoy_update.zip")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error, continuation != nil {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        self.session?.finishTasksAndInvalidate()
    }
}
