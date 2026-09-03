import Foundation
import Observation
import Darwin

@MainActor
@Observable
final class VibeJoyProcessService {
    private(set) var phase: VibeJoyPhase = .stopped
    private(set) var logLines: [String] = []
    private(set) var connectedSides: Set<String> = []
    private(set) var desiredRunning = false
    var projectURL: URL
    var uvURL: URL

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var retryTask: Task<Void, Never>?
    private var launchPreparationTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var restartRequested = false

    init(projectURL: URL, uvURL: URL) { self.projectURL = projectURL; self.uvURL = uvURL }
    func start() { desiredRunning = true; prepareExclusiveLaunch() }

    func stop() {
        desiredRunning = false; restartRequested = false
        retryTask?.cancel(); retryTask = nil; launchPreparationTask?.cancel(); launchPreparationTask = nil; stopTask?.cancel()
        appendLog("正在请求 VibeJoy 优雅停止…")
        stopTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.runOneShot(arguments: ["stop"])
            guard !Task.isCancelled else { return }
            self.finishStop()
        }
    }

    /// Synchronous finalizer used by applicationWillTerminate. The daemon gets
    /// the IPC stop request before the launched wrapper is terminated, so a
    /// menu-bar quit cannot strand a Python/uv child process.
    func terminateForShutdown() {
        desiredRunning = false
        stopStatusPolling()
        retryTask?.cancel(); launchPreparationTask?.cancel(); stopTask?.cancel()
        let command = resolvedCommand(arguments: ["stop"])
        let request = Process(); let pipe = Pipe()
        request.executableURL = command.executable; request.arguments = command.arguments
        request.standardOutput = pipe; request.standardError = pipe
        do { try request.run(); request.waitUntilExit() } catch { appendLog("停止请求失败：\(error.localizedDescription)") }
        if let child = process, child.isRunning { terminateProcessTree(child) }
        cleanupPipes(); process = nil; phase = .stopped
    }

    func restart() {
        desiredRunning = true; restartRequested = true; retryTask?.cancel()
        if process != nil { appendLog("映射已更新，正在重启…"); stop(); desiredRunning = true; restartRequested = true }
        else { prepareExclusiveLaunch() }
    }

    func reload() async -> Bool {
        guard desiredRunning, let proc = process, proc.isRunning else {
            appendLog("VibeJoy 未在运行，正在启动…")
            restart()
            return false
        }
        appendLog("正在请求 VibeJoy 零中断热重载…")
        let result = await runOneShot(arguments: ["reload"])
        if result.exitCode == 0 {
            appendLog("零中断热重载成功。")
            return true
        } else {
            appendLog("热重载失败（\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))），正在回退至完整重启…")
            restart()
            return false
        }
    }

    func clearLogs() { logLines.removeAll() }

    func runOneShot(arguments: [String]) async -> CommandResult {
        let command = resolvedCommand(arguments: arguments)
        return await Task.detached(priority: .userInitiated) {
            let child = Process(); let pipe = Pipe()
            child.executableURL = command.executable; child.arguments = command.arguments; child.currentDirectoryURL = FileManager.default.temporaryDirectory
            child.standardOutput = pipe; child.standardError = pipe
            var environment = ProcessInfo.processInfo.environment; environment["PYTHONUNBUFFERED"] = "1"; child.environment = environment
            do { try child.run(); child.waitUntilExit(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); return CommandResult(exitCode: child.terminationStatus, output: String(decoding: data, as: UTF8.self)) }
            catch { return CommandResult(exitCode: -1, output: error.localizedDescription) }
        }.value
    }

    private func resolvedCommand(arguments: [String]) -> (executable: URL, arguments: [String]) {
        let candidates = [projectURL.appendingPathComponent(".venv/bin/vibejoy"), projectURL.appendingPathComponent("venv/bin/vibejoy")]
        if let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) { return (executable, arguments) }
        return (uvURL, ["run", "--project", projectURL.path, "vibejoy"] + arguments)
    }

    private func launchIfNeeded() {
        guard desiredRunning, process == nil else { return }
        guard FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("pyproject.toml").path) else { phase = .failed("项目路径无效"); appendLog("VibeJoy 项目路径无效：\(projectURL.path)"); return }
        let command = resolvedCommand(arguments: ["run"])
        guard FileManager.default.isExecutableFile(atPath: command.executable.path) else { phase = .failed("找不到 VibeJoy 或 uv"); appendLog("找不到可用的 VibeJoy 启动器"); return }
        let child = Process(); let stdout = Pipe(); let stderr = Pipe()
        child.executableURL = command.executable; child.arguments = command.arguments; child.currentDirectoryURL = projectURL; child.standardOutput = stdout; child.standardError = stderr
        var environment = ProcessInfo.processInfo.environment; environment["PYTHONUNBUFFERED"] = "1"; environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; child.environment = environment
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in let data = handle.availableData; guard !data.isEmpty else { return }; Task { @MainActor in self?.consume(String(decoding: data, as: UTF8.self)) } }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in let data = handle.availableData; guard !data.isEmpty else { return }; Task { @MainActor in self?.consume(String(decoding: data, as: UTF8.self)) } }
        child.terminationHandler = { [weak self] terminated in let code = terminated.terminationStatus; Task { @MainActor in self?.handleTermination(code: code) } }
        process = child; stdoutPipe = stdout; stderrPipe = stderr; phase = .starting; appendLog("启动 VibeJoy（\(command.executable.lastPathComponent)）…")
        do {
            try child.run()
            startStatusPolling()
        } catch {
            process = nil
            cleanupPipes()
            phase = .failed(error.localizedDescription)
            appendLog("启动失败：\(error.localizedDescription)")
            scheduleRetry(afterNanoseconds: 8_000_000_000)
        }
    }

    private func prepareExclusiveLaunch() {
        guard desiredRunning, process == nil, launchPreparationTask == nil else { return }
        phase = .starting; appendLog("正在确认只有一个 VibeJoy 后台进程…")
        launchPreparationTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.runOneShot(arguments: ["stop"]); try? await Task.sleep(nanoseconds: 500_000_000)
            let permissionResult = await self.runOneShot(arguments: ["permission", "--request"])
            self.launchPreparationTask = nil
            guard !Task.isCancelled, self.desiredRunning else { return }
            guard permissionResult.exitCode == 0 else { self.desiredRunning = false; self.phase = .needsAccessibility; self.appendLog(permissionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)); return }
            self.launchIfNeeded()
        }
    }

    private func finishStop() {
        stopStatusPolling()
        guard let child = process else { phase = .stopped; appendLog("VibeJoy 已停止。"); return }
        if child.isRunning {
            child.interrupt(); appendLog("已发送停止信号，正在清理后台进程…")
            let target = child
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard target.isRunning else { return }
                self?.terminateProcessTree(target)
            }
        }
        else { process = nil; cleanupPipes(); phase = .stopped }
    }

    private func consume(_ text: String) {
        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            appendLog(line)
            if line.contains("connected:") {
                if line.contains("right") {
                    connectedSides.insert("right")
                }
                if line.contains("left") {
                    connectedSides.insert("left")
                }
            }
            if line.contains("disconnected:") {
                if line.contains("right") {
                    connectedSides.remove("right")
                }
                if line.contains("left") {
                    connectedSides.remove("left")
                }
            }
            if line.contains("waiting:") || line.contains("no Joy-Con") || line.contains("none detected") {
                connectedSides.removeAll()
            }
            updatePhaseFromConnectedSides(line: line)
        }
    }

    private func updatePhaseFromConnectedSides(line: String? = nil) {
        let sides = connectedSides
        if !sides.isEmpty {
            if sides.count > 1 {
                phase = .running("双持")
            } else if sides.contains("right") {
                phase = .running("右手柄")
            } else {
                phase = .running("左手柄")
            }
        } else if let line = line, (line.contains("disconnected:") || line.contains("waiting:") || line.contains("no Joy-Con") || line.contains("none detected")) {
            phase = .waitingForController
        }
    }

    private var statusPollTask: Task<Void, Never>?

    private func startStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled, let self else { break }
                guard self.desiredRunning, self.process != nil else { continue }
                let result = await self.runOneShot(arguments: ["status"])
                guard !Task.isCancelled, result.exitCode == 0 else { continue }
                if let data = result.output.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sidesList = json["sides"] as? [String] {
                    let newSides = Set(sidesList)
                    if newSides != self.connectedSides {
                        self.connectedSides = newSides
                        self.updatePhaseFromConnectedSides()
                    }
                }
            }
        }
    }

    private func stopStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = nil
    }

    private func handleTermination(code: Int32) {
        stopStatusPolling()
        cleanupPipes(); process = nil
        if desiredRunning {
            if restartRequested { restartRequested = false; phase = .starting; scheduleRetry(afterNanoseconds: 400_000_000); return }
            if code == 2 { phase = .waitingForController; appendLog("未检测到 Joy-Con，稍后自动重试。") } else if code == 3 { phase = .failed("检测到另一个 VibeJoy 进程"); appendLog("检测到另一个 VibeJoy 进程，正在尝试接管。") } else { phase = .failed("退出码 \(code)"); appendLog("VibeJoy 已退出（\(code)），稍后自动重试。") }
            scheduleRetry(afterNanoseconds: 8_000_000_000)
        } else { connectedSides.removeAll(); phase = .stopped; appendLog("VibeJoy 已停止。") }
    }

    private func scheduleRetry(afterNanoseconds delay: UInt64) { guard desiredRunning else { return }; retryTask?.cancel(); retryTask = Task { [weak self] in try? await Task.sleep(nanoseconds: delay); guard !Task.isCancelled else { return }; self?.launchIfNeeded() } }
    private func terminateProcessTree(_ root: Process) {
        let rootPID = root.processIdentifier
        guard rootPID > 0 else { root.terminate(); return }
        let probe = Process(); let pipe = Pipe()
        probe.executableURL = URL(fileURLWithPath: "/bin/ps")
        probe.arguments = ["-axo", "pid=,ppid="]
        probe.standardOutput = pipe; probe.standardError = FileHandle.nullDevice
        do { try probe.run(); probe.waitUntilExit() } catch { return }
        var childrenByParent: [Int32: [Int32]] = [:]
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, let pid = Int32(parts[0]), let parent = Int32(parts[1]) else { continue }
            childrenByParent[parent, default: []].append(pid)
        }
        var pending = childrenByParent[rootPID] ?? []; var descendants: [Int32] = []
        while let pid = pending.popLast() { descendants.append(pid); pending.append(contentsOf: childrenByParent[pid] ?? []) }
        root.terminate()
        for pid in descendants.reversed() { _ = Darwin.kill(pid, SIGTERM) }
    }
    private func cleanupPipes() { stdoutPipe?.fileHandleForReading.readabilityHandler = nil; stderrPipe?.fileHandleForReading.readabilityHandler = nil; stdoutPipe = nil; stderrPipe = nil }
    private func appendLog(_ line: String) { logLines.append("\(Date.now.formatted(date: .omitted, time: .standard))  \(line)"); if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) } }
}
