//
//  MelkProtocol.swift
//  MelkLED
//
//  Pure wire protocol for MELK-OA10 (ELK-BLEDOM / Triones family) BLE LED
//  controllers. No CoreBluetooth dependency so it stays trivially testable.
//
//  This is a direct port of the reference Python implementation in
//  `melk_led/protocol.py`, cross-validated against two community projects:
//    - https://github.com/dave-code-ruiz/elkbledom
//    - https://github.com/dougppaz/python-bt-led-strip
//
//  Wire facts:
//    * Write characteristic: 0000fff3-0000-1000-8000-00805f9b34fb (write
//      WITHOUT response).
//    * Read/notify characteristic: 0000fff4-... (present but treated as
//      write-only in practice).
//    * Frame: 9 bytes, prefix 0x7E, suffix 0xEF. There is NO checksum.
//    * Login: MELK controllers disconnect unless a login handshake is
//      written immediately after connecting (see `loginSequence`).
//

import Foundation

enum MelkProtocol {

    // GATT characteristic UUIDs (short 16-bit forms are fine for CoreBluetooth).
    static let writeCharacteristicUUID = "FFF3"
    static let notifyCharacteristicUUID = "FFF4"
    static let serviceUUID = "FFF0"

    /// Advertised-name prefixes we treat as MELK-family controllers.
    static let namePrefixes = ["MELK", "ELK-BLEDOM", "ELK-BLEDOB", "LEDBLE", "MODELX"]

    static let framePrefix: UInt8 = 0x7E
    static let frameSuffix: UInt8 = 0xEF

    /// MELK controllers reject all real commands until this handshake is sent
    /// right after connecting. Each frame is written in order with a short
    /// delay between them (applied by the caller — see `MelkController`).
    static let loginSequence: [Data] = [
        Data([0x7E, 0x07, 0x83]),
        Data([0x7E, 0x04, 0x04]),
    ]

    /// Built-in effect / scene ids for the MELK-Ox effect class.
    /// Values come from elkbledom `definitions.json` -> `EFFECTS_MELK_Ox`.
    enum Effect: Int, CaseIterable, Identifiable {
        case autoPlay = 0
        case magicBack = 1
        case rainbowCycle = 16
        case colorWave = 32
        case breathing = 48
        case strobe = 64
        case jumpRGB = 128
        case fadeRGB = 144
        case blueScroll = 207

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .autoPlay: return "Auto Play"
            case .magicBack: return "Magic"
            case .rainbowCycle: return "Rainbow Cycle"
            case .colorWave: return "Color Wave"
            case .breathing: return "Breathing"
            case .strobe: return "Strobe"
            case .jumpRGB: return "Jump"
            case .fadeRGB: return "Fade"
            case .blueScroll: return "Blue Scroll"
            }
        }
    }

    // Convenience named white points expressed as warm-percent (0 = cool, 100 = warm).
    static let whiteWarm = 100
    static let whiteNeutral = 50
    static let whiteCool = 0

    // MARK: - Helpers

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> UInt8 {
        UInt8(max(low, min(high, value)))
    }

    /// Wrap a 9-byte frame and validate the prefix/suffix.
    private static func frame(_ payload: [UInt8]) -> Data {
        precondition(payload.count == 9, "frame must be 9 bytes, got \(payload.count)")
        precondition(payload.first == framePrefix && payload.last == frameSuffix,
                     "frame must be 0x7E..0xEF")
        return Data(payload)
    }

    // MARK: - Command builders

    /// Turn the controller on or off.
    static func power(on: Bool) -> Data {
        on
            ? frame([0x7E, 0x04, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF])
            : frame([0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF])
    }

    /// Set a static RGB colour. Each channel is 0-255.
    static func color(r: Int, g: Int, b: Int) -> Data {
        frame([0x7E, 0x00, 0x05, 0x03, clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255), 0x00, 0xEF])
    }

    /// Set brightness as a percentage, 0-100.
    static func brightness(percent: Int) -> Data {
        frame([0x7E, 0x04, 0x01, clamp(percent, 0, 100), 0x01, 0xFF, 0xFF, 0x00, 0xEF])
    }

    /// Set white colour temperature.
    /// `warmPercent` 0-100: 0 = fully cool white, 100 = fully warm white.
    static func colorTemperature(warmPercent: Int) -> Data {
        let warm = clamp(warmPercent, 0, 100)
        let cold = UInt8(100 - Int(warm))
        return frame([0x7E, 0x06, 0x05, 0x02, warm, cold, 0xFF, 0x08, 0xEF])
    }

    /// Select a built-in effect / scene by id.
    static func effect(id: Int) -> Data {
        frame([0x7E, 0x05, 0x03, clamp(id, 0, 255), 0x06, 0xFF, 0xFF, 0x00, 0xEF])
    }

    static func effect(_ effect: Effect) -> Data {
        self.effect(id: effect.rawValue)
    }

    /// Set effect animation speed as a percentage, 0-100.
    static func effectSpeed(percent: Int) -> Data {
        frame([0x7E, 0x04, 0x02, clamp(percent, 0, 100), 0xFF, 0xFF, 0xFF, 0x00, 0xEF])
    }

    /// Request a status frame (notify-capable models only).
    static func queryState() -> Data {
        frame([0x7E, 0x00, 0x01, 0xFA, 0x00, 0x00, 0x00, 0x00, 0xEF])
    }
}
