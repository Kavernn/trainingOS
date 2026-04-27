import SwiftUI

struct ExerciseSwapSheet: View {
    let originalName: String
    let originalType: String
    let originalMuscles: [String]
    let originalPattern: String
    let inventory: [String]
    let inventoryTypes: [String: String]
    let inventoryMuscles: [String: [String]]
    let inventoryPatterns: [String: String]
    let onSwap: (String) -> Void
    let onCreateVariant: () -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var suggestions: [String] {
        let muscles = Set(originalMuscles.map { $0.lowercased() })
        return inventory
            .filter { $0 != originalName }
            .filter { name in
                let m = Set((inventoryMuscles[name] ?? []).map { $0.lowercased() })
                let p = inventoryPatterns[name] ?? ""
                return !m.isDisjoint(with: muscles) || p == originalPattern
            }
            .sorted()
    }

    private var allExercises: [String] {
        inventory.filter { $0 != originalName }.sorted()
    }

    private var filteredSuggestions: [String] {
        searchText.isEmpty ? suggestions : suggestions.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredAll: [String] {
        let q = searchText.lowercased()
        let base = searchText.isEmpty ? allExercises : allExercises.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
        let suggestionSet = Set(filteredSuggestions.map { $0.lowercased() })
        return base.filter { !suggestionSet.contains($0.lowercased()) }
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "barbell":    return "Barre"
        case "ez-bar":     return "EZ-Bar"
        case "dumbbell":   return "Haltères"
        case "bodyweight": return "Poids corps"
        case "cable":      return "Câble"
        default:           return "Machine"
        }
    }

    private func conversionNote(for name: String) -> String? {
        let repType = inventoryTypes[name] ?? "machine"
        let conv = EquipmentConversion(from: originalType, to: repType)
        if conv.requiresWarning { return "Charges non comparables" }
        switch conv {
        case .dumbbellToBarbell: return "Charge × 2"
        case .barbellToDumbbell: return "Charge ÷ 2"
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0E0E1A").ignoresSafeArea()
                VStack(spacing: 0) {
                    // Search
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Rechercher un exercice…", text: $searchText)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                    }
                    .padding(12)
                    .background(Color(hex: "1A1A2E"))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    List {
                        if !filteredSuggestions.isEmpty {
                            Section {
                                ForEach(filteredSuggestions, id: \.self) { name in
                                    row(name: name)
                                }
                            } header: {
                                Text("Suggestions")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(.orange)
                            }
                        }

                        if !filteredAll.isEmpty {
                            Section {
                                ForEach(filteredAll, id: \.self) { name in
                                    row(name: name)
                                }
                            } header: {
                                Text("Tous les exercices")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(.gray)
                            }
                        }

                        Section {
                            Button {
                                dismiss()
                                onCreateVariant()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Créer une variante de \"\(originalName)\"")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Changer l'exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundColor(.gray)
                }
            }
        }
    }

    @ViewBuilder
    private func row(name: String) -> some View {
        let type = inventoryTypes[name] ?? "machine"
        let note = conversionNote(for: name)
        Button {
            dismiss()
            onSwap(name)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if let note {
                        HStack(spacing: 4) {
                            Image(systemName: note.contains("comparables") ? "exclamationmark.triangle" : "arrow.left.arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(note.contains("comparables") ? .yellow : .gray.opacity(0.6))
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundColor(note.contains("comparables") ? .yellow : .gray.opacity(0.6))
                        }
                    }
                }
                Spacer()
                Text(typeLabel(type))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(hex: "14142A"))
    }
}
