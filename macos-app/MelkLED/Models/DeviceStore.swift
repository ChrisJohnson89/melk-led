//
//  DeviceStore.swift
//  MelkLED
//
//  Tiny JSON-backed persistence for device aliases, keyed by CoreBluetooth
//  peripheral UUID. Lives in Application Support so it survives app updates.
//

import Foundation

struct DeviceStore {

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MelkLED", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("devices.json")
    }

    /// Returns a map of peripheral-UUID string -> alias.
    func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    func save(_ aliases: [String: String]) {
        guard let data = try? JSONEncoder().encode(aliases) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
