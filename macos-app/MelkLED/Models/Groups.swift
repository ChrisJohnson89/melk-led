//
//  Groups.swift
//  MelkLED
//
//  User-defined groups of controllers. A group is a name plus member device
//  IDs; commands sent to a group fan out to every member. Persisted to
//  groups.json in Application Support.
//

import Foundation

struct LightGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var memberIDs: [UUID] = []
}
