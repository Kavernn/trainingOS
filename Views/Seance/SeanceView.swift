import SwiftUI



struct SeanceView: View {
    @StateObject private var vm = SeanceViewModel(draftSessionType: "morning")

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if vm.isLoading {
                    AppLoadingView()
                } else if let data = vm.seanceData {
                    seanceContent(data: data)
                } else if let err = vm.error {
                    ErrorView(message: err) { Task { await vm.load() } }
                }
            }
            .navigationTitle("Séance")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .sessionCompleted)) { _ in
            ActionFeedbackManager.shared.show(.sessionComplete(streak: nil))
        }
    }

    @ViewBuilder
    private func seanceContent(data: SeanceData) -> some View {
        if data.alreadyLogged {
            AlreadyLoggedSeanceView(data: data, vm: vm)
        } else if data.today == "Yoga / Tai Chi" || data.today == "Recovery" {
            SpecialSeanceView(sessionType: data.today, vm: vm)
        } else if (data.fullProgram[data.today] ?? [:]).isEmpty {
            NoProgramEmptyState()
        } else {
            WorkoutSeanceView(data: data, vm: vm)
        }
    }
}

// MARK: - Already Logged → Recap + Tomorrow Preview + Extra
struct AlreadyLoggedSeanceView: View {
    let data: SeanceData
    @ObservedObject var vm: SeanceViewModel
    @State private var showExtra = false
    @State private var showEditSheet = false
    @State private var confirmReset = false
    @State private var animateHeader = false
    @State private var showConfetti = false
    @State private var showFinishRemaining = false
    @State private var showSeanceSoir = false
    @State private var seance2Count: Int = 0
    @State private var todayWeekday: Int = {
        let localSecs = Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()
        return ((localSecs / 86400 + 4) % 7) + 1  // Jan 1 1970 = Thu = weekday 5
    }()

    var todaySession: SessionEntry? {
        APIService.shared.dashboard?.sessions[data.todayDate]
    }

    var unloggedExercises: [(String, String)] {
        guard let program = data.fullProgram[data.today] else { return [] }
        let order = data.exerciseOrder[data.today] ?? program.keys.sorted()
        return order.compactMap { name -> (String, String)? in
            guard let scheme = program[name] else { return nil }
            let loggedToday = data.weights[name]?.history?.first?.date == data.todayDate
            return loggedToday ? nil : (name, scheme.value)
        }
    }

    var sessionColor: Color {
        switch data.today {
        case "Push A", "Push B":           return .statusOrange
        case "Pull A", "Pull B + Full Body": return .statusCyan
        case "Legs":                       return .statusYellow
        case "Yoga / Tai Chi":             return .statusPurple
        case "Recovery":                   return .statusGreen
        default:                           return .gray
        }
    }

    var tomorrowType: String {
        // Calendar.current (Gregorian): Sun=1, Mon=2, …, Sat=7
        let weekday = todayWeekday
        let todayIdx = (weekday + 5) % 7   // 0=Lun … 6=Dim
        let tomorrowIdx = (todayIdx + 1) % 7
        return data.schedule[TrainingDoctrine.dayNames[tomorrowIdx]] ?? "Repos"
    }

    var tomorrowColor: Color {
        switch tomorrowType {
        case "Push A", "Push B":           return .statusOrange
        case "Pull A", "Pull B + Full Body": return .statusCyan
        case "Legs":                       return .statusYellow
        case "Yoga / Tai Chi":             return .statusPurple
        case "Recovery":                   return .statusGreen
        default:                           return .gray
        }
    }

    var tomorrowExercises: [(String, String)] {
        guard let program = data.fullProgram[tomorrowType] else { return [] }
        let order = data.exerciseOrder[tomorrowType] ?? program.keys.sorted()
        return order.compactMap { name in
            guard let scheme = program[name] else { return nil }
            return (name, scheme.value)
        }
    }
    var body: some View {
        ZStack {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Header ──────────────────────────────────────────────
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.statusGreen.opacity(0.15))
                            .frame(width: 72, height: 72)
                            .scaleEffect(animateHeader ? 1.0 : 0.5)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.statusGreen)
                            .scaleEffect(animateHeader ? 1.0 : 0.3)
                            .opacity(animateHeader ? 1.0 : 0.0)
                    }
                    Text("Séance complétée")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.appOnBackground)
                        .opacity(animateHeader ? 1.0 : 0.0)
                        .offset(y: animateHeader ? 0 : 12)
                    Text(data.today)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(sessionColor)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(sessionColor.opacity(0.12))
                        .clipShape(Capsule())
                        .opacity(animateHeader ? 1.0 : 0.0)
                }
                .padding(.top, 24)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                        animateHeader = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showConfetti = true
                    }
                }

                // ── Recap aujourd'hui ────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text("RÉCAP D'AUJOURD'HUI")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.gray)

                    if let session = todaySession {
                        // RPE + stats row
                        HStack(spacing: 12) {
                            if let rpe = session.rpe {
                                VStack(spacing: 3) {
                                    Text(String(format: "%.1f", rpe))
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(rpeColor(rpe))
                                    HStack(spacing: 3) {
                                        Text("RPE")
                                            .font(.appMicro.weight(.bold))
                                            .tracking(1)
                                            .foregroundColor(.gray)
                                        CardInfoButton(title: "RPE & RIR", entries: InfoEntry.rpeRirEntries)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(rpeColor(rpe).opacity(0.08))
                                .cornerRadius(10)
                            }
                            if let exos = session.exos {
                                VStack(spacing: 3) {
                                    Text("\(exos.count)")
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(sessionColor)
                                    Text("EXOS")
                                        .font(.appMicro.weight(.bold))
                                        .tracking(1)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(sessionColor.opacity(0.08))
                                .cornerRadius(10)
                            }
                        }

                        // Exercise list
                        if let exos = session.exos, !exos.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(exos, id: \.self) { exo in
                                    let entry = data.weights[exo]?.history?.first(where: { $0.date == data.todayDate })
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(sessionColor.opacity(0.3))
                                            .frame(width: 5, height: 5)
                                        Text(exo)
                                            .font(.appLabel)
                                            .foregroundColor(Color.appOnSurface.opacity(0.85))
                                        Spacer()
                                        if let w = entry?.weight, w > 0 {
                                            Text(UnitSettings.shared.format(w))
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(sessionColor.opacity(0.8))
                                        }
                                        if let r = entry?.reps, !r.isEmpty {
                                            Text(r)
                                                .font(.appCaption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    Divider().background(Color.appSeparatorSubtle)
                                }
                            }
                        }

                        // Comment
                        if let comment = session.comment, !comment.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "quote.bubble")
                                    .font(.system(size: 12))
                                    .foregroundColor(.statusBlue)
                                Text(comment)
                                    .font(.appLabel)
                                    .foregroundColor(.gray)
                                    .italic()
                                Spacer()
                            }
                        }
                    } else {
                        Text("Données non disponibles")
                            .font(.appLabel)
                            .foregroundColor(.gray)
                    }
                }
                .padding(16)
                .background(Color.appCard)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.statusGreen.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── Aperçu demain ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("DEMAIN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(tomorrowType)
                            .font(.appLabel.weight(.bold))
                            .foregroundColor(tomorrowColor)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(tomorrowColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if tomorrowExercises.isEmpty {
                        Text(tomorrowType == "Repos" ? "Journée de repos 🛌" : "Aucun exercice défini")
                            .font(.appLabel)
                            .foregroundColor(.gray)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(tomorrowExercises.prefix(5), id: \.0) { name, scheme in
                                HStack {
                                    Circle()
                                        .fill(tomorrowColor.opacity(0.25))
                                        .frame(width: 5, height: 5)
                                    Text(name)
                                        .font(.appLabel)
                                        .foregroundColor(Color.appOnSurface.opacity(0.75))
                                    Spacer()
                                    Text(scheme)
                                        .font(.appCaption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 6)
                                Divider().background(Color.appSeparatorSubtle)
                            }
                            if tomorrowExercises.count > 5 {
                                Text("+ \(tomorrowExercises.count - 5) exercices")
                                    .font(.appCaption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.appCard)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(tomorrowColor.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── Partager la séance ─────────────────────────────────
                let shareText: String = {
                    let u = UnitSettings.shared
                    var lines: [String] = []

                    // Header
                    var header = "💪 \(data.today)"
                    if let s = todaySession {
                        var meta: [String] = []
                        if let dur = s.durationMin { meta.append("\(Int(dur)) min") }
                        if let rpe = s.rpe { meta.append("RPE \(String(format: "%.1f", rpe))") }
                        if !meta.isEmpty { header += " · " + meta.joined(separator: " · ") }
                    }
                    lines.append(header)
                    lines.append("")

                    // Per-exercise detail
                    if let exos = todaySession?.exos {
                        for exo in exos {
                            let entry = data.weights[exo]?.history?.first(where: { $0.date == data.todayDate })
                                     ?? data.weights[exo]?.history?.first
                            if let e = entry, let w = e.weight, let r = e.reps {
                                let oneRM = e.oneRM.map { "  🏆 1RM \(u.format($0))" } ?? ""
                                lines.append("• \(exo): \(u.format(w)) · \(r)\(oneRM)")
                            } else {
                                lines.append("• \(exo)")
                            }
                        }
                        lines.append("")
                    }

                    // Volume summary
                    if let s = todaySession {
                        var stats: [String] = []
                        if let vol = s.sessionVolume, vol > 0 { stats.append("Volume: \(u.format(vol))") }
                        if let sets = s.totalSets { stats.append("\(sets) sets") }
                        if let reps = s.totalReps { stats.append("\(reps) reps") }
                        if !stats.isEmpty { lines.append("📊 " + stats.joined(separator: " · ")) }
                    }

                    lines.append("\nTrainingOS 🏋️")
                    return lines.joined(separator: "\n")
                }()
                ShareLink(item: shareText) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.appBody)
                        Text("Partager la séance").font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.appCard)
                    .foregroundColor(Color.appOnSurface.opacity(0.7))
                    .cornerRadius(14)
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Modifier la séance ─────────────────────────────────
                Button(action: { showEditSheet = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.circle.fill").font(.system(size: 18))
                        Text("Modifier la séance").font(.appBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.statusBlue.opacity(0.12))
                    .foregroundColor(.statusBlue)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusBlue.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Reset aujourd'hui ───────────────────────────────────
                Button(action: { confirmReset = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16))
                        Text("Réinitialiser la séance")
                            .font(.appBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.statusRed.opacity(0.12))
                    .foregroundColor(.statusRed)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusRed.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Exercices non loggés ─────────────────────────────────
                if !unloggedExercises.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.appLabel)
                                .foregroundColor(.statusYellow)
                            Text("\(unloggedExercises.count) exercice\(unloggedExercises.count > 1 ? "s" : "") non loggé\(unloggedExercises.count > 1 ? "s" : "")")
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.appOnBackground)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(unloggedExercises.prefix(3), id: \.0) { ex in
                                HStack(spacing: 6) {
                                    Circle().fill(Color.statusYellow.opacity(0.4)).frame(width: 4, height: 4)
                                    Text(ex.0)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.appOnSurface.opacity(0.7))
                                }
                            }
                            if unloggedExercises.count > 3 {
                                Text("+ \(unloggedExercises.count - 3) autre\(unloggedExercises.count - 3 > 1 ? "s" : "")…")
                                    .font(.appCaption)
                                    .foregroundColor(.gray)
                            }
                        }
                        Button(action: { showFinishRemaining = true }) {
                            Text("Finir la séance")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.statusYellow.opacity(0.18))
                                .foregroundColor(.statusYellow)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.statusYellow.opacity(0.35), lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .background(Color.statusYellow.opacity(0.07))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusYellow.opacity(0.2), lineWidth: 1))
                    .padding(.horizontal, 16)
                }

                // ── CTA Séance 2 (P2.B.4) — visible si exos envoyés à la Séance 2 ──
                if seance2Count > 0 {
                    Button { showSeanceSoir = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "2.circle.fill")
                                .font(.appLabel)
                            Text("Séance 2 (\(seance2Count) exo\(seance2Count > 1 ? "s" : "")) →")
                                .font(.appLabel).fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.forge.opacity(0.12))
                        .foregroundColor(Color.forge)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal, 16)
                }

                // ── Séance supplémentaire ────────────────────────────────
                Button(action: { showExtra = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Faire une séance supplémentaire")
                            .font(.appBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [sessionColor, sessionColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: sessionColor.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showFinishRemaining) {
            FinishRemainingSheet(data: data, remaining: unloggedExercises, sessionType: vm.draftSessionType) {
                await vm.load()
            }
        }
        .sheet(isPresented: $showSeanceSoir) {
            // nil = pas d'override → fetchSeanceSoirData() → plan evening seedé.
            // data.eveningSessionName est le nom seedé (get_today_evening), pas un
            // override utilisateur — le passer forçait le chemin matin (bug d26373c).
            SeanceSoirView()
        }
        .onChange(of: showSeanceSoir) { isPresented in
            if !isPresented {
                seance2Count = data.pushedToEvening.count
            }
        }
        .onAppear {
            seance2Count = data.pushedToEvening.count
        }
        .onReceive(NotificationCenter.default.publisher(for: .planOverridesDidChange)) { _ in
            // Étape 3b — refetch pour repopuler data.pushedToEvening depuis le backend.
            Task {
                await vm.load()
                seance2Count = data.pushedToEvening.count
            }
        }
        .sheet(isPresented: $showExtra) {
            ExtraSessionSheet(data: data)
        }
        .sheet(isPresented: $showEditSheet) {
            PostSessionEditSheet(data: data, vm: vm)
        }
        .confirmationDialog("Réinitialiser la séance d'aujourd'hui ?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Réinitialiser", role: .destructive) { Task { await resetToday() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les données loggées aujourd'hui seront effacées.")
        }
        // Confetti overlay
        if showConfetti {
            ConfettiView()
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        showConfetti = false
                    }
                }
        }
        } // end ZStack
        .onAppear {
            Task { await vm.load() }
        }
    }

    private func resetToday() async {
        try? await APIService.shared.deleteSession(date: data.todayDate)
        await vm.load()
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }
}

// MARK: - Post Session Edit Sheet
struct PostSessionEditSheet: View {
    let data: SeanceData
    @ObservedObject var vm: SeanceViewModel
    @Environment(\.dismiss) private var dismiss

    struct SetEdit {
        var weight: String
        var reps: String
    }
    struct ExerciseEdit {
        let name: String
        let equipmentType: String
        var sets: [SetEdit]
        var rpe: Double
    }

    @State private var edits: [ExerciseEdit] = []
    @State private var isSaving = false
    @State private var saveError: String? = nil
    // W-D6 — snapshot for unsaved-changes detection on Annuler
    @State private var editsSnapshot: [ExerciseEdit] = []
    @State private var showDiscardConfirm = false

    private var exoNames: [String] {
        let session = APIService.shared.dashboard?.sessions[data.todayDate]
        return session?.exos ?? []
    }

    private func weightLabel(_ eq: String) -> String {
        let u = UnitSettings.shared.label.uppercased()
        switch eq {
        case "barbell":      return "PAR CÔTÉ (\(u))"
        case "dumbbell":     return "PAR HALTÈRE (\(u))"
        case "cable_double": return "PAR CÂBLE (\(u))"
        default:             return "POIDS (\(u))"
        }
    }

    private func displayWeight(_ stored: Double, eq: String) -> String {
        let perSide: Double
        switch eq {
        case "barbell":                  perSide = stored > 45 ? (stored - 45) / 2 : 0
        case "dumbbell", "cable_double": perSide = stored / 2
        default:                         perSide = stored
        }
        let display = UnitSettings.shared.display(perSide)
        return display > 0 ? String(format: "%.1f", display) : ""
    }

    private func storedWeight(_ input: Double, eq: String) -> Double {
        switch eq {
        case "barbell":                  return input * 2 + 45
        case "dumbbell", "cable_double": return input * 2
        default:                         return input
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(edits.indices, id: \.self) { i in
                            exerciseCard(index: i)
                        }

                        if let err = saveError {
                            Text(err)
                                .font(.system(size: 12)).foregroundColor(.statusRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }

                        Button(action: save) {
                            HStack {
                                if isSaving { ProgressView().tint(.onAccent).scaleEffect(0.8) }
                                Text(isSaving ? "Enregistrement…" : (saveError != nil ? "Réessayer" : "Sauvegarder les modifications"))
                                    .font(.appBody.weight(.bold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.statusBlue).foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isSaving)
                        .padding(.horizontal, 16).padding(.bottom, 24)
                    }
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Modifier la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // W-D6 — confirm discard if edits were made
                    Button("Annuler") {
                        if hasUnsavedEdits {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(Color.forge)
                }
            }
            .confirmationDialog("Abandonner les modifications ?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer à éditer", role: .cancel) {}
            }
        }
        .onAppear {
            buildEdits()
            // W-D6 — snapshot must be taken after buildEdits() populates edits
            DispatchQueue.main.async { editsSnapshot = edits }
        }
    }

    // W-D6 — detect if the user has modified anything since the sheet opened
    private var hasUnsavedEdits: Bool {
        guard edits.count == editsSnapshot.count else { return true }
        for (a, b) in zip(edits, editsSnapshot) {
            if a.sets.count != b.sets.count { return true }
            for (sa, sb) in zip(a.sets, b.sets) {
                if sa.weight != sb.weight || sa.reps != sb.reps { return true }
            }
            if a.rpe != b.rpe { return true }
        }
        return false
    }

    @ViewBuilder
    private func exerciseCard(index i: Int) -> some View {
        let eq = edits[i].equipmentType
        VStack(alignment: .leading, spacing: 10) {
            Text(edits[i].name)
                .font(.appLabel.weight(.bold)).foregroundColor(.appTextPrimary)

            HStack(spacing: 6) {
                Text("S#").font(.appMicro.weight(.bold)).foregroundColor(.clear)
                    .frame(width: 22)
                Text(weightLabel(eq))
                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                Spacer()
                Text("REPS")
                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    .frame(width: 60)
            }
            .padding(.horizontal, 2)

            ForEach(edits[i].sets.indices, id: \.self) { j in
                HStack(spacing: 6) {
                    Text("S\(j + 1)")
                        .font(.appCaption.weight(.bold)).foregroundColor(.gray)
                        .frame(width: 22)
                    TextField("0.0", text: $edits[i].sets[j].weight)
                        .keyboardType(.decimalPad)
                        .font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                        .padding(8).background(Color.appSurfaceInset).cornerRadius(8)
                    TextField("0", text: $edits[i].sets[j].reps)
                        .keyboardType(.numberPad)
                        .font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                        .padding(8).background(Color.appSurfaceInset).cornerRadius(8)
                        .frame(width: 60)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("RPE").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.1f", edits[i].rpe))
                        .font(.appLabel.weight(.black)).foregroundColor(Color.forge)
                }
                Slider(value: $edits[i].rpe, in: 1...10, step: 0.5).tint(Color.forge)
            }
        }
        .padding(14).background(Color.appCard).cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func buildEdits() {
        edits = exoNames.map { name in
            let eq = data.inventoryTypes[name] ?? "barbell"
            let entry = data.weights[name]?.history?.first
            let setEdits: [SetEdit]
            if let rawSets = entry?.sets, !rawSets.isEmpty {
                setEdits = rawSets.map { s in
                    SetEdit(weight: displayWeight(s.weight, eq: eq), reps: s.reps)
                }
            } else {
                let stored = entry?.weight ?? 0
                let repsStr = entry?.reps ?? ""
                let repParts = repsStr.split(separator: ",").map(String.init)
                if repParts.count > 1 {
                    setEdits = repParts.map { r in
                        SetEdit(weight: displayWeight(stored, eq: eq), reps: r.trimmingCharacters(in: .whitespaces))
                    }
                } else {
                    setEdits = [SetEdit(weight: displayWeight(stored, eq: eq), reps: repsStr)]
                }
            }
            return ExerciseEdit(name: name, equipmentType: eq, sets: setEdits, rpe: 7.0)
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            for edit in edits {
                let validSets = edit.sets.filter { !$0.weight.isEmpty || !$0.reps.isEmpty }
                guard !validSets.isEmpty else { continue }
                let setsPayload: [[String: Any]] = validSets.map { s in
                    let input = Double(s.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let stored = storedWeight(UnitSettings.shared.toStorage(input), eq: edit.equipmentType)
                    return ["weight": stored, "reps": s.reps]
                }
                let weights = setsPayload.compactMap { $0["weight"] as? Double }
                let avgStored = weights.isEmpty ? 0 : weights.reduce(0, +) / Double(weights.count)
                let repsStr = validSets.map(\.reps).joined(separator: ",")
                do {
                    try await APIService.shared.logExercise(
                        exercise: edit.name, weight: avgStored, reps: repsStr,
                        rpe: edit.rpe, sets: setsPayload, force: true,
                        equipmentType: edit.equipmentType)
                } catch {
                    await MainActor.run { saveError = "Erreur: \(error.localizedDescription)"; isSaving = false }
                    return
                }
            }
            await vm.load()
            await MainActor.run { isSaving = false; dismiss() }
        }
    }
}

// MARK: - Extra Session Sheet
struct ExtraSessionSheet: View {
    let data: SeanceData
    @StateObject private var extraVM = SeanceViewModel(draftSessionType: "bonus")
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSession: String? = nil
    @State private var bonusData: SeanceData? = nil
    @State private var isLoading = false
    @State private var loadError: String? = nil

    @State private var showFinishFromExit = false
    @State private var exitRpe: Double = 7
    @State private var exitComment: String = ""

    private var sessionList: [String] {
        let known  = TrainingDoctrine.canonicalSeanceOrder.filter { data.fullProgram[$0] != nil }
        let custom = data.fullProgram.keys.filter { !TrainingDoctrine.canonicalSeanceOrder.contains($0) }.sorted()
        return known + custom
    }

    private func sessionColor(_ s: String) -> Color {
        switch s {
        case "Push A", "Push B":             return .statusOrange
        case "Pull A", "Pull B + Full Body": return .statusCyan
        case "Legs":                         return .statusYellow
        case "Yoga / Tai Chi":               return .statusPurple
        case "Recovery":                     return .statusGreen
        default:                             return .statusBlue
        }
    }

    private func sessionIcon(_ s: String) -> String {
        switch s {
        case "Push A", "Push B":             return "arrow.up.circle.fill"
        case "Pull A", "Pull B + Full Body": return "arrow.down.circle.fill"
        case "Legs":                         return "figure.run"
        case "Yoga / Tai Chi":               return "figure.mind.and.body"
        case "Recovery":                     return "heart.fill"
        default:                             return "dumbbell.fill"
        }
    }

    private func pick(_ session: String) {
        selectedSession = session
        isLoading = true
        loadError = nil
        Task {
            do {
                let d = try await APIService.shared.fetchSeanceData(sessionName: session)
                await MainActor.run { bonusData = d; isLoading = false }
            } catch {
                await MainActor.run { loadError = error.localizedDescription; isLoading = false }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if let bonus = bonusData, let session = selectedSession {
                    Group {
                        if session == "Yoga / Tai Chi" || session == "Recovery" {
                            SpecialSeanceView(sessionType: session, vm: extraVM)
                        } else {
                            WorkoutSeanceView(data: bonus, vm: extraVM, isBonusSession: true, onDidFinish: { dismiss() })
                        }
                    }
                } else if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(Color.forge)
                        Text("Chargement…")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                } else {
                    sessionPickerBody
                }
            }
            .navigationTitle(selectedSession.map { "Séance — \($0)" } ?? "Séance supplémentaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(bonusData != nil ? "Retour" : "Fermer") {
                        if bonusData != nil {
                            if !extraVM.showSuccess && !extraVM.logResults.isEmpty {
                                showFinishFromExit = true
                            } else {
                                bonusData = nil
                                selectedSession = nil
                            }
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(Color.forge)
                }
            }
            .sheet(isPresented: $showFinishFromExit) {
                FinishSessionSheet(
                    exercises: Array(extraVM.logResults.keys),
                    logResults: extraVM.logResults,
                    elapsedMin: Double(extraVM.chrono.elapsedSeconds) / 60.0,
                    rpe: $exitRpe,
                    comment: $exitComment,
                    onSubmit: { energy in
                        let dur = Double(extraVM.chrono.stop())
                        Task { await extraVM.finish(rpe: exitRpe, comment: exitComment, durationMin: dur, energyPre: energy, bonusSession: true) }
                    }
                )
            }
            .onChange(of: extraVM.showSuccess) { success in
                guard success else { return }
                showFinishFromExit = false
                // Dismiss déferré : WorkoutSeanceView appelle onDidFinish après récap fermé
                // (fix race parent-dismiss vs child-showRecap → "not in window hierarchy").
            }
        }
    }

    private var sessionPickerBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("QUELLE SÉANCE ?")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if let err = loadError {
                    Text(err)
                        .font(.appLabel)
                        .foregroundColor(.statusRed)
                        .padding(.horizontal)
                }

                VStack(spacing: 1) {
                    ForEach(sessionList, id: \.self) { session in
                        let color = sessionColor(session)
                        let exoCount = data.fullProgram[session]?.count ?? 0
                        Button { pick(session) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: sessionIcon(session))
                                    .font(.system(size: 18))
                                    .foregroundColor(color)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.appTextPrimary)
                                    if exoCount > 0 {
                                        Text("\(exoCount) exercices")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.appLabel.weight(.semibold))
                                    .foregroundColor(Color.gray.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.appCard)
                        }
                    }
                }
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Finish Remaining Sheet
struct FinishRemainingSheet: View {
    let data: SeanceData
    let remaining: [(String, String)]
    var onDone: () async -> Void

    @StateObject private var finishVM: SeanceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showExitAlert = false
    @State private var exitRpe: Double = 7
    @State private var exitComment: String = ""
    @State private var showFinishFromExit = false
    @AppStorage("energy_pre_date") private var energyPreDate = ""
    @AppStorage("energy_pre_value") private var energyPreValue: Int = 3

    init(data: SeanceData, remaining: [(String, String)], sessionType: String = "morning", onDone: @escaping () async -> Void) {
        self.data = data
        self.remaining = remaining
        self.onDone = onDone
        _finishVM = StateObject(wrappedValue: SeanceViewModel(draftSessionType: sessionType))
    }

    private var loggedExercises: [(name: String, scheme: String, weight: Double?, reps: String?)] {
        guard let program = data.fullProgram[data.today] else { return [] }
        let order = data.exerciseOrder[data.today] ?? program.keys.sorted()
        let remainingNames = Set(remaining.map(\.0))
        return order.compactMap { name -> (String, String, Double?, String?)? in
            guard !remainingNames.contains(name), let scheme = program[name] else { return nil }
            let h = data.weights[name]?.history?.first
            guard h?.date == data.todayDate else { return nil }
            return (name, scheme.value, h?.weight, h?.reps)
        }
    }

    private var patchedData: SeanceData {
        var filteredProgram = data.fullProgram
        filteredProgram[data.today] = Dictionary(uniqueKeysWithValues: remaining.map { ($0.0, SafeString($0.1)) })
        var filteredOrder = data.exerciseOrder
        filteredOrder[data.today] = remaining.map(\.0)
        let remainingNames = Set(remaining.map(\.0))
        let todaySupersets = data.exerciseSupersets[data.today] ?? [:]
        let filteredSupersets = todaySupersets.filter { remainingNames.contains($0.value.a) && remainingNames.contains($0.value.b) }
        var patchedSupersets = data.exerciseSupersets
        patchedSupersets[data.today] = filteredSupersets
        return SeanceData(
            today: data.today, todayDate: data.todayDate, alreadyLogged: false,
            schedule: data.schedule, fullProgram: filteredProgram,
            weights: data.weights, week: data.week, mesocycle: data.mesocycle,
            inventoryTypes: data.inventoryTypes, inventoryTracking: data.inventoryTracking,
            inventoryUnilateral: data.inventoryUnilateral,
            inventoryRest: data.inventoryRest, inventoryHints: data.inventoryHints,
            exerciseOrder: filteredOrder, exerciseSupersets: patchedSupersets,
            prescriptions: data.prescriptions, exerciseSuggestions: data.exerciseSuggestions
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                WorkoutSeanceView(data: patchedData, vm: finishVM)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !loggedExercises.isEmpty {
                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("DÉJÀ LOGGÉS")
                                        .font(.appMicro.weight(.bold))
                                        .tracking(2)
                                        .foregroundColor(.gray)
                                    ForEach(loggedExercises, id: \.name) { ex in
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.appLabel)
                                                .foregroundColor(Color.statusGreen.opacity(0.7))
                                            Text(ex.name)
                                                .font(.appLabel)
                                                .foregroundColor(Color.appOnSurface.opacity(0.5))
                                            Spacer()
                                            if let w = ex.weight {
                                                Text(UnitSettings.shared.format(w))
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(Color.statusGreen.opacity(0.6))
                                            }
                                            if let r = ex.reps {
                                                Text("· \(r)")
                                                    .font(.appCaption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.appBg)
                                Divider().background(Color.appSeparator)
                            }
                        }
                    }
            }
            .onAppear { finishVM.seanceData = patchedData }
            .navigationTitle("Finir la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") {
                        if !finishVM.logResults.isEmpty {
                            showExitAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(Color.forge)
                }
            }
            .alert("Exercices non sauvegardés", isPresented: $showExitAlert) {
                Button("Sauvegarder") { showFinishFromExit = true }
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Tu as \(finishVM.logResults.count) exercice(s) loggé(s) non sauvegardés.")
            }
            .sheet(isPresented: $showFinishFromExit) {
                FinishSessionSheet(
                    exercises: remaining.map(\.0),
                    logResults: finishVM.logResults,
                    elapsedMin: Double(finishVM.chrono.elapsedSeconds) / 60.0,
                    rpe: $exitRpe, comment: $exitComment,
                    preEnergy: energyPreDate == data.todayDate ? energyPreValue : nil,
                    onSubmit: { energy in
                        let dur = Double(finishVM.chrono.stop())
                        Task { await finishVM.finish(rpe: exitRpe, comment: exitComment, durationMin: dur, energyPre: energy, sessionName: data.today) }
                    }
                )
            }
        }
        .onChange(of: finishVM.showSuccess) { success in
            guard success else { return }
            finishVM.showSuccess = false
            showFinishFromExit = false
            dismiss()
            Task { await onDone() }
        }
    }
}

// MARK: - Empty state shown when no program is configured for today

struct NoProgramEmptyState: View {
    @State private var showFreePicker = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.gray.opacity(0.35))
                    .padding(.bottom, 4)

                Text("Aucun programme pour aujourd'hui")
                    .font(.appHeadline)
                    .foregroundColor(.appOnBackground)
                    .multilineTextAlignment(.center)

                Text("Tu peux partir en séance libre ou créer un programme.")
                    .font(.appLabel)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button { showFreePicker = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.appBody.weight(.semibold))
                        Text("Séance libre")
                            .font(.appHeadline.weight(.bold))
                    }
                    .foregroundColor(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.forge)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)

                NavigationLink(destination: ProgrammeView()) {
                    Text("Créer mon programme")
                        .font(.appBody.weight(.medium))
                        .foregroundColor(Color.forge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.forge.opacity(0.1))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    AppState.shared.pendingDeepLink = "intelligence"
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14))
                        Text("Demander au Coach")
                            .font(.appBody.weight(.medium))
                    }
                    .foregroundColor(.statusPurple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.statusPurple.opacity(0.1))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusPurple.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showFreePicker) {
            FreeSessionPickerView()
        }
    }
}

// MARK: - Free session exercise picker

struct FreeSessionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [InventoryItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedNames: Set<String> = []
    @State private var showWorkout = false

    private let categories = ["push", "pull", "legs", "core", "mobility"]
    private let categoryLabels = [
        "push": "Poussée",
        "pull": "Tirage",
        "legs": "Jambes",
        "core": "Gainage",
        "mobility": "Mobilité",
    ]

    private var filtered: [InventoryItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return items }
        return items.filter { $0.name.lowercased().contains(q) }
    }

    private func exercises(for category: String) -> [InventoryItem] {
        filtered.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(Color.forge)
                } else {
                    exerciseList
                }
            }
            .navigationTitle("Séance libre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !selectedNames.isEmpty {
                        Button("Commencer (\(selectedNames.count))") { showWorkout = true }
                            .font(.appBody.weight(.bold))
                            .foregroundColor(Color.forge)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Chercher un exercice")
            .navigationDestination(isPresented: $showWorkout) {
                FreeWorkoutView(exerciseNames: Array(selectedNames).sorted())
            }
        }
        .task { await loadInventory() }
    }

    private var exerciseList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if !selectedNames.isEmpty {
                    selectedBar
                }
                ForEach(categories, id: \.self) { cat in
                    let exos = exercises(for: cat)
                    if !exos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text((categoryLabels[cat] ?? cat).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)
                            VStack(spacing: 0) {
                                ForEach(exos) { item in
                                    exerciseRow(item)
                                    if item.id != exos.last?.id {
                                        Divider()
                                            .background(Color.appSurfaceInset)
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                            .background(Color.appCard)
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    private var selectedBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedNames).sorted(), id: \.self) { name in
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.forge)
                            .lineLimit(1)
                        Button {
                            selectedNames.remove(name)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.appMicro.weight(.bold))
                                .foregroundColor(Color.forge.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.forge.opacity(0.12))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func exerciseRow(_ item: InventoryItem) -> some View {
        let selected = selectedNames.contains(item.name)
        return Button {
            triggerImpact(style: .light)
            if selected { selectedNames.remove(item.name) } else { selectedNames.insert(item.name) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.forge.opacity(0.15) : Color.appSurfaceInset)
                        .frame(width: 32, height: 32)
                    Image(systemName: selected ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selected ? Color.forge : .gray)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appTextPrimary)
                    Text(item.defaultScheme)
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.forge)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadInventory() async {
        guard let url = URL(string: "\(APIConfig.base)/api/inventory") else {
            isLoading = false; return
        }
        do {
            let (data, _) = try await URLSession.authed.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let inv = json["inventory"] as? [String: [String: Any]] {
                let parsed = inv.map { InventoryItem(name: $0.key, $0.value) }.sorted { $0.name < $1.name }
                await MainActor.run { items = parsed; isLoading = false }
            } else {
                await MainActor.run { isLoading = false }
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Lightweight free workout view

struct FreeWorkoutView: View {
    let exerciseNames: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var logResults: [String: ExerciseLogResult?] = [:]
    @State private var expandedIndex: Int? = 0

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(exerciseNames.indices, id: \.self) { i in
                        let name = exerciseNames[i]
                        ExerciseCard(
                            name: name,
                            scheme: "3x8-12",
                            weightData: nil,
                            logResult: Binding(
                                get: { logResults[name] ?? nil },
                                set: { logResults[name] = $0 }
                            ),
                            isExpanded: expandedIndex == i,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    expandedIndex = expandedIndex == i ? nil : i
                                }
                            }
                        )
                    }
                    Button {
                        triggerImpact(style: .medium)
                        dismiss()
                    } label: {
                        Text("Terminer la séance")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.forge)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Séance libre")
        .navigationBarTitleDisplayMode(.inline)
    }
}
