//
//  DeviceStore.swift
//  MelkLED
//
//  Tiny JSON-backed persistence in Application Support/MelkLED:
//    devices.json  alias map keyed by CoreBluetooth peripheral UUID
//    groups.json   user-defined groups
//    scenes.json   user-created scenes
//

import Foundation

/// Shared location + Codable load/save for the app's small JSON files.
enum AppStorageDir {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MelkLED", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to filename: String) {
        let url = directory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Device aliases: peripheral-UUID string -> display name.
struct DeviceStore {
    func load() -> [String: String] {
        AppStorageDir.load([String: String].self, from: "devices.json") ?? [:]
    }

    func save(_ aliases: [String: String]) {
        AppStorageDir.save(aliases, to: "devices.json")
    }
}

struct GroupStore {
    func load() -> [LightGroup] {
        AppStorageDir.load([LightGroup].self, from: "groups.json") ?? []
    }

    func save(_ groups: [LightGroup]) {
        AppStorageDir.save(groups, to: "groups.json")
    }
}

struct SceneStore {
    func load() -> [LightScene] {
        AppStorageDir.load([LightScene].self, from: "scenes.json") ?? []
    }

    func save(_ scenes: [LightScene]) {
        AppStorageDir.save(scenes, to: "scenes.json")
    }
}
