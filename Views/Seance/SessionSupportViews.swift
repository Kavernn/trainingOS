import SwiftUI

// MARK: - Session Picker Sheet
struct SessionPickerSheet: View {
    let currentSession: String
    let availableSessions: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text("Changer de séance")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 20)
                        Text("Séance active aujourd'hui")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 16)

                    VStack(spacing: 0) {
                        ForEach(availableSessions, id: \.self) { session in
                            let isActive = session == currentSession
                            Button {
                                if !isActive {
                                    onSelect(session)
                                }
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 17))
                                        .foregroundColor(isActive ? .orange : .gray.opacity(0.4))
                                    Text(session)
                                        .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                                        .foregroundColor(isActive ? .white : .white.opacity(0.75))
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            if session != availableSessions.last {
                                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 20)
                            }
                        }
                    }
                    .background(Color.appCard)
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}


// MARK: - Unlogged Warning Sheet (shown before FinishSessionSheet when exercises are missing)
struct WorkoutSummarySheet: View {
    let exercises: [String]
    let logResults: [String: ExerciseLogResult]
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var unloggedExercises: [String] {
        exercises.filter { logResults[$0] == nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.orange)
                                    .padding(.top, 28)
                                Text("\(unloggedExercises.count) exercice\(unloggedExercises.count > 1 ? "s" : "") non loggué\(unloggedExercises.count > 1 ? "s" : "")")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Ces exercices ne seront pas enregistrés.\nVeux-tu continuer quand même ?")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)

                            // Unlogged list
                            VStack(spacing: 0) {
                                ForEach(unloggedExercises, id: \.self) { name in
                                    HStack(spacing: 12) {
                                        Image(systemName: "minus.circle")
                                            .font(.system(size: 16))
                                            .foregroundColor(.orange.opacity(0.6))
                                        Text(name)
                                            .font(.system(size: 15))
                                            .foregroundColor(.white.opacity(0.75))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20).padding(.vertical, 14)
                                    if name != unloggedExercises.last {
                                        Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 20)
                                    }
                                }
                            }
                            .background(Color.appCard)
                            .cornerRadius(14)
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 16)
                    }

                    // CTAs — pinned to bottom
                    VStack(spacing: 10) {
                        Divider().background(Color.white.opacity(0.07))
                        Button(action: {
                            onConfirm()
                            dismiss()
                        }) {
                            Text("Terminer quand même")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 20)
                        Button("Retourner à la séance") { dismiss() }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.bottom, 20)
                    }
                    .background(Color.appBg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Retour") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Finish Sheet
struct FinishSessionSheet: View {
    let exercises: [String]
    let logResults: [String: ExerciseLogResult]
    let elapsedMin: Double
    @Binding var rpe: Double
    @Binding var comment: String
    var preEnergy: Int? = nil
    var preloadedAnalysis: String? = nil
    var onSubmit: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var energyPre: Int = 3
    @State private var confirmDiscard = false
    @State private var showConfirmSubmit = false
    @State private var pendingEnergy: Int? = nil
    @State private var aiAnalysis: String? = nil
    @State private var isLoadingAI = false
    @State private var showExtras = false

    private var hasUnsavedData: Bool { !comment.isEmpty || energyPre != 3 }

    var loggedCount: Int { logResults.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundColor(.orange)
                            Text("Terminer la séance").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                            Text("\(loggedCount) / \(exercises.count) exercices loggés").font(.system(size: 14)).foregroundColor(.gray)
                        }.padding(.top, 20)

                        // Durée auto-calculée
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.cyan)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DURÉE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Text("\(Int(elapsedMin)) min")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                        // Récap exercices — compact
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("EXERCICES")
                                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(loggedCount)/\(exercises.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(loggedCount == exercises.count ? .green : .orange)
                            }
                            .padding(.horizontal, 16).padding(.bottom, 6)
                            ForEach(Array(exercises.enumerated()), id: \.0) { idx, name in
                                let result = logResults[name]
                                HStack(spacing: 10) {
                                    Image(systemName: result != nil ? "checkmark.circle.fill" : "minus.circle")
                                        .font(.system(size: 13))
                                        .foregroundColor(result != nil ? .green : .orange.opacity(0.6))
                                    Text(name)
                                        .font(.system(size: 13))
                                        .foregroundColor(result != nil ? .white : .gray)
                                    Spacer()
                                    if let r = result {
                                        Text("\(UnitSettings.shared.format(r.weight)) · \(r.reps)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    } else {
                                        Text("Non loggué")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                if idx < exercises.count - 1 {
                                    Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                        // Effort global — saisie via RIR tiles
                        VStack(alignment: .leading, spacing: 10) {
                            Text("EFFORT GLOBAL").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                            Text("Combien de reps aurais-tu pu faire en plus ?")
                                .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.75))
                            let selectedRIR = Binding<Int>(
                                get: { RPEHelper.rirFromRPE(rpe) },
                                set: { rpe = RPEHelper.rirToRPE($0) }
                            )
                            RPEHelper.RIRTiles(rir: selectedRIR, showLabels: true)
                            Text(RPEHelper.feedback(for: rpe))
                                .font(.system(size: 12))
                                .foregroundColor(RPEHelper.color(for: rpe))
                                .fixedSize(horizontal: false, vertical: true)
                            if let hint = RPEHelper.progressionHint(for: rpe) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.forward.circle")
                                        .font(.system(size: 11)).foregroundColor(.cyan.opacity(0.7))
                                    Text(hint).font(.system(size: 11)).foregroundColor(.cyan.opacity(0.7))
                                }
                            }
                        }
                        .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                        // Énergie — affichage inline si déjà saisie pendant la séance
                        if let pre = preEnergy {
                            HStack(spacing: 10) {
                                Text("ÉNERGIE AVANT").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(1...5, id: \.self) { i in
                                        Image(systemName: i <= pre ? "bolt.fill" : "bolt")
                                            .font(.system(size: 16))
                                            .foregroundColor(i <= pre ? energyColor(pre) : .gray.opacity(0.25))
                                    }
                                }
                                Text(energyLabel(pre))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(energyColor(pre))
                            }
                            .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)
                        }

                        // Extras collapsible (notes, IA — ou énergie si pas encore saisie)
                        let extrasLabel = preEnergy != nil ? "Notes · Analyse IA" : "Énergie · Notes · Analyse IA"
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showExtras.toggle() } }) {
                            HStack(spacing: 6) {
                                Image(systemName: showExtras ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(showExtras ? "Masquer les options" : extrasLabel)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                            }
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)

                        if showExtras {
                            // Énergie — uniquement si pas encore saisie (séance bonus)
                            if preEnergy == nil {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("ÉNERGIE AVANT LA SÉANCE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(energyLabel(energyPre))
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(energyColor(energyPre))
                                    }
                                    HStack(spacing: 8) {
                                        ForEach(1...5, id: \.self) { i in
                                            Button(action: { energyPre = i }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: i <= energyPre ? "bolt.fill" : "bolt")
                                                        .font(.system(size: 20))
                                                        .foregroundColor(i <= energyPre ? energyColor(energyPre) : .gray.opacity(0.3))
                                                    Text("\(i)").font(.system(size: 9)).foregroundColor(.gray)
                                                }
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                                .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)
                            }

                            // Notes
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NOTES").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                TextField("Commentaire optionnel...", text: $comment, axis: .vertical)
                                    .foregroundColor(.white).tint(.orange)
                                    .lineLimit(3, reservesSpace: true)
                                    .submitLabel(.done)
                                    .onSubmit { hideKeyboard() }
                                    .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                            }
                            .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                            // IA analyse post-séance
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: loadAIAnalysis) {
                                    HStack(spacing: 6) {
                                        if isLoadingAI {
                                            ProgressView().tint(.purple).scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "brain.head.profile").font(.system(size: 13))
                                        }
                                        Text(isLoadingAI ? "Analyse en cours…" : aiAnalysis == nil ? "Analyse IA post-séance" : "Relancer l'analyse")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundColor(.purple)
                                    .cornerRadius(10)
                                }
                                .disabled(isLoadingAI)

                                if let analysis = aiAnalysis {
                                    Text(analysis)
                                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                                        .padding(12).background(Color.purple.opacity(0.08))
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        // Soumission partielle — visible si des exercices ne sont pas loggués
                        if loggedCount < exercises.count && loggedCount > 0 {
                            Button(action: {
                                pendingEnergy = preEnergy ?? energyPre
                                showConfirmSubmit = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle")
                                    Text("Soumettre \(loggedCount) exercice\(loggedCount > 1 ? "s" : "") seulement")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                            }
                            .padding(.horizontal, 20)
                        }

                        Button(action: {
                            pendingEnergy = preEnergy ?? energyPre
                            showConfirmSubmit = true
                        }) {
                            Text(loggedCount == exercises.count ? "Enregistrer la séance" : "Enregistrer quand même tout")
                                .font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
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
            }
            .confirmationDialog("Enregistrer la séance ?", isPresented: $showConfirmSubmit, titleVisibility: .visible) {
                Button("Enregistrer") {
                    onSubmit(pendingEnergy)
                    dismiss()
                }
                Button("Continuer l'entraînement", role: .cancel) {}
            }
            .onAppear {
                if let preloaded = preloadedAnalysis {
                    aiAnalysis = preloaded
                } else {
                    loadAIAnalysis()
                }
            }
        }
    }

    private func loadAIAnalysis() {
        guard !isLoadingAI else { return }
        isLoadingAI = true
        let exoSummary = logResults.map { k, v in
            "\(k): \(v.reps) @ \(String(format: "%.0f", v.weight))lbs RPE\(String(format: "%.1f", v.rpe ?? rpe))"
        }.joined(separator: ", ")
        let prompt = "Séance terminée en \(Int(elapsedMin)) min. Exercices: \(exoSummary). RPE global: \(String(format: "%.1f", rpe)). Donne une analyse courte (3-4 phrases) : points positifs, point à améliorer, conseil pour la prochaine séance."
        Task {
            do {
                let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: [
                    "context": "Post-session analysis",
                    "messages": [["role": "user", "content": prompt]]
                ])
                let (data, _) = try await URLSession.authed.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reply = json["response"] as? String {
                    await MainActor.run { aiAnalysis = reply; isLoadingAI = false }
                } else { await MainActor.run { isLoadingAI = false } }
            } catch { await MainActor.run { isLoadingAI = false } }
        }
    }

    private func energyLabel(_ v: Int) -> String {
        switch v {
        case 1: return "Épuisé 😴"
        case 2: return "Fatigué 😕"
        case 3: return "Normal 😐"
        case 4: return "En forme 💪"
        default: return "Excellent ⚡"
        }
    }
    private func energyColor(_ v: Int) -> Color {
        switch v {
        case 1, 2: return .red
        case 3: return .yellow
        default: return .green
        }
    }
}

// MARK: - Session Recap Sheet

struct SessionRecapSheet: View {
    let snapshot: SessionRecapSnapshot
    @Environment(\.dismiss) private var dismiss

    private var totalSets: Int {
        snapshot.logResults.values.reduce(0) { $0 + $1.sets.count }
    }

    private var totalVolume: Double {
        snapshot.logResults.values.reduce(0.0) { total, result in
            total + result.sets.reduce(0.0) { s, set in
                let w = (set["weight"] as? Double) ?? 0
                let r = Double((set["reps"] as? String) ?? "0") ?? 0
                return s + w * r
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {

                        // Header
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 96, height: 96)
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 46))
                                    .foregroundColor(.orange)
                            }
                            Text("Séance complète !")
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.white)
                            Text(snapshot.sessionName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(20)
                        }
                        .padding(.top, 24)

                        // Stats row
                        HStack(spacing: 10) {
                            statPill("\(Int(snapshot.durationMin)) min", label: "DURÉE", color: .cyan)
                            statPill("\(snapshot.logResults.count)", label: "EXERCICES", color: .orange)
                            statPill("\(totalSets)", label: "SÉRIES", color: .green)
                        }
                        .padding(.horizontal, 20)

                        // Volume total
                        if totalVolume > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("VOLUME TOTAL")
                                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    Text(UnitSettings.shared.format(totalVolume))
                                        .font(.system(size: 28, weight: .black)).foregroundColor(.white)
                                }
                                Spacer()
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.purple.opacity(0.5))
                            }
                            .padding(16)
                            .background(Color.appCard).cornerRadius(14)
                            .padding(.horizontal, 20)
                        }

                        // Exercise list
                        VStack(alignment: .leading, spacing: 0) {
                            Text("EXERCICES")
                                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                .padding(.horizontal, 16).padding(.bottom, 8)
                            ForEach(Array(snapshot.exercises.enumerated()), id: \.0) { idx, name in
                                let r = snapshot.logResults[name]
                                HStack(spacing: 10) {
                                    Image(systemName: r != nil ? "checkmark.circle.fill" : "minus.circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(r != nil ? .green : .orange.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.system(size: 13, weight: r != nil ? .semibold : .regular))
                                            .foregroundColor(r != nil ? .white : .gray)
                                        if let r, !r.reps.isEmpty {
                                            Text(r.reps)
                                                .font(.system(size: 11))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    Spacer()
                                    if let r {
                                        Text(UnitSettings.shared.format(r.weight))
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.orange)
                                    } else {
                                        Text("Ignoré")
                                            .font(.system(size: 11))
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                if idx < snapshot.exercises.count - 1 {
                                    Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color.appCard).cornerRadius(14)
                        .padding(.horizontal, 20)

                        // RPE + Energy
                        HStack(spacing: 10) {
                            VStack(spacing: 6) {
                                Text("RPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Text(String(format: "%.1f", snapshot.rpe))
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundColor(rpeColor(snapshot.rpe))
                                Text("/10").font(.system(size: 11)).foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity).padding(16)
                            .background(Color.appCard).cornerRadius(14)

                            VStack(spacing: 6) {
                                Text("ÉNERGIE AVANT").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 3) {
                                    ForEach(1...5, id: \.self) { i in
                                        Image(systemName: i <= snapshot.energyPre ? "bolt.fill" : "bolt")
                                            .font(.system(size: 14))
                                            .foregroundColor(i <= snapshot.energyPre ? energyColor(snapshot.energyPre) : .gray.opacity(0.25))
                                    }
                                }
                                Text(energyLabel(snapshot.energyPre))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(energyColor(snapshot.energyPre))
                            }
                            .frame(maxWidth: .infinity).padding(16)
                            .background(Color.appCard).cornerRadius(14)
                        }
                        .padding(.horizontal, 20)

                        // Notes
                        if !snapshot.comment.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 15))
                                    .foregroundColor(.gray)
                                    .padding(.top, 1)
                                Text(snapshot.comment)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(14)
                            .background(Color.appCard).cornerRadius(14)
                            .padding(.horizontal, 20)
                        }

                        Button(action: { dismiss() }) {
                            Text("Continuer")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Récapitulatif")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func statPill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(1.5)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(color.opacity(0.08))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }

    private func energyColor(_ v: Int) -> Color {
        switch v {
        case 1, 2: return .red
        case 3:    return .yellow
        default:   return .green
        }
    }

    private func energyLabel(_ v: Int) -> String {
        switch v {
        case 1: return "Épuisé"
        case 2: return "Fatigué"
        case 3: return "Normal"
        case 4: return "En forme"
        default: return "Excellent"
        }
    }
}

// MARK: - Energy Pre-Workout Sheet
struct EnergyPreWorkoutSheet: View {
    @Binding var energy: Int
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Avant de commencer")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("Comment te sens-tu aujourd'hui ?")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.top, 16)

            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { i in
                    Button(action: { energy = i; triggerImpact(style: .light) }) {
                        VStack(spacing: 6) {
                            Image(systemName: i <= energy ? "bolt.fill" : "bolt")
                                .font(.system(size: 32))
                                .foregroundColor(i <= energy ? energyColor(i) : .gray.opacity(0.25))
                                .animation(.spring(response: 0.2), value: energy)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Text(energyLabel(energy))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(energyColor(energy))

            Button("C'est parti ! 💪") {
                onConfirm()
                dismiss()
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(14)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .background(Color.appBg)
    }

    private func energyColor(_ v: Int) -> Color {
        switch v {
        case 1, 2: return .red
        case 3: return .yellow
        default: return .green
        }
    }

    private func energyLabel(_ v: Int) -> String {
        switch v {
        case 1: return "Épuisé 😴"
        case 2: return "Fatigué 😕"
        case 3: return "Normal 😐"
        case 4: return "En forme 💪"
        default: return "Excellent ⚡"
        }
    }
}

// MARK: - HIIT Seance
struct HIITSeanceView: View {
    let sessionType: String
    @ObservedObject var vm: SeanceViewModel
    @State private var rounds = 8
    @State private var workTime = 40
    @State private var restTime = 20
    @State private var rpe: Double = 7
    @State private var notes = ""
    @State private var logError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: "figure.run").font(.system(size: 48)).foregroundColor(.red)
                    Text(sessionType).font(.system(size: 24, weight: .black)).foregroundColor(.white)
                }.padding(.top, 20)

                VStack(spacing: 12) {
                    StepperRow(title: "ROUNDS", value: $rounds, range: 1...30)
                    StepperRow(title: "WORK (s)", value: $workTime, range: 10...120, step: 5)
                    StepperRow(title: "REST (s)", value: $restTime, range: 5...120, step: 5)
                }.padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                        Spacer()
                        Text("\(rpe, specifier: "%.1f")").font(.system(size: 20, weight: .black)).foregroundColor(.orange)
                    }
                    Slider(value: $rpe, in: 1...10, step: 0.5).tint(.orange)
                }
                .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                    TextField("Notes optionnelles...", text: $notes, axis: .vertical)
                        .foregroundColor(.white).lineLimit(3, reservesSpace: true)
                }
                .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                Button(action: logHIIT) {
                    Text("Enregistrer HIIT")
                        .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.red).foregroundColor(.white).cornerRadius(14)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .alert("HIIT enregistré ✅", isPresented: $vm.showSuccess) {
            Button("OK") { Task { await vm.load() } }
        }
        .alert("Erreur", isPresented: Binding(get: { logError != nil }, set: { if !$0 { logError = nil } })) {
            Button("OK", role: .cancel) { logError = nil }
        } message: { Text(logError ?? "") }
    }

    private func logHIIT() {
        Task {
            do {
                try await APIService.shared.logHIIT(
                    sessionType: sessionType, rounds: rounds,
                    workTime: workTime, restTime: restTime, rpe: rpe, notes: notes
                )
                await vm.load()
                await APIService.shared.fetchDashboard()
                vm.showSuccess = true
            } catch {
                logError = error.localizedDescription
            }
        }
    }
}

// MARK: - Inline Coaching Chip

struct CoachingChip: View {
    let suggestion: ProgressionSuggestion

    @State private var applied = false
    @State private var ignored = false

    var body: some View {
        if ignored {
            EmptyView()
        } else if applied {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(.green)
                Text("Appliqué")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.green)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.green.opacity(0.1)).cornerRadius(8)
        } else {
            HStack(spacing: 8) {
                Image(systemName: typeIcon)
                    .font(.system(size: 12)).foregroundColor(typeColor)
                if let w = suggestion.suggestedWeight {
                    Text(w.fmtLbs())
                        .font(.system(size: 13, weight: .black)).foregroundColor(typeColor)
                }
                Text(suggestion.reason)
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer()
                Button("Ignorer") { ignored = true }
                    .font(.system(size: 11)).foregroundColor(.gray)
                if let w = suggestion.suggestedWeight {
                    Button("Appliquer") {
                        triggerImpact(style: .light)
                        Task {
                            do {
                                try await APIService.shared.applyProgression(
                                    exerciseName: suggestion.exerciseName,
                                    suggestedWeight: w,
                                    suggestedScheme: suggestion.suggestedScheme
                                )
                                applied = true
                            } catch {
                                print("[Progression] apply failed for \(suggestion.exerciseName): \(error)")
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(typeColor)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(typeColor.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(typeColor.opacity(0.2), lineWidth: 1))
            .cornerRadius(8)
        }
    }

    private var typeIcon: String {
        switch suggestion.suggestionType {
        case "increase_weight": return "arrow.up.circle.fill"
        case "increase_sets":   return "plus.circle.fill"
        case "deload":          return "arrow.down.circle.fill"
        case "regression":      return "exclamationmark.circle.fill"
        default:                return "minus.circle"
        }
    }
    private var typeColor: Color {
        switch suggestion.suggestionType {
        case "increase_weight": return .cyan
        case "increase_sets":   return .green
        case "deload":          return .orange
        case "regression":      return .red
        default:                return .gray
        }
    }
}

// MARK: - Special (Yoga/Recovery)
struct SpecialSeanceView: View {
    let sessionType: String
    @ObservedObject var vm: SeanceViewModel
    @State private var rpe: Double = 5
    @State private var comment = ""
    @AppStorage("special_session_logged_date") private var loggedDate: String = ""

    private var alreadyLoggedToday: Bool {
        // Server is source of truth — if server says not logged, allow re-log
        // (handles case where local AppStorage is stale after a failed network call)
        let localSaysLogged = loggedDate == DateFormatter.isoDate.string(from: Date())
        let serverSaysLogged = vm.seanceData?.alreadyLogged ?? false
        return localSaysLogged && serverSaysLogged
    }

    var color: Color { sessionType == "Yoga / Tai Chi" ? .purple : .green }
    var icon: String  { sessionType == "Yoga / Tai Chi" ? "figure.mind.and.body" : "heart.fill" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 48)).foregroundColor(color)
                    Text(sessionType).font(.system(size: 24, weight: .black)).foregroundColor(.white)
                }.padding(.top, 24)
                .onAppear {
                    if alreadyLoggedToday {
                        APIService.shared.sessionLoggedToday = true
                    }
                }

                if alreadyLoggedToday {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(color)
                        Text("Séance déjà enregistrée aujourd'hui")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(color.opacity(0.12))
                    .cornerRadius(14)
                    .padding(.horizontal, 16)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                            Spacer()
                            Text("\(rpe, specifier: "%.1f")").font(.system(size: 20, weight: .black)).foregroundColor(color)
                        }
                        Slider(value: $rpe, in: 1...10, step: 0.5).tint(color)
                    }
                    .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                        TextField("Comment c'était ?", text: $comment, axis: .vertical)
                            .foregroundColor(.white).tint(.orange)
                            .lineLimit(3, reservesSpace: true)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                            .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                    }
                    .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                    Button(action: logSession) {
                        Text("Enregistrer \(sessionType)")
                            .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(color).foregroundColor(.white).cornerRadius(14)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .alert("Séance enregistrée ✅", isPresented: $vm.showSuccess) {
            Button("OK") { Task { await vm.load() } }
        }
        .alert("Erreur", isPresented: Binding(
            get: { vm.submitError != nil },
            set: { if !$0 { vm.submitError = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let err = vm.submitError { Text(err) }
        }
    }

    private func logSession() {
        Task {
            do {
                try await APIService.shared.logSession(
                    exos: [sessionType], rpe: rpe, comment: comment, sessionName: sessionType
                )
            } catch {
                vm.submitError = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
                await APIService.shared.fetchDashboard()
                return
            }
            loggedDate = DateFormatter.isoDate.string(from: Date())
            let fresh = try? await APIService.shared.fetchSeanceData()
            let verified = fresh?.alreadyLogged ?? false
            await APIService.shared.fetchDashboard()
            if verified {
                // fetchDashboard() peut resetter sessionLoggedToday si le serveur
                // retourne alreadyLoggedToday=false (timing DB). On le re-asserte ici.
                await MainActor.run { APIService.shared.sessionLoggedToday = true }
                vm.showSuccess = true
            } else {
                loggedDate = ""
                vm.submitError = "Séance non confirmée — vérifie ta connexion et réessaie."
            }
        }
    }
}

// MARK: - Stepper Row
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
            Spacer()
            HStack(spacing: 12) {
                Button(action: { if value - step >= range.lowerBound { value -= step } }) {
                    Image(systemName: "minus.circle.fill").font(.system(size: 28)).foregroundColor(.gray)
                }
                Text("\(value)").font(.system(size: 20, weight: .black)).foregroundColor(.white).frame(width: 50, alignment: .center)
                Button(action: { if value + step <= range.upperBound { value += step } }) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 28)).foregroundColor(.orange)
                }
            }
        }
        .padding(14).background(Color.appCard).cornerRadius(12)
    }
}

// MARK: - Rest Timer live indicator (used in ExerciseCard and WorkoutSeanceView header)

/// Shows a live countdown when the timer is running, or the configured rest time when idle.
/// Isolated into its own View so only this small widget re-renders every second.
struct RestTimerBadge: View {
    let restSeconds: Int?
    var onTap: () -> Void
    @ObservedObject private var timer = RestTimerManager.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .semibold))
                Group {
                    if timer.isRunning {
                        Text(formatTime(timer.remaining))
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                    } else if let r = restSeconds {
                        Text(r < 60 ? "\(r)s" : "\(r / 60):\(String(format: "%02d", r % 60))")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                    }
                }
            }
            .foregroundColor(timer.isRunning ? timer.timerColor : .cyan)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background((timer.isRunning ? timer.timerColor : Color.cyan).opacity(0.12))
            .cornerRadius(8)
            .animation(.easeInOut(duration: 0.2), value: timer.isRunning)
        }
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

// MARK: - Error View
struct ErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash").font(.system(size: 48)).foregroundColor(.gray)
            Text("Erreur").foregroundColor(.white).font(.headline)
            Text(message).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
            Button("Réessayer", action: retry).foregroundColor(.orange)
        }.padding()
    }
}
