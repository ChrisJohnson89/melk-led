//
//  Scenes.swift
//  MelkLED
//
//  User-editable scenes. A scene is an ordered list of steps; each step
//  compiles to one 9-byte protocol frame. "Movie" is the only built-in;
//  everything else is created by the user in the scene editor and persisted
//  to scenes.json.
//

import Foundation
import SwiftUI

/// One step of a scene. Struct (not enum) so it is trivially Codable and
/// editable in place: `op` selects which of the value fields apply.
struct SceneStep: Codable, Identifiable, Hashable {
    enum Op: String, Codable, CaseIterable, Identifiable {
        case on, off, color, brightness, white, effect, effectSpeed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .on: return "Power on"
            case .off: return "Power off"
            case .color: return "Colour"
            case .brightness: return "Brightness"
            case .white: return "White temperature"
            case .effect: return "Effect"
            case .effectSpeed: return "Effect speed"
            }
        }
    }

    var id = UUID()
    var op: Op

    // Value fields; which ones matter depends on `op`.
    var r: Int = 255
    var g: Int = 255
    var b: Int = 255
    var percent: Int = 100       // brightness / effectSpeed
    var warm: Int = 50           // white temperature (0 cool, 100 warm)
    var effectID: Int = MelkProtocol.Effect.rainbowCycle.rawValue

    var frame: Data {
        switch op {
        case .on: return MelkProtocol.power(on: true)
        case .off: return MelkProtocol.power(on: false)
        case .color: return MelkProtocol.color(r: r, g: g, b: b)
        case .brightness: return MelkProtocol.brightness(percent: percent)
        case .white: return MelkProtocol.colorTemperature(warmPercent: warm)
        case .effect: return MelkProtocol.effect(id: effectID)
        case .effectSpeed: return MelkProtocol.effectSpeed(percent: percent)
        }
    }

    /// Short human summary for the editor's step list.
    var summary: String {
        switch op {
        case .on, .off: return op.label
        case .color: return "Colour (\(r), \(g), \(b))"
        case .brightness: return "Brightness \(percent)%"
        case .white: return "White \(warm >= 66 ? "warm" : warm <= 33 ? "cool" : "neutral") (\(warm))"
        case .effect:
            let name = MelkProtocol.Effect(rawValue: effectID)?.label ?? "#\(effectID)"
            return "Effect: \(name)"
        case .effectSpeed: return "Effect speed \(percent)%"
        }
    }
}

/// A named scene: label, SF Symbol, and the ordered steps to run.
struct LightScene: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String = "sparkles"
    var steps: [SceneStep] = []
    var isBuiltin: Bool = false

    var label: String { name.prefix(1).uppercased() + name.dropFirst() }

    /// The flat list of frames to write, in order.
    var frames: [Data] { steps.map(\.frame) }

    /// Swatch colour for the UI, derived from the scene's look.
    var tint: Color {
        for step in steps {
            switch step.op {
            case .color:
                return Color(.sRGB, red: Double(step.r) / 255,
                             green: Double(step.g) / 255, blue: Double(step.b) / 255)
            case .white:
                return step.warm >= 50
                    ? Color(red: 1.0, green: 0.78, blue: 0.5)
                    : Color(red: 0.65, green: 0.85, blue: 1.0)
            case .effect:
                return Color(red: 0.6, green: 0.4, blue: 1.0)
            default:
                continue
            }
        }
        return Color(white: 0.85)
    }

    /// SF Symbols offered in the scene editor.
    static let symbolChoices = [
        "sparkles", "film.fill", "gamecontroller.fill", "moon.stars.fill",
        "sun.max.fill", "flame.fill", "snowflake", "pawprint.fill",
        "book.fill", "music.note", "party.popper.fill", "heart.fill",
    ]
}

enum Scenes {
    /// The single built-in scene. Everything else is user-created.
    static let movie = LightScene(
        name: "movie",
        symbol: "film.fill",
        steps: [
            SceneStep(op: .on),
            SceneStep(op: .color, r: 255, g: 80, b: 15),
            SceneStep(op: .brightness, percent: 20),
        ],
        isBuiltin: true
    )
}
