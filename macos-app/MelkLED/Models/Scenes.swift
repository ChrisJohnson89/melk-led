//
//  Scenes.swift
//  MelkLED
//
//  High-level scenes / modes built from protocol primitives. A scene is an
//  ordered list of steps; each step compiles to one 9-byte protocol frame.
//  Ported from `melk_led/scenes.py`.
//

import Foundation
import SwiftUI

/// One step of a scene. Compiles directly to a wire frame.
enum SceneStep {
    case on
    case off
    case color(r: Int, g: Int, b: Int)
    case brightness(percent: Int)
    case white(warmPercent: Int)
    case effect(id: Int)
    case effectSpeed(percent: Int)

    var frame: Data {
        switch self {
        case .on: return MelkProtocol.power(on: true)
        case .off: return MelkProtocol.power(on: false)
        case let .color(r, g, b): return MelkProtocol.color(r: r, g: g, b: b)
        case let .brightness(p): return MelkProtocol.brightness(percent: p)
        case let .white(w): return MelkProtocol.colorTemperature(warmPercent: w)
        case let .effect(id): return MelkProtocol.effect(id: id)
        case let .effectSpeed(p): return MelkProtocol.effectSpeed(percent: p)
        }
    }
}

/// A named scene: a label, an SF Symbol, a swatch colour for the UI, and the
/// ordered steps to run on the controller.
struct LightScene: Identifiable, Hashable {
    let name: String
    let symbol: String
    let tint: Color
    let steps: [SceneStep]

    var id: String { name }
    var label: String { name.prefix(1).uppercased() + name.dropFirst() }

    static func == (lhs: LightScene, rhs: LightScene) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// The flat list of frames to write, in order (power on first, then look).
    var frames: [Data] { steps.map(\.frame) }
}

enum Scenes {
    /// Built-in scenes. Order matters: power on first, then set the look.
    static let all: [LightScene] = [
        LightScene(name: "office", symbol: "briefcase.fill", tint: Color(white: 0.95), steps: [
            .on, .white(warmPercent: 35), .brightness(percent: 100),
        ]),
        LightScene(name: "movie", symbol: "film.fill", tint: Color(red: 1.0, green: 0.31, blue: 0.06), steps: [
            .on, .color(r: 255, g: 80, b: 15), .brightness(percent: 20),
        ]),
        LightScene(name: "pet", symbol: "pawprint.fill", tint: Color(red: 1.0, green: 0.85, blue: 0.6), steps: [
            .on, .white(warmPercent: 70), .brightness(percent: 30),
        ]),
        LightScene(name: "gaming", symbol: "gamecontroller.fill", tint: Color(red: 0.4, green: 0.9, blue: 1.0), steps: [
            .on, .effect(id: MelkProtocol.Effect.colorWave.rawValue), .effectSpeed(percent: 85),
        ]),
        LightScene(name: "rainbow", symbol: "rainbow", tint: Color(red: 0.6, green: 0.4, blue: 1.0), steps: [
            .on, .effect(id: MelkProtocol.Effect.rainbowCycle.rawValue), .effectSpeed(percent: 60),
        ]),
        LightScene(name: "white", symbol: "sun.max.fill", tint: Color(white: 0.9), steps: [
            .on, .white(warmPercent: MelkProtocol.whiteNeutral), .brightness(percent: 100),
        ]),
        LightScene(name: "warm", symbol: "flame.fill", tint: Color(red: 1.0, green: 0.75, blue: 0.45), steps: [
            .on, .white(warmPercent: MelkProtocol.whiteWarm), .brightness(percent: 80),
        ]),
        LightScene(name: "cool", symbol: "snowflake", tint: Color(red: 0.6, green: 0.85, blue: 1.0), steps: [
            .on, .white(warmPercent: MelkProtocol.whiteCool), .brightness(percent: 100),
        ]),
    ]

    static func named(_ name: String) -> LightScene? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
