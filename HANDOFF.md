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

## macOS app — BUILT (2026-07-09), simplified (2026-07-10)

The polished standalone macOS app is in `macos-app/` (Option A: SwiftUI +
CoreBluetooth). It builds clean and launches. The architecture is:

- The app owns all BLE connections (CoreBluetooth, no Python/Bleak).
- Standalone by design: the HTTP endpoint, Hermes NLU, and the Claude Code
  "flash on approval" integration were REMOVED on 2026-07-10 at the user's
  request (the hook was also removed from ~/.claude/settings.json).
- Groups: user-defined, persisted to groups.json, full editor UI.
- Scenes: user-editable; "movie" is the ONLY built-in. Scene editor sheet
  with ordered steps, persisted to scenes.json.
- Devices renameable; aliases persist to devices.json. All persistence is in
  ~/Library/Application Support/MelkLED/.

The Python package (`melk_led/`) remains as the CLI and reference
implementation (its own REST/Hermes files still exist but are demoted).

`melk_led/async_runner.py` is an Option B leftover (asyncio bridge for PyObjC).
Safe to delete; it is not used by the app or tests.

## Repo map

### macOS app (production target)
- `macos-app/MelkLED/Protocol/MelkProtocol.swift` - Swift wire protocol.
- `macos-app/MelkLED/BLE/MelkController.swift` - CoreBluetooth controller,
  plus group/scene management.
- `macos-app/MelkLED/BLE/MelkDevice.swift` - per-device model.
- `macos-app/MelkLED/Models/Scenes.swift` - editable scene model (movie only built-in).
- `macos-app/MelkLED/Models/Groups.swift` - group model.
- `macos-app/MelkLED/Models/DeviceStore.swift` - JSON stores (devices/groups/scenes).
- `macos-app/MelkLED/Views/SceneEditorView.swift` - custom scene editor.
- `macos-app/MelkLED/Views/GroupEditorView.swift` - group editor.

### Python package (CLI / reference)
- `melk_led/protocol.py` - wire protocol (pure, tested).
- `melk_led/device.py` - MelkDevice: connect/login/retry/write, scan().
- `melk_led/manager.py` - MelkManager: multi-device pool, group fan-out.
- `melk_led/scenes.py` - built-in modes + scene engine.
- `melk_led/config.py` - ~/.melk-led.toml loader.
- `melk_led/nlu.py` - Hermes natural-language parser.
- `melk_led/cli.py` - `lights ...` CLI.
- `melk_led/api.py` - FastAPI REST + /hermes.
- `scripts/lights-bundle` - macOS BLE launcher (open via Python.app).
- `scripts/fix_macos_bluetooth.sh` - patch + deep re-sign Python.app.
- `scripts/selftest.py` - visible hardware protocol test.
- `AGENTS.md` - protocol, TCC notes, full project map (read this first).

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

1. Connect to a real strip from the app UI and confirm colours/scenes land
   visually (BLE writes are unverifiable without the physical lights).
2. Map led1-led4 to physical room names and update `~/.melk-led.toml` aliases.
3. Consider deleting `melk_led/async_runner.py` (Option B leftover, unused).
