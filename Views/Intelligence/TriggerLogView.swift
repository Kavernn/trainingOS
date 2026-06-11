import SwiftUI

// MARK: - Trigger History

struct TriggerHistoryView: View {
    @ObservedObject var vm: WarRoomViewModel
    @Binding var showSheet: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {
                showSheet = true
            } label: {
                Label("Logger une tentation", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.forge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.forge.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .padding(16)
            }

            if vm.triggers.isEmpty {
                Spacer()
                Text("Aucun journal")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
                Spacer()
            } else {
                List(vm.triggers) { t in
                    TriggerRow(trigger: t)
                        .listRowBackground(Color.appCard)
                        .listRowSeparatorTint(Color.appSeparator)
                }
                .listStyle(.plain)
                .background(Color.appBg)
            }
        }
        .background(Color.appBg)
    }
}

private struct TriggerRow: View {
    let trigger: WarRoomTrigger

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                ForEach(0..<trigger.intensity, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(intensityColor)
                        .frame(width: 4, height: 6)
                }
            }
            .frame(width: 14, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(trigger.context.label)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(shortDate(trigger.date))
                        .font(.appCaption)
                        .foregroundStyle(Color.secondary)
                }

                if let note = trigger.contextNote, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if trigger.yielded {
                        Label("Cédé", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    } else {
                        Label("Tenu", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.forge.opacity(0.8))
                    }
                    if let held = trigger.heldWith, !held.isEmpty {
                        Text("via \(held.joined(separator: ", "))")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var intensityColor: Color {
        trigger.intensity >= 4 ? Color.forge : trigger.intensity >= 3 ? Color.forge.opacity(0.7) : Color.secondary.opacity(0.5)
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_CA")
        return f.string(from: d)
    }
}

// MARK: - Log Sheet

struct TriggerLogView: View {
    @ObservedObject var vm: WarRoomViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var context:     TriggerContext = .stress
    @State private var intensity:   Int    = 3
    @State private var yielded:     Bool   = false
    @State private var contextNote: String = ""
    @State private var saving       = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Contexte") {
                    Picker("Type", selection: $context) {
                        ForEach(TriggerContext.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Note (optionnel)", text: $contextNote)
                        .font(.system(size: 14))
                }
                .listRowBackground(Color.appCard)

                Section("Intensité  \(intensity)/5") {
                    Slider(value: Binding(
                        get: { Double(intensity) },
                        set: { intensity = Int($0) }
                    ), in: 1...5, step: 1)
                    .tint(intensity >= 4 ? Color.forge : Color.forge)
                }
                .listRowBackground(Color.appCard)

                Section {
                    Toggle("J'ai cédé", isOn: $yielded)
                        .tint(Color.forge)
                }
                .listRowBackground(Color.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBg)
            .navigationTitle("Journaliser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(Color.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .font(.appBody.weight(.semibold))
                        .foregroundStyle(Color.forge)
                        .disabled(saving)
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            _ = try? await APIService.shared.logTrigger(
                context:     context,
                intensity:   intensity,
                yielded:     yielded,
                contextNote: contextNote.isEmpty ? nil : contextNote
            )
            await vm.loadTriggers()
            dismiss()
        }
    }
}

