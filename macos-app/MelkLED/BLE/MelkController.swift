//
//  MelkController.swift
//  MelkLED
//
//  The single BLE owner for the whole app. Owns one CBCentralManager, acts as
//  central + peripheral delegate for every controller, and exposes a small
//  high-level command surface (on/off/colour/brightness/white/effect/scene)
//  used by both the SwiftUI views and the local HTTP control endpoint.
//
//  Design mirrors the Python reference stack (device.py / manager.py):
//    * connect -> discover fff0 service -> find fff3 write characteristic
//    * mandatory login handshake (7E 07 83, then 7E 04 04) with ~1s spacing
//    * frames queued while connecting are flushed once login completes
//    * one central; commands fan out to a resolved set of devices
//
//  CBCentralManager is created with queue == nil, so every delegate callback
//  arrives on the main queue, matching this @MainActor type.
//

import Foundation
import CoreBluetooth
import SwiftUI

@MainActor
final class MelkController: NSObject, ObservableObject {

    // The 4 controllers already discovered during protocol bring-up
    // (see HANDOFF.md). Seeding their CoreBluetooth UUIDs lets the app show
    // and connect to them immediately, before any scan. Aliases persist and
    // can be renamed in the UI.
    static let seededDevices: [(uuid: String, name: String)] = [
        ("2C6B9004-9E7D-2D9B-3546-4613A77E254E", "led1"),
        ("9448314C-F489-8169-B3F2-48145D7B5579", "led2"),
        ("92F38122-6791-0C44-FE33-0C78501BFF39", "led3"),
        ("CB1606C6-A343-AA43-170C-007F2F00D287", "led4"),
    ]

    // Delay between the two login frames. MELK firmware is picky; ~1s is what
    // the reference implementations use and what works reliably in practice.
    private let loginStepDelay: TimeInterval = 1.0
    private let maxConnectRetries = 3

    @Published private(set) var devices: [MelkDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var lastMessage: String = ""

    private var central: CBCentralManager!
    private var byPeripheral: [UUID: MelkDevice] = [:]
    private var connectRetries: [UUID: Int] = [:]
    private let store = DeviceStore()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        seedKnownDevices()
    }

    // MARK: - Seeding & persistence

    private func seedKnownDevices() {
        let saved = store.load()
        // Union of the built-in seeds and anything the user has saved before.
        var entries = MelkController.seededDevices.map { (UUID(uuidString: $0.uuid), $0.name) }
        for (uuidStr, name) in saved where !MelkController.seededDevices.contains(where: { $0.uuid == uuidStr }) {
            entries.append((UUID(uuidString: uuidStr), name))
        }
        for (uuid, name) in entries {
            guard let uuid else { continue }
            let display = saved[uuid.uuidString] ?? name
            let device = MelkDevice(id: uuid, name: display)
            devices.append(device)
            byPeripheral[uuid] = device
        }
    }

    private func persist() {
        store.save(devices.reduce(into: [:]) { $0[$1.id.uuidString] = $1.name })
    }

    /// Re-attach CBPeripheral objects for seeded devices once Bluetooth is on.
    private func retrieveSeededPeripherals() {
        let ids = devices.map(\.id)
        for peripheral in central.retrievePeripherals(withIdentifiers: ids) {
            if let device = byPeripheral[peripheral.identifier] {
                device.peripheral = peripheral
                peripheral.delegate = self
            }
        }
    }

    // MARK: - Scanning

    func startScan() {
        guard bluetoothState == .poweredOn else {
            lastMessage = "Bluetooth is not powered on."
            return
        }
        isScanning = true
        lastMessage = "Scanning for MELK controllers…"
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
        // Auto-stop after a reasonable window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
    }

    // MARK: - Connection lifecycle

    func connect(_ device: MelkDevice) {
        guard bluetoothState == .poweredOn else {
            lastMessage = "Bluetooth is not powered on."
            return
        }
        if device.peripheral == nil {
            // Try to retrieve it by identifier (works for seeded/known devices).
            if let p = central.retrievePeripherals(withIdentifiers: [device.id]).first {
                device.peripheral = p
                p.delegate = self
            }
        }
        guard let peripheral = device.peripheral else {
            lastMessage = "\(device.name): not found yet — run a scan."
            return
        }
        guard device.connectionState == .disconnected else { return }
        device.connectionState = .connecting
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func disconnect(_ device: MelkDevice) {
        guard let peripheral = device.peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    private func beginLogin(_ device: MelkDevice) {
        guard let peripheral = device.peripheral, device.writeCharacteristic != nil else { return }
        device.connectionState = .loggingIn
        let sequence = MelkProtocol.loginSequence
        for (index, frame) in sequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + loginStepDelay * Double(index)) {
                guard device.peripheral === peripheral,
                      let char = device.writeCharacteristic else { return }
                peripheral.writeValue(frame, for: char, type: .withoutResponse)
            }
        }
        // Mark ready one step after the final login frame, then flush queue.
        DispatchQueue.main.asyncAfter(deadline: .now() + loginStepDelay * Double(sequence.count)) { [weak self] in
            guard let self, device.peripheral === peripheral else { return }
            device.connectionState = .ready
            self.connectRetries[device.id] = 0
            self.lastMessage = "\(device.name): connected."
            self.flush(device)
        }
    }

    // MARK: - Command surface

    /// Queue frames for a device, connecting/logging in first if needed.
    func send(_ frames: [Data], to device: MelkDevice) {
        guard !frames.isEmpty else { return }
        device.pendingFrames.append(contentsOf: frames)
        switch device.connectionState {
        case .ready:
            flush(device)
        case .connecting, .loggingIn:
            break // will flush once ready
        case .disconnected:
            connect(device)
        }
    }

    private func flush(_ device: MelkDevice) {
        guard device.connectionState == .ready,
              let peripheral = device.peripheral,
              let char = device.writeCharacteristic else { return }
        let frames = device.pendingFrames
        device.pendingFrames.removeAll()
        for frame in frames {
            peripheral.writeValue(frame, for: char, type: .withoutResponse)
        }
    }

    // Single-device high-level commands (also update optimistic UI state).

    func setOn(_ device: MelkDevice, _ on: Bool) {
        device.isOn = on
        send([MelkProtocol.power(on: on)], to: device)
    }

    func setColor(_ device: MelkDevice, _ color: Color) {
        device.color = color
        device.isOn = true
        let (r, g, b) = Self.rgb(from: color)
        send([MelkProtocol.color(r: r, g: g, b: b)], to: device)
    }

    func setColor(_ device: MelkDevice, r: Int, g: Int, b: Int) {
        device.color = Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        device.isOn = true
        send([MelkProtocol.color(r: r, g: g, b: b)], to: device)
    }

    func setBrightness(_ device: MelkDevice, percent: Int) {
        device.brightness = Double(percent)
        send([MelkProtocol.brightness(percent: percent)], to: device)
    }

    func setWhite(_ device: MelkDevice, warmPercent: Int) {
        device.warmPercent = Double(warmPercent)
        device.isOn = true
        send([MelkProtocol.colorTemperature(warmPercent: warmPercent)], to: device)
    }

    func setEffect(_ device: MelkDevice, id: Int) {
        device.isOn = true
        send([MelkProtocol.effect(id: id)], to: device)
    }

    func apply(_ scene: LightScene, to device: MelkDevice) {
        device.isOn = true
        send(scene.frames, to: device)
    }

    // Group fan-out.

    var connectableDevices: [MelkDevice] { devices }

    func setOnAll(_ on: Bool) { devices.forEach { setOn($0, on) } }
    func apply(_ scene: LightScene, toAll: Bool) { if toAll { devices.forEach { apply(scene, to: $0) } } }

    // MARK: - Attention / alert

    /// Default attention colour (amber).
    static let alertColor = (r: 255, g: 140, b: 0)

    private var flashGeneration = 0
    /// True while an attention flash is running (for the UI).
    @Published private(set) var isFlashing = false

    /// Flash using the appearance configured in Settings (colour, blink count,
    /// target). Used by the Settings "Test" button and by the bare `/flash`
    /// endpoint the Claude Code hook calls with no parameters.
    func flashAlert() {
        let c = AlertSettings.color()
        let target = AlertSettings.targetID()
        let chosen = target.isEmpty ? devices : devices.filter { $0.id.uuidString == target }
        flash(targets: chosen.isEmpty ? devices : chosen,
              r: c.r, g: c.g, b: c.b, blinks: AlertSettings.blinks())
    }

    /// Flash the given devices to get attention (e.g. an approval is waiting),
    /// then restore each device's prior state. A fresh call cancels any flash
    /// already in progress so alerts never pile up or leave lights stuck.
    func flash(targets: [MelkDevice],
               r: Int = alertColor.r, g: Int = alertColor.g, b: Int = alertColor.b,
               blinks: Int = 4) {
        let devices = targets.isEmpty ? self.devices : targets
        guard !devices.isEmpty else { return }

        flashGeneration += 1
        let generation = flashGeneration
        isFlashing = true

        // Snapshot prior optimistic state so we can restore it afterwards.
        let priors = devices.map { ($0, $0.isOn, $0.color, Int($0.brightness)) }

        // Ensure connections; give cold devices time to finish the login
        // handshake before the blink sequence so the blinks are clean.
        var startDelay = 0.0
        for d in devices where !d.isReady {
            connect(d)
            startDelay = 2.4
        }

        let interval = 0.3
        let onFrames = [MelkProtocol.power(on: true),
                        MelkProtocol.color(r: r, g: g, b: b),
                        MelkProtocol.brightness(percent: 100)]
        let offFrames = [MelkProtocol.power(on: false)]

        var t = startDelay
        schedule(at: t, generation) { devices.forEach { self.send(onFrames, to: $0) } }
        for _ in 0..<blinks {
            t += interval
            schedule(at: t, generation) { devices.forEach { self.send(offFrames, to: $0) } }
            t += interval
            schedule(at: t, generation) { devices.forEach { self.send(onFrames, to: $0) } }
        }

        // Restore prior look and clear the flashing flag.
        t += interval
        schedule(at: t, generation) {
            for (d, wasOn, color, bright) in priors {
                if wasOn {
                    let (rr, gg, bb) = Self.rgb(from: color)
                    self.send([MelkProtocol.power(on: true),
                               MelkProtocol.color(r: rr, g: gg, b: bb),
                               MelkProtocol.brightness(percent: bright)], to: d)
                    d.isOn = true; d.color = color; d.brightness = Double(bright)
                } else {
                    self.send(offFrames, to: d)
                    d.isOn = false
                }
            }
            self.isFlashing = false
        }
    }

    private func schedule(at delay: TimeInterval, _ generation: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            action()
        }
    }

    // MARK: - Alias editing

    func rename(_ device: MelkDevice, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        device.name = trimmed
        persist()
    }

    func device(named target: String) -> MelkDevice? {
        devices.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
            ?? devices.first { $0.id.uuidString.caseInsensitiveCompare(target) == .orderedSame }
    }

    /// Resolve a Hermes/HTTP target string to a set of devices. "all" (or an
    /// empty target) fans out to every known device.
    func resolveTargets(_ target: String?) -> [MelkDevice] {
        guard let target, !target.isEmpty, target.lowercased() != "all" else { return devices }
        if let match = device(named: target) { return [match] }
        return []
    }

    // MARK: - Colour helpers

    static func rgb(from color: Color) -> (Int, Int, Int) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        return (Int((ns.redComponent * 255).rounded()),
                Int((ns.greenComponent * 255).rounded()),
                Int((ns.blueComponent * 255).rounded()))
    }
}

// MARK: - CBCentralManagerDelegate
//
// The central is created with `queue: nil`, so every delegate callback is
// delivered on the main queue. The methods are declared `nonisolated` to
// satisfy the (non-isolated) delegate protocol, then immediately re-enter the
// main actor via `assumeIsolated` — correct at runtime and clean under Swift 6.

extension MelkController: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetoothState = central.state
            switch central.state {
            case .poweredOn:
                lastMessage = "Bluetooth ready."
                retrieveSeededPeripherals()
            case .poweredOff:
                lastMessage = "Bluetooth is off."
            case .unauthorized:
                lastMessage = "Bluetooth permission denied — enable it in System Settings."
            case .unsupported:
                lastMessage = "Bluetooth LE is not supported on this Mac."
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
            guard let advName else { return }
            let upper = advName.uppercased()
            guard MelkProtocol.namePrefixes.contains(where: { upper.hasPrefix($0) }) else { return }

            if let existing = byPeripheral[peripheral.identifier] {
                existing.peripheral = peripheral
                existing.isDiscovered = true
                peripheral.delegate = self
            } else {
                let device = MelkDevice(id: peripheral.identifier, name: advName, peripheral: peripheral)
                device.isDiscovered = true
                peripheral.delegate = self
                devices.append(device)
                byPeripheral[peripheral.identifier] = device
                persist()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard let device = byPeripheral[peripheral.identifier] else { return }
            device.connectionState = .connecting
            peripheral.discoverServices([CBUUID(string: MelkProtocol.serviceUUID)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            retryOrFail(peripheral, reason: error?.localizedDescription ?? "connect failed")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            guard let device = byPeripheral[peripheral.identifier] else { return }
            device.writeCharacteristic = nil
            // If we still have work queued, try to reconnect; otherwise go idle.
            if !device.pendingFrames.isEmpty {
                device.connectionState = .disconnected
                retryOrFail(peripheral, reason: error?.localizedDescription ?? "disconnected")
            } else {
                device.connectionState = .disconnected
            }
        }
    }

    private func retryOrFail(_ peripheral: CBPeripheral, reason: String) {
        guard let device = byPeripheral[peripheral.identifier] else { return }
        let attempts = (connectRetries[device.id] ?? 0) + 1
        connectRetries[device.id] = attempts
        if attempts <= maxConnectRetries {
            device.connectionState = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(attempts)) { [weak self] in
                self?.central.connect(peripheral, options: nil)
            }
        } else {
            device.connectionState = .disconnected
            device.pendingFrames.removeAll()
            connectRetries[device.id] = 0
            lastMessage = "\(device.name): \(reason)"
        }
    }
}

// MARK: - CBPeripheralDelegate

extension MelkController: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil else {
                retryOrFail(peripheral, reason: error!.localizedDescription)
                return
            }
            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(
                    [CBUUID(string: MelkProtocol.writeCharacteristicUUID),
                     CBUUID(string: MelkProtocol.notifyCharacteristicUUID)],
                    for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let device = byPeripheral[peripheral.identifier], error == nil else {
                if error != nil { retryOrFail(peripheral, reason: error!.localizedDescription) }
                return
            }
            let writeUUID = CBUUID(string: MelkProtocol.writeCharacteristicUUID)
            if let char = service.characteristics?.first(where: { $0.uuid == writeUUID }) {
                device.writeCharacteristic = char
                beginLogin(device)
            }
        }
    }
}
