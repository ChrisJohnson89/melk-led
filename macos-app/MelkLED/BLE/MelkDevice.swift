//
//  MelkDevice.swift
//  MelkLED
//
//  Observable model for a single MELK controller: its identity, live BLE
//  connection state, and the optimistic UI state (power/colour/brightness)
//  the views bind to. The actual CoreBluetooth work lives in MelkController;
//  this type holds no Bluetooth logic so views can observe it cheaply.
//

import Foundation
import CoreBluetooth
import SwiftUI

@MainActor
final class MelkDevice: ObservableObject, Identifiable {

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case loggingIn
        case ready

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .loggingIn: return "Logging in…"
            case .ready: return "Connected"
            }
        }

        var color: Color {
            switch self {
            case .disconnected: return .secondary
            case .connecting, .loggingIn: return .orange
            case .ready: return .green
            }
        }
    }

    /// Stable CoreBluetooth peripheral identifier (per-Mac UUID).
    let id: UUID

    @Published var name: String
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isDiscovered: Bool = false

    // Optimistic UI state — updated as the user drives controls. MELK is
    // effectively write-only, so we do not read these back from hardware.
    @Published var isOn: Bool = false
    @Published var color: Color = .white
    @Published var brightness: Double = 100
    @Published var warmPercent: Double = 50

    // --- CoreBluetooth wiring, owned/updated by MelkController ---
    var peripheral: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?

    /// Frames waiting to be written once the login handshake completes.
    var pendingFrames: [Data] = []

    init(id: UUID, name: String, peripheral: CBPeripheral? = nil) {
        self.id = id
        self.name = name
        self.peripheral = peripheral
    }

    var isReady: Bool { connectionState == .ready }
    var shortID: String { String(id.uuidString.prefix(8)) }
}
