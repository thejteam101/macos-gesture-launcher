import CoreFoundation
import Darwin
import Foundation

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout
    var zero2: (Int32, Int32)
    var density: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallbackFunction = @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) -> Int32
typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>?
typealias MTRegisterContactFrameCallbackFunc = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
typealias MTUnregisterContactFrameCallbackFunc = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
typealias MTDeviceStartFunc = @convention(c) (MTDeviceRef, Int32) -> Void
typealias MTDeviceStopFunc = @convention(c) (MTDeviceRef, Int32) -> Void

enum MultitouchSupport {
    // These symbols are loaded once on startup and used from a C callback.
    nonisolated(unsafe) static var handle: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var deviceCreateList: MTDeviceCreateListFunc?
    nonisolated(unsafe) static var registerCallback: MTRegisterContactFrameCallbackFunc?
    nonisolated(unsafe) static var unregisterCallback: MTUnregisterContactFrameCallbackFunc?
    nonisolated(unsafe) static var deviceStart: MTDeviceStartFunc?
    nonisolated(unsafe) static var deviceStop: MTDeviceStopFunc?

    static func load(debug: Bool) -> Bool {
        if handle != nil {
            return true
        }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let opened = dlopen(path, RTLD_NOW) else {
            Logger.info("Failed to load MultitouchSupport framework.")
            return false
        }
        handle = opened

        deviceCreateList = loadSymbol("MTDeviceCreateList", as: MTDeviceCreateListFunc.self)
        registerCallback = loadSymbol("MTRegisterContactFrameCallback", as: MTRegisterContactFrameCallbackFunc.self)
        unregisterCallback = loadSymbol("MTUnregisterContactFrameCallback", as: MTUnregisterContactFrameCallbackFunc.self)
        deviceStart = loadSymbol("MTDeviceStart", as: MTDeviceStartFunc.self)
        deviceStop = loadSymbol("MTDeviceStop", as: MTDeviceStopFunc.self)

        if deviceCreateList == nil || registerCallback == nil || deviceStart == nil {
            Logger.info("MultitouchSupport missing required symbols.")
            return false
        }
        if debug {
            Logger.info("MultitouchSupport loaded.")
        }
        return true
    }

    private static func loadSymbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = handle, let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

struct TouchPoint: Sendable {
    let x: Double
    let y: Double
    let state: Int32
}

actor TouchPinchDetector {
    private let requiredTouches: Int
    private let engine: GestureEngine
    private let debug: Bool
    private var active = false
    private var startDistance: Double = 0
    private var lastDistance: Double = 0
    private var lastTouchCount: Int = -1

    init(requiredTouches: Int, engine: GestureEngine, debug: Bool) {
        self.requiredTouches = requiredTouches
        self.engine = engine
        self.debug = debug
    }

    func handleFrame(_ points: [TouchPoint]) async {
        let activePoints = points.filter { $0.state != 0 }
        let count = activePoints.count
        if debug, count != lastTouchCount {
            lastTouchCount = count
            Logger.info("touches: \(count) required=\(requiredTouches)")
        }
        if count >= requiredTouches {
            let sample = Array(activePoints.prefix(requiredTouches))
            let distance = averageDistance(sample)
            if !active {
                active = true
                startDistance = distance
                lastDistance = distance
                if debug {
                    Logger.info("pinch start: distance=\(Logger.formatMagnitude(distance)) touches=\(requiredTouches)")
                }
            } else {
                lastDistance = distance
            }
        } else if active {
            let magnitude = startDistance > 0 ? (lastDistance - startDistance) / startDistance : 0
            active = false
            if debug {
                Logger.info(
                    "pinch end: start=\(Logger.formatMagnitude(startDistance)) end=\(Logger.formatMagnitude(lastDistance)) rel=\(Logger.formatMagnitude(magnitude)) touches=\(requiredTouches)"
                )
            }
            await engine.handleGestureMagnitude(magnitude, touches: requiredTouches)
        }
    }

    private func averageDistance(_ points: [TouchPoint]) -> Double {
        guard !points.isEmpty else {
            return 0
        }
        let count = Double(points.count)
        let centerX = points.reduce(0.0) { $0 + $1.x } / count
        let centerY = points.reduce(0.0) { $0 + $1.y } / count
        let sum = points.reduce(0.0) { total, point in
            total + hypot(point.x - centerX, point.y - centerY)
        }
        return sum / count
    }
}

final class MultiTouchListener {
    nonisolated(unsafe) static var shared: MultiTouchListener?

    private let detectors: [TouchPinchDetector]
    private let debug: Bool
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray? // Hold CFArray lifetime for MTDevice pointers.
    private var started = false

    init(engine: GestureEngine, touchCounts: [Int], debug: Bool) {
        self.detectors = touchCounts.map { TouchPinchDetector(requiredTouches: $0, engine: engine, debug: debug) }
        self.debug = debug
    }

    func start() {
        guard !started else {
            return
        }
        started = true
        MultiTouchListener.shared = self
        guard MultitouchSupport.load(debug: debug) else {
            Logger.info("MultitouchSupport not available.")
            return
        }
        guard let createList = MultitouchSupport.deviceCreateList else {
            Logger.info("MultitouchSupport device list unavailable.")
            return
        }
        guard let listRef = createList() else {
            Logger.info("MultitouchSupport returned no devices.")
            return
        }

        let list = listRef.takeUnretainedValue()
        deviceList = list
        let count = CFArrayGetCount(list)
        if count == 0 {
            Logger.info("No multitouch devices found.")
            return
        }

        for index in 0..<count {
            let value = CFArrayGetValueAtIndex(list, index)
            let device = unsafeBitCast(value, to: MTDeviceRef.self)
            devices.append(device)
            MultitouchSupport.registerCallback?(device, mtCallback)
            MultitouchSupport.deviceStart?(device, 0)
        }
        if debug {
            Logger.info("Multitouch devices registered: \(devices.count)")
        }
    }

    fileprivate func handleTouches(_ points: [TouchPoint]) {
        let detectors = detectors
        Task {
            for detector in detectors {
                await detector.handleFrame(points)
            }
        }
    }
}

private func mtCallback(
    _ device: MTDeviceRef,
    _ touches: UnsafeMutableRawPointer,
    _ count: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    guard let listener = MultiTouchListener.shared, count > 0 else {
        return 0
    }
    let typedTouches = touches.assumingMemoryBound(to: MTTouch.self)
    let buffer = UnsafeBufferPointer(start: typedTouches, count: Int(count))
    var points: [TouchPoint] = []
    points.reserveCapacity(buffer.count)
    for touch in buffer {
        let point = TouchPoint(
            x: Double(touch.normalized.position.x),
            y: Double(touch.normalized.position.y),
            state: touch.state
        )
        points.append(point)
    }
    listener.handleTouches(points)
    return 0
}
