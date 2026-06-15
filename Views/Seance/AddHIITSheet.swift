import SwiftUI

// MARK: - HIIT Template
struct HIITTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var sessionType: String
    var rounds: Int
    var workTime: Int
    var restTime: Int
}

// MARK: - Add HIIT Sheet
struct AddHIITSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sessionType = "HIIT"
    @State private var rounds      = "10"
    @State private var workTime    = "20"
    @State private var restTime    = "10"
    @State private var rpe: Double = 8
    @State private var notes       = ""
    @State private var isLogging   = false
    @State private var showSavePrompt = false
    @State private var templateName   = ""
    @State private var logError: String? = nil

    @AppStorage("hiit_templates") private var templatesData: String = "[]"

    private var templates: [HIITTemplate] {
        (try? JSONDecoder().decode([HIITTemplate].self, from: Data(templatesData.utf8))) ?? []
    }

    private var isHIITValid: Bool {
        let r = Int(rounds) ?? 0
        let w = Int(workTime) ?? 0
        let rest = Int(restTime) ?? -1
        return (1...30).contains(r) && (5...300).contains(w) && (0...300).contains(rest)
    }

    private func saveTemplates(_ list: [HIITTemplate]) {
        if let d = try? JSONEncoder().encode(list) {
            templatesData = String(data: d, encoding: .utf8) ?? "[]"
        }
    }

    private func applyTemplate(_ t: HIITTemplate) {
        sessionType = t.sessionType
        rounds      = "\(t.rounds)"
        workTime    = "\(t.workTime)"
        restTime    = "\(t.restTime)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Saved templates
                        if !templates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TEMPLATES SAUVEGARDÉS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(templates) { t in
                                            HStack(spacing: 4) {
                                                Button(t.name) { applyTemplate(t) }
                                                    .font(.appLabel.weight(.semibold))
                                                    .foregroundColor(.statusRed)
                                                Button {
                                                    saveTemplates(templates.filter { $0.id != t.id })
                                                } label: {
                                                    Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.gray)
                                                }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color.appCard).cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(14)
                        }

                        // Session type
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TYPE DE SESSION").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("HIIT", text: $sessionType)
                                .font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                                .padding(12).background(Color.appSurfaceInset).cornerRadius(10)
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Rounds / Work / Rest
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("RONDES").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $rounds).keyboardType(.numberPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.appTextPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(10).background(Color.appSurfaceInset).cornerRadius(10)
                                Text("Entre 1 et 30 rounds")
                                    .font(.appCaption).foregroundColor(.gray.opacity(0.6))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TRAVAIL (s)").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $workTime).keyboardType(.numberPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.appTextPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(10).background(Color.appSurfaceInset).cornerRadius(10)
                                Text("Entre 5 et 300s")
                                    .font(.appCaption).foregroundColor(.gray.opacity(0.6))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REPOS (s)").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $restTime).keyboardType(.numberPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.appTextPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(10).background(Color.appSurfaceInset).cornerRadius(10)
                                Text("Entre 0 et 300s")
                                    .font(.appCaption).foregroundColor(.gray.opacity(0.6))
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
                                .font(.system(size: 14)).foregroundColor(.appTextPrimary).tint(.statusRed)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color.appSurfaceInset).cornerRadius(10)
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Save template button
                        Button {
                            templateName = sessionType.isEmpty ? "HIIT" : sessionType
                            showSavePrompt = true
                        } label: {
                            Label("Sauvegarder comme template", systemImage: "bookmark")
                                .font(.appLabel)
                                .foregroundColor(Color.forge)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color.appCard).cornerRadius(10)
                        }

                        PrimaryButton(
                            title: "Enregistrer HIIT",
                            icon: "bolt.fill",
                            style: .destructive,
                            isLoading: isLogging,
                            isDisabled: !isHIITValid,
                            action: submit
                        )
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("HIIT").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
            }
            .alert("Nom du template", isPresented: $showSavePrompt) {
                TextField("Ex: Tabata 20/10", text: $templateName)
                Button("Sauvegarder") {
                    guard !templateName.isEmpty else { return }
                    let t = HIITTemplate(
                        name: templateName,
                        sessionType: sessionType.isEmpty ? "HIIT" : sessionType,
                        rounds:   Int(rounds)   ?? 10,
                        workTime: Int(workTime) ?? 20,
                        restTime: Int(restTime) ?? 10
                    )
                    saveTemplates(templates + [t])
                }
                Button("Annuler", role: .cancel) {}
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
                try await APIService.shared.logHIIT(
                    sessionType: sessionType.isEmpty ? "HIIT" : sessionType,
                    rounds:     Int(rounds)   ?? 10,
                    workTime:   Int(workTime) ?? 20,
                    restTime:   Int(restTime) ?? 10,
                    rpe:        rpe,
                    notes:      notes,
                    secondSession: true
                )
                await MainActor.run { isLogging = false; onDone(); dismiss() }
            } catch {
                await MainActor.run { isLogging = false; logError = error.localizedDescription }
            }
        }
    }
}
