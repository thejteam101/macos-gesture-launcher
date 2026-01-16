# macos-gesture-launcher

Headless macOS tool that launches apps when you pinch on the trackpad. Configuration is a single YAML file.

## Features

- Map pinch in/out to apps or bundle IDs
- 2-finger pinch via NSEvent magnify
- 3+ finger pinch via private MultitouchSupport (for Launchpad-style gestures)
- Debug logging for tuning thresholds

## Requirements

- macOS 12+
- Input Monitoring permission (prompted on first run)

## Build

```
swift build -c release
```

## Run

```
cp config.example.yaml config.yaml
./.build/release/macos-gesture-launcher --config ./config.yaml
```

## Run in Background

Start in the background and keep logs in `/tmp`:

```
nohup ./.build/release/macos-gesture-launcher --config ./config.yaml \
  >/tmp/macos-gesture-launcher.out 2>/tmp/macos-gesture-launcher.err &
```

Stop it:

```
pkill -f macos-gesture-launcher
```

## Autostart

Enable autostart on login (installs a LaunchAgent for you). This will stop any running instance first:

```
./.build/release/macos-gesture-launcher --autostart --config ./config.yaml
```

Remove autostart:

```
./.build/release/macos-gesture-launcher --autostart-remove
```

Check autostart status:

```
./.build/release/macos-gesture-launcher --autostart-status
```

This writes a LaunchAgent at `~/Library/LaunchAgents/com.macos-gesture-launcher.plist` and
starts the service immediately.

## Config

Example:

```yaml
cooldown_ms: 700
idle_window_ms: 150
min_gesture_magnitude: 0.1

gestures:
  - type: pinch
    direction: in
    touches: 4
    threshold: 0.2
    app: /Applications/Raycast.app
```

Options:

- `cooldown_ms`: Minimum time between launches (default 700)
- `idle_window_ms`: Gesture end window in milliseconds (default 150)
- `min_gesture_magnitude`: Ignore tiny pinches (default 0.1)
- `gestures`: List of mappings
  - `type`: only `pinch` is supported
  - `direction`: `in` or `out`
  - `touches`: number of fingers (default 2)
  - `threshold`: magnitude threshold (default 0.6)
  - `app`: app path or name (uses `open -a`)
  - `bundle_id`: bundle id (uses `open -b`)

Notes:

- `touches: 2` uses standard magnify events.
- `touches >= 3` uses the private MultitouchSupport framework.

## Debug

Run with `--debug` to log magnification values and decision points:

```
./.build/debug/macos-gesture-launcher --config ./config.yaml --debug
```

Logs are printed to stderr; if you run in the background you can tail:

```
tail -f /tmp/macos-gesture-launcher.err
```

## Permissions

You will be prompted for Input Monitoring permissions on first run. If you don't see the prompt,
enable Input Monitoring for `macos-gesture-launcher` (or the terminal you launched it from) in:

System Settings -> Privacy & Security -> Input Monitoring

## LaunchAgent (manual)

Edit the placeholders in `launchd/com.macos-gesture-launcher.plist`, then load it:

```
launchctl bootstrap gui/$(id -u) launchd/com.macos-gesture-launcher.plist
```

Stop and unload:

```
launchctl bootout gui/$(id -u) launchd/com.macos-gesture-launcher.plist
```

## Disable Launchpad/Apps pinch gesture

To avoid conflicts with Launchpad/Apps:

- Standard macOS: System Settings -> Trackpad -> More Gestures -> Launchpad -> Off
- macOS Tahoe: use defaults commands

Disable:

```
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerPinchGesture -int 0
```
Note: You may need to restart services or logout for this change to take effect

Reset:

```
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerPinchGesture -int 2
```

## Limitations

- Uses a private Apple framework for 3+ finger gestures; macOS updates may break this.
- Only pinch gestures are supported today.

## License

MIT (see `LICENSE`)
