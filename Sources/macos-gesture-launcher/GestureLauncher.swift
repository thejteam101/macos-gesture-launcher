import AppKit
import CoreGraphics
import Foundation

final class GestureLauncher {
    private let actions: [GestureAction]
    private let engine: GestureEngine
    private let debug: Bool
    private let multitouchTouches: [Int]
    private var monitor: Any?
    private var multitouchListener: MultiTouchListener?

    init(config: Config, debug: Bool) {
        let cooldown = config.cooldownMs ?? Defaults.cooldownMs
        let idleWindow = config.idleWindowMs ?? Defaults.idleWindowMs
        let minMagnitude = config.minGestureMagnitude ?? Defaults.minGestureMagnitude
        self.actions = GestureLauncher.makeActions(from: config.gestures)
        self.debug = debug
        let touchSet = Set(actions.map { $0.touches }).filter { $0 >= 3 }
        self.multitouchTouches = touchSet.sorted()
        self.engine = GestureEngine(
            actions: actions,
            idleWindowMs: idleWindow,
            cooldownMs: cooldown,
            minMagnitude: minMagnitude,
            debug: debug
        )
        Logger.debug(
            debug,
            "config: cooldown_ms=\(cooldown) idle_window_ms=\(idleWindow) min_gesture_magnitude=\(Logger.formatMagnitude(minMagnitude))"
        )
        if debug {
            for action in actions {
                Logger.info(
                    "action: pinch \(action.direction.rawValue) touches=\(action.touches) threshold=\(Logger.formatMagnitude(action.threshold)) -> \(action.targetDescription)"
                )
            }
        }
    }

    func start() {
        guard !actions.isEmpty else {
            Logger.info("No usable gestures found in config.")
            exit(1)
        }
        ensureInputMonitoringPermission(debug: debug)

        let mask: NSEvent.EventTypeMask = debug
            ? [.magnify, .gesture, .beginGesture, .endGesture, .smartMagnify]
            : [.magnify]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [engine, debug] event in
            if debug {
                let phase = event.phase.rawValue
                Logger.info(
                    "event: type=\(event.type) phase=\(phase) magnify=\(Logger.formatMagnitude(Double(event.magnification)))"
                )
            }
            if event.type == .magnify {
                let magnification = Double(event.magnification)
                Task {
                    await engine.handleMagnification(magnification)
                }
            }
        }
        if monitor == nil {
            Logger.info("Unable to install global event monitor. Check Input Monitoring permissions.")
            exit(1)
        }
        if !multitouchTouches.isEmpty {
            let listener = MultiTouchListener(engine: engine, touchCounts: multitouchTouches, debug: debug)
            listener.start()
            multitouchListener = listener
            Logger.debug(debug, "Multitouch enabled for touches: \(multitouchTouches)")
        } else {
            Logger.debug(debug, "Multitouch disabled: no gestures require 3+ touches.")
        }
        Logger.info("Listening for pinch gestures...")
    }

    private static func makeActions(from configs: [GestureConfig]) -> [GestureAction] {
        var actions: [GestureAction] = []
        for gesture in configs {
            if gesture.type.lowercased() != "pinch" {
                Logger.info("Skipping unsupported gesture type: \(gesture.type)")
                continue
            }
            guard let directionValue = gesture.direction?.lowercased(),
                  let direction = GestureDirection(rawValue: directionValue) else {
                Logger.info("Skipping pinch gesture without direction (in/out).")
                continue
            }
            let touches = max(gesture.touches ?? Defaults.touches, 1)
            let threshold = abs(gesture.threshold ?? Defaults.threshold)
            let action = GestureAction(
                direction: direction,
                threshold: threshold,
                touches: touches,
                app: gesture.app,
                bundleId: gesture.bundleId
            )
            actions.append(action)
        }
        return actions
    }
}

func ensureInputMonitoringPermission(debug: Bool) {
    if #available(macOS 10.15, *) {
        if CGPreflightListenEventAccess() {
            Logger.debug(debug, "Input Monitoring permission OK.")
            return
        }
        Logger.info("Input Monitoring permission missing. Requesting...")
        let granted = CGRequestListenEventAccess()
        if !granted {
            Logger.info("Input Monitoring not granted. Enable it in System Settings -> Privacy & Security -> Input Monitoring.")
        }
    }
}
