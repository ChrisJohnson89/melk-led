//
//  MelkLEDApp.swift
//  MelkLED
//
//  A polished, standalone macOS app for controlling MELK-OA10 BLE LED strips
//  locally — no cloud, no official app. Declares its own Bluetooth usage
//  string in Info.plist, so it owns its TCC identity and sidesteps all the
//  Homebrew-Python / py2app packaging friction of the reference CLI.
//

import SwiftUI

@main
struct MelkLEDApp: App {
    @StateObject private var controller: MelkController
    @StateObject private var server: ControlServer

    init() {
        // The control server needs the controller; build both here so the
        // Hermes/CLI HTTP endpoint shares the app's single BLE owner.
        let controller = MelkController()
        _controller = StateObject(wrappedValue: controller)
        _server = StateObject(wrappedValue: ControlServer(controller: controller))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .environmentObject(server)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear { server.start() }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New Window"
        }
    }
}
