import SwiftUI

// MARK: - Add Cardio Sheet
struct AddCardioSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cardioType  = "Course"
    @State private var durationMin = ""
    @State private var distanceKm  = ""
    @State private var rpe: Double = 7
    @State private var notes       = ""
    @State private var isLogging      = false
    @State private var confirmDiscard = false
    @State private var logError: String? = nil

    private var hasUnsavedData: Bool { !durationMin.isEmpty || !notes.isEmpty || rpe != 7 }

    private let types = ["Course", "Vélo", "Natation", "Elliptique", "Rameur", "Marche", "Autre"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Type
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(types, id: \.self) { t in
                                        Button(t) { cardioType = t }
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(cardioType == t ? Color.blue.opacity(0.2) : Color.appSurfaceInset)
                                            .foregroundColor(cardioType == t ? .blue : .gray)
                                            .cornerRadius(8)
                                            .font(.appLabel)
                                    }
                                }
                            }
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Durée + Distance
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DURÉE (MIN)").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                                TextField("30", text: $durationMin).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color.appSurfaceInset).cornerRadius(10)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DISTANCE (\(UnitSettings.shared.distanceUnit))").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $distanceKm).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color.appSurfaceInset).cornerRadius(10)
                            }
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // RPE
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 18, weight: .black)).foregroundColor(rpeColor(rpe))
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(rpeColor(rpe))
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes...", text: $notes, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.white).tint(.blue)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color.appSurfaceInset).cornerRadius(10)
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        Button(action: submit) {
                            HStack {
                                if isLogging { ProgressView().tint(.white) }
                                else { Image(systemName: "checkmark.circle.fill") }
                                Text("Enregistrer Cardio").font(.appBody.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(durationMin.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isLogging || durationMin.isEmpty)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Cardio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if hasUnsavedData { confirmDiscard = true } else { dismiss() }
                    }
                    .foregroundColor(.orange)
                }
            }
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Toutes tes notes et configurations seront perdues.")
            }
            .alert("Erreur", isPresented: Binding(get: { logError != nil }, set: { if !$0 { logError = nil } })) {
                Button("OK", role: .cancel) { logError = nil }
            } message: { Text(logError ?? "") }
        }
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }

    private func submit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isLogging = true
        Task {
            do {
                try await APIService.shared.logCardio(
                    type: cardioType,
                    durationMin: Double(durationMin.replacingOccurrences(of: ",", with: ".")),
                    distanceKm: Double(distanceKm.replacingOccurrences(of: ",", with: ".")),
                    avgPace: nil, avgHr: nil, cadence: nil, calories: nil,
                    rpe: rpe, notes: notes
                )
                await MainActor.run { isLogging = false; onDone(); dismiss() }
            } catch {
                await MainActor.run { isLogging = false; logError = error.localizedDescription }
            }
        }
    }
}
