import Foundation

enum AppLauncher {
    static func open(_ action: GestureAction, debug: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if let bundleId = action.bundleId {
            task.arguments = ["-b", bundleId]
        } else if let app = action.app {
            task.arguments = ["-a", app]
        } else {
            Logger.info("Gesture has no app or bundle_id configured.")
            return
        }
        do {
            Logger.debug(debug, "Launching: \(action.targetDescription)")
            try task.run()
        } catch {
            Logger.info("Failed to launch app: \(error)")
        }
    }
}
