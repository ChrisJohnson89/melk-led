//
//  ClaudeHookManager.swift
//  MelkLED
//
//  Reads and writes the Claude Code Notification hook in ~/.claude/settings.json
//  so the app can install/remove the "flash on approval" integration from the
//  Settings window. The app is non-sandboxed, so it can touch this file
//  directly. Existing settings are preserved — only our own hook entry (matched
//  by its command) is added or removed.
//

import Foundation

enum ClaudeHookError: LocalizedError {
    case unreadableSettings
    var errorDescription: String? {
        "~/.claude/settings.json exists but isn't valid JSON — refusing to modify it so nothing is lost. Fix or remove that file and try again."
    }
}

struct ClaudeHookManager {
    let port: UInt16

    var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private var command: String { "curl -s -m 2 -X POST localhost:\(port)/flash >/dev/null 2>&1 &" }
    /// Substring that identifies our hook entry regardless of exact matcher.
    private var marker: String { "localhost:\(port)/flash" }

    // MARK: - Status

    /// Whether our hook is present, and whether it also covers the idle prompt.
    func status() -> (installed: Bool, includesIdle: Bool) {
        for entry in notificationEntries(load()) where entryIsOurs(entry) {
            let matcher = (entry["matcher"] as? String) ?? ""
            return (true, matcher.contains("idle_prompt"))
        }
        return (false, false)
    }

    // MARK: - Mutations

    func install(includeIdle: Bool) throws {
        var root = try loadForWrite()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var notif = hooks["Notification"] as? [[String: Any]] ?? []
        notif.removeAll(where: entryIsOurs)   // replace any prior version
        notif.append([
            "matcher": includeIdle ? "permission_prompt|idle_prompt" : "permission_prompt",
            "hooks": [["type": "command", "command": command]],
        ])
        hooks["Notification"] = notif
        root["hooks"] = hooks
        try write(root)
    }

    func uninstall() throws {
        var root = try loadForWrite()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        var notif = hooks["Notification"] as? [[String: Any]] ?? []
        notif.removeAll(where: entryIsOurs)
        if notif.isEmpty { hooks.removeValue(forKey: "Notification") } else { hooks["Notification"] = notif }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try write(root)
    }

    // MARK: - Helpers

    /// Lenient read for status display: any problem = "no hook".
    private func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// Strict read for mutation: a missing/empty file is fine (start fresh),
    /// but a file that exists and won't parse must NOT be overwritten.
    private func loadForWrite() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeHookError.unreadableSettings
        }
        return obj
    }

    private func notificationEntries(_ root: [String: Any]) -> [[String: Any]] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return hooks["Notification"] as? [[String: Any]] ?? []
    }

    private func entryIsOurs(_ entry: [String: Any]) -> Bool {
        let inner = entry["hooks"] as? [[String: Any]] ?? []
        return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }
}
