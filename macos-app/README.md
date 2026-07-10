# MelkLED.app — native macOS controller

A polished, standalone SwiftUI + CoreBluetooth app for controlling
**MELK-OA10** BLE LED strips locally. This is the production front end for the
project; the Python package (`../melk_led`) remains as a reference protocol
implementation and CLI.

## Why native

The MELK wire protocol is tiny and fully documented in
[../AGENTS.md](../AGENTS.md), so reimplementing it in Swift is quick and buys a
first-class native app with **zero py2app / TCC friction**: the app declares
`NSBluetoothAlwaysUsageDescription` in its own `Info.plist`, so it owns its
Bluetooth permission identity independent of any launching terminal.

## Features

- Sidebar of controllers, an **All Lights** row, and your own **Groups**.
- Power, full colour picker + preset swatches, brightness, and white-temperature.
- **Custom scenes**: build your own one-tap scenes in the scene editor
  (ordered steps: power, colour, brightness, white, effect, effect speed).
  **Movie** is the only built-in. Right-click a scene to edit or delete it;
  the editor has a live "Preview on all lights" button.
- **Groups**: create rooms like "Living Room" from any set of controllers,
  edit membership any time (sidebar right-click, or the pencil on the group
  page), and control the whole group at once.
- **Reassign / rename controllers**: rename any controller from its page
  (pencil button); names persist across launches.
- Scan for new controllers; the four already-discovered units are seeded so
  the app is useful on first launch.
- The mandatory MELK login handshake (`7E 07 83`, then `7E 04 04`) plus
  connect/retry is handled automatically; frames queued while a strip is
  connecting are flushed once login completes.

Everything persists as small JSON files in
`~/Library/Application Support/MelkLED/` (`devices.json`, `groups.json`,
`scenes.json`).

## Build & run

Open `MelkLED.xcodeproj` in Xcode 16+ (developed against Xcode 26.5) and run,
or from the command line:

```bash
xcodebuild -project MelkLED.xcodeproj -scheme MelkLED -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/MelkLED-*/Build/Products/Release/MelkLED.app
```

On first launch, macOS shows a one-time Bluetooth permission prompt. Click
Allow. The app targets macOS 14+.

## Releases

Prebuilt `MelkLED.app` bundles are attached to
[GitHub Releases](https://github.com/ChrisJohnson89/melk-led/releases). To cut
a new one, bump the version by pushing a tag; the
[`release`](../.github/workflows/release.yml) workflow builds the app at that
version, zips it, and publishes the release automatically:

```bash
git tag v1.2.0
git push origin v1.2.0
```

CI has no Apple Developer certificate, so the published app is **unsigned**.
After downloading, clear the quarantine flag before first launch:

```bash
xattr -dr com.apple.quarantine /Applications/MelkLED.app
```

## Project layout

```
MelkLED/
  MelkLEDApp.swift              app entry
  ContentView.swift             split view: sidebar (groups + controllers) + detail
  Protocol/MelkProtocol.swift   pure wire protocol (port of protocol.py)
  Models/Scenes.swift           editable scene model (Movie is the only built-in)
  Models/Groups.swift           group model
  Models/DeviceStore.swift      JSON persistence (devices/groups/scenes)
  BLE/MelkDevice.swift          observable per-device model
  BLE/MelkController.swift      single CBCentralManager BLE owner
  Views/ControlSurface.swift    reusable control panel + scene grid
  Views/SceneEditorView.swift   custom scene editor sheet
  Views/GroupEditorView.swift   group editor sheet
  Views/DetailViews.swift       device / group / all-lights adapters
```

Note: the app no longer runs a local HTTP endpoint. Earlier versions exposed
`127.0.0.1:8765` for Hermes and a Claude Code "flash on approval" hook; both
were removed in favour of keeping the app a simple standalone controller.
