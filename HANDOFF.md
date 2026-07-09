# melk-led handoff

Status snapshot for continuing in a fresh session opened in this directory
(`/Users/chrisdev/Developer/melk-led`).

## TL;DR

Goal: replace the official MELK-OA10 mobile app with a local macOS solution,
controllable by Hermes. The BLE protocol is fully reverse engineered and the
Python control stack works.

**UPDATE (2026-07-09):** the polished standalone macOS app was built —
Option A (SwiftUI + CoreBluetooth) in [`macos-app/`](macos-app/). It builds
clean, launches, and its HTTP control endpoint + Hermes NLU are verified
end-to-end. The Python package stays as the reference/CLI/automation surface.
Remaining hardware step: connect to a real strip from the app UI and confirm
colours/scenes land (BLE writes are unverifiable without the physical lights).

## What is done and verified

- Phase 1-2 (research + protocol): COMPLETE. MELK-OA10 is an
  ELK-BLEDOM / Triones controller. Full command table is in `AGENTS.md`,
  encoded in `melk_led/protocol.py`, and pinned by `tests/test_protocol.py`
  (21 tests pass, offline).
- Phase 3 (packet capture): NOT NEEDED. Protocol cross validated against two
  community implementations. Capture instructions kept in `AGENTS.md` as an
  optional fallback if a new command ever needs mapping.
- Phase 4 (Python package with Bleak): COMPLETE. scan / connect / login /
  retry / multi-device / logging in `melk_led/`.
- Phase 5 (REST API): COMPLETE (`melk_led/api.py`), verified with a fake
  manager (routing, validation, scenes, Hermes NLU path).
- Phase 6 (Hermes NLU): COMPLETE (`melk_led/nlu.py`), deterministic parser.
- macOS BLE actually works now: `./scripts/lights-bundle scan` finds all
  4 controllers. Self-test connected, logged in, and sent every command
  (on / RGB / brightness / white / effect / off) with a clean finish.

## Open verification item

Confirm visually that the self-test physically changed the lights on `led1`
(`2C6B9004-...`). The log showed one mid-run reconnect that the retry logic
absorbed; commands should have landed, but a human needs to confirm the strip
actually cycled colors. If a specific command had no visible effect, that is
the only thing that could still need a per-unit protocol tweak.

## The 4 discovered controllers

Saved in `~/.melk-led.toml` as `led1`-`led4` plus an `all` group. Rename to
real locations once mapped:

| alias | address (macOS CoreBluetooth UUID) | adv suffix |
|-------|-----------------------------------|-----------|
| led1  | 2C6B9004-9E7D-2D9B-3546-4613A77E254E | 60 |
| led2  | 9448314C-F489-8169-B3F2-48145D7B5579 | 61 |
| led3  | 92F38122-6791-0C44-FE33-0C78501BFF39 | 61 |
| led4  | CB1606C6-A343-AA43-170C-007F2F00D287 | 25 |

## macOS Bluetooth / TCC (critical, do not relitigate)

Full writeup is in `AGENTS.md` under "macOS Bluetooth (TCC)". Short version:

- A process needs `NSBluetoothAlwaysUsageDescription` or macOS SIGABRT-kills it.
- Homebrew Python lacks it; we patch `Python.app/Contents/Info.plist` with
  `scripts/fix_macos_bluetooth.sh` and launch via `scripts/lights-bundle`
  (LaunchServices `open`, which reads the bundle plist).
- The re-sign MUST use `codesign --force --deep --sign -`. Without `--deep`
  the inner binary keeps its old signature sealing the pre-edit plist, macOS 26
  rejects the chain with error -67030, and silently denies with no dialog.
  (This was the multi-hour blocker; the Warp agent found it.)
- Bluetooth permission is attributed to the launching terminal (Warp), which
  must be enabled under System Settings > Privacy & Security > Bluetooth.

A native `.app` with the key in its OWN Info.plist sidesteps all of the above,
which is one more reason the desktop app is the right production target.

## Desired next deliverable: a polished standalone Mac app

The user does NOT want a menu-bar utility. They want a proper application with
its own window and a polished UI: device list, per-device and group controls,
color picker, brightness slider, white-temperature control, scene / mode
buttons (Movie, Pet, Gaming, Rainbow, etc.).

Recommended architecture (decide with the user first):

- OPTION A (recommended for "polished + native"): **SwiftUI + CoreBluetooth**.
  The protocol is tiny and fully documented in `AGENTS.md`, so reimplementing
  it in Swift is quick and yields a first-class native app with zero Python /
  py2app / TCC friction (an Xcode app declares the Bluetooth key natively).
  Keep the Python package as the reference implementation, CLI, and the
  Hermes/REST surface. To avoid two processes fighting over BLE (one device
  allows one connection), let the Swift app be the single BLE owner and expose
  a small local HTTP endpoint (or URL scheme) that Hermes/CLI call.

- OPTION B (stay all-Python): a windowed PyObjC AppKit app (NSWindow, not
  NSStatusItem) reusing `melk_led`, packaged with py2app (0.28.10 is available;
  confirm it builds on Python 3.14). `melk_led/async_runner.py` already bridges
  AppKit's main run loop to a background asyncio loop for Bleak; reuse it.
  More polish work in AppKit, and inherits the py2app/TCC packaging chores.

- OPTION C: Python FastAPI backend (already built) + a web/Tauri/Electron
  front end. Polished UI quickly, but BLE stays in the Python process and keeps
  the TCC packaging burden.

Recommendation: OPTION A for the app itself, keeping the Python package for
CLI + Hermes. Confirm this direction before building.

## Files already created for the app (reusable or removable)

- `melk_led/async_runner.py`: background asyncio loop bridge. Useful only if
  you go OPTION B. Safe to delete if going SwiftUI.
- No window/UI code was written yet. Nothing to undo.

## Repo map

- `melk_led/protocol.py` - wire protocol (pure, tested).
- `melk_led/device.py` - MelkDevice: connect/login/retry/write, scan().
- `melk_led/manager.py` - MelkManager: multi-device pool, group fan-out.
- `melk_led/scenes.py` - built-in modes + scene engine.
- `melk_led/config.py` - ~/.melk-led.toml loader.
- `melk_led/nlu.py` - Hermes natural-language parser.
- `melk_led/cli.py` - `lights ...` CLI.
- `melk_led/api.py` - FastAPI REST + /hermes.
- `melk_led/async_runner.py` - asyncio-on-thread bridge (Option B only).
- `scripts/lights-bundle` - macOS BLE launcher (open via Python.app).
- `scripts/fix_macos_bluetooth.sh` - patch + deep re-sign Python.app.
- `scripts/_bundle_bootstrap.py` - in-bundle sys.path splice + GUI activation.
- `scripts/selftest.py` - visible hardware protocol test.
- `AGENTS.md` - protocol + macOS TCC notes (read this first).

## Command cheat sheet

```bash
cd /Users/chrisdev/Developer/melk-led
source .venv/bin/activate

pytest                                             # offline tests
./scripts/lights-bundle scan                       # discover devices
./scripts/lights-bundle scripts/selftest.py <UUID> # visible hardware test
./scripts/lights-bundle --target led1 on           # single device
./scripts/lights-bundle --target all scene movie    # group + scene
```

## Immediate next steps for the new session

1. Confirm with the user: SwiftUI native app (Option A) vs all-Python (Option B).
2. If SwiftUI: scaffold an Xcode project, port the ~8 command builders from
   `melk_led/protocol.py` (they are trivial byte arrays), implement scan +
   connect + the mandatory login handshake (`7E 07 83`, then `7E 04 04`),
   then build the UI (device list, color, brightness, white, scenes).
3. Keep the Python CLI/REST/Hermes as the automation surface; decide how the
   app and Hermes share BLE ownership (single-owner + local endpoint).
4. Map led1-led4 to physical rooms and set real aliases.
