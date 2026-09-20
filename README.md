# Magic Mouse Tap

A small personal macOS menu-bar utility that adds trackpad-style gestures to an Apple Magic Mouse.

## Gestures

- One-finger tap: left click
- Double tap: double click/select
- Double tap and hold the second tap: select text or drag and drop
- Two-finger tap: right click
- Scroll gestures never generate a click
- A tap used to stop inertial scrolling is consumed and does not click

The app refreshes its Magic Mouse listener after wake or session unlock and writes diagnostics to `/tmp/MagicMouseTap.log`.

## Requirements

- Apple Silicon Mac
- macOS 11 or later
- Apple Magic Mouse connected over Bluetooth
- Accessibility permission for the installed executable
- Xcode Command Line Tools to build

This project uses Apple's private `MultitouchSupport` framework. It is intended for personal use and cannot be distributed through the Mac App Store.

## Build

The build script uses the local signing identity `Magic Mouse Tap Local` so macOS can retain Accessibility approval between builds.

```bash
./build.sh
```

The app bundle is produced at:

```text
build/Magic Mouse Tap.app
```

## Personal installation

The tested installation uses a consistently signed standalone executable at a stable path:

```bash
cp "build/Magic Mouse Tap.app/Contents/MacOS/MagicMouseTap" /Applications/MagicMouseTapStandalone
chmod 755 /Applications/MagicMouseTapStandalone
codesign --force --sign "Magic Mouse Tap Local" \
  --identifier com.roshan.personal.magicmousetap.standalone \
  /Applications/MagicMouseTapStandalone
launchctl submit -l com.roshan.magicmousetap.standalone -- \
  /Applications/MagicMouseTapStandalone
```

Then enable `/Applications/MagicMouseTapStandalone` in **System Settings → Privacy & Security → Accessibility**.

To stop it:

```bash
launchctl remove com.roshan.magicmousetap.standalone
```

## Testing

```bash
./run_tests.sh
```

## Privacy

Magic Mouse Tap runs locally. It does not collect data or use the network.

## Credits and license

This personal version is based on [Mouse Toucher](https://github.com/slopcore/mousetoucher). The upstream MIT license is retained in [LICENSE](LICENSE).
