import Dispatch
import Foundation

actor GestureEngine {
    private let actions: [GestureAction]
    private let idleWindowNs: UInt64
    private let cooldownNs: UInt64
    private let minMagnitude: Double
    private let debug: Bool
    private var accumulator: Double = 0
    private var lastEventTime: UInt64 = 0
    private var lastTriggerTime: UInt64 = 0
    private var pendingTask: Task<Void, Never>?

    init(actions: [GestureAction], idleWindowMs: Int, cooldownMs: Int, minMagnitude: Double, debug: Bool) {
        self.actions = actions
        self.idleWindowNs = UInt64(max(idleWindowMs, 10)) * 1_000_000
        self.cooldownNs = UInt64(max(cooldownMs, 0)) * 1_000_000
        self.minMagnitude = max(minMagnitude, 0)
        self.debug = debug
    }

    func handleMagnification(_ magnification: Double) {
        if magnification == 0 {
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastEventTime > idleWindowNs {
            accumulator = 0
        }
        lastEventTime = now
        accumulator += magnification
        Logger.debug(
            debug,
            "magnify: delta=\(Logger.formatMagnitude(magnification)) total=\(Logger.formatMagnitude(accumulator))"
        )
        scheduleEmit()
    }

    func handleGestureMagnitude(_ magnitude: Double, touches: Int) {
        evaluate(magnitude: magnitude, touches: touches)
    }

    private func scheduleEmit() {
        pendingTask?.cancel()
        let idleWindowNs = idleWindowNs
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: idleWindowNs)
            if Task.isCancelled {
                return
            }
            await self?.emitIfNeeded()
        }
    }

    private func emitIfNeeded() {
        defer { accumulator = 0 }
        evaluate(magnitude: accumulator, touches: 2)
    }

    private func evaluate(magnitude: Double, touches: Int?) {
        if abs(magnitude) < minMagnitude {
            Logger.debug(
                debug,
                "gesture ignored: total=\(Logger.formatMagnitude(magnitude)) below min=\(Logger.formatMagnitude(minMagnitude)) touches=\(touches ?? -1)"
            )
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastTriggerTime < cooldownNs {
            Logger.debug(debug, "gesture ignored: cooldown active touches=\(touches ?? -1)")
            return
        }
        lastTriggerTime = now
        for action in actions where action.matches(magnitude: magnitude, touches: touches) {
            Logger.debug(
                debug,
                "gesture match: direction=\(action.direction.rawValue) threshold=\(Logger.formatMagnitude(action.threshold)) total=\(Logger.formatMagnitude(magnitude)) touches=\(action.touches)"
            )
            AppLauncher.open(action, debug: debug)
            return
        }
        Logger.debug(
            debug,
            "gesture ignored: no action matched total=\(Logger.formatMagnitude(magnitude)) touches=\(touches ?? -1)"
        )
    }
}
