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
                                        .foregroundColor(isActive ? .white : Color.appOnSurface.opacity(0.75))
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
                                            .foregroundColor(Color.appOnSurface.opacity(0.75))
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
    var onSubmit: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var energyPre: Int = 3
    @State private var confirmDiscard = false
    @State private var showConfirmSubmit = false
    @State private var pendingEnergy: Int? = nil
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
                                        .foregroundColor(result != nil ? .statusGreen : Color.statusOrange.opacity(0.6))
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
                                .font(.appLabel).foregroundColor(Color.appOnSurface.opacity(0.75))
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
                                        .font(.appCaption).foregroundColor(Color.statusCyan.opacity(0.7))
                                    Text(hint).font(.appCaption).foregroundColor(Color.statusCyan.opacity(0.7))
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
            .interactiveDismissDisabled(hasUnsavedData)
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

    private var totalVolume: Double {
        snapshot.logResults.values.reduce(0.0) { total, result in
            total + result.sets.reduce(0.0) { s, set in
                let w = (set["weight"] as? Double) ?? 0
                let r = Double((set["reps"] as? String) ?? "0") ?? 0
                return s + w * r
            }
        }
    }

    // Compact hero format: "4.2t" if ≥ 1000 in display unit, else "832".
    // ponytail: divergence assumée avec UnitSettings.format() qui garde l'unité —
    // ici on veut un chiffre hero très lisible, pas un affichage précis.
    private var totalVolumeCompact: String {
        let units = UnitSettings.shared
        let display = units.isKg ? totalVolume * 0.453592 : totalVolume
        if display >= 1000 {
            return String(format: "%.1ft", display / 1000)
        }
        return "\(Int(display.rounded()))"
    }

    private var shareText: String {
        let dur = Int(snapshot.durationMin)
        let vol = UnitSettings.shared.format(totalVolume)
        let rpe = String(format: "%.1f", snapshot.rpe)
        return "Séance complétée — \(snapshot.sessionName)\nDurée \(dur) min · Volume \(vol) · RPE \(rpe)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        statsRow
                        exercisesList
                        if snapshot.energyPre > 0 { energyRow }
                        if !snapshot.comment.trimmingCharacters(in: .whitespaces).isEmpty { notesBlock }
                        actions.padding(.top, 4).padding(.bottom, 32)
                    }
                    .padding(.horizontal, 20)
                }
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header (épuré : cercle ember + checkmark, un seul titre, pill compacte)
    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.forge.opacity(0.14))
                    .frame(width: 84, height: 84)
                    .scaleEffect(animateHeader ? 1.0 : 0.4)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(Color.forge)
                    .scaleEffect(animateHeader ? 1.0 : 0.3)
                    .opacity(animateHeader ? 1.0 : 0.0)
            }
            Text("Séance complétée")
                .font(.appTitle).fontWeight(.bold)
                .foregroundColor(.appTextPrimary)
                .opacity(animateHeader ? 1.0 : 0.0)
                .offset(y: animateHeader ? 0 : 8)
            Text(snapshot.sessionName)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(Color.forge)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.forge.opacity(0.10))
                .clipShape(Capsule())
                .opacity(animateHeader ? 1.0 : 0.0)
        }
        .padding(.top, 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                animateHeader = true
            }
            showConfetti = true
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            triggerNotificationFeedback(.success)
        }
    }

    // Best-match historique (GhostData). nil = 1ère séance de ce type, pas d'overlap.
    private var volumeDelta: (String, Color)? {
        guard let prev = snapshot.previousVolume, prev > 0 else { return nil }
        let pct = (totalVolume - prev) / prev * 100
        if pct >= 1 { return ("▲ +\(Int(pct.rounded()))%", Color.forge) }
        if pct <= -1 { return ("▼ \(Int(abs(pct).rounded()))%", Color.gray) }
        return nil
    }

    private var volumeSubtitle: String? {
        volumeDelta != nil ? "vs record" : nil
    }

    // MARK: - Stats 3-col (durée · vol · RPE) — StatCard partagé
    private var statsRow: some View {
        let vDelta = volumeDelta
        let vSub = volumeSubtitle
        return HStack(spacing: 10) {
            StatCard(value: "\(Int(snapshot.durationMin))", label: "min", color: .appTextPrimary)
            StatCard(value: totalVolumeCompact, label: "vol", color: .appTextPrimary, subtitle: vSub, delta: vDelta)
            StatCard(value: String(format: "%.1f", snapshot.rpe), label: "rpe", color: rpeColor(snapshot.rpe))
        }
    }

    // MARK: - Liste exos restylée (fond card, hairline separators, summary compact)
    private var exercisesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(snapshot.exercises.enumerated()), id: \.0) { idx, name in
                exerciseRow(name: name, result: snapshot.logResults[name])
                if idx < snapshot.exercises.count - 1 {
                    Divider()
                        .background(Color.appSeparatorSubtle)
                        .padding(.leading, 16)
                }
            }
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func exerciseRow(name: String, result: ExerciseLogResult?) -> some View {
        let done = result != nil
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.appBody).fontWeight(done ? .semibold : .regular)
                    .foregroundColor(done ? .appTextPrimary : .gray)
                if let r = result {
                    Text(setsSummary(r))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.gray)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.statusGreen)
            } else {
                Text("ignoré")
                    .font(.appCaption)
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // "3×5 · 80kg" — reprend le rendu compact du design.
    // ponytail: rendu time/unilatéral fin = Lot C ; ici on affiche "count×firstReps",
    // ce qui donne "3×L+R" pour l'unilatéral — moche mais rien de perdu.
    private func setsSummary(_ r: ExerciseLogResult) -> String {
        guard !r.sets.isEmpty else {
            return r.reps.isEmpty ? "—" : r.reps
        }
        let count = r.sets.count
        let firstReps = (r.sets.first?["reps"] as? String) ?? "—"
        if r.weight > 0 {
            return "\(count)×\(firstReps) · \(UnitSettings.shared.format(r.weight))"
        }
        return "\(count)×\(firstReps)"
    }

    // MARK: - Énergie (ligne discrète, plus le gros card)
    private var energyRow: some View {
        HStack(spacing: 10) {
            Text("Énergie avant")
                .font(.appCaption).fontWeight(.semibold)
                .foregroundColor(.gray)
            Spacer()
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= snapshot.energyPre ? "bolt.fill" : "bolt")
                        .font(.system(size: 12))
                        .foregroundColor(i <= snapshot.energyPre ? energyColor(snapshot.energyPre) : .gray.opacity(0.25))
                }
            }
            Text(energyLabel(snapshot.energyPre))
                .font(.appCaption).fontWeight(.semibold)
                .foregroundColor(energyColor(snapshot.energyPre))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Notes (inchangé structurellement, restylé card)
    private var notesBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text")
                .font(.appBody)
                .foregroundColor(.gray)
                .padding(.top, 2)
            Text(snapshot.comment)
                .font(.appBody)
                .foregroundColor(Color.appOnSurface.opacity(0.85))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - CTA principal + partage secondaire
    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: { dismiss() }) {
                Text("Terminé")
                    .font(.appBody).fontWeight(.bold)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.forge)
                    .foregroundColor(Color.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(SpringButtonStyle())

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary.opacity(0.7))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.appSeparatorSubtle, lineWidth: 1)
                    )
            }
            .buttonStyle(SpringButtonStyle())
        }
    }

    // MARK: - Helpers couleurs / labels
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
                    .font(.appCaption).foregroundColor(Color.appOnSurface.opacity(0.65))
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
                        .font(.appCaption).fontWeight(.semibold)
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
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background((timer.isRunning ? timerColor : Color.statusCyan).opacity(0.12))
                .cornerRadius(6)
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
