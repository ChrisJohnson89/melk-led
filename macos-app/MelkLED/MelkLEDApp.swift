//
//  MelkLEDApp.swift
//  MelkLED
//
//  A polished, standalone macOS app for controlling MELK-OA10 BLE LED strips
//  locally: no cloud, no official app. Declares its own Bluetooth usage
//  string in Info.plist, so it owns its TCC identity.
//

import SwiftUI

@main
struct MelkLEDApp: App {
    @StateObject private var controller = MelkController()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New Window"
        }
    }
}
