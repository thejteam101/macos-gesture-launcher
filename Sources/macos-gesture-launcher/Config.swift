import Foundation

enum Defaults {
    static let cooldownMs = 700
    static let idleWindowMs = 150
    static let minGestureMagnitude = 0.1
    static let touches = 2
    static let threshold = 0.6
}

struct Config: Decodable {
    let gestures: [GestureConfig]
    let cooldownMs: Int?
    let idleWindowMs: Int?
    let minGestureMagnitude: Double?

    enum CodingKeys: String, CodingKey {
        case gestures
        case cooldownMs = "cooldown_ms"
        case idleWindowMs = "idle_window_ms"
        case minGestureMagnitude = "min_gesture_magnitude"
    }
}

struct GestureConfig: Decodable {
    let type: String
    let direction: String?
    let threshold: Double?
    let touches: Int?
    let app: String?
    let bundleId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case direction
        case threshold
        case touches
        case app
        case bundleId = "bundle_id"
    }
}

enum GestureDirection: String {
    case `in`
    case out
}

struct GestureAction {
    let direction: GestureDirection
    let threshold: Double
    let touches: Int
    let app: String?
    let bundleId: String?

    var targetDescription: String {
        bundleId ?? app ?? "unknown"
    }

    func matches(magnitude: Double, touches: Int?) -> Bool {
        if let touches, touches != self.touches {
            return false
        }
        let limit = abs(threshold)
        switch direction {
        case .in:
            return magnitude <= -limit
        case .out:
            return magnitude >= limit
        }
    }
}
