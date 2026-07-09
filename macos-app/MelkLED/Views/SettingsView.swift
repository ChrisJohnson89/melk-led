//
//  SettingsView.swift
//  MelkLED
//
//  The app's Settings window (⌘,). One place to turn the "flash on approval"
//  integration on or off (it writes the Claude Code hook for you), tune the
//  flash appearance, and toggle the local control endpoint.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: MelkController
    @EnvironmentObject private var server: ControlServer

    @AppStorage(AlertSettings.colorRKey) private var colorR = AlertSettings.defaultColor.r
    @AppStorage(AlertSettings.colorGKey) private var colorG = AlertSettings.defaultColor.g
    @AppStorage(AlertSettings.colorBKey) private var colorB = AlertSettings.defaultColor.b
    @AppStorage(AlertSettings.blinksKey) private var blinks = AlertSettings.defaultBlinks
    @AppStorage(AlertSettings.targetKey) private var targetID = ""

    @State private var hookInstalled = false
    @State private var includeIdle = false
    @State private var hookError: String?

    private var hookManager: ClaudeHookManager { ClaudeHookManager(port: server.port) }

    private var alertColor: Binding<Color> {
        Binding(
            get: { Color(.sRGB, red: Double(colorR) / 255, green: Double(colorG) / 255, blue: Double(colorB) / 255) },
            set: {
                let (r, g, b) = MelkController.rgb(from: $0)
                colorR = r; colorG = g; colorB = b
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Flash the lights when Claude Code needs approval", isOn: Binding(
                    get: { hookInstalled },
                    set: { setHook(installed: $0) }
                ))
                Toggle("Also flash when Claude is waiting for my next prompt", isOn: Binding(
                    get: { includeIdle },
                    set: { includeIdle = $0; if hookInstalled { setHook(installed: true) } }
                ))
                .disabled(!hookInstalled)
                if let hookError {
                    Label(hookError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                }
            } header: {
                Text("Approval alerts")
            } footer: {
                Text("Adds a hook to ~/.claude/settings.json, so it works in any terminal. The MelkLED app must be running. After turning this on, open /hooks in Claude Code (or restart it) once so it loads the hook.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Flash appearance") {
                ColorPicker("Alert colour", selection: alertColor, supportsOpacity: false)
                Stepper("Blinks: \(blinks)", value: $blinks, in: 1...20)
                Picker("Flash which lights", selection: $targetID) {
                    Text("All lights").tag("")
                    ForEach(controller.devices) { device in
                        Text(device.name).tag(device.id.uuidString)
                    }
                }
                Button("Test alert") { controller.flashAlert() }
                    .disabled(controller.devices.isEmpty || controller.isFlashing)
            }

            Section("Control endpoint") {
                Toggle("Local HTTP endpoint (Hermes & hooks)", isOn: Binding(
                    get: { server.isRunning },
                    set: { $0 ? server.start() : server.stop() }
                ))
                LabeledContent("Address", value: "http://127.0.0.1:\(server.port)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshHookStatus)
    }

    private func refreshHookStatus() {
        let status = hookManager.status()
        hookInstalled = status.installed
        includeIdle = status.includesIdle
    }

    private func setHook(installed: Bool) {
        do {
            if installed {
                try hookManager.install(includeIdle: includeIdle)
            } else {
                try hookManager.uninstall()
            }
            hookError = nil
            refreshHookStatus()
        } catch {
            hookError = "Couldn't update ~/.claude/settings.json: \(error.localizedDescription)"
        }
    }
}
