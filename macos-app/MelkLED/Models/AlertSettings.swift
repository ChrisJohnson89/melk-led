//
//  AlertSettings.swift
//  MelkLED
//
//  Shared UserDefaults keys + accessors for the approval-alert flash
//  appearance, so the Settings UI (@AppStorage) and the controller/server
//  (plain reads) stay in sync on one source of truth.
//

import Foundation

enum AlertSettings {
    static let colorRKey = "alertColorR"
    static let colorGKey = "alertColorG"
    static let colorBKey = "alertColorB"
    static let blinksKey = "alertBlinks"
    static let targetKey = "alertTargetID"   // "" means all devices

    static let defaultColor = (r: 255, g: 140, b: 0)   // amber
    static let defaultBlinks = 4

    static func color(_ d: UserDefaults = .standard) -> (r: Int, g: Int, b: Int) {
        (d.object(forKey: colorRKey) as? Int ?? defaultColor.r,
         d.object(forKey: colorGKey) as? Int ?? defaultColor.g,
         d.object(forKey: colorBKey) as? Int ?? defaultColor.b)
    }

    static func blinks(_ d: UserDefaults = .standard) -> Int {
        max(1, min(20, d.object(forKey: blinksKey) as? Int ?? defaultBlinks))
    }

    static func targetID(_ d: UserDefaults = .standard) -> String {
        d.string(forKey: targetKey) ?? ""
    }
}
