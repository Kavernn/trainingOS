import SwiftUI

// Sheet d'édition d'une séance HIIT (RPE, rounds, notes).
// Partagée : utilisée par CardioView (historique unifié). Historiquement
// vivait dans HistoriqueView — déplacée ici pour une seule implémentation.
struct EditHIITSheet: View {
    let session: HIITEntry
    let onSave: (Double, Int, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Double
    @State private var rounds: Int
    @State private var notes: String
    @State private var isSaving = false

    init(session: HIITEntry, onSave: @escaping (Double, Int, String) async -> Bool) {
        self.session = session
        self.onSave = onSave
        _rpe = State(initialValue: session.rpe ?? 7)
        _rounds = State(initialValue: session.rounds ?? 4)
        _notes = State(initialValue: session.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ROUNDS").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                            Stepper("\(rounds) rounds", value: $rounds, in: 1...20)
                                .foregroundColor(.appTextPrimary)
                                .padding(12).background(Color.appCard).clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("RPE").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.1f", rpe)).font(.appBody.weight(.black)).foregroundColor(Color.forge)
                            }
                            Slider(value: $rpe, in: 6...10, step: 0.5).tint(Color.forge)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes…", text: $notes, axis: .vertical)
                                .lineLimit(3...5).font(.appLabel.weight(.regular)).foregroundColor(.appTextPrimary)
                                .padding(12).background(Color.appCard).clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            isSaving = true
                            Task {
                                let ok = await onSave(rpe, rounds, notes)
                                if !ok { isSaving = false }
                            }
                        } label: {
                            HStack {
                                if isSaving { ProgressView().tint(Color.onAccent).scaleEffect(0.8) }
                                Text("Sauvegarder").font(.appBody.weight(.bold))
                            }
                            .foregroundColor(Color.onAccent).frame(maxWidth: .infinity).padding(14)
                            .background(Color.forge).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Modifier le HIIT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
            }
        }
    }
}
