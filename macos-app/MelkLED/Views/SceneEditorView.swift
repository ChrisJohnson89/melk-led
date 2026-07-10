//
//  SceneEditorView.swift
//  MelkLED
//
//  Sheet for creating or editing a custom scene: name, icon, and an ordered,
//  editable list of steps. Steps run top to bottom when the scene is applied.
//

import SwiftUI

struct SceneEditorView: View {
    @EnvironmentObject private var controller: MelkController
    @Environment(\.dismiss) private var dismiss

    @State var draft: LightScene
    let isNew: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Scene") {
                    TextField("Name", text: $draft.name)
                    Picker("Icon", selection: $draft.symbol) {
                        ForEach(LightScene.symbolChoices, id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if draft.steps.isEmpty {
                        Text("No steps yet. Add at least one below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($draft.steps) { $step in
                        StepRow(step: $step)
                    }
                    .onDelete { draft.steps.remove(atOffsets: $0) }
                    .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }

                    Menu {
                        ForEach(SceneStep.Op.allCases) { op in
                            Button(op.label) { draft.steps.append(SceneStep(op: op)) }
                        }
                    } label: {
                        Label("Add step", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Steps (run in order)")
                } footer: {
                    Text("Tip: start with Power on, then set the look. Drag to reorder, swipe or right-click to delete.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Preview on all lights") {
                    let scene = draft
                    controller.devices.forEach { controller.apply(scene, to: $0) }
                }
                .disabled(draft.steps.isEmpty || controller.devices.isEmpty)
                Button(isNew ? "Create Scene" : "Save") {
                    controller.saveScene(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.steps.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 480, height: 520)
    }
}

/// One editable step: op picker plus the controls that op needs.
private struct StepRow: View {
    @Binding var step: SceneStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $step.op) {
                ForEach(SceneStep.Op.allCases) { op in
                    Text(op.label).tag(op)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200, alignment: .leading)

            switch step.op {
            case .on, .off:
                EmptyView()
            case .color:
                ColorPicker("Colour", selection: Binding(
                    get: {
                        Color(.sRGB, red: Double(step.r) / 255,
                              green: Double(step.g) / 255, blue: Double(step.b) / 255)
                    },
                    set: {
                        let (r, g, b) = MelkController.rgb(from: $0)
                        step.r = r; step.g = g; step.b = b
                    }
                ), supportsOpacity: false)
            case .brightness, .effectSpeed:
                HStack {
                    Slider(value: Binding(
                        get: { Double(step.percent) },
                        set: { step.percent = Int($0) }
                    ), in: 0...100)
                    Text("\(step.percent)%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
            case .white:
                HStack {
                    Image(systemName: "snowflake").foregroundStyle(.cyan)
                    Slider(value: Binding(
                        get: { Double(step.warm) },
                        set: { step.warm = Int($0) }
                    ), in: 0...100)
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                }
            case .effect:
                Picker("Effect", selection: $step.effectID) {
                    ForEach(MelkProtocol.Effect.allCases) { effect in
                        Text(effect.label).tag(effect.rawValue)
                    }
                }
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }
}
