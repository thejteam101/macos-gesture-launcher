// Version: v0.1.9
import Cocoa
import Foundation
import ApplicationServices

// MARK: - Private MultitouchSupport C-Bindings (Aligned with exact 96-Byte C Stride)
struct MTContact {
    var frame: Int32          // 4 bytes (offset 0)
    var timestamp: Double     // 8 bytes (offset 8)
    var identifier: Int32     // 4 bytes (offset 16)
    var state: Int32          // 4 bytes (offset 20)
    var size: Float           // 4 bytes (offset 24)
    var unknown1: Int32       // 4 bytes (offset 28)
    var x: Float              // 4 bytes (offset 32)
    var y: Float              // 4 bytes (offset 36)
    var vx: Float             // 4 bytes (offset 40)
    var vy: Float             // 4 bytes (offset 44)
    var majorAxis: Float      // 4 bytes (offset 48)
    var minorAxis: Float      // 4 bytes (offset 52)
    var unknown2_1: Int32     // 4 bytes (offset 56)
    var unknown2_2: Int32     // 4 bytes (offset 60)
    var unknown2_3: Int32     // 4 bytes (offset 64)
    var orientation: Float    // 4 bytes (offset 68)
    var unknown3_1: Int32     // 4 bytes (offset 72)
    var unknown3_2: Int32     // 4 bytes (offset 76)
    var padding1: Int64       // 8 bytes (offset 80)
    var padding2: Int64       // 8 bytes (offset 88)
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

@_silgen_name("MTDeviceCreateDefault")
func MTDeviceCreateDefault() -> MTDeviceRef?

@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallback)

@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ flags: Int32)

// MARK: - Application Data Model
struct AppInfo {
    let name: String
    let bundleID: String
    let icon: NSImage
}

// MARK: - System Actions
enum SystemAction: String, CaseIterable {
    case missionControl = "sys:mission_control"
    case showDesktop = "sys:show_desktop"
    case spotlight = "sys:spotlight"
    case sleepDisplay = "sys:sleep_display"
    case playPause = "sys:play_pause"
    case skipForward = "sys:skip_forward"
    case skipBack = "sys:skip_back"
    case mute = "sys:mute"
    
    var title: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        case .spotlight: return "Spotlight Search"
        case .sleepDisplay: return "Sleep Display"
        case .playPause: return "Play / Pause"
        case .skipForward: return "Skip Forward"
        case .skipBack: return "Skip Backward"
        case .mute: return "Mute / Unmute"
        }
    }
    
    var icon: NSImage? {
        switch self {
        case .missionControl: return NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        case .showDesktop: return NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        case .spotlight: return NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        case .sleepDisplay: return NSImage(systemSymbolName: "display.sleep", accessibilityDescription: nil)
        case .playPause: return NSImage(systemSymbolName: "playpause.fill", accessibilityDescription: nil)
        case .skipForward: return NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil)
        case .skipBack: return NSImage(systemSymbolName: "backward.fill", accessibilityDescription: nil)
        case .mute: return NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil)
        }
    }
}

// MARK: - Gesture Types
enum GestureType: String, CaseIterable {
    case pinch = "Pinch (Inward)"
    case spread = "Spread (Outward)"
    case swipeUp = "Swipe Up (4+ Fingers)"
    case swipeDown = "Swipe Down (4+ Fingers)"
    case swipeLeft = "Swipe Left (4+ Fingers)"
    case swipeRight = "Swipe Right (4+ Fingers)"
    
    var defaultsKey: String { "GestureMapping_\(self.rawValue)" }
}

// MARK: - Gesture Engine State
final class GestureEngine {
    static let shared = GestureEngine()
    
    var isPaused: Bool = false
    
    // Retrieves the mapped bundle ID for a given gesture
    func getAction(for gesture: GestureType) -> String? {
        return UserDefaults.standard.string(forKey: gesture.defaultsKey)
    }
    
    // Sets the mapped bundle ID for a given gesture
    func setAction(_ bundleID: String?, for gesture: GestureType) {
        if let id = bundleID {
            UserDefaults.standard.set(id, forKey: gesture.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: gesture.defaultsKey)
        }
    }
    
    var pinchThreshold: Double {
        get { 
            let val = UserDefaults.standard.double(forKey: "PinchThreshold")
            return val == 0 ? 0.035 : val // Default to Medium (0.035)
        }
        set { UserDefaults.standard.set(newValue, forKey: "PinchThreshold") }
    }
    
    var cooldownInterval: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: "CooldownInterval")
            return val == 0 ? 1.0 : val // Default to Normal (1.0s)
        }
        set { UserDefaults.standard.set(newValue, forKey: "CooldownInterval") }
    }
    
    var soundFeedbackEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "SoundFeedbackEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "SoundFeedbackEnabled") }
    }
    
    var hapticFeedbackEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "HapticFeedbackEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "HapticFeedbackEnabled") }
    }
    
    var hapticPattern: NSHapticFeedbackManager.FeedbackPattern {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "HapticPatternRawValue")
            switch rawValue {
            case 1: return .alignment
            case 2: return .levelChange
            default: return .generic
            }
        }
        set {
            var rawValue = 0
            switch newValue {
            case .alignment: rawValue = 1
            case .levelChange: rawValue = 2
            default: rawValue = 0
            }
            UserDefaults.standard.set(rawValue, forKey: "HapticPatternRawValue")
        }
    }
    
    private var state: GestureState = .idle
    private var lastTriggerTime: Date = .distantPast

    enum GestureState {
        case idle
        case tracking(initialDistance: Double, initialX: Float, initialY: Float)
        case cooldown
    }

    func handleTouches(contacts: UnsafeMutablePointer<MTContact>, count: Int) {
        if isPaused { return }
        if Date().timeIntervalSince(lastTriggerTime) < cooldownInterval { return }
        
        // BIG-O OPTIMIZATION: Zero-Allocation Traversal (O(1) Space, O(N) Time)
        // We traverse the C pointer memory directly to avoid allocating expensive Swift arrays in a 60Hz loop.
        var activeCount = 0
        var sumX: Float = 0.0
        var sumY: Float = 0.0
        
        for i in 0..<count {
            let s = contacts[i].state
            if s >= 1 && s <= 4 { // 1 = Down, 2 = Moving, 3 = Hover, 4 = Stationary
                activeCount += 1
                sumX += contacts[i].x
                sumY += contacts[i].y
            }
        }
        
        guard activeCount >= 4 else {
            state = .idle
            return
        }
        
        let avgX = sumX / Float(activeCount)
        let avgY = sumY / Float(activeCount)
        
        var totalDistance: Double = 0.0
        for i in 0..<count {
            let s = contacts[i].state
            if s >= 1 && s <= 4 {
                let dx = Double(contacts[i].x - avgX)
                let dy = Double(contacts[i].y - avgY)
                totalDistance += sqrt((dx * dx) + (dy * dy))
            }
        }
        
        let currentAvgDistance = totalDistance / Double(activeCount)
        
        switch state {
        case .idle:
            state = .tracking(initialDistance: currentAvgDistance, initialX: avgX, initialY: avgY)
            
        case .tracking(let initialDistance, let initialX, let initialY):
            let deltaDist = initialDistance - currentAvgDistance // positive = pinch, negative = spread
            let deltaX = Double(avgX - initialX)                 // positive = right, negative = left
            let deltaY = Double(avgY - initialY)                 // positive = up, negative = down
            
            let absDist = abs(deltaDist) / pinchThreshold
            let absX = abs(deltaX) / (pinchThreshold * 1.5)
            let absY = abs(deltaY) / (pinchThreshold * 1.5)
            
            let maxMove = max(absDist, absX, absY)
            
            if maxMove >= 1.0 {
                let gesture: GestureType
                if maxMove == absDist {
                    gesture = deltaDist > 0 ? .pinch : .spread
                } else if maxMove == absX {
                    gesture = deltaX > 0 ? .swipeRight : .swipeLeft
                } else {
                    gesture = deltaY > 0 ? .swipeUp : .swipeDown
                }
                
                triggerAction(for: gesture)
                state = .cooldown
                lastTriggerTime = Date()
            }
            
        case .cooldown:
            break
        }
    }
    
    private func triggerAction(for gesture: GestureType) {
        guard let bundleID = getAction(for: gesture), bundleID != "action:none" else { return }
        
        DispatchQueue.main.async {
            let onActivationSuccess = {
                DispatchQueue.main.async {
                    if self.soundFeedbackEnabled { NSSound(named: "Pop")?.play() }
                    if self.hapticFeedbackEnabled { NSHapticFeedbackManager.defaultPerformer.perform(self.hapticPattern, performanceTime: .now) }
                }
            }
            
            if bundleID.starts(with: "sys:") {
                self.performSystemAction(bundleID)
                onActivationSuccess()
                return
            }
            
            let workspace = NSWorkspace.shared
            if let runningApp = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                runningApp.activate(options: [.activateAllWindows])
                if let bundleURL = runningApp.bundleURL {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    workspace.openApplication(at: bundleURL, configuration: config) { _, error in
                        if error == nil { onActivationSuccess() }
                    }
                } else {
                    onActivationSuccess()
                }
            } else {
                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    workspace.openApplication(at: appURL, configuration: config) { _, error in
                        if error == nil { onActivationSuccess() }
                    }
                }
            }
        }
    }
    
    private func performSystemAction(_ id: String) {
        func sendMediaKey(_ key: Int32) {
            let eventDown = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: 0xa00), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: Int((key << 16) | ((0xa) << 8)), data2: -1)
            let eventUp = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: 0xb00), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: Int((key << 16) | ((0xb) << 8)), data2: -1)
            eventDown?.cgEvent?.post(tap: .cghidEventTap)
            eventUp?.cgEvent?.post(tap: .cghidEventTap)
        }
        
        switch id {
        case "sys:mission_control":
            NSAppleScript(source: "tell application \"Mission Control\" to launch")?.executeAndReturnError(nil)
        case "sys:show_desktop":
            NSAppleScript(source: "tell application \"System Events\" to key code 103")?.executeAndReturnError(nil)
        case "sys:spotlight":
            NSAppleScript(source: "tell application \"System Events\" to key code 49 using command down")?.executeAndReturnError(nil)
        case "sys:sleep_display":
            NSAppleScript(source: "tell application \"Finder\" to sleep")?.executeAndReturnError(nil)
        case "sys:play_pause": sendMediaKey(16)
        case "sys:skip_forward": sendMediaKey(17)
        case "sys:skip_back": sendMediaKey(18)
        case "sys:mute": sendMediaKey(7)
        default: break
        }
    }
}

// MARK: - App GUI & Lifecycle
final class AppDelegate: NSObject, NSApplicationDelegate, NSSearchFieldDelegate {
    var device: MTDeviceRef?
    var statusItem: NSStatusItem?
    var appsSubmenu = NSMenu()
    var searchField = NSSearchField()
    var cachedApps: [AppInfo] = []
    
    var permissionTimer: Timer?
    var isDriverActive = false
    var isAppCacheLoaded = false
    
    var currentEditingGesture: GestureType = .pinch
    
    var recentBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "RecentSearchedApps") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(5)), forKey: "RecentSearchedApps") }
    }
    
    private var launchAgentURL: URL {
        let libraryFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").appendingPathComponent("LaunchAgents")
        return libraryFolder.appendingPathComponent("com.gesturelauncher.plist")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarGUI()
        checkAndInitializeDriver()
        
        // BIG-O OPTIMIZATION: Non-blocking Async Loading
        // Prevents the main thread from stalling on launch while scanning the hard drive for applications
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let discovered = self?.discoverApplications() ?? []
            DispatchQueue.main.async {
                self?.cachedApps = discovered
                self?.isAppCacheLoaded = true
                self?.updateAppsList(filter: nil)
            }
        }
    }
    
    private func checkAndInitializeDriver() {
        if checkAccessibilityPermission(promptIfNeeded: false) {
            startTrackpadDriver()
        } else {
            promptForAccessibility()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                if self.checkAccessibilityPermission(promptIfNeeded: false) {
                    self.startTrackpadDriver()
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }
    
    private func startTrackpadDriver() {
        guard !isDriverActive else { return }
        guard let trackpadDevice = MTDeviceCreateDefault() else { return }
        self.device = trackpadDevice
        
        MTRegisterContactFrameCallback(trackpadDevice) { device, rawContacts, count, timestamp, frame in
            if let rawContacts = rawContacts {
                let typedContacts = rawContacts.assumingMemoryBound(to: MTContact.self)
                GestureEngine.shared.handleTouches(contacts: typedContacts, count: Int(count))
            }
            return 0
        }
        
        MTDeviceStart(trackpadDevice, 0)
        isDriverActive = true
        
        DispatchQueue.main.async {
            self.updateMenuBarIcon()
            self.updateAppsList(filter: nil)
        }
    }
    
    private func checkAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func promptForAccessibility() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "Gesture Launcher needs Accessibility permissions to detect trackpad pinch gestures.\n\nPlease click 'Open System Settings' below, enable 'GestureLauncher' in the list, and the app will activate automatically."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.openAccessibilitySettings()
            }
        }
    }

    private func openAccessibilitySettings() {
        _ = checkAccessibilityPermission(promptIfNeeded: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupMenuBarGUI() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        
        let mainMenu = NSMenu()
        let headerItem = NSMenuItem(title: "Gesture Launcher v0.1.9", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        mainMenu.addItem(headerItem)
        mainMenu.addItem(NSMenuItem.separator())
        
        // Pause Gestures Toggle
        let pauseItem = NSMenuItem(title: "Pause Gestures", action: #selector(togglePauseGestures(_:)), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.state = GestureEngine.shared.isPaused ? .on : .off
        mainMenu.addItem(pauseItem)
        mainMenu.addItem(NSMenuItem.separator())
        
        // --- 1. Gesture Selection Submenu ---
        let editGestureMenu = NSMenu()
        for type in GestureType.allCases {
            let item = NSMenuItem(title: type.rawValue, action: #selector(selectGestureToEdit(_:)), keyEquivalent: "")
            item.representedObject = type
            item.target = self
            item.state = (type == currentEditingGesture) ? .on : .off
            editGestureMenu.addItem(item)
        }
        let editGestureParent = NSMenuItem(title: "Configuring: \(currentEditingGesture.rawValue)", action: nil, keyEquivalent: "")
        editGestureParent.submenu = editGestureMenu
        editGestureParent.tag = 101 
        mainMenu.addItem(editGestureParent)
        
        // --- 2. Action / App Mapping Submenu ---
        let searchContainer = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        searchField = NSRect(x: 10, y: 4, width: 220, height: 22).makeSearchField()
        searchField.delegate = self
        searchField.placeholderString = "Search Apps & Actions..."
        searchContainer.addSubview(searchField)
        
        let searchMenuItem = NSMenuItem()
        searchMenuItem.view = searchContainer
        appsSubmenu.addItem(searchMenuItem)
        appsSubmenu.addItem(NSMenuItem.separator())
        
        let disableItem = NSMenuItem(title: "None (Disabled)", action: #selector(selectAppTarget(_:)), keyEquivalent: "")
        disableItem.representedObject = "action:none"
        disableItem.target = self
        appsSubmenu.addItem(disableItem)
        appsSubmenu.addItem(NSMenuItem.separator())
        
        updateAppsList(filter: nil)
        
        let currentTargetID = GestureEngine.shared.getAction(for: currentEditingGesture)
        let mappedAppName = getAppName(forBundleID: currentTargetID)
        let actionParent = NSMenuItem(title: "Action: \(mappedAppName)", action: nil, keyEquivalent: "")
        actionParent.submenu = appsSubmenu
        actionParent.tag = 102
        mainMenu.addItem(actionParent)
        mainMenu.addItem(NSMenuItem.separator())
        
        // --- Settings & Sensitivity ---
        let sensitivityMenu = NSMenu()
        let sensHigh = NSMenuItem(title: "High (More Responsive)", action: #selector(setSensitivityPreset(_:)), keyEquivalent: "")
        sensHigh.representedObject = Double(0.02)
        sensHigh.target = self
        sensHigh.state = GestureEngine.shared.pinchThreshold == 0.02 ? .on : .off
        
        let sensMed = NSMenuItem(title: "Medium (Default)", action: #selector(setSensitivityPreset(_:)), keyEquivalent: "")
        sensMed.representedObject = Double(0.035)
        sensMed.target = self
        sensMed.state = GestureEngine.shared.pinchThreshold == 0.035 ? .on : .off
        
        let sensLow = NSMenuItem(title: "Low (Requires Hard Pinch)", action: #selector(setSensitivityPreset(_:)), keyEquivalent: "")
        sensLow.representedObject = Double(0.05)
        sensLow.target = self
        sensLow.state = GestureEngine.shared.pinchThreshold == 0.05 ? .on : .off
        
        sensitivityMenu.addItem(sensHigh)
        sensitivityMenu.addItem(sensMed)
        sensitivityMenu.addItem(sensLow)
        
        let sensitivityParent = NSMenuItem(title: "Physical Sensitivity", action: nil, keyEquivalent: "")
        sensitivityParent.submenu = sensitivityMenu
        mainMenu.addItem(sensitivityParent)
        
        // --- Cooldown Menu ---
        let cooldownMenu = NSMenu()
        let coolFast = NSMenuItem(title: "Fast (0.5s)", action: #selector(setCooldownPreset(_:)), keyEquivalent: "")
        coolFast.representedObject = Double(0.5)
        coolFast.target = self
        coolFast.state = GestureEngine.shared.cooldownInterval == 0.5 ? .on : .off
        
        let coolMed = NSMenuItem(title: "Normal (1.0s)", action: #selector(setCooldownPreset(_:)), keyEquivalent: "")
        coolMed.representedObject = Double(1.0)
        coolMed.target = self
        coolMed.state = GestureEngine.shared.cooldownInterval == 1.0 ? .on : .off
        
        let coolSlow = NSMenuItem(title: "Relaxed (1.5s)", action: #selector(setCooldownPreset(_:)), keyEquivalent: "")
        coolSlow.representedObject = Double(1.5)
        coolSlow.target = self
        coolSlow.state = GestureEngine.shared.cooldownInterval == 1.5 ? .on : .off
        
        cooldownMenu.addItem(coolFast)
        cooldownMenu.addItem(coolMed)
        cooldownMenu.addItem(coolSlow)
        
        let cooldownParent = NSMenuItem(title: "Gesture Cooldown", action: nil, keyEquivalent: "")
        cooldownParent.submenu = cooldownMenu
        mainMenu.addItem(cooldownParent)
        
        let soundToggle = NSMenuItem(title: "Play Sound on Gesture", action: #selector(toggleSoundFeedback(_:)), keyEquivalent: "")
        soundToggle.target = self
        soundToggle.state = GestureEngine.shared.soundFeedbackEnabled ? .on : .off
        mainMenu.addItem(soundToggle)
        
        let hapticToggle = NSMenuItem(title: "Haptic Feedback on Gesture", action: #selector(toggleHapticFeedback(_:)), keyEquivalent: "")
        hapticToggle.target = self
        hapticToggle.state = GestureEngine.shared.hapticFeedbackEnabled ? .on : .off
        mainMenu.addItem(hapticToggle)
        
        let hapticMenu = NSMenu()
        let hapGeneric = NSMenuItem(title: "Click (Generic)", action: #selector(setHapticPreset(_:)), keyEquivalent: "")
        hapGeneric.representedObject = 0
        hapGeneric.target = self
        hapGeneric.state = GestureEngine.shared.hapticPattern == .generic ? .on : .off
        
        let hapLevel = NSMenuItem(title: "Snap (Level Change)", action: #selector(setHapticPreset(_:)), keyEquivalent: "")
        hapLevel.representedObject = 2
        hapLevel.target = self
        hapLevel.state = GestureEngine.shared.hapticPattern == .levelChange ? .on : .off
        
        let hapAlign = NSMenuItem(title: "Thud (Alignment)", action: #selector(setHapticPreset(_:)), keyEquivalent: "")
        hapAlign.representedObject = 1
        hapAlign.target = self
        hapAlign.state = GestureEngine.shared.hapticPattern == .alignment ? .on : .off
        
        hapticMenu.addItem(hapGeneric)
        hapticMenu.addItem(hapLevel)
        hapticMenu.addItem(hapAlign)
        
        let hapticParent = NSMenuItem(title: "Haptic Style", action: nil, keyEquivalent: "")
        hapticParent.submenu = hapticMenu
        mainMenu.addItem(hapticParent)
        
        mainMenu.addItem(NSMenuItem.separator())
        
        let launchLoginToggle = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchLoginToggle.target = self
        launchLoginToggle.state = isLaunchAtLoginEnabled() ? .on : .off
        mainMenu.addItem(launchLoginToggle)
        
        mainMenu.addItem(NSMenuItem.separator())
        mainMenu.addItem(NSMenuItem(title: "Quit Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = mainMenu
    }
    
    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        if GestureEngine.shared.isPaused {
            button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Gestures Paused")
        } else if isDriverActive {
            button.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Gesture Launcher")
        } else {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Permissions Blocked")
        }
        button.image?.isTemplate = true
    }
    
    @objc func togglePauseGestures(_ sender: NSMenuItem) {
        GestureEngine.shared.isPaused.toggle()
        sender.state = GestureEngine.shared.isPaused ? .on : .off
        updateMenuBarIcon()
    }
    
    @objc func selectGestureToEdit(_ sender: NSMenuItem) {
        guard let newGesture = sender.representedObject as? GestureType else { return }
        currentEditingGesture = newGesture
        
        if let parentMenu = sender.menu {
            for item in parentMenu.items { item.state = (item == sender) ? .on : .off }
        }
        
        if let mainMenu = statusItem?.menu {
            if let gestureTitleItem = mainMenu.item(withTag: 101) {
                gestureTitleItem.title = "Configuring: \(newGesture.rawValue)"
            }
            if let actionTitleItem = mainMenu.item(withTag: 102) {
                let currentTargetID = GestureEngine.shared.getAction(for: newGesture)
                actionTitleItem.title = "Action: \(getAppName(forBundleID: currentTargetID))"
            }
        }
        updateAppsList(filter: nil)
    }
    
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enable = (sender.state == .off)
        setLaunchAtLogin(enabled: enable)
        sender.state = enable ? .on : .off
    }
    
    @objc func toggleSoundFeedback(_ sender: NSMenuItem) {
        let enable = (sender.state == .off)
        GestureEngine.shared.soundFeedbackEnabled = enable
        sender.state = enable ? .on : .off
    }
    
    @objc func toggleHapticFeedback(_ sender: NSMenuItem) {
        let enable = (sender.state == .off)
        GestureEngine.shared.hapticFeedbackEnabled = enable
        sender.state = enable ? .on : .off
    }
    
    @objc func setSensitivityPreset(_ sender: NSMenuItem) {
        guard let threshold = sender.representedObject as? Double else { return }
        GestureEngine.shared.pinchThreshold = threshold
        if let parentMenu = sender.menu {
            for item in parentMenu.items { item.state = (item == sender) ? .on : .off }
        }
    }
    
    @objc func setCooldownPreset(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? Double else { return }
        GestureEngine.shared.cooldownInterval = interval
        if let parentMenu = sender.menu {
            for item in parentMenu.items { item.state = (item == sender) ? .on : .off }
        }
    }
    
    @objc func setHapticPreset(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int else { return }
        switch rawValue {
        case 1: GestureEngine.shared.hapticPattern = .alignment
        case 2: GestureEngine.shared.hapticPattern = .levelChange
        default: GestureEngine.shared.hapticPattern = .generic
        }
        
        if let parentMenu = sender.menu {
            for item in parentMenu.items { item.state = (item == sender) ? .on : .off }
        }
        
        if GestureEngine.shared.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(GestureEngine.shared.hapticPattern, performanceTime: .now)
        }
    }
    
    private func isLaunchAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        let fileManager = FileManager.default
        if enabled {
            let execPath = CommandLine.arguments[0]
            let absPath = URL(fileURLWithPath: execPath).path
            let plist: [String: Any] = [
                "Label": "com.gesturelauncher",
                "ProgramArguments": [absPath],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try? data.write(to: launchAgentURL)
            }
        } else {
            try? fileManager.removeItem(at: launchAgentURL)
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updateAppsList(filter: query.isEmpty ? nil : query)
    }
    
    private func getAppName(forBundleID bundleID: String?) -> String {
        if bundleID == nil || bundleID == "action:none" { return "None (Disabled)" }
        if let sysAction = SystemAction(rawValue: bundleID!) { return sysAction.title }
        if !isAppCacheLoaded { return "Loading Apps..." }
        return cachedApps.first(where: { $0.bundleID == bundleID })?.name ?? "Unknown App"
    }
    
    private func addSystemActionMenuItem(action: SystemAction, isChecked: Bool) {
        let item = NSMenuItem(title: action.title, action: #selector(selectAppTarget(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        item.image = action.icon
        item.image?.isTemplate = true
        item.image?.size = NSSize(width: 16, height: 16)
        if isChecked { item.state = .on }
        appsSubmenu.addItem(item)
    }
    
    private func updateAppsList(filter: String?) {
        while appsSubmenu.items.count > 4 { appsSubmenu.removeItem(at: 4) }
        
        if !isDriverActive {
            let warnItem = NSMenuItem(title: "⚠️ Permissions Blocked", action: #selector(fixPermissionsClicked), keyEquivalent: "")
            warnItem.target = self
            appsSubmenu.addItem(warnItem)
            return
        }
        
        if !isAppCacheLoaded {
            let loadItem = NSMenuItem(title: "Loading application library...", action: nil, keyEquivalent: "")
            loadItem.isEnabled = false
            appsSubmenu.addItem(loadItem)
            return
        }
        
        let currentTargetID = GestureEngine.shared.getAction(for: currentEditingGesture)
        if let noneItem = appsSubmenu.items[safe: 2] {
            noneItem.state = (currentTargetID == nil || currentTargetID == "action:none") ? .on : .off
        }
        
        if filter == nil {
            if !recentBundleIDs.isEmpty {
                let recentHeader = NSMenuItem(title: "Recently Used", action: nil, keyEquivalent: "")
                recentHeader.isEnabled = false
                appsSubmenu.addItem(recentHeader)
                for bundleID in recentBundleIDs {
                    if let sysAction = SystemAction(rawValue: bundleID) {
                        addSystemActionMenuItem(action: sysAction, isChecked: sysAction.rawValue == currentTargetID)
                    } else if let app = cachedApps.first(where: { $0.bundleID == bundleID }) {
                        addAppMenuItem(app: app, isChecked: app.bundleID == currentTargetID)
                    }
                }
                appsSubmenu.addItem(NSMenuItem.separator())
            }
            
            let sysHeader = NSMenuItem(title: "System Actions", action: nil, keyEquivalent: "")
            sysHeader.isEnabled = false
            appsSubmenu.addItem(sysHeader)
            for action in SystemAction.allCases {
                addSystemActionMenuItem(action: action, isChecked: action.rawValue == currentTargetID)
            }
            appsSubmenu.addItem(NSMenuItem.separator())
            
            let appsHeader = NSMenuItem(title: "Applications", action: nil, keyEquivalent: "")
            appsHeader.isEnabled = false
            appsSubmenu.addItem(appsHeader)
        }
        
        let filteredSys = filter == nil ? [] : SystemAction.allCases.filter { $0.title.localizedCaseInsensitiveContains(filter!) }
        let filteredApps = filter == nil ? cachedApps : cachedApps.filter { $0.name.localizedCaseInsensitiveContains(filter!) }
        
        if filter != nil && (!filteredSys.isEmpty || !filteredApps.isEmpty) {
            if !filteredSys.isEmpty {
                let sysHeader = NSMenuItem(title: "System Actions", action: nil, keyEquivalent: "")
                sysHeader.isEnabled = false
                appsSubmenu.addItem(sysHeader)
                for action in filteredSys {
                    addSystemActionMenuItem(action: action, isChecked: action.rawValue == currentTargetID)
                }
                appsSubmenu.addItem(NSMenuItem.separator())
            }
            if !filteredApps.isEmpty {
                let appsHeader = NSMenuItem(title: "Applications", action: nil, keyEquivalent: "")
                appsHeader.isEnabled = false
                appsSubmenu.addItem(appsHeader)
                for app in filteredApps {
                    addAppMenuItem(app: app, isChecked: app.bundleID == currentTargetID)
                }
            }
        } else if filter != nil {
            let noResults = NSMenuItem(title: "No Results Found", action: nil, keyEquivalent: "")
            noResults.isEnabled = false
            appsSubmenu.addItem(noResults)
        } else {
            for app in cachedApps {
                addAppMenuItem(app: app, isChecked: app.bundleID == currentTargetID)
            }
        }
    }
    
    @objc func fixPermissionsClicked() { openAccessibilitySettings() }
    
    private func addAppMenuItem(app: AppInfo, isChecked: Bool) {
        let item = NSMenuItem(title: app.name, action: #selector(selectAppTarget(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app.bundleID
        item.image = app.icon
        if isChecked { item.state = .on }
        appsSubmenu.addItem(item)
    }
    
    @objc func selectAppTarget(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        GestureEngine.shared.setAction(bundleID, for: currentEditingGesture)
        
        if let mainMenu = statusItem?.menu, let actionTitleItem = mainMenu.item(withTag: 102) {
            actionTitleItem.title = "Action: \(getAppName(forBundleID: bundleID))"
        }
        
        if bundleID != "action:none" {
            var recents = recentBundleIDs
            recents.removeAll { $0 == bundleID }
            recents.insert(bundleID, at: 0)
            recentBundleIDs = recents
        }
        
        searchField.stringValue = ""
        updateAppsList(filter: nil)
    }
    
    private func discoverApplications() -> [AppInfo] {
        let directoriesToScan = ["/Applications", "/System/Applications"]
        var appList: [AppInfo] = []
        let workspace = NSWorkspace.shared
        
        for dirPath in directoriesToScan {
            let appFolderURL = URL(fileURLWithPath: dirPath)
            guard let urls = try? FileManager.default.contentsOfDirectory(at: appFolderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            
            for url in urls where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    let name = url.deletingPathExtension().lastPathComponent
                    let sysIcon = workspace.icon(forFile: url.path)
                    sysIcon.size = NSSize(width: 16, height: 16)
                    appList.append(AppInfo(name: name, bundleID: bundleID, icon: sysIcon))
                }
            }
        }
        return appList.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Array/NSRect Extensions
extension Array {
    subscript(safe index: Index) -> Element? { return indices.contains(index) ? self[index] : nil }
}
extension NSRect {
    func makeSearchField() -> NSSearchField { return NSSearchField(frame: self) }
}

// MARK: - Entry Point
final class AppEntry {
    static let delegate = AppDelegate()
    static func run() {
        enforceSingleInstance()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
    static func enforceSingleInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let processName = ProcessInfo.processInfo.processName
        for app in NSWorkspace.shared.runningApplications {
            if (app.localizedName == processName || app.executableURL?.lastPathComponent == processName) && app.processIdentifier != currentPID {
                app.forceTerminate()
            }
        }
    }
}
AppEntry.run()
