# Magic Mouse Tap for Windows

Personal Windows 11 version of Magic Mouse Tap. It runs in the system tray and implements the same core behavior as the macOS app:

- one-finger tap: left click;
- double tap: double click;
- double tap, then move while holding: select or drag and drop;
- double tap, then swipe up: zoom out;
- double tap, then swipe down: zoom in;
- two-finger tap: right click;
- any wheel event during a touch sequence suppresses its click;
- a tap immediately after scrolling stops the scroll without clicking;
- sensitivity controls and start-with-Windows support.

## Important driver requirement

The stock Windows Bluetooth mouse driver exposes movement and physical clicks, but not the Magic Mouse touch surface. This app therefore needs a compatible raw-touch driver that exposes either `\\.\MagicMouseRawPDO` or `\\.\MagicMouse`.

One known option is the `MagicMouse.sys` driver installed by Magic Utilities. Obtain and use that driver under its vendor's license. It is proprietary and is not included here. The app does not disable Secure Boot, install a kernel driver, or change Windows driver-signing policy.

V1 parses the standard Apple Magic Mouse report IDs `0x29` and `0x12`, covering the original Magic Mouse and Magic Mouse 2 family when the raw driver forwards complete reports. Hardware verification is still required on the target Windows PC.

## Build

Requirements:

- Windows 11 x64;
- .NET 8 SDK;
- a paired Magic Mouse;
- a compatible raw-touch driver.

From PowerShell:

```powershell
cd windows
.\build.ps1
```

Output:

```text
windows\artifacts\win-x64\MagicMouseTap.exe
```

The GitHub Actions workflow also builds a self-contained `win-x64` artifact.

## Run

1. Confirm the raw-touch driver is installed and the Magic Mouse is connected.
2. Run `MagicMouseTap.exe`.
3. Open the tray menu and choose **Gesture Sensitivity…**.
4. Enable **Start with Windows**, then save.

Settings are stored at `%APPDATA%\MagicMouseTap\settings.json`.

## Safety and rollback

The app only reads the driver's user-mode raw interface and injects standard Windows input through `SendInput`. If it is closed, the normal mouse driver remains in control. Remove the Start-with-Windows checkbox or delete the `MagicMouseTap` value under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` to disable autostart.

## Current validation status

- Gesture engine and Apple report parser have deterministic tests.
- The source is prepared for Windows CI compilation.
- Physical Magic Mouse validation must be completed on a Windows 11 x64 machine with the raw driver installed.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for protocol and implementation references.
