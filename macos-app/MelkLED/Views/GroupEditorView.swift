//
//  GroupEditorView.swift
//  MelkLED
//
//  Sheet for creating or editing a group: name plus a checklist of member
//  controllers. Reassign a light between rooms by ticking it in one group
//  and unticking it in another.
//

import SwiftUI

struct GroupEditorView: View {
    @EnvironmentObject private var controller: MelkController
    @Environment(\.dismiss) private var dismiss

    @State var draft: LightGroup
    let isNew: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Group") {
                    TextField("Name (e.g. Living Room)", text: $draft.name)
                }
                Section("Members") {
                    if controller.devices.isEmpty {
                        Text("No controllers known yet. Run a scan first.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.devices) { device in
                        Toggle(isOn: Binding(
                            get: { draft.memberIDs.contains(device.id) },
                            set: { included in
                                if included {
                                    if !draft.memberIDs.contains(device.id) {
                                        draft.memberIDs.append(device.id)
                                    }
                                } else {
                                    draft.memberIDs.removeAll { $0 == device.id }
                                }
                            }
                        )) {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text(device.shortID)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isNew ? "Create Group" : "Save") {
                    controller.saveGroup(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.memberIDs.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 420, height: 400)
    }
}
