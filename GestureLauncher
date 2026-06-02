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

// MARK: - Gesture Engine State
final class GestureEngine {
    static let shared = GestureEngine()
    
    // Thread safety lock for hardware callbacks
    private let stateLock = NSLock()
    
    var targetBundleIdentifier: String {
        get { UserDefaults.standard.string(forKey: "SelectedTargetBundleID") ?? "com.apple.Terminal" }
        set { UserDefaults.standard.set(newValue, forKey: "SelectedTargetBundleID") }
    }
    
    private let pinchThreshold: Double = 0.03
    private let cooldownInterval: TimeInterval = 1.5
    private var state: GestureState = .idle
    private var lastTriggerTime: Date = .distantPast

    enum GestureState {
        case idle
        case tracking(initialDistance: Double)
        case cooldown
    }

    func handleTouches(contacts: UnsafeMutablePointer<MTContact>, count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        if Date().timeIntervalSince(lastTriggerTime) < cooldownInterval { return }
        
        // Use UnsafeBufferPointer for safe, zero-copy Swift array capabilities
        let buffer = UnsafeBufferPointer(start: contacts, count: count)
        
        // Filter for active/hover states (1, 2, 3, 4)
        let activeContacts = buffer.filter { (1...4).contains($0.state) }
        
        guard activeContacts.count >= 4 else {
            if case .tracking = state {
                print("[DEBUG GESTURE] Fingers dropped below 4. Resetting tracking engine.")
            }
            state = .idle
            return
        }
        
        // Swift idiomatic coordinate averaging
        let floatCount = Float(activeContacts.count)
        let avgX = activeContacts.reduce(0) { $0 + $1.x } / floatCount
        let avgY = activeContacts.reduce(0) { $0 + $1.y } / floatCount
        
        // Calculate average distance of fingers from the center point
        let currentAvgDistance = activeContacts.reduce(0.0) { result, contact in
            let dx = Double(contact.x - avgX)
            let dy = Double(contact.y - avgY)
            return result + sqrt((dx * dx) + (dy * dy))
        } / Double(activeContacts.count)
        
        switch state {
        case .idle:
            print("[DEBUG GESTURE] Hand detected! Active Fingers: \(activeContacts.count) | Baseline Span: \(String(format: "%.4f", currentAvgDistance))")
            state = .tracking(initialDistance: currentAvgDistance)
            
        case .tracking(let initialDistance):
            let delta = initialDistance - currentAvgDistance
            
            if delta > pinchThreshold {
                print("[DEBUG GESTURE] 💥 PINCH DETECTED! Deploying target application...")
                triggerAction()
                state = .cooldown
                lastTriggerTime = Date()
            }
            
        case .cooldown:
            break
        }
    }
    
    private func triggerAction() {
        let bundleID = self.targetBundleIdentifier
        
        DispatchQueue.main.async {
            let workspace = NSWorkspace.shared
            print("[DEBUG LAUNCH] Attempting action routing for bundle: \(bundleID)")
            
            // By using NSWorkspace.openApplication even for apps that are already running, 
            // we hand the activation request over to LaunchServices, bypassing the strict 
            // focus-stealing restrictions imposed on background apps.
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                
                print("[DEBUG LAUNCH] Dispatching command to LaunchServices...")
                workspace.openApplication(at: appURL, configuration: config) { app, error in
                    if let error = error {
                        print("[DEBUG LAUNCH] ❌ Launch/Activation Error: \(error.localizedDescription)")
                    } else {
                        print("[DEBUG LAUNCH] ✅ LaunchServices successfully routed app to foreground.")
                        // Redundant fallback call using process options just for absolute certainty
                        app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                    }
                }
            } else {
                print("[DEBUG LAUNCH] ❌ Could not resolve app URL for bundle: \(bundleID)")
            }
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
    
    var recentBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "RecentSearchedApps") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(5)), forKey: "RecentSearchedApps") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // Offload app discovery to a background queue to speed up initial launch
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = self?.discoverApplications() ?? []
            DispatchQueue.main.async {
                self?.cachedApps = apps
                self?.setupMenuBarGUI()
                self?.checkAndInitializeDriver()
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
        
        guard let trackpadDevice = MTDeviceCreateDefault() else {
            print("[DEBUG STARTUP] ❌ CRITICAL: Hardware reference returned nil.")
            return
        }
        self.device = trackpadDevice
        
        MTRegisterContactFrameCallback(trackpadDevice) { _, rawContacts, count, _, _ in
            if let rawContacts = rawContacts {
                let typedContacts = rawContacts.assumingMemoryBound(to: MTContact.self)
                GestureEngine.shared.handleTouches(contacts: typedContacts, count: Int(count))
            }
            return 0
        }
        
        MTDeviceStart(trackpadDevice, 0)
        isDriverActive = true
        
        updateMenuBarIcon()
        updateAppsList(filter: nil)
    }
    
    private func checkAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "Gesture Launcher needs Accessibility permissions to detect trackpad pinch gestures.\n\nPlease click 'Open System Settings', enable the app in the list, and it will activate automatically."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
    
    @objc private func openAccessibilitySettings() {
        _ = checkAccessibilityPermission(promptIfNeeded: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupMenuBarGUI() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        
        let mainMenu = NSMenu()
        let headerItem = NSMenuItem(title: "Gesture Launcher", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        mainMenu.addItem(headerItem)
        mainMenu.addItem(NSMenuItem.separator())
        
        let appsMenuItem = NSMenuItem(title: "Select Target App...", action: nil, keyEquivalent: "")
        let searchContainer = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        searchField = NSRect(x: 10, y: 4, width: 220, height: 22).makeSearchField()
        searchField.delegate = self
        searchField.placeholderString = "Search Apps..."
        searchContainer.addSubview(searchField)
        
        let searchMenuItem = NSMenuItem()
        searchMenuItem.view = searchContainer
        appsSubmenu.addItem(searchMenuItem)
        appsSubmenu.addItem(NSMenuItem.separator())
        
        updateAppsList(filter: nil)
        appsMenuItem.submenu = appsSubmenu
        mainMenu.addItem(appsMenuItem)
        
        mainMenu.addItem(NSMenuItem.separator())
        mainMenu.addItem(NSMenuItem(title: "Quit Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = mainMenu
    }
    
    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName = isDriverActive ? "hand.point.up.left" : "exclamationmark.triangle"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Gesture Launcher")
        button.image?.isTemplate = true
    }
    
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updateAppsList(filter: query.isEmpty ? nil : query)
    }
    
    private func updateAppsList(filter: String?) {
        while appsSubmenu.items.count > 2 { appsSubmenu.removeItem(at: 2) }
        
        if !isDriverActive {
            let warnItem = NSMenuItem(title: "⚠️ Permissions Blocked", action: nil, keyEquivalent: "")
            warnItem.isEnabled = false
            appsSubmenu.addItem(warnItem)
            
            let fixItem = NSMenuItem(title: "Grant Accessibility...", action: #selector(fixPermissionsClicked), keyEquivalent: "")
            fixItem.target = self
            appsSubmenu.addItem(fixItem)
            return
        }
        
        let currentTarget = GestureEngine.shared.targetBundleIdentifier
        
        if filter == nil && !recentBundleIDs.isEmpty {
            let recentHeader = NSMenuItem(title: "Recently Used", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            appsSubmenu.addItem(recentHeader)
            
            for bundleID in recentBundleIDs {
                if let app = cachedApps.first(where: { $0.bundleID == bundleID }) {
                    addAppMenuItem(app: app, isChecked: app.bundleID == currentTarget)
                }
            }
            appsSubmenu.addItem(NSMenuItem.separator())
        }
        
        let filteredApps = filter == nil ? cachedApps : cachedApps.filter { $0.name.localizedCaseInsensitiveContains(filter!) }
        
        if filteredApps.isEmpty {
            let noResults = NSMenuItem(title: "No Apps Found", action: nil, keyEquivalent: "")
            noResults.isEnabled = false
            appsSubmenu.addItem(noResults)
        } else {
            for app in filteredApps {
                addAppMenuItem(app: app, isChecked: app.bundleID == currentTarget)
            }
        }
    }
    
    @objc func fixPermissionsClicked() {
        openAccessibilitySettings()
    }
    
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
        GestureEngine.shared.targetBundleIdentifier = bundleID
        print("[DEBUG UI] Selected target switched to: \(bundleID)")
        
        var recents = recentBundleIDs
        recents.removeAll { $0 == bundleID }
        recents.insert(bundleID, at: 0)
        recentBundleIDs = recents
        
        searchField.stringValue = ""
        updateAppsList(filter: nil)
    }
    
    private func discoverApplications() -> [AppInfo] {
        // Expanded directories to include Utilities and User Applications
        let directoriesToScan = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "~/Applications"
        ]
        var appList: [AppInfo] = []
        let workspace = NSWorkspace.shared
        
        for dirPath in directoriesToScan {
            let expandedPath = NSString(string: dirPath).expandingTildeInPath
            let appFolderURL = URL(fileURLWithPath: expandedPath)
            
            guard let urls = try? FileManager.default.contentsOfDirectory(at: appFolderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                continue
            }
            
            for url in urls where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    let name = url.deletingPathExtension().lastPathComponent
                    let sysIcon = workspace.icon(forFile: url.path)
                    sysIcon.size = NSSize(width: 16, height: 16)
                    
                    appList.append(AppInfo(name: name, bundleID: bundleID, icon: sysIcon))
                }
            }
        }
        
        // Remove duplicates (e.g., if a system app overrides a user app space)
        let uniqueApps = Array(Dictionary(grouping: appList, by: { $0.bundleID }).compactMap { $0.value.first })
        return uniqueApps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

// MARK: - NSRect Extension
extension NSRect {
    func makeSearchField() -> NSSearchField {
        return NSSearchField(frame: self)
    }
}

// MARK: - Entry Point
final class AppEntry {
    static let delegate = AppDelegate()
    static func run() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
AppEntry.run()
