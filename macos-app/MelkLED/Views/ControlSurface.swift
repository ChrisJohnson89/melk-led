//
//  ControlSurface.swift
//  MelkLED
//
//  The reusable control panel: power, colour, brightness, white temperature,
//  scenes, and effects. Driven by bindings + commit closures so it serves
//  both a single device and the "All Lights" group.
//

import SwiftUI

struct ControlSurface: View {
    let title: String
    let subtitle: String
    let statusText: String?
    let statusColor: Color?

    @Binding var isOn: Bool
    @Binding var color: Color
    @Binding var brightness: Double
    @Binding var warm: Double

    var onPower: (Bool) -> Void
    var onColor: (Color) -> Void
    var onBrightness: (Int) -> Void
    var onWhite: (Int) -> Void
    var onScene: (LightScene) -> Void
    var onEffect: (Int) -> Void
    var onConnect: (() -> Void)?
    var onRename: ((String) -> Void)?

    @State private var editingName = false
    @State private var draftName = ""
    @State private var lastThrottle: [String: Date] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                powerCard
                Group {
                    sectionLabel("Colour", "paintpalette.fill")
                    colorCard
                    sectionLabel("Brightness", "sun.max.fill")
                    sliderCard(value: $brightness, key: "brightness", tint: .yellow,
                               onCommit: { pct in onBrightness(pct) },
                               label: { "\(Int(brightness))%" })
                    sectionLabel("White temperature", "thermometer.medium")
                    whiteCard
                    sectionLabel("Scenes", "sparkles")
                    SceneStrip(onScene: onScene)
                    sectionLabel("Effects", "wand.and.stars")
                    EffectMenu(onEffect: onEffect)
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(backgroundGradient)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(isOn ? 0.9 : 0.25))
                    .frame(width: 52, height: 52)
                    .shadow(color: isOn ? color.opacity(0.6) : .clear, radius: 10)
                Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                    .font(.title2)
                    .foregroundStyle(isOn ? .white : .secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title.bold())
                HStack(spacing: 6) {
                    if let statusColor {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                    }
                    Text(statusText ?? subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let onConnect {
                Button(action: onConnect) {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.bordered)
            }
            if let onRename {
                Button {
                    draftName = title
                    editingName = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .help("Rename")
                .popover(isPresented: $editingName) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rename controller").font(.headline)
                        TextField("Name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        HStack {
                            Spacer()
                            Button("Save") {
                                onRename(draftName)
                                editingName = false
                            }.keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: Cards

    private var powerCard: some View {
        card {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { newValue in isOn = newValue; onPower(newValue) }
            )) {
                Label(isOn ? "On" : "Off", systemImage: "power")
                    .font(.headline)
            }
            .toggleStyle(.switch)
            .tint(.green)
        }
    }

    private var colorCard: some View {
        card {
            HStack(spacing: 16) {
                ColorPicker("", selection: Binding(
                    get: { color },
                    set: { newValue in
                        color = newValue
                        throttled("color", minInterval: 0.12) { onColor(newValue) }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.4)
                .frame(width: 60)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap the swatch for the full picker, or pick a preset:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(ColorSwatch.presets) { swatch in
                            Button {
                                color = swatch.color
                                onColor(swatch.color)
                            } label: {
                                Circle().fill(swatch.color)
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(swatch.name)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private var whiteCard: some View {
        card {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "snowflake").foregroundStyle(.cyan)
                    Slider(value: Binding(
                        get: { warm },
                        set: { newValue in
                            warm = newValue
                            throttled("white", minInterval: 0.12) { onWhite(Int(newValue)) }
                        }
                    ), in: 0...100, onEditingChanged: { editing in
                        if !editing { onWhite(Int(warm)) }
                    })
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                }
                Text(warm >= 66 ? "Warm" : warm <= 33 ? "Cool" : "Neutral")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sliderCard(value: Binding<Double>, key: String, tint: Color,
                            onCommit: @escaping (Int) -> Void,
                            label: @escaping () -> String) -> some View {
        card {
            HStack(spacing: 14) {
                Slider(value: Binding(
                    get: { value.wrappedValue },
                    set: { newValue in
                        value.wrappedValue = newValue
                        throttled(key, minInterval: 0.12) { onCommit(Int(newValue)) }
                    }
                ), in: 0...100) { editing in
                    if !editing { onCommit(Int(value.wrappedValue)) }
                }
                .tint(tint)
                Text(label())
                    .font(.body.monospacedDigit())
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.5)))
    }

    private var backgroundGradient: some View {
        LinearGradient(colors: [color.opacity(isOn ? 0.10 : 0.02), .clear],
                       startPoint: .top, endPoint: .center)
        .ignoresSafeArea()
    }

    /// Rate-limit rapid slider/picker drags so we don't flood the BLE queue.
    private func throttled(_ key: String, minInterval: TimeInterval, _ action: () -> Void) {
        let now = Date()
        if let last = lastThrottle[key], now.timeIntervalSince(last) < minInterval { return }
        lastThrottle[key] = now
        action()
    }
}

// MARK: - Colour presets

struct ColorSwatch: Identifiable {
    let name: String
    let color: Color
    var id: String { name }

    static let presets: [ColorSwatch] = [
        .init(name: "Red", color: Color(red: 1, green: 0, blue: 0)),
        .init(name: "Orange", color: Color(red: 1, green: 0.39, blue: 0)),
        .init(name: "Yellow", color: Color(red: 1, green: 1, blue: 0)),
        .init(name: "Green", color: Color(red: 0, green: 1, blue: 0)),
        .init(name: "Cyan", color: Color(red: 0, green: 1, blue: 1)),
        .init(name: "Blue", color: Color(red: 0, green: 0, blue: 1)),
        .init(name: "Purple", color: Color(red: 0.63, green: 0, blue: 1)),
        .init(name: "Pink", color: Color(red: 1, green: 0.2, blue: 0.59)),
    ]
}

// MARK: - Scene strip

struct SceneStrip: View {
    var onScene: (LightScene) -> Void
    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Scenes.all) { scene in
                Button {
                    onScene(scene)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: scene.symbol)
                            .font(.title3)
                        Text(scene.label)
                            .font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(scene.tint.opacity(0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(scene.tint.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Effect menu

struct EffectMenu: View {
    var onEffect: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            ForEach(MelkProtocol.Effect.allCases) { effect in
                Button {
                    onEffect(effect.rawValue)
                } label: {
                    Text(effect.label)
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.background.secondary))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
    }
}
