//
//  ContentView.swift
//  MelkLED
//
//  Top-level layout: a sidebar of groups and controllers, and a detail pane
//  with the full control surface for the selection.
//

import SwiftUI

enum Selection: Hashable {
    case all
    case group(UUID)
    case device(UUID)
}

struct ContentView: View {
    @EnvironmentObject private var controller: MelkController
    @State private var selection: Selection? = .all
    @State private var editingGroup: LightGroup?
    @State private var editingGroupIsNew = false

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
                    controller.isScanning ? controller.stopScan() : controller.startScan()
                } label: {
                    Label(controller.isScanning ? "Scanning…" : "Scan",
                          systemImage: controller.isScanning ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                }
                .disabled(controller.bluetoothState != .poweredOn)
            }
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorView(draft: group, isNew: editingGroupIsNew)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                AllLightsRow()
                    .tag(Selection.all)
            }

            Section("Groups") {
                ForEach(controller.groups) { group in
                    GroupRow(group: group)
                        .tag(Selection.group(group.id))
                        .contextMenu {
                            Button("Edit Group…") {
                                editingGroupIsNew = false
                                editingGroup = group
                            }
                            Button("Delete Group", role: .destructive) {
                                if selection == .group(group.id) { selection = .all }
                                controller.deleteGroup(group)
                            }
                        }
                }
                Button {
                    editingGroupIsNew = true
                    editingGroup = LightGroup(name: "")
                } label: {
                    Label("New Group…", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                .fill(controller.bluetoothState == .poweredOn ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(controller.lastMessage.isEmpty ? "Ready" : controller.lastMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
            MultiDeviceDetailView(
                title: "All Lights",
                subtitle: "\(controller.devices.count) controllers",
                devices: controller.devices,
                onEdit: nil
            )
        case .group(let id):
            if let group = controller.groups.first(where: { $0.id == id }) {
                MultiDeviceDetailView(
                    title: group.name,
                    subtitle: "\(group.memberIDs.count) controllers",
                    devices: controller.members(of: group),
                    onEdit: {
                        editingGroupIsNew = false
                        editingGroup = group
                    }
                )
                .id(group.id)
            } else {
                ContentUnavailableView("Select a group", systemImage: "lightbulb.2")
            }
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

struct GroupRow: View {
    @EnvironmentObject private var controller: MelkController
    let group: LightGroup

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).font(.body)
                Text(controller.members(of: group).map(\.name).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "rectangle.3.group.fill")
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
