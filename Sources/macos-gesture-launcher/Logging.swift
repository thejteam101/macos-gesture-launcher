import Foundation

enum Logger {
    static func info(_ message: String) {
        let line = "[macos-gesture-launcher] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    static func debug(_ enabled: Bool, _ message: @autoclosure () -> String) {
        if enabled {
            info(message())
        }
    }

    static func formatMagnitude(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
