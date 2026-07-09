//
//  ContentView.swift
//  MelkLED
//
//  Top-level layout: a sidebar of controllers (plus an "All Lights" group)
//  and a detail pane with the full control surface for the selection.
//

import SwiftUI

enum Selection: Hashable {
    case all
    case device(UUID)
}

struct ContentView: View {
    @EnvironmentObject private var controller: MelkController
    @EnvironmentObject private var server: ControlServer
    @State private var selection: Selection? = .all

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    flashSelection()
                } label: {
                    Label("Test Alert", systemImage: "bell.badge.fill")
                }
                .help("Flash the lights — preview the approval alert")
                .disabled(controller.devices.isEmpty || controller.isFlashing)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    controller.isScanning ? controller.stopScan() : controller.startScan()
                } label: {
                    Label(controller.isScanning ? "Scanning…" : "Scan",
                          systemImage: controller.isScanning ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                }
                .disabled(controller.bluetoothState != .poweredOn)
            }
        }
    }

    private func flashSelection() {
        switch selection {
        case .device(let id):
            if let device = controller.devices.first(where: { $0.id == id }) {
                controller.flash(targets: [device])
            }
        default:
            controller.flash(targets: controller.devices)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                AllLightsRow()
                    .tag(Selection.all)
            }
            Section("Controllers") {
                ForEach(controller.devices) { device in
                    DeviceRow(device: device)
                        .tag(Selection.device(device.id))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { statusFooter }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(server.isRunning ? "Hermes endpoint on :\(server.port)" : "Endpoint off")
                    .font(.caption2)
                if !controller.lastMessage.isEmpty {
                    Text(controller.lastMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .all, .none:
            AllDetailView()
        case .device(let id):
            if let device = controller.devices.first(where: { $0.id == id }) {
                DeviceDetailView(device: device)
            } else {
                ContentUnavailableView("Select a controller", systemImage: "lightbulb")
            }
        }
    }
}

// MARK: - Sidebar rows

struct AllLightsRow: View {
    @EnvironmentObject private var controller: MelkController

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("All Lights").font(.body)
                Text("\(controller.devices.count) controllers")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lightbulb.2.fill")
                .foregroundStyle(.tint)
        }
    }
}

struct DeviceRow: View {
    @ObservedObject var device: MelkDevice

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.body)
                Text(device.connectionState.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: device.isOn ? "lightbulb.fill" : "lightbulb")
                .foregroundStyle(device.connectionState.color)
        }
    }
}
