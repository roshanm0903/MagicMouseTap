# Magic Mouse Tap

A small personal macOS menu-bar utility that adds trackpad-style gestures to an Apple Magic Mouse.

## Gestures

- One-finger tap: left click
- Double tap: double click/select
- Double tap and hold the second tap: select text or drag and drop
- While holding the second tap, swipe up to zoom out or down to zoom in
- Two-finger tap: right click
- Scroll gestures never generate a click
- A tap used to stop inertial scrolling is consumed and does not click

The app refreshes its Magic Mouse listener after wake, session unlock, or Bluetooth disconnect/reconnect and writes diagnostics to `/tmp/MagicMouseTap.log`.

Open **Gesture Sensitivity…** from the menu-bar icon to adjust tap timing, movement tolerance, double-tap timing, zoom distance, drag activation, and scroll-stop protection. Changes apply live and persist across restarts.

The top **Tap sensitivity** control is the quickest way to reduce accidental clicks: move it left for stricter recognition or right if intended taps are being missed.

## Requirements

- Apple Silicon Mac
- macOS 11 or later
- Apple Magic Mouse connected over Bluetooth
- Accessibility permission for the installed executable
- Xcode Command Line Tools to build

This project uses Apple's private `MultitouchSupport` framework. It is intended for personal use and cannot be distributed through the Mac App Store.

## Build

The build script uses the local signing identity `Magic Mouse Tap Local` for the development bundle. The personal standalone installation is ad-hoc signed because macOS 26.7.1 no longer accepts that self-signed identity from `/Applications` without weakening certificate trust.

```bash
./build.sh
```

The app bundle is produced at:

```text
build/Magic Mouse Tap.app
```

## Personal installation

The tested installation uses an ad-hoc-signed standalone executable in the user Applications folder:

```bash
mkdir -p /Users/roshanmanellore/Applications
cp "build/Magic Mouse Tap.app/Contents/MacOS/MagicMouseTap" \
  /Users/roshanmanellore/Applications/MagicMouseTapStandalone
chmod 755 /Users/roshanmanellore/Applications/MagicMouseTapStandalone
codesign --force --sign - \
  --identifier com.roshan.personal.magicmousetap.standalone \
  /Users/roshanmanellore/Applications/MagicMouseTapStandalone
cp LaunchAgents/com.roshan.magicmousetap.autostart.plist \
  /Users/roshanmanellore/Library/LaunchAgents/
launchctl bootstrap gui/501 \
  /Users/roshanmanellore/Library/LaunchAgents/com.roshan.magicmousetap.autostart.plist
```

Then enable `/Users/roshanmanellore/Applications/MagicMouseTapStandalone` in **System Settings → Privacy & Security → Accessibility**.

To stop it:

```bash
launchctl bootout gui/501/com.roshan.magicmousetap.autostart
```

## Testing

```bash
./run_tests.sh
```

## Privacy

Magic Mouse Tap runs locally. It does not collect data or use the network.

## Credits and license

This personal version is based on [Mouse Toucher](https://github.com/slopcore/mousetoucher). The upstream MIT license is retained in [LICENSE](LICENSE).
