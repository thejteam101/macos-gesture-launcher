import Foundation

enum Autostart {
    static let label = "com.macos-gesture-launcher"
    static let plistName = "\(label).plist"
    static let stdoutPath = "/tmp/macos-gesture-launcher.out"
    static let stderrPath = "/tmp/macos-gesture-launcher.err"

    static func install(executablePath: String, configPath: String, debug: Bool) throws {
        let launchAgentsDir = expandTilde("~/Library/LaunchAgents")
        let plistPath = (launchAgentsDir as NSString).appendingPathComponent(plistName)
        let fileManager = FileManager.default

        try fileManager.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)

        stopRunningInstances(plistPath: plistPath)

        let execURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let configURL = URL(fileURLWithPath: configPath).resolvingSymlinksInPath()
        var arguments = [execURL.path, "--config", configURL.path]
        if debug {
            arguments.append("--debug")
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardErrorPath": stderrPath,
            "StandardOutPath": stdoutPath,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)

        let domain = "gui/\(getuid())"
        try? runLaunchctl(arguments: ["bootout", domain, plistPath], allowFailure: true)
        try runLaunchctl(arguments: ["bootstrap", domain, plistPath], allowFailure: false)

        Logger.info("Autostart enabled via \(plistPath)")
    }

    static func remove() throws {
        let launchAgentsDir = expandTilde("~/Library/LaunchAgents")
        let plistPath = (launchAgentsDir as NSString).appendingPathComponent(plistName)
        let domain = "gui/\(getuid())"

        try? runLaunchctl(arguments: ["bootout", domain, plistPath], allowFailure: true)
        if FileManager.default.fileExists(atPath: plistPath) {
            try FileManager.default.removeItem(atPath: plistPath)
        }

        Logger.info("Autostart removed.")
    }

    static func status() throws {
        let launchAgentsDir = expandTilde("~/Library/LaunchAgents")
        let plistPath = (launchAgentsDir as NSString).appendingPathComponent(plistName)
        let installed = FileManager.default.fileExists(atPath: plistPath)

        let listResult = try runCommand(path: "/bin/launchctl", arguments: ["list", label])
        let loaded = listResult.status == 0
        let pid = parsePid(from: listResult.stdout)

        var message = "Autostart status: installed=\(installed ? "yes" : "no") loaded=\(loaded ? "yes" : "no")"
        if let pid {
            message += " pid=\(pid)"
        }
        message += " plist=\(plistPath)"
        Logger.info(message)
    }

    private static func runLaunchctl(arguments: [String], allowFailure: Bool) throws {
        let result = try runCommand(path: "/bin/launchctl", arguments: arguments)
        if result.status != 0 && !allowFailure {
            throw NSError(
                domain: "Autostart",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: "launchctl failed with status \(result.status)"]
            )
        }
    }

    private static func stopRunningInstances(plistPath: String) {
        let domain = "gui/\(getuid())"
        try? runLaunchctl(arguments: ["bootout", domain, label], allowFailure: true)
        try? runLaunchctl(arguments: ["bootout", domain, plistPath], allowFailure: true)

        let currentPid = getpid()
        if let result = try? runCommand(path: "/usr/bin/pgrep", arguments: ["-f", "macos-gesture-launcher"]) {
            let pids = result.stdout.split(whereSeparator: \.isNewline).compactMap { Int32($0) }
            for pid in pids where pid != currentPid {
                _ = kill(pid, SIGTERM)
            }
        }
    }

    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static func runCommand(path: String, arguments: [String]) throws -> CommandResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        try task.run()
        task.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(status: task.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func parsePid(from output: String) -> Int? {
        let pattern = #"PID"\s*=\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            return Int(output[range])
        }
        return nil
    }
}
