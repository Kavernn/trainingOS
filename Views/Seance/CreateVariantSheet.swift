import SwiftUI

struct CreateVariantSheet: View {
    let originalName: String
    let originalMuscles: [String]
    let originalPattern: String
    let originalScheme: String
    let originalCategory: String
    let onCreated: (String) -> Void   // called with the new exercise name after catalogue save

    @State private var variantName: String
    @State private var selectedType: String
    @State private var showPreview = false
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    private let availableTypes = ["barbell", "dumbbell", "machine", "cable", "bodyweight", "ez-bar"]
    private func typeLabel(_ t: String) -> String {
        switch t {
        case "barbell":    return "Barre"
        case "ez-bar":     return "EZ-Bar"
        case "dumbbell":   return "Haltères"
        case "bodyweight": return "Poids corps"
        case "cable":      return "Câble"
        default:           return "Machine"
        }
    }

    init(originalName: String, originalMuscles: [String], originalPattern: String,
         originalScheme: String, originalCategory: String, onCreated: @escaping (String) -> Void) {
        self.originalName     = originalName
        self.originalMuscles  = originalMuscles
        self.originalPattern  = originalPattern
        self.originalScheme   = originalScheme
        self.originalCategory = originalCategory
        self.onCreated        = onCreated
        // Default variant name: prefix first token of type
        _variantName  = State(initialValue: originalName)
        _selectedType = State(initialValue: "barbell")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0E0E1A").ignoresSafeArea()
                if showPreview {
                    previewView
                } else {
                    formView
                }
            }
            .navigationTitle(showPreview ? "Confirmer la variante" : "Nouvelle variante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if showPreview {
                        Button("Modifier") { showPreview = false }
                            .foregroundColor(.gray)
                    } else {
                        Button("Annuler") { dismiss() }
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Name field
                fieldBlock(label: "NOM") {
                    TextField("Nom de l'exercice", text: $variantName)
                        .foregroundColor(.white)
                        .font(.system(size: 15))
                }

                // Type picker
                fieldBlock(label: "TYPE D'ÉQUIPEMENT") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableTypes, id: \.self) { t in
                                Button {
                                    selectedType = t
                                } label: {
                                    Text(typeLabel(t))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedType == t ? .black : .white)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(selectedType == t ? Color.orange : Color.white.opacity(0.07))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Read-only fields
                fieldBlock(label: "MUSCLES CIBLÉS") {
                    Text(originalMuscles.isEmpty ? "—" : originalMuscles.joined(separator: ", "))
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                fieldBlock(label: "MOUVEMENT") {
                    Text(originalPattern.isEmpty ? "—" : originalPattern)
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                fieldBlock(label: "SCHÈME") {
                    Text(originalScheme.isEmpty ? "—" : originalScheme)
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }

                // Prévisualiser
                Button {
                    withAnimation { showPreview = true }
                } label: {
                    Text("Prévisualiser")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(variantName.isEmpty ? Color.gray : Color.orange)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .disabled(variantName.isEmpty)
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    // MARK: - Preview / Confirmation

    private var previewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Fiche
                    VStack(alignment: .leading, spacing: 14) {
                        Text(variantName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)

                        Divider().background(Color.white.opacity(0.08))

                        infoRow(icon: "dumbbell.fill",     label: "Équipement", value: typeLabel(selectedType))
                        infoRow(icon: "figure.strengthtraining.traditional", label: "Muscles",
                                value: originalMuscles.isEmpty ? "—" : originalMuscles.joined(separator: ", "))
                        infoRow(icon: "arrow.up.right",    label: "Mouvement",  value: originalPattern.isEmpty ? "—" : originalPattern)
                        infoRow(icon: "list.number",       label: "Schème",     value: originalScheme.isEmpty ? "—" : originalScheme)
                        infoRow(icon: "tag",               label: "Catégorie",  value: originalCategory.isEmpty ? "—" : originalCategory)
                    }
                    .padding(20)
                    .background(Color(hex: "14142A"))
                    .cornerRadius(16)

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }

            // Confirm button
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.85)
                    }
                    Text(isSaving ? "Enregistrement…" : "Confirmer et ajouter au catalogue")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(20)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldBlock<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundColor(.gray)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "14142A"))
                .cornerRadius(10)
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.orange.opacity(0.7))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            Spacer()
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await APIService.shared.saveExercise(
                name: variantName,
                type: selectedType,
                muscles: originalMuscles,
                pattern: originalPattern,
                scheme: originalScheme,
                category: originalCategory
            )
            await MainActor.run {
                isSaving = false
                onCreated(variantName)
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = "Erreur : \(error.localizedDescription)"
            }
        }
    }
}
