import AppKit
import Foundation
import Yams

struct Options {
    let configPath: String?
    let debug: Bool
    let autostartInstall: Bool
    let autostartRemove: Bool
    let autostartStatus: Bool
}

@main
struct GestureLauncherMain {
    static func main() {
        let _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let options = parseOptions()
        let autostartFlags = [
            options.autostartInstall,
            options.autostartRemove,
            options.autostartStatus,
        ].filter { $0 }.count
        if autostartFlags > 0 {
            if autostartFlags > 1 {
                Logger.info("Use only one of --autostart, --autostart-remove, or --autostart-status.")
                exit(1)
            }
            do {
                if options.autostartInstall {
                    guard let configPath = resolveConfigPath(explicit: options.configPath) else {
                        Logger.info("Config not found. Provide --config <path> or create ./config.yaml.")
                        exit(1)
                    }
                    let executablePath = resolveExecutablePath()
                    try Autostart.install(
                        executablePath: executablePath,
                        configPath: configPath,
                        debug: options.debug
                    )
                } else if options.autostartRemove {
                    try Autostart.remove()
                } else {
                    try Autostart.status()
                }
                exit(0)
            } catch {
                Logger.info("Autostart failed: \(error)")
                exit(1)
            }
        }

        guard let configPath = resolveConfigPath(explicit: options.configPath) else {
            Logger.info("Config not found. Provide --config <path> or create ./config.yaml.")
            exit(1)
        }
        Logger.debug(options.debug, "Using config: \(configPath)")
        do {
            let config = try loadConfig(path: configPath)
            let launcher = GestureLauncher(config: config, debug: options.debug)
            launcher.start()
            dispatchMain()
        } catch {
            Logger.info("Failed to load config: \(error)")
            exit(1)
        }
    }
}

func resolveConfigPath(explicit: String?) -> String? {
    if let explicit {
        return explicit
    }
    let fileManager = FileManager.default
    let localPath = fileManager.currentDirectoryPath + "/config.yaml"
    if fileManager.fileExists(atPath: localPath) {
        return localPath
    }

    let homeConfig = expandTilde("~/.config/macos-gesture-launcher/config.yaml")
    if fileManager.fileExists(atPath: homeConfig) {
        return homeConfig
    }

    return nil
}

func loadConfig(path: String) throws -> Config {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let yamlString = String(decoding: data, as: UTF8.self)
    let decoder = YAMLDecoder()
    return try decoder.decode(Config.self, from: yamlString)
}

func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

func parseOptions() -> Options {
    let args = Array(CommandLine.arguments.dropFirst())
    var configPath: String?
    var debug = false
    var autostartInstall = false
    var autostartRemove = false
    var autostartStatus = false
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--config", "-c":
            let next = index + 1
            if next < args.count {
                configPath = expandTilde(args[next])
                index = next
            }
        case "--debug":
            debug = true
        case "--autostart":
            autostartInstall = true
        case "--autostart-remove":
            autostartRemove = true
        case "--autostart-status":
            autostartStatus = true
        default:
            break
        }
        index += 1
    }
    return Options(
        configPath: configPath,
        debug: debug,
        autostartInstall: autostartInstall,
        autostartRemove: autostartRemove,
        autostartStatus: autostartStatus
    )
}

func resolveExecutablePath() -> String {
    let rawPath = CommandLine.arguments.first ?? "macos-gesture-launcher"
    let expanded = expandTilde(rawPath)
    let url: URL
    if expanded.hasPrefix("/") {
        url = URL(fileURLWithPath: expanded)
    } else {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
    }
    return url.resolvingSymlinksInPath().path
}
