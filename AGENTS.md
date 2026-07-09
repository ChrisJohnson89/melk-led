# melk-led — protocol & development notes

Native local control of **MELK-OA10** BLE LED controllers, replacing the
official mobile app. macOS-first, Bleak-based.

## Device identity

- Advertised name: `MELK-OA10` (family: `MELK-*`, `ELK-BLEDOM`, `LEDBLE`).
- Chipset family: **ELK-BLEDOM / Triones** clone controllers. Dozens of
  rebranded strips share this exact BLE protocol.
- Companion apps: "Magic Lantern" / "DuoCo Strip" / "LotusLantern" style apps.

The protocol below was NOT guessed — it is cross-validated against two
independent community implementations:

- `dave-code-ruiz/elkbledom` (`models.json` entry `MELK-OA10`, `elkbledom.py`)
- `dougppaz/python-bt-led-strip` (`MELKController`)

## BLE topology

| Item | Value |
|---|---|
| Write characteristic | `0000fff3-0000-1000-8000-00805f9b34fb` |
| Read/notify characteristic | `0000fff4-0000-1000-8000-00805f9b34fb` |
| Write mode | write **without** response |
| Notifications | present on `fff4` but unreliable; MELK is treated as write-only |

## Frame format

All commands are **9 bytes**: `7E <cmd...> EF`. Prefix `0x7E`, suffix `0xEF`.
**There is no checksum.** (The login handshake frames are the only 3-byte
exception.)

## Login handshake (mandatory)

MELK firmware silently drops the connection unless this is written
immediately after connecting, before any real command:

```
7E 07 83           # write, wait ~1s
7E 04 04           # write, wait ~1s
```

Implemented in `melk_led/device.py :: MelkDevice._login`.

## Command table (MELK-OA10)

| Function | Bytes | Params |
|---|---|---|
| Power on | `7E 04 04 F0 00 01 FF 00 EF` | — |
| Power off | `7E 04 04 00 00 00 FF 00 EF` | — |
| RGB colour | `7E 00 05 03 RR GG BB 00 EF` | R,G,B = 0–255 |
| Brightness | `7E 04 01 PP 01 FF FF 00 EF` | PP = 0–100 |
| White temp | `7E 06 05 02 WW CC FF 08 EF` | WW warm%, CC cold% (WW+CC=100) |
| Effect | `7E 05 03 II 06 FF FF 00 EF` | II = effect id |
| Effect speed | `7E 04 02 VV FF FF FF 00 EF` | VV = 0–100 |
| Query state | `7E 00 01 FA 00 00 00 00 EF` | (notify models only) |

Encoded in `melk_led/protocol.py`; pinned by `tests/test_protocol.py`.

## Effect / scene ids (`EFFECTS_MELK_Ox`)

`0` AutoPlay, `1` Magic_Back, `16` Rainbow_Cycle, `32` Color_Wave,
`48` Breathing, `64` Strobe, `128` Jump_RGB, `144` Fade_RGB, `207` Blue_Scroll.

## Project map

- `melk_led/protocol.py` — pure wire protocol (byte builders, effect enum).
- `melk_led/device.py` — `MelkDevice`: Bleak connect/login/retry/write, `scan()`.
- `melk_led/manager.py` — `MelkManager`: multi-device pool, group fan-out.
- `melk_led/scenes.py` — built-in modes (movie/pet/gaming/…) + scene engine.
- `melk_led/config.py` — `~/.melk-led.toml` (aliases, groups, custom scenes).
- `melk_led/nlu.py` — deterministic natural-language parser for Hermes.
- `melk_led/cli.py` — `lights ...` command.
- `melk_led/api.py` — FastAPI REST + `/hermes` endpoint.
- `scripts/selftest.py` — visible hardware protocol verification.
- `tests/` — offline unit tests (no hardware).

## macOS Bluetooth (TCC) — the launch story

Getting BLE to run at all on macOS 26 (Tahoe) took real effort; do not
undo any of this:

1. **Usage string required.** A process that touches CoreBluetooth is
   SIGABRT-killed by TCC unless it declares `NSBluetoothAlwaysUsageDescription`.
   A direct `python x.py` reads it from the Mach-O `__TEXT,__info_plist`
   section, which Homebrew's Python lacks -> instant crash.
2. **Bundle launch.** We instead launch the framework `Python.app` via
   LaunchServices (`open`), which reads the key from the bundle
   `Contents/Info.plist`. `scripts/fix_macos_bluetooth.sh` adds the key;
   `scripts/lights-bundle` does the `open` launch and splices the venv's
   site-packages onto `sys.path` via `scripts/_bundle_bootstrap.py`.
3. **`--deep` re-sign is mandatory.** After editing the plist, the bundle
   MUST be re-signed with `codesign --force --deep --sign -`. Without
   `--deep`, only the outer wrapper is re-signed; the inner binary keeps
   its Homebrew signature sealing the OLD plist, and macOS 26 TCC rejects
   the whole chain with `-67030` (errSecCSSignatureFailed) — silently
   denying with no dialog and no TCC.db entry (so `tccutil reset` finds
   nothing). This is the single most confusing failure mode.
4. **Responsible process.** TCC attributes the Bluetooth request to the
   terminal app that launched it (e.g. Warp), so that app must be enabled
   under System Settings > Privacy & Security > Bluetooth. `DENIED_BY_USER`
   means it is listed there with the box unchecked.
5. The bootstrap sets `NSApplicationActivationPolicyRegular` so the
   permission dialog comes to the foreground on first grant.
6. Re-run `fix_macos_bluetooth.sh` after `brew upgrade python@3.14`.

Durable production path: ship a signed `.app` (py2app) with the key in its
own Info.plist, so it owns its TCC identity independent of the terminal.

## Development notes

- Keep `protocol.py` free of BLE imports so it stays unit-testable offline.
- All inputs are clamped in `protocol.py`; callers pass human units
  (percent 0–100, RGB 0–255).
- Reconnect+retry lives in `MelkDevice._send`; don't reconnect per command
  elsewhere — reuse the pooled connection via `MelkManager`.
- Never surface raw tracebacks from the CLI/API; return friendly messages.

## Optional: capture your own traffic to extend the protocol

The protocol above is complete for on/off/RGB/brightness/white/effects/speed.
If you later want to map something not covered (e.g. music-reactive mic mode,
timers, or a model-specific scene), capture the official app's writes:

1. **iOS PacketLogger (best on Mac):** install *Additional Tools for Xcode*,
   run **PacketLogger**, start capture, drive the official app, stop, then
   filter for `ATT Send Write Command` to `0xfff3`. Each 9-byte `7E..EF`
   payload is a command.
2. **nRF Connect (iOS/Android):** connect to the device, expand service
   `fff0`, enable logging, tap through the app on a second phone, read the
   written bytes on characteristic `fff3`.
3. **LightBlue (iOS/Mac):** connect, open the `fff3` characteristic, and you
   can both observe and manually write hex to test hypotheses live.
4. **Android HCI snoop + Wireshark:** enable *Bluetooth HCI snoop log* in
   Developer Options, reproduce actions, pull `btsnoop_hci.log`, open in
   Wireshark, filter `btatt.opcode == 0x52` (Write Command).

Send any new `7E..EF` frames here and they can be decoded and added to
`protocol.py`.
