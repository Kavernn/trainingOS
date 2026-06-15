import SwiftUI
import OSLog

private let logger = Logger(subsystem: "TrainingOS", category: "Progression")

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
                            .font(.appHeadline).fontWeight(.bold)
                            .foregroundColor(.appTextPrimary)
                            .padding(.top, 20)
                        Text("Séance active aujourd'hui")
                            .font(.appCaption)
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
                                        .font(.appHeadline)
                                        .foregroundColor(isActive ? Color.forge : .gray.opacity(0.4))
                                    Text(session)
                                        .font(.appBody).fontWeight(isActive ? .semibold : .regular)
                                        .foregroundColor(isActive ? .white : .white.opacity(0.75))
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            if session != availableSessions.last {
                                Divider().background(Color.appSeparator).padding(.horizontal, 20)
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
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
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
                                    .foregroundColor(Color.forge)
                                    .padding(.top, 28)
                                Text("\(unloggedExercises.count) exercice\(unloggedExercises.count > 1 ? "s" : "") non loggué\(unloggedExercises.count > 1 ? "s" : "")")
                                    .font(.appTitle)
                                    .foregroundColor(.appTextPrimary)
                                Text("Ces exercices ne seront pas enregistrés.\nVeux-tu continuer quand même ?")
                                    .font(.appLabel)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)

                            // Unlogged list
                            VStack(spacing: 0) {
                                ForEach(unloggedExercises, id: \.self) { name in
                                    HStack(spacing: 12) {
                                        Image(systemName: "minus.circle")
                                            .font(.appBody)
                                            .foregroundColor(Color.forge.opacity(0.6))
                                        Text(name)
                                            .font(.appBody)
                                            .foregroundColor(.white.opacity(0.75))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20).padding(.vertical, 14)
                                    if name != unloggedExercises.last {
                                        Divider().background(Color.appSeparator).padding(.horizontal, 20)
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
                        Divider().background(Color.appSeparator)
                        Button(action: {
                            onConfirm()
                            dismiss()
                        }) {
                            Text("Terminer quand même")
                                .font(.appBody).fontWeight(.bold)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.forge)
                                .foregroundColor(Color.onAccent)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 20)
                        Button("Retourner à la séance") { dismiss() }
                            .font(.appBody).fontWeight(.medium)
                            .foregroundColor(Color.forge)
                            .padding(.bottom, 20)
                    }
                    .background(Color.appBg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Retour") { dismiss() }.foregroundColor(Color.forge)
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
    @State private var aiError = false
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
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundColor(Color.forge)
                            Text("Terminer la séance").font(.appTitle).foregroundColor(.appTextPrimary)
                            Text("\(loggedCount) / \(exercises.count) exercices loggés").font(.appLabel).foregroundColor(.gray)
                        }.padding(.top, 20)

                        // Durée auto-calculée
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .font(.appTitle)
                                .foregroundColor(.statusCyan)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DURÉE").font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                Text("\(Int(elapsedMin)) min")
                                    .font(.appTitle).fontWeight(.black)
                                    .foregroundColor(.forge)
                            }
                            Spacer()
                        }
                        .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                        // Récap exercices — compact
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("EXERCICES")
                                    .font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(loggedCount)/\(exercises.count)")
                                    .font(.appCaption).fontWeight(.bold)
                                    .foregroundColor(loggedCount == exercises.count ? .statusGreen : .statusOrange)
                            }
                            .padding(.horizontal, 16).padding(.bottom, 6)
                            ForEach(Array(exercises.enumerated()), id: \.0) { idx, name in
                                let result = logResults[name]
                                HStack(spacing: 10) {
                                    Image(systemName: result != nil ? "checkmark.circle.fill" : "minus.circle")
                                        .font(.appLabel)
                                        .foregroundColor(result != nil ? .statusGreen : .statusOrange.opacity(0.6))
                                    Text(name)
                                        .font(.appLabel)
                                        .foregroundColor(result != nil ? .white : .gray)
                                    Spacer()
                                    if let r = result {
                                        Text("\(UnitSettings.shared.format(r.weight)) · \(r.reps)")
                                            .font(.appCaption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                if idx < exercises.count - 1 {
                                    Divider().background(Color.appSeparatorSubtle).padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                        // Effort global — saisie via RIR tiles
                        VStack(alignment: .leading, spacing: 10) {
                            Text("EFFORT GLOBAL").font(.appCaption).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                            Text("Combien de reps aurais-tu pu faire en plus ?")
                                .font(.appLabel).foregroundColor(.white.opacity(0.75))
                            let selectedRIR = Binding<Int>(
                                get: { RPEHelper.rirFromRPE(rpe) },
                                set: { rpe = RPEHelper.rirToRPE($0) }
                            )
                            RPEHelper.RIRTiles(rir: selectedRIR, showLabels: true)
                            Text("RPE estimé : \(String(format: "%.1f", 10.0 - Double(RPEHelper.rirFromRPE(rpe))))")
                                .font(.appCaption)
                                .foregroundColor(.gray)
                            Text(RPEHelper.feedback(for: rpe))
                                .font(.appCaption)
                                .foregroundColor(RPEHelper.color(for: rpe))
                                .fixedSize(horizontal: false, vertical: true)
                            if let hint = RPEHelper.progressionHint(for: rpe) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.forward.circle")
                                        .font(.appCaption).foregroundColor(.statusCyan.opacity(0.7))
                                    Text(hint).font(.appCaption).foregroundColor(.statusCyan.opacity(0.7))
                                }
                            }
                        }
                        .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                        // Énergie — affichage inline si déjà saisie pendant la séance
                        if let pre = preEnergy {
                            HStack(spacing: 10) {
                                Text("ÉNERGIE AVANT").font(.appCaption).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(1...5, id: \.self) { i in
                                        Image(systemName: i <= pre ? "bolt.fill" : "bolt")
                                            .font(.appBody)
                                            .foregroundColor(i <= pre ? energyColor(pre) : .gray.opacity(0.25))
                                    }
                                }
                                Text(energyLabel(pre))
                                    .font(.appLabel).fontWeight(.bold)
                                    .foregroundColor(energyColor(pre))
                            }
                            .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)
                        }

                        // Extras collapsible (notes, IA — ou énergie si pas encore saisie)
                        let extrasLabel = preEnergy != nil ? "Notes · Analyse IA" : "Énergie · Notes · Analyse IA"
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showExtras.toggle() } }) {
                            HStack(spacing: 6) {
                                Image(systemName: showExtras ? "chevron.up" : "chevron.down")
                                    .font(.appMicro).fontWeight(.semibold)
                                Text(showExtras ? "Masquer les options" : extrasLabel)
                                    .font(.appCaption).fontWeight(.medium)
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
                                        Text("ÉNERGIE AVANT LA SÉANCE").font(.appCaption).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(energyLabel(energyPre))
                                            .font(.appLabel).fontWeight(.bold)
                                            .foregroundColor(energyColor(energyPre))
                                    }
                                    HStack(spacing: 8) {
                                        ForEach(1...5, id: \.self) { i in
                                            Button(action: { energyPre = i }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: i <= energyPre ? "bolt.fill" : "bolt")
                                                        .font(.appTitle)
                                                        .foregroundColor(i <= energyPre ? energyColor(energyPre) : .gray.opacity(0.3))
                                                    Text("\(i)").font(.appMicro).foregroundColor(.gray)
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
                                Text("NOTES").font(.appCaption).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                TextField("Commentaire optionnel...", text: $comment, axis: .vertical)
                                    .foregroundColor(.appTextPrimary).tint(Color.forge)
                                    .lineLimit(3, reservesSpace: true)
                                    .submitLabel(.done)
                                    .onSubmit { hideKeyboard() }
                                    .padding(12).background(Color.appSurfaceInset).cornerRadius(10)
                            }
                            .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 20)

                            // IA analyse post-séance
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: loadAIAnalysis) {
                                    HStack(spacing: 6) {
                                        if isLoadingAI {
                                            ProgressView().tint(.statusPurple).scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "brain.head.profile").font(.appLabel)
                                        }
                                        Text(isLoadingAI ? "Analyse en cours…" : aiAnalysis == nil ? "Analyse IA post-séance" : "Relancer l'analyse")
                                            .font(.appLabel)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(Color.statusPurple.opacity(0.12))
                                    .foregroundColor(.statusPurple)
                                    .cornerRadius(10)
                                }
                                .disabled(isLoadingAI)

                                if aiError {
                                    Text("Analyse IA indisponible — réessaie")
                                        .font(.appCaption)
                                        .foregroundColor(.statusRed.opacity(0.8))
                                }

                                if let analysis = aiAnalysis {
                                    Text(analysis)
                                        .font(.appLabel).foregroundColor(.white.opacity(0.85))
                                        .padding(12).background(Color.statusPurple.opacity(0.08))
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
                                        .font(.appLabel).fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.forge.opacity(0.15))
                                .foregroundColor(Color.forge)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.forge.opacity(0.3), lineWidth: 1))
                            }
                            .padding(.horizontal, 20)
                        }

                        Button(action: {
                            pendingEnergy = preEnergy ?? energyPre
                            showConfirmSubmit = true
                        }) {
                            Text(loggedCount == exercises.count ? "Enregistrer la séance" : "Enregistrer quand même tout")
                                .font(.appBody).fontWeight(.bold).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.forge).foregroundColor(Color.onAccent).cornerRadius(14)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 8)

                        NavigationLink(destination: GraveyardView()) {
                            HStack(spacing: 8) {
                                Image(systemName: "cross.fill")
                                    .font(.appCaption)
                                    .foregroundColor(Color.forge)
                                Text("Voir le Graveyard")
                                    .font(.appLabel)
                                    .foregroundColor(Color.forge)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.appCaption)
                                    .foregroundColor(Color.forge.opacity(0.5))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.forge.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.forge.opacity(0.2), lineWidth: 1))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnTap()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if hasUnsavedData { confirmDiscard = true } else { dismiss() }
                    }
                    .foregroundColor(Color.forge)
                }
            }
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Toutes tes notes et configurations seront perdues.")
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
            .interactiveDismissDisabled(hasUnsavedData)
        }
    }

    private func loadAIAnalysis() {
        guard !isLoadingAI else { return }
        isLoadingAI = true
        aiError = false
        let exoSummary = logResults.map { k, v in
            "\(k): \(v.reps) @ \(String(format: "%.0f", v.weight))lbs RPE\(String(format: "%.1f", v.rpe ?? rpe))"
        }.joined(separator: ", ")
        let prompt = "Séance terminée en \(Int(elapsedMin)) min. Exercices: \(exoSummary). RPE global: \(String(format: "%.1f", rpe)). Donne une analyse courte (3-4 phrases) : points positifs, point à améliorer, conseil pour la prochaine séance."
        // W-B4 — 10-second timeout; show "Analyse indisponible" instead of infinite spinner
        let apiTask = Task {
            do {
                guard let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach") else { return }
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
            } catch { await MainActor.run { isLoadingAI = false; aiError = true } }
        }
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if !apiTask.isCancelled {
                apiTask.cancel()
                await MainActor.run {
                    if isLoadingAI {
                        isLoadingAI = false
                        aiError = true
                    }
                }
            }
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
        case 1, 2: return .statusRed
        case 3: return .statusYellow
        default: return .statusGreen
        }
    }
}

// MARK: - Session Recap Sheet

struct SessionRecapSheet: View {
    let snapshot: SessionRecapSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var animateHeader = false
    @State private var showConfetti = false

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

                        // Header — spring-animated entry + celebration haptic
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.forge.opacity(0.12))
                                    .frame(width: 96, height: 96)
                                    .scaleEffect(animateHeader ? 1.0 : 0.4)
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 46))
                                    .foregroundColor(Color.forge)
                                    .scaleEffect(animateHeader ? 1.0 : 0.3)
                                    .opacity(animateHeader ? 1.0 : 0.0)
                            }
                            Text("Séance complète !")
                                .font(.appTitle).fontWeight(.black)
                                .foregroundColor(.appTextPrimary)
                                .opacity(animateHeader ? 1.0 : 0.0)
                                .offset(y: animateHeader ? 0 : 10)
                            Text(snapshot.sessionName)
                                .font(.appLabel).fontWeight(.semibold)
                                .foregroundColor(Color.forge)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(Color.forge.opacity(0.1))
                                .cornerRadius(20)
                                .opacity(animateHeader ? 1.0 : 0.0)
                        }
                        .padding(.top, 24)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                                animateHeader = true
                            }
                            showConfetti = true
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            triggerNotificationFeedback(.success)
                        }

                        // Stats row
                        HStack(spacing: 10) {
                            statPill("(Int(snapshot.durationMin)) min", label: "DURÉE", color: .statusCyan)
                            statPill("\(snapshot.logResults.count)", label: "EXERCICES", color: Color.forge)
                            statPill("\(totalSets)", label: "SÉRIES", color: .statusGreen)
                        }
                        .padding(.horizontal, 20)

                        // Volume total
                        if totalVolume > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("VOLUME TOTAL")
                                        .font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                    Text(UnitSettings.shared.format(totalVolume))
                                        .font(.system(size: 28, weight: .black)).foregroundColor(.appTextPrimary)
                                        .contentTransition(.numericText())
                                }
                                Spacer()
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.statusPurple.opacity(0.5))
                            }
                            .padding(16)
                            .background(Color.appCard).cornerRadius(14)
                            .padding(.horizontal, 20)
                        }

                        // Exercise list
                        VStack(alignment: .leading, spacing: 0) {
                            Text("EXERCICES")
                                .font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                .padding(.horizontal, 16).padding(.bottom, 8)
                            ForEach(Array(snapshot.exercises.enumerated()), id: \.0) { idx, name in
                                let r = snapshot.logResults[name]
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: r != nil ? "checkmark.circle.fill" : "minus.circle")
                                        .font(.appLabel)
                                        .foregroundColor(r != nil ? .statusGreen : .statusOrange.opacity(0.5))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(name)
                                            .font(.appLabel).fontWeight(r != nil ? .semibold : .regular)
                                            .foregroundColor(r != nil ? .white : .gray)
                                        if let r, !r.sets.isEmpty {
                                            setRows(sets: r.sets, fallbackWeight: r.weight)
                                        } else if let r, !r.reps.isEmpty {
                                            Text(r.reps)
                                                .font(.appCaption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    Spacer()
                                    if let r {
                                        if r.sets.isEmpty {
                                            Text(UnitSettings.shared.format(r.weight))
                                                .font(.appLabel).fontWeight(.bold)
                                                .foregroundColor(Color.forge)
                                        }
                                    } else {
                                        Text("Ignoré")
                                            .font(.appCaption)
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                if idx < snapshot.exercises.count - 1 {
                                    Divider().background(Color.appSeparatorSubtle).padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color.appCard).cornerRadius(14)
                        .padding(.horizontal, 20)

                        // RPE + Energy
                        HStack(spacing: 10) {
                            VStack(spacing: 6) {
                                Text("RPE").font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                Text(String(format: "%.1f", snapshot.rpe))
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundColor(rpeColor(snapshot.rpe))
                                Text("/10").font(.appCaption).foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity).padding(16)
                            .background(Color.appCard).cornerRadius(14)

                            VStack(spacing: 6) {
                                Text("ÉNERGIE AVANT").font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 3) {
                                    ForEach(1...5, id: \.self) { i in
                                        Image(systemName: i <= snapshot.energyPre ? "bolt.fill" : "bolt")
                                            .font(.appLabel)
                                            .foregroundColor(i <= snapshot.energyPre ? energyColor(snapshot.energyPre) : .gray.opacity(0.25))
                                    }
                                }
                                Text(energyLabel(snapshot.energyPre))
                                    .font(.appCaption).fontWeight(.semibold)
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
                                    .font(.appBody)
                                    .foregroundColor(.gray)
                                    .padding(.top, 1)
                                Text(snapshot.comment)
                                    .font(.appLabel)
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
                                .font(.appBody).fontWeight(.bold)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.forge).foregroundColor(Color.onAccent).cornerRadius(14)
                        }
                        .buttonStyle(SpringButtonStyle())
                        .padding(.horizontal, 20).padding(.bottom, 32)
                    }
                }
                // Confetti overlay
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("Récapitulatif")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func setRows(sets: [[String: Any]], fallbackWeight: Double) -> some View {
        ForEach(Array(sets.enumerated()), id: \.offset) { j, s in
            HStack(spacing: 4) {
                Text("S\(j + 1)")
                    .font(.appMicro).fontWeight(.bold)
                    .foregroundColor(.gray.opacity(0.4))
                    .frame(width: 16, alignment: .leading)
                Text(UnitSettings.shared.format(s["weight"] as? Double ?? fallbackWeight))
                    .font(.appMicro).foregroundColor(.white.opacity(0.6))
                Text("×").font(.appMicro).foregroundColor(.gray.opacity(0.35))
                Text(s["reps"] as? String ?? "—")
                    .font(.appMicro).foregroundColor(.gray)
            }
        }
    }

    private func statPill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.appTitle).fontWeight(.black)
                .foregroundColor(.appTextPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.appMicro).fontWeight(.bold).tracking(1.5)
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
        case 1, 2: return .statusRed
        case 3:    return .statusYellow
        default:   return .statusGreen
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
                    .font(.appTitle)
                    .foregroundColor(.appTextPrimary)
                Text("Comment te sens-tu aujourd'hui ?")
                    .font(.appLabel)
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
                .font(.appHeadline).fontWeight(.bold)
                .foregroundColor(energyColor(energy))

            Button("C'est parti ! 💪") {
                onConfirm()
                dismiss()
            }
            .font(.appBody).fontWeight(.bold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.forge)
            .foregroundColor(Color.onAccent)
            .cornerRadius(14)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .background(Color.appBg)
    }

    private func energyColor(_ v: Int) -> Color {
        switch v {
        case 1, 2: return .statusRed
        case 3: return .statusYellow
        default: return .statusGreen
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
                    Image(systemName: "figure.run").font(.system(size: 48)).foregroundColor(.statusRed)
                    Text(sessionType).font(.appTitle).fontWeight(.black).foregroundColor(.appTextPrimary)
                }.padding(.top, 20)

                VStack(spacing: 12) {
                    StepperRow(title: "ROUNDS", value: $rounds, range: 1...30)
                    StepperRow(title: "WORK (s)", value: $workTime, range: 10...120, step: 5)
                    StepperRow(title: "REST (s)", value: $restTime, range: 5...120, step: 5)
                }.padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("RPE").font(.appCaption).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                        Spacer()
                        Text("\(rpe, specifier: "%.1f")").font(.appTitle).fontWeight(.black).foregroundColor(Color.forge)
                    }
                    Slider(value: $rpe, in: 1...10, step: 0.5).tint(Color.forge)
                }
                .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES").font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                    TextField("Notes optionnelles...", text: $notes, axis: .vertical)
                        .foregroundColor(.appTextPrimary).lineLimit(3, reservesSpace: true)
                }
                .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                Button(action: logHIIT) {
                    Text("Enregistrer HIIT")
                        .font(.appBody).fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.appDanger).foregroundColor(.white).cornerRadius(14)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .dismissKeyboardOnTap()
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
                    .font(.appCaption).foregroundColor(.statusGreen)
                Text("Appliqué")
                    .font(.appCaption).fontWeight(.medium).foregroundColor(.statusGreen)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.appSuccess.opacity(0.1)).cornerRadius(8)
        } else if suggestion.suggestionType == "maintain" {
            HStack(spacing: 6) {
                Image(systemName: "equal.circle")
                    .font(.appCaption).foregroundColor(.gray.opacity(0.7))
                Text("Pas de changement recommandé")
                    .font(.appCaption).fontWeight(.medium).foregroundColor(.gray.opacity(0.8))
                Spacer()
                Button("OK") { ignored = true }
                    .font(.appCaption).foregroundColor(.gray)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.gray.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            .cornerRadius(8)
        } else {
            HStack(spacing: 8) {
                Image(systemName: typeIcon)
                    .font(.appCaption).foregroundColor(typeColor)
                if let w = suggestion.suggestedWeight {
                    Text(UnitSettings.shared.format(w))
                        .font(.appLabel).fontWeight(.black).foregroundColor(typeColor)
                }
                Text(suggestion.reason)
                    .font(.appCaption).foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                Spacer()
                Button("Ignorer") { ignored = true }
                    .font(.appCaption).foregroundColor(.gray)
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
                                logger.error("apply failed for \(suggestion.exerciseName): \(error)")
                            }
                        }
                    }
                    .font(.appCaption).fontWeight(.semibold).foregroundColor(typeColor)
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
        case "increase_weight": return .statusCyan
        case "increase_sets":   return .statusGreen
        case "deload":          return .statusOrange
        case "regression":      return .statusRed
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
        // W-D5 — Server is source of truth: both local AND server must agree.
        // If server says not logged, always show the form (even if AppStorage is stale).
        let localSaysLogged = loggedDate == DateFormatter.isoDate.string(from: Date())
        let serverSaysLogged = vm.seanceData?.alreadyLogged ?? false
        return localSaysLogged && serverSaysLogged
    }

    var color: Color { sessionType == "Yoga / Tai Chi" ? .statusPurple : .statusGreen }
    var icon: String  { sessionType == "Yoga / Tai Chi" ? "figure.mind.and.body" : "heart.fill" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 48)).foregroundColor(color)
                    Text(sessionType).font(.appTitle).fontWeight(.black).foregroundColor(.appTextPrimary)
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
                            .font(.appLabel).fontWeight(.semibold)
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
                            Text("RPE").font(.appCaption).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                            Spacer()
                            Text("\(rpe, specifier: "%.1f")").font(.appTitle).fontWeight(.black).foregroundColor(color)
                        }
                        Slider(value: $rpe, in: 1...10, step: 0.5).tint(color)
                    }
                    .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES").font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                        TextField("Comment c'était ?", text: $comment, axis: .vertical)
                            .foregroundColor(.appTextPrimary).tint(Color.forge)
                            .lineLimit(3, reservesSpace: true)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                            .padding(12).background(Color.appSurfaceInset).cornerRadius(10)
                    }
                    .padding(16).background(Color.appCard).cornerRadius(14).padding(.horizontal, 16)

                    Button(action: logSession) {
                        Text("Enregistrer \(sessionType)")
                            .font(.appBody).fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(color).foregroundColor(.white).cornerRadius(14)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
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
            Text(title).font(.appCaption).fontWeight(.bold).tracking(2).foregroundColor(.gray)
            Spacer()
            HStack(spacing: 12) {
                Button(action: { if value - step >= range.lowerBound { value -= step } }) {
                    Image(systemName: "minus.circle.fill").font(.system(size: 28)).foregroundColor(.gray)
                }
                Text("\(value)").font(.appTitle).fontWeight(.black).foregroundColor(.appTextPrimary).frame(width: 50, alignment: .center)
                Button(action: { if value + step <= range.upperBound { value += step } }) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 28)).foregroundColor(Color.forge)
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
            TimelineView(.periodic(from: timer.startDate ?? .now, by: 1)) { ctx in
                let elapsed = timer.isRunning ? max(0, ctx.date.timeIntervalSince(timer.startDate ?? .now)) : 0
                let remaining = max(0, timer.totalSeconds - Int(elapsed))
                let progress = timer.totalSeconds > 0 ? Double(remaining) / Double(timer.totalSeconds) : 0
                let timerColor: Color = progress > 0.5 ? .statusGreen : (progress > 0.25 ? .statusYellow : .statusRed)

                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.appLabel).fontWeight(.semibold)
                    Group {
                        if timer.isRunning {
                            Text(formatTime(remaining))
                                .font(.appCaption).fontWeight(.bold)
                                .monospacedDigit()
                        } else if let r = restSeconds {
                            Text(r < 60 ? "\(r)s" : "\(r / 60):\(String(format: "%02d", r % 60))")
                                .font(.appCaption).fontWeight(.bold)
                                .monospacedDigit()
                        }
                    }
                }
                .foregroundColor(timer.isRunning ? timerColor : .statusCyan)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background((timer.isRunning ? timerColor : Color.statusCyan).opacity(0.12))
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: timer.isRunning)
            }
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
            Text("Erreur").foregroundColor(.appTextPrimary).font(.headline)
            Text(message).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
            Button("Réessayer", action: retry).foregroundColor(Color.forge)
        }.padding()
    }
}
