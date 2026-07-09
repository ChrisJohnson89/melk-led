# MelkLED.app — native macOS controller

A polished, standalone SwiftUI + CoreBluetooth app for controlling
**MELK-OA10** BLE LED strips locally. This is the production front end for the
project; the Python package (`../melk_led`) remains the reference protocol
implementation, CLI, and automation surface.

## Why native (Option A)

The MELK wire protocol is tiny and fully documented in
[../AGENTS.md](../AGENTS.md), so reimplementing it in Swift is quick and buys a
first-class native app with **zero py2app / TCC friction**: the app declares
`NSBluetoothAlwaysUsageDescription` in its own `Info.plist`, so it owns its
Bluetooth permission identity independent of any launching terminal. No
`fix_macos_bluetooth.sh`, no `--deep` re-sign dance.

## Features

- Sidebar of controllers plus an **All Lights** group.
- Power, full colour picker + preset swatches, brightness, and white-temperature.
- One-tap **scenes** (office, movie, pet, gaming, rainbow, white, warm, cool)
  and built-in **effects** (rainbow cycle, color wave, breathing, strobe, …).
- Scan for new controllers; the four already-discovered units are seeded so the
  app is useful on first launch. Rename any controller (persists to
  `~/Library/Application Support/MelkLED/devices.json`).
- The mandatory MELK login handshake (`7E 07 83`, then `7E 04 04`) plus
  connect/retry is handled automatically; frames queued while a strip is
  connecting are flushed once login completes.

## Single BLE owner + Hermes endpoint

A BLE device accepts only one connection, so the app is the **single BLE
owner** and exposes a small local HTTP endpoint on `127.0.0.1:8765` (loopback
only) that Hermes and the Python CLI can call. Routes mirror the FastAPI
service and the deterministic Hermes NLU is ported from `melk_led/nlu.py`:

```bash
curl -s localhost:8765/health
curl -sX POST localhost:8765/hermes -d '{"command":"movie mode"}'
curl -sX POST localhost:8765/hermes -d '{"command":"led2 lights on"}'
curl -sX POST localhost:8765/lights/color -d '{"target":"led1","r":255,"g":0,"b":0}'
curl -sX POST localhost:8765/lights/scene -d '{"target":"all","name":"gaming"}'
```

| Method | Path | Body |
|---|---|---|
| GET | `/health`, `/devices`, `/scenes` | — |
| POST | `/lights/on` · `/off` | `{"target":"led1"}` |
| POST | `/lights/color` | `{"target":"led1","r":255,"g":0,"b":0}` |
| POST | `/lights/brightness` | `{"target":"all","percent":40}` |
| POST | `/lights/white` | `{"target":"led1","warm":100}` |
| POST | `/lights/scene` | `{"target":"all","name":"movie"}` |
| POST | `/lights/effect` | `{"target":"all","effect":"Rainbow Cycle"}` |
| POST/GET | `/flash` | `{"target":"all","blinks":4}` (optional `r`,`g`,`b`) |
| POST | `/hermes` | `{"command":"office lights on"}` |

`target` defaults to `all` when omitted.

## Approval alerts (flash the lights when an agent needs you)

`POST /flash` (GET also works) blinks the lights amber a few times, then
restores their previous state. It is meant as an ambient "come look at the
screen" signal — e.g. when Claude Code is waiting for you to approve a tool
use. The toolbar's **Test Alert** button previews the same thing.

### Wire it to Claude Code

Claude Code fires a `Notification` hook when it needs your approval. Add this
to `~/.claude/settings.json` (applies to every project, and works in any
terminal including Warp):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          { "type": "command", "command": "curl -s -m 2 -X POST localhost:8765/flash >/dev/null 2>&1 &" }
        ]
      }
    ]
  }
}
```

The MelkLED app must be running for the flash to happen; the `curl` fails
silently (and never blocks Claude Code) if it isn't. Broaden the `matcher` to
`"permission_prompt|idle_prompt"` to also flash when Claude finishes and is
waiting for your next prompt.

**Warp's own agent and the Claude desktop app** don't expose an approval hook,
so they can't trigger this directly — the only universal catch-all would be
watching the macOS Notification Center database (needs Full Disk Access and is
fragile), which this project deliberately does not do.

## Build & run

Open `MelkLED.xcodeproj` in Xcode 16+ (developed against Xcode 26.5) and run,
or from the command line:

```bash
xcodebuild -project MelkLED.xcodeproj -scheme MelkLED -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/MelkLED-*/Build/Products/Release/MelkLED.app
```

On first launch, macOS shows a one-time Bluetooth permission prompt — click
Allow. The app targets macOS 14+.

## Releases

Prebuilt `MelkLED.app` bundles are attached to
[GitHub Releases](https://github.com/ChrisJohnson89/melk-led/releases). To cut
a new one, bump the version by pushing a tag — the
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
  MelkLEDApp.swift          app entry; wires controller + HTTP server
  ContentView.swift         split view: sidebar + detail
  Protocol/MelkProtocol.swift   pure wire protocol (port of protocol.py)
  Models/Scenes.swift           scene definitions (port of scenes.py)
  Models/DeviceStore.swift      alias persistence
  BLE/MelkDevice.swift          observable per-device model
  BLE/MelkController.swift      single CBCentralManager BLE owner
  Views/ControlSurface.swift    reusable control panel
  Views/DetailViews.swift       device + all-lights adapters
  Server/ControlServer.swift    local HTTP endpoint + Hermes NLU
  Server/HTTP.swift             minimal HTTP request/response
```
