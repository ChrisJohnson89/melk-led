//
//  DetailViews.swift
//  MelkLED
//
//  Thin wrappers that adapt ControlSurface to either a single device
//  (fully reactive via @ObservedObject) or the "All Lights" group.
//

import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var controller: MelkController
    @ObservedObject var device: MelkDevice

    var body: some View {
        ControlSurface(
            title: device.name,
            subtitle: device.shortID,
            statusText: device.connectionState.label,
            statusColor: device.connectionState.color,
            isOn: $device.isOn,
            color: $device.color,
            brightness: $device.brightness,
            warm: $device.warmPercent,
            onPower: { controller.setOn(device, $0) },
            onColor: { controller.setColor(device, $0) },
            onBrightness: { controller.setBrightness(device, percent: $0) },
            onWhite: { controller.setWhite(device, warmPercent: $0) },
            onScene: { controller.apply($0, to: device) },
            onEffect: { controller.setEffect(device, id: $0) },
            onConnect: device.isReady ? nil : { controller.connect(device) },
            onRename: { controller.rename(device, to: $0) }
        )
        .id(device.id)
    }
}

struct AllDetailView: View {
    @EnvironmentObject private var controller: MelkController
    @State private var isOn = false
    @State private var color: Color = .white
    @State private var brightness: Double = 100
    @State private var warm: Double = 50

    var body: some View {
        ControlSurface(
            title: "All Lights",
            subtitle: "\(controller.devices.count) controllers",
            statusText: "\(controller.devices.count) controllers · commands fan out to every device",
            statusColor: nil,
            isOn: $isOn,
            color: $color,
            brightness: $brightness,
            warm: $warm,
            onPower: { on in controller.devices.forEach { controller.setOn($0, on) } },
            onColor: { c in controller.devices.forEach { controller.setColor($0, c) } },
            onBrightness: { p in controller.devices.forEach { controller.setBrightness($0, percent: p) } },
            onWhite: { w in controller.devices.forEach { controller.setWhite($0, warmPercent: w) } },
            onScene: { s in controller.devices.forEach { controller.apply(s, to: $0) } },
            onEffect: { id in controller.devices.forEach { controller.setEffect($0, id: id) } },
            onConnect: { controller.devices.forEach { controller.connect($0) } },
            onRename: nil
        )
    }
}
