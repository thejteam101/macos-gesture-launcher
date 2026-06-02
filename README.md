Original by @okruts/macos-gesture-launcher

Converted the package into a single file for macOS Tahoe 
Added menu bar icon
Added ability to select app in the menubar to use with 5 finger pinch
(goal is to bring back launchpad equivalency with launchos, but can map to opening any app)

1. Save the code to a file eg ```GestureLauncher```
2. Allow Execute permissions using ```chmod +x GestureLauncher```
3. Build/compile and launch using: ```swiftc launcher.swift -F /System/Library/PrivateFrameworks -framework MultitouchSupport -o GestureLauncher && ./GestureLauncher &```
