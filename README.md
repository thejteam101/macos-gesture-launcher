Original by @okruts/macos-gesture-launcher

Converted the package into a single file for macOS Tahoe 
Added menu bar icon
Added ability to select app in the menubar to use with 5 finger pinch
(goal is to bring back launchpad equivalency with launchos, but can map to opening any app)

1. Save the code to a file eg ```launcher.swift```
2. Allow Execute permissions using ```chmod +x launcher.swift```
3. Build/compile and launch using: ```swiftc launcher.swift -F /System/Library/PrivateFrameworks -framework MultitouchSupport -o GestureLauncher && ./GestureLauncher &```

---

# Gesture Launcher (v0.1.9)

Gesture Launcher is a high-performance, lightweight, background-resident macOS status bar utility. It taps directly into the private multitouch hardware stream of your Mac's trackpad, allowing you to bind complex physical finger gestures to standard applications or deep macOS system operations.

It is designed to be highly optimized, utilizing low-level C bindings for Apple's private `MultitouchSupport` framework.

## 🚀 Key Features

* **6 Distinct Gestures**: Map actions to a 5-Finger Pinch (Inward), 5-Finger Spread (Outward), or 4+ Finger directional swipes (Up, Down, Left, Right).
* **Zero-Allocation Touch Loop**: The core gesture engine runs with $O(1)$ space and $O(N)$ time complexity, bypassing the Swift memory allocator entirely during the 60Hz-120Hz trackpad loop to eliminate Automatic Reference Counting (ARC) overhead.
* **Asynchronous App Discovery**: Scans your system's application directories asynchronously on background queues, preventing your system thread from hanging at startup.
* **System Action Mapping**: Go beyond apps; trigger core OS behaviors natively:
* *Mission Control*
* *Show Desktop*
* *Spotlight Search*
* *Sleep Display*
* *Media Key Simulation* (Play/Pause, Skip Forward, Skip Backward, Mute) using low-level `HID` event taps.


* **Sensory Feedback Mixer**: Toggle a physical haptic tap or auditory "pop" sound to notify you of a successful gesture trigger.
* *Haptic Textures*: **Click** (Generic), **Snap** (Level Change - rubbery pop), and **Thud** (Alignment - subtle haptic).


* **Single-Instance Enforcement**: Rebuilding or running a new instance automatically terminates older running binaries to free up the hardware driver safely.
* **Launch at Login**: Adds a custom LaunchAgent (`~/Library/LaunchAgents/com.gesturelauncher.plist`) dynamically targeting your binary's absolute file path.

## 🛠️ Compilation & Execution

Because this utility relies on Apple’s private frameworks, compiling it requires explicitly targeting the private frameworks directory and linking against the `MultitouchSupport` framework.

Open your Terminal, navigate to the folder containing `launcher.swift`, and compile it:

```bash
swiftc launcher.swift \
  -F /System/Library/PrivateFrameworks \
  -framework MultitouchSupport \
  -o GestureLauncher

```

To run the launcher in the background, append `&` to your launch command:

```bash
./GestureLauncher &

```

## 🔑 System Permissions Required

macOS blocks raw hardware multitouch stream interception unless your application is explicitly granted **Accessibility** privileges.

1. Upon the first launch, the app will display a native alert requesting access.
2. Clicking **Open System Settings** will redirect you to **System Settings > Privacy & Security > Accessibility**.
3. Enable the terminal application from which you executed the binary (e.g., **Terminal**, **iTerm**, or **GestureLauncher** itself if packaged inside an `.app` wrapper).
4. Our background daemon polls system authorization state in real-time. The millisecond permission is toggled **ON**, the trackpad driver wakes up, initializes the hardware callback loop, and arms the engine.

## ⚙️ Configuration & Customization

The status bar dropdown menu contains the following settings:

* **Configuring**: Select the active gesture you wish to bind.
* **Action**: Choose the application or custom system action (Mute, Play/Pause, Sleep Display, etc.) to trigger when the gesture is detected. Selecting **None (Disabled)** unbinds it.
* **Physical Sensitivity**:
* *High (0.02)*: Responds to micro-movements.
* *Medium (0.035)*: Default, balanced for daily use.
* *Low (0.05)*: Requires assertive, fully closed sweeps.


* **Gesture Cooldown**: Prevents accidental repeated triggers. Choose between **Fast (0.5s)**, **Normal (1.0s)**, and **Relaxed (1.5s)**.
* **Play Sound / Haptic Feedback**: Customize and mix auditory and hardware sensations to confirm gesture execution.

## 💡 Troubleshooting & Pro-Tips

### Conflict with macOS Native Gestures

If you find that your custom swipes are fighting with native macOS trackpad swipes (like triggering native Launchpad or Mission Control simultaneously), you can disable Apple’s built-in 4-finger gestures using defaults:

```bash
# Disable native four-finger pinch (Launchpad)
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerPinchGesture -int 0

```

### Stopping the Background App

Because the app runs in the background, you can terminate it safely at any time:

```bash
killall GestureLauncher

```

## 📝 Technical Implementation Details

```
              ┌──────────────────────────────────────────────┐
              │  MultitouchSupport Private HID Callback      │
              └──────────────────────┬───────────────────────┘
                                     │ (60-120Hz raw frames)
                                     ▼
              ┌──────────────────────────────────────────────┐
              │  O(1) Spatial Zero-Allocation Filtering       │
              └──────────────────────┬───────────────────────┘
                                     │
                                     ▼
              ┌──────────────────────────────────────────────┐
              │  Centroid Analysis & Euclidean Distance Math  │
              └──────────────────────┬───────────────────────┘
                                     │ (Crosses threshold)
                                     ▼
              ┌──────────────────────────────────────────────┐
              │  System Event Dispatch / Workspace Activation │
              └──────────────────────┬───────────────────────┘
                                     │ (Asynchronous Completion)
                                     ▼
              ┌──────────────────────────────────────────────┐
              │  Audio & Haptic (NSHapticFeedbackManager)    │
              └──────────────────────────────────────────────┘

```

The underlying struct memory map represents the precise 96-byte stride of Apple Silicon trackpad packets. By reading pointer arithmetic straight out of `UnsafeMutableRawPointer`, we achieve native execution speeds with virtually no impact on macOS system resources.
