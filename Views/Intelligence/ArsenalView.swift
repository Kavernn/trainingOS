import SwiftUI

struct ArsenalView: View {
    @ObservedObject var vm: WarRoomViewModel
    @Binding var showAdd: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                if vm.arsenal.isEmpty {
                    emptyState
                } else {
                    let grouped = Dictionary(grouping: vm.arsenal, by: \.category)
                    ForEach(ArsenalCategory.allCases, id: \.self) { cat in
                        if let items = grouped[cat], !items.isEmpty {
                            categorySection(cat, items: items)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("TON ARSENAL")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forge)
                    .tracking(3)
                Text("Déploie une arme dès la 1ère seconde.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.forge)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 32))
                .foregroundStyle(Color.secondary)
            Text("Arsenal vide — ajoute tes armes.")
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary)
            Button("Ajouter") { showAdd = true }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.forge)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func categorySection(_ cat: ArsenalCategory, items: [WarRoomArsenalItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(cat.label.uppercased(), systemImage: cat.icon)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(2)

            ForEach(items) { item in
                arsenalRow(item)
            }
        }
    }

    private func arsenalRow(_ item: WarRoomArsenalItem) -> some View {
        HStack(spacing: 12) {
            Text(item.label)
                .font(.appBody.weight(.medium))
                .foregroundStyle(Color.primary)

            Spacer()

            if item.useCount > 0 {
                Text("×\(item.useCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }

            Button {
                Task { await vm.deployWeapon(item) }
            } label: {
                Text("DÉPLOYER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forge)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.forge.opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(role: .destructive) {
                Task { await vm.deleteWeapon(item) }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Arsenal Sheet

struct AddArsenalView: View {
    @ObservedObject var vm: WarRoomViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var label:    String          = ""
    @State private var category: ArsenalCategory = .physical
    @State private var saving    = false
    @State private var addError: String?
    @State private var isQueued  = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Arme") {
                    TextField("Ex : Appeler Mathieu", text: $label)
                }
                .listRowBackground(Color.appCard)

                Section("Catégorie") {
                    Picker("Catégorie", selection: $category) {
                        ForEach(ArsenalCategory.allCases, id: \.self) { c in
                            Label(c.label, systemImage: c.icon).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(Color.appCard)

                if isQueued {
                    Text("Ajout en attente — sera envoyé à la reconnexion")
                        .font(.appCaption)
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.appCard)
                }
                if let msg = addError {
                    Text(msg)
                        .font(.appCaption)
                        .foregroundColor(.appDanger)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.appCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBg)
            .navigationTitle("Nouvelle arme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(Color.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }
                        .font(.appBody.weight(.semibold))
                        .foregroundStyle(Color.forge)
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() {
        saving = true
        addError = nil
        isQueued = false
        Task {
            defer { saving = false }
            do {
                _ = try await APIService.shared.addArsenalItem(
                    label: label.trimmingCharacters(in: .whitespaces),
                    category: category
                )
                await vm.loadArsenal()
                dismiss()
            } catch APIError.queuedOffline {
                isQueued = true
                // Sheet reste ouverte : l'utilisateur voit "en attente" ; au rejeu
                // la mutation sera visible dans l'arsenal au prochain loadArsenal.
                // Pour ne pas bloquer le flow, on dismiss après notification brève.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await vm.loadArsenal()
                dismiss()
            } catch APIError.serverError(_, let msg) {
                addError = msg.isEmpty ? "Erreur serveur" : msg
            } catch {
                addError = "Erreur réseau — réessaie"
            }
        }
    }
}
