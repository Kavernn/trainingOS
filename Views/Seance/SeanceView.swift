import SwiftUI
import Combine
import Charts

struct SeanceView: View {
    @StateObject private var vm = SeanceViewModel()
    @ObservedObject private var timer = RestTimerManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(.orange)
                } else if let data = vm.seanceData {
                    seanceContent(data: data)
                } else if let err = vm.error {
                    ErrorView(message: err) { Task { await vm.load() } }
                }
            }
            .navigationTitle("Séance")
            .navigationBarTitleDisplayMode(.inline)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if timer.isVisible {
                FloatingRestTimerCard()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: timer.isVisible)
            }
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func seanceContent(data: SeanceData) -> some View {
        if data.alreadyLogged {
            AlreadyLoggedSeanceView(data: data, vm: vm)
        } else if data.today == "Yoga / Tai Chi" || data.today == "Recovery" {
            SpecialSeanceView(sessionType: data.today, vm: vm)
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
    @State private var postWorkoutBrief: String? = nil
    @State private var isLoadingBrief = false

    var todaySession: SessionEntry? {
        APIService.shared.dashboard?.sessions[data.todayDate]
    }

    var sessionColor: Color {
        switch data.today {
        case "Push A", "Push B":           return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                       return .yellow
        case "Yoga / Tai Chi":             return .purple
        case "Recovery":                   return .green
        default:                           return .gray
        }
    }

    var tomorrowType: String {
        // Calendar.current (Gregorian): Sun=1, Mon=2, …, Sat=7
        let weekday = Calendar.current.component(.weekday, from: Date())
        let todayIdx = (weekday + 5) % 7   // 0=Lun … 6=Dim
        let tomorrowIdx = (todayIdx + 1) % 7
        let keys = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        return data.schedule[keys[tomorrowIdx]] ?? "Repos"
    }

    var tomorrowColor: Color {
        switch tomorrowType {
        case "Push A", "Push B":           return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                       return .yellow
        case "Yoga / Tai Chi":             return .purple
        case "Recovery":                   return .green
        default:                           return .gray
        }
    }

    var tomorrowExercises: [(String, String)] {
        guard let program = data.fullProgram[tomorrowType] else { return [] }
        // On ajoute .value ici pour transformer le SafeString en String
        return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        ZStack {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Header ──────────────────────────────────────────────
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.15))
                            .frame(width: 72, height: 72)
                            .scaleEffect(animateHeader ? 1.0 : 0.5)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                            .scaleEffect(animateHeader ? 1.0 : 0.3)
                            .opacity(animateHeader ? 1.0 : 0.0)
                    }
                    Text("Séance complétée")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(animateHeader ? 1.0 : 0.0)
                        .offset(y: animateHeader ? 0 : 12)
                    Text(data.today)
                        .font(.system(size: 13, weight: .semibold))
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
                    Task { await loadPostWorkoutBrief() }
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
                                    Text("RPE")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(1)
                                        .foregroundColor(.gray)
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
                                        .font(.system(size: 9, weight: .bold))
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
                                    HStack {
                                        Circle()
                                            .fill(sessionColor.opacity(0.3))
                                            .frame(width: 5, height: 5)
                                        Text(exo)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.85))
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    Divider().background(Color.white.opacity(0.04))
                                }
                            }
                        }

                        // Comment
                        if let comment = session.comment, !comment.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "quote.bubble")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                Text(comment)
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                    .italic()
                                Spacer()
                            }
                        }
                    } else {
                        Text("Données non disponibles")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }
                .padding(16)
                .background(Color(hex: "11111c"))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── Bilan IA ─────────────────────────────────────────────
                if isLoadingBrief {
                    HStack(spacing: 10) {
                        ProgressView().tint(.purple)
                        Text("Analyse en cours…")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(hex: "11111c"))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.2), lineWidth: 1))
                    .padding(.horizontal, 16)
                } else if let brief = postWorkoutBrief {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.purple)
                            Text("BILAN IA")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.purple.opacity(0.8))
                        }
                        Text(brief)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(Color(hex: "11111c"))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.2), lineWidth: 1))
                    .padding(.horizontal, 16)
                }

                // ── Aperçu demain ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("DEMAIN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(tomorrowType)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(tomorrowColor)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(tomorrowColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if tomorrowExercises.isEmpty {
                        Text(tomorrowType == "Repos" ? "Journée de repos 🛌" : "Aucun exercice défini")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(tomorrowExercises.prefix(5), id: \.0) { name, scheme in
                                HStack {
                                    Circle()
                                        .fill(tomorrowColor.opacity(0.25))
                                        .frame(width: 5, height: 5)
                                    Text(name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.75))
                                    Spacer()
                                    Text(scheme)
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 6)
                                Divider().background(Color.white.opacity(0.04))
                            }
                            if tomorrowExercises.count > 5 {
                                Text("+ \(tomorrowExercises.count - 5) exercices")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(hex: "11111c"))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(tomorrowColor.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── Partager la séance ─────────────────────────────────
                let shareText: String = {
                    var parts = ["💪 \(data.today) — TrainingOS"]
                    if let s = todaySession {
                        if let exos = s.exos { parts.append("\(exos.count) exercices : \(exos.prefix(3).joined(separator: ", "))\(exos.count > 3 ? "…" : "")") }
                        if let rpe = s.rpe { parts.append("RPE \(String(format: "%.1f", rpe))") }
                        if let dur = s.durationMin { parts.append("\(Int(dur)) min") }
                    }
                    return parts.joined(separator: "\n")
                }()
                ShareLink(item: shareText) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15))
                        Text("Partager la séance").font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(hex: "1c1c2e"))
                    .foregroundColor(.white.opacity(0.7))
                    .cornerRadius(14)
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Modifier la séance ─────────────────────────────────
                Button(action: { showEditSheet = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.circle.fill").font(.system(size: 18))
                        Text("Modifier la séance").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Reset aujourd'hui ───────────────────────────────────
                Button(action: { confirmReset = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16))
                        Text("Réinitialiser la séance")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Séance supplémentaire ────────────────────────────────
                Button(action: { showExtra = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Faire une séance supplémentaire")
                            .font(.system(size: 15, weight: .semibold))
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
    }

    private func loadPostWorkoutBrief() async {
        guard postWorkoutBrief == nil, !isLoadingBrief else { return }
        guard let session = todaySession else { return }
        isLoadingBrief = true
        defer { isLoadingBrief = false }
        let brief = try? await APIService.shared.fetchPostWorkoutBrief(
            sessionType: data.today,
            rpe: session.rpe,
            exos: session.exos ?? [],
            comment: session.comment,
            date: data.todayDate
        )
        postWorkoutBrief = brief
    }

    private func resetToday() async {
        try? await APIService.shared.deleteSession(date: data.todayDate)
        await vm.load()
    }

    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }
        if v <= 6 { return .yellow }
        if v <= 8 { return .orange }
        return .red
    }
}

// MARK: - Post Session Edit Sheet
struct PostSessionEditSheet: View {
    let data: SeanceData
    @ObservedObject var vm: SeanceViewModel
    @Environment(\.dismiss) private var dismiss

    struct ExerciseEdit {
        let name: String
        var weight: String
        var reps: String
        var rpe: Double
    }

    @State private var edits: [ExerciseEdit] = []
    @State private var isSaving = false
    @State private var saveError: String? = nil

    private var exoNames: [String] {
        let session = APIService.shared.dashboard?.sessions[data.todayDate]
        return session?.exos ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        if let err = saveError {
                            Text(err)
                                .font(.system(size: 12)).foregroundColor(.red)
                                .padding(.horizontal, 20)
                        }
                        ForEach(edits.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(edits[i].name)
                                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("POIDS (\(UnitSettings.shared.label.uppercased()))")
                                            .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                        TextField("0.0", text: $edits[i].weight)
                                            .keyboardType(.decimalPad)
                                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                            .padding(8).background(Color(hex: "191926")).cornerRadius(8)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("REPS")
                                            .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                        TextField("0", text: $edits[i].reps)
                                            .keyboardType(.numberPad)
                                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                            .padding(8).background(Color(hex: "191926")).cornerRadius(8)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("RPE").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.1f", edits[i].rpe))
                                            .font(.system(size: 13, weight: .black)).foregroundColor(.orange)
                                    }
                                    Slider(value: $edits[i].rpe, in: 1...10, step: 0.5).tint(.orange)
                                }
                            }
                            .padding(14).background(Color(hex: "11111c")).cornerRadius(12)
                            .padding(.horizontal, 16)
                        }

                        Button(action: save) {
                            HStack {
                                if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text(isSaving ? "Enregistrement…" : "Sauvegarder les modifications")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.blue).foregroundColor(.white).cornerRadius(14)
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
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
        .onAppear { buildEdits() }
    }

    private func buildEdits() {
        edits = exoNames.map { name in
            let entry = data.weights[name]?.history?.first
            let w = entry?.weight.map { UnitSettings.shared.display($0) } ?? 0.0
            let r = entry?.reps ?? ""
            return ExerciseEdit(name: name, weight: w > 0 ? String(format: "%.1f", w) : "", reps: r, rpe: 7.0)
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            for edit in edits {
                guard !edit.weight.isEmpty || !edit.reps.isEmpty else { continue }
                let w = Double(edit.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                do {
                    try await APIService.shared.logExercise(
                        exercise: edit.name, weight: UnitSettings.shared.toStorage(w),
                        reps: edit.reps, rpe: edit.rpe, force: true)
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
    @State private var showExitAlert = false
    @State private var showFinishFromExit = false
    @State private var exitRpe: Double = 7
    @State private var exitComment: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Group {
                    if data.today == "Yoga / Tai Chi" || data.today == "Recovery" {
                        SpecialSeanceView(sessionType: data.today, vm: extraVM)
                    } else {
                        WorkoutSeanceView(data: data, vm: extraVM, isBonusSession: true)
                    }
                }
            }
            .navigationTitle("Séance supplémentaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") {
                        if !extraVM.showSuccess && !extraVM.logResults.isEmpty {
                            showExitAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.orange)
                }
            }
            .alert("Séance en cours", isPresented: $showExitAlert) {
                Button("Sauvegarder") { showFinishFromExit = true }
                Button("Abandonner", role: .destructive) {
                    extraVM.logResults = [:]
                    dismiss()
                }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Tu as \(extraVM.logResults.count) exercice(s) loggé(s) non sauvegardés.")
            }
            .sheet(isPresented: $showFinishFromExit) {
                FinishSessionSheet(
                    exercises: Array(extraVM.logResults.keys),
                    logResults: extraVM.logResults,
                    elapsedMin: Date().timeIntervalSince(extraVM.sessionStart) / 60,
                    rpe: $exitRpe,
                    comment: $exitComment,
                    onSubmit: { energy in
                        let dur = Date().timeIntervalSince(extraVM.sessionStart) / 60
                        Task { await extraVM.finish(rpe: exitRpe, comment: exitComment, durationMin: dur, energyPre: energy, bonusSession: true) }
                    }
                )
            }
            .onChange(of: extraVM.showSuccess) { success in
                guard success else { return }
                showFinishFromExit = false
                dismiss()
            }
        }
    }
}

// MARK: - Workout Seance (Upper/Lower)
struct GhostData {
    let date: String
    let volume: Double
    let rpe: Double?
    let sets: Int?
}

struct SessionRecapSnapshot {
    let sessionName: String
    let durationMin: Double
    let logResults: [String: ExerciseLogResult]
    let exercises: [String]
    let rpe: Double
    let comment: String
    let energyPre: Int
}

struct WorkoutSeanceView: View {
    let data: SeanceData
    @ObservedObject var vm: SeanceViewModel
    var isSecondSession: Bool = false
    var isBonusSession: Bool = false
    @State private var rpe: Double = 7
    @State private var comment = ""
    @State private var showFinish = false
    @State private var showFinishConfirm = false
    @State private var showSummary = false
    @State private var ghostData: GhostData? = nil
    @State private var showGhost = true
    @State private var ghostBeaten = false
    
    // Programme edit
    @State private var localProgram: [String: String] = [:]
    @State private var exerciseOrder: [String] = []
    @State private var inventoryTypes: [String: String] = [:]
    @State private var inventoryTracking: [String: String] = [:]
    @State private var inventoryRest: [String: Int] = [:]
    @State private var inventoryHints: [String: String] = [:]
    @State private var sessionSupersets: [String: SupersetEntry] = [:]
    @State private var draggingName: String?
    @State private var dragOffset: CGFloat = 0
    @State private var cardHeights: [String: CGFloat] = [:]
    @State private var inventory: [String] = []
    @State private var addTarget: SeanceName?
    @State private var editTarget: ExerciseTarget?
    @State private var isEditMode = false
    @State private var orderSaveError = false
    @State private var expandedExercise: String? = nil
    @ObservedObject private var timer = RestTimerManager.shared
    @Environment(\.scenePhase) private var scenePhase

    // Progression
    @State private var showProgressionSheet = false
    @State private var progressionSuggestions: [ProgressionSuggestion] = []

    // Session recap
    @State private var showRecap = false
    @State private var recapSnapshot: SessionRecapSnapshot? = nil
    @State private var didLoadPreCoaching = false

    // Energy pre-session
    @State private var energyPre: Int = 3
    @State private var showEnergyPreSheet = false
    @AppStorage("energy_pre_date") private var energyPreDate = ""

    // Optional add-ons
    @State private var showAddCardio = false
    @State private var showAddHIIT   = false
    @State private var cardioCount   = 0
    @State private var hiitCount     = 0
    @State private var lastScrollY: CGFloat? = nil
    
    /// Moyenne des RPE par exercice loggés — fallback 7 si aucun
    private var computedSessionRPE: Double {
        let vals = vm.logResults.values.compactMap(\.rpe)
        guard !vals.isEmpty else { return 7.0 }
        return (vals.reduce(0, +) / Double(vals.count) * 2).rounded() / 2  // arrondi au 0.5
    }

    private var exercises: [(String, String)] {
        let ordered = exerciseOrder.filter { localProgram[$0] != nil }
        let extra   = localProgram.keys.filter { !exerciseOrder.contains($0) }.sorted()
        return (ordered + extra).compactMap { name -> (String, String)? in
            guard let scheme = localProgram[name] else { return nil }
            return (name, scheme)
        }
    }
    private var currentVolume: Double {
        vm.logResults.values.reduce(0.0) { acc, r in
            let s = r.reps.trimmingCharacters(in: .whitespaces).lowercased()
            let reps: Double
            if s.contains(",") {
                reps = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
            } else if let rx = s.range(of: "x"),
                      let sets = Double(s[s.startIndex..<rx.lowerBound]),
                      let rep  = Double(s[rx.upperBound...]) {
                reps = sets * rep
            } else {
                reps = Double(s) ?? 0
            }
            return acc + r.weight * reps
        }
    }

    private struct GhostSnapshot: Codable {
        let sessions: [String: SessionEntry]
    }

    private func computeGhost() {
        if CacheService.shared.load(for: "stats_data") == nil {
            Task { try? await APIService.shared.fetchStatsData(); computeGhost() }
            return
        }
        guard let cached  = CacheService.shared.load(for: "stats_data"),
              let snap    = try? JSONDecoder().decode(GhostSnapshot.self, from: cached)
        else { return }
        let currentExos = Set(localProgram.keys.map { $0.lowercased() })
        guard !currentExos.isEmpty else { return }

        let best = snap.sessions
            .filter { $0.key != data.todayDate && ($0.value.sessionVolume ?? 0) > 0 }
            .compactMap { date, s -> (String, SessionEntry)? in
                guard let exos = s.exos else { return nil }
                let overlap = currentExos.intersection(Set(exos.map { $0.lowercased() })).count
                guard Double(overlap) / Double(min(currentExos.count, exos.count)) >= 0.5 else { return nil }
                return (date, s)
            }
            .max { ($0.1.sessionVolume ?? 0) < ($1.1.sessionVolume ?? 0) }

        if let (date, s) = best, let vol = s.sessionVolume {
            ghostData = GhostData(date: date, volume: vol, rpe: s.rpe, sets: s.totalSets)
        }
    }

    @ViewBuilder private var sessionSummaryTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VUE RÉSUMÉ")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("\(vm.logResults.count)/\(exercises.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(vm.logResults.count == exercises.count ? .green : .orange)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            ForEach(exercises, id: \.0) { name, scheme in
                let r = vm.logResults[name]
                HStack(spacing: 10) {
                    Image(systemName: r != nil ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(r != nil ? .green : .gray.opacity(0.3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 13, weight: r != nil ? .semibold : .regular))
                            .foregroundColor(r != nil ? .white : .gray)
                        Text(scheme).font(.system(size: 10)).foregroundColor(.gray)
                    }
                    Spacer()
                    if let r = r {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(UnitSettings.shared.format(r.weight))
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.orange)
                            Text(r.reps).font(.system(size: 10)).foregroundColor(.gray)
                        }
                    } else {
                        Text("—").font(.system(size: 12)).foregroundColor(.gray.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
            }
        }
        .background(Color(hex: "11111c")).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var exerciseSection: some View {
        if showSummary {
            sessionSummaryTable
        } else if isEditMode {
            VStack(spacing: 0) {
                ForEach(exercises, id: \.0) { name, scheme in
                    editModeRow(name: name, scheme: scheme)
                }
                Button { addTarget = SeanceName(id: data.today) } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundColor(.orange)
                        Text("Ajouter un exercice")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(hex: "11111c"))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 8) {
                ForEach(exerciseRenderItems) { item in
                    renderExerciseItem(item)
                }
            }
            .onPreferenceChange(CardHeightKey.self) { cardHeights.merge($0) { $1 } }

            if orderSaveError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text("Ordre non sauvegardé — réessaie").font(.system(size: 12)).foregroundColor(.red)
                    Spacer()
                    Button { orderSaveError = false } label: {
                        Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func editModeRow(name: String, scheme: String) -> some View {
        HStack(spacing: 12) {
            Button { Task { await deleteExercise(name) } } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22)).foregroundColor(.red)
            }
            Button {
                editTarget = ExerciseTarget(seance: data.today, exercise: name, scheme: scheme)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 14)).foregroundColor(.white)
                        Text(scheme).font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 13)).foregroundColor(.orange.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: "11111c"))
        Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 16)
    }

    // MARK: - Superset render model

    private enum ExerciseRenderItem: Identifiable {
        case superset(id: String, group: String, entry: SupersetEntry, schemeA: String, schemeB: String, nextName: String?)
        case solo(name: String, scheme: String, next: String?)
        var id: String {
            switch self {
            case .superset(let id, _, _, _, _, _): return id
            case .solo(let name, _, _): return name
            }
        }
    }

    private var exerciseRenderItems: [ExerciseRenderItem] {
        guard !sessionSupersets.isEmpty else {
            let exs = exercises
            return exs.enumerated().map { idx, pair in
                .solo(name: pair.0, scheme: pair.1, next: idx + 1 < exs.count ? exs[idx + 1].0 : nil)
            }
        }
        var ssLookup: [String: (group: String, entry: SupersetEntry)] = [:]
        for (group, entry) in sessionSupersets {
            ssLookup[entry.a] = (group, entry)
            ssLookup[entry.b] = (group, entry)
        }
        var rendered = Set<String>()
        var items: [ExerciseRenderItem] = []
        let exs = exercises
        for (idx, pair) in exs.enumerated() {
            let name = pair.0
            guard !rendered.contains(name) else { continue }
            if let ss = ssLookup[name], ss.entry.a == name {
                let bName = ss.entry.b
                let schemeB = exs.first(where: { $0.0 == bName })?.1 ?? ""
                let bIdx = exs.firstIndex(where: { $0.0 == bName }) ?? idx
                let nextAfterB = bIdx + 1 < exs.count ? exs[bIdx + 1].0 : nil
                items.append(.superset(id: "ss_\(ss.group)", group: ss.group, entry: ss.entry,
                                       schemeA: pair.1, schemeB: schemeB, nextName: nextAfterB))
                rendered.insert(name)
                rendered.insert(bName)
            } else {
                let next = idx + 1 < exs.count ? exs[idx + 1].0 : nil
                items.append(.solo(name: name, scheme: pair.1, next: next))
                rendered.insert(name)
            }
        }
        return items
    }

    @ViewBuilder
    private func renderExerciseItem(_ item: ExerciseRenderItem) -> some View {
        switch item {
        case .superset(_, let group, let entry, let schemeA, let schemeB, let nextName):
            supersetBlock(group: group, entry: entry, schemeA: schemeA, schemeB: schemeB, nextName: nextName)
        case .solo(let name, let scheme, let next):
            draggableCard(name: name, scheme: scheme, nextExerciseName: next)
        }
    }

    @ViewBuilder
    private func supersetBlock(group: String, entry: SupersetEntry, schemeA: String, schemeB: String, nextName: String?) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(group)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                Text("Superset")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text("\(entry.rest ?? 120) s repos")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)

            draggableCard(name: entry.a, scheme: schemeA, nextExerciseName: nil, forceNoRest: true)

            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10))
                Text("enchaîner")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.orange.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .center)

            draggableCard(name: entry.b, scheme: schemeB, nextExerciseName: nextName,
                          restOverride: entry.rest ?? 120)
        }
    }

    @ViewBuilder
    private func draggableCard(name: String, scheme: String, nextExerciseName: String? = nil,
                               forceNoRest: Bool = false, restOverride: Int? = nil) -> some View {
        let isDragging = draggingName == name
        let shift = shiftY(for: name)
        let card = ExerciseCard(
            name: name,
            scheme: scheme,
            weightData: data.weights[name],
            equipmentType: equipmentType(for: name),
            trackingType: trackingType(for: name),
            bodyWeight: APIService.shared.dashboard?.profile.weight ?? 0,
            isSecondSession: isSecondSession,
            isBonusSession: isBonusSession,
            restSeconds: forceNoRest ? nil : (restOverride ?? restSeconds(for: name)),
            prescription: data.prescriptions?[name],
            suggestion: data.exerciseSuggestions?[name],
            hint: inventoryHints[name],
            logResult: $vm.logResults[name],
            onLogged: nil,
            isExpanded: expandedExercise == name,
            onToggle: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    expandedExercise = expandedExercise == name ? nil : name
                }
            },
            nextExerciseName: nextExerciseName
        )
        card
            .padding(.horizontal, 16)
            .background(GeometryReader { geo in
                Color.clear.preference(key: CardHeightKey.self, value: [name: geo.size.height])
            })
            .overlay(alignment: .topLeading) {
                // Gesture is restricted to the drag handle area so ScrollView can scroll freely
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.leading, 16)
                    .gesture(dragGesture(for: name))
            }
            .scaleEffect(isDragging ? 1.03 : 1.0, anchor: .center)
            .shadow(color: isDragging ? .black.opacity(0.45) : .clear, radius: isDragging ? 18 : 0)
            .offset(y: isDragging ? dragOffset : shift)
            .zIndex(isDragging ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: shift)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: isDragging)
    }

    private func dragGesture(for name: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if draggingName == nil {
                        draggingName = name
                        triggerImpact(style: .medium)
                    }
                    dragOffset = drag.translation.height
                default:
                    break
                }
            }
            .onEnded { _ in
                if let dragging = draggingName {
                    let to = proposedDropIndex
                    if let from = exerciseOrder.firstIndex(of: dragging), from != to {
                        withAnimation(.spring(response: 0.28)) {
                            exerciseOrder.move(fromOffsets: IndexSet(integer: from),
                                               toOffset: to > from ? to + 1 : to)
                        }
                        let newOrder = exerciseOrder
                        Task { await saveOrder(newOrder) }
                    }
                }
                withAnimation(.spring(response: 0.28)) {
                    draggingName = nil
                    dragOffset   = 0
                }
            }
    }

    // MARK: - Drag helpers

    private var proposedDropIndex: Int {
        guard let name = draggingName,
              let fromIdx = exerciseOrder.firstIndex(of: name) else { return 0 }
        let slotH = (cardHeights[name] ?? 200) + 12
        let steps = Int((dragOffset / slotH).rounded())
        return max(0, min(exerciseOrder.count - 1, fromIdx + steps))
    }

    private func shiftY(for cardName: String) -> CGFloat {
        guard let dragging = draggingName, dragging != cardName,
              let from = exerciseOrder.firstIndex(of: dragging),
              let idx  = exerciseOrder.firstIndex(of: cardName) else { return 0 }
        let to = proposedDropIndex
        let h  = (cardHeights[dragging] ?? 200) + 12
        if from < to, idx > from, idx <= to { return -h }
        if from > to, idx >= to,  idx < from { return  h }
        return 0
    }
    
    @ViewBuilder private var optionalAddonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPTIONNEL")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 10) {
                Button(action: { showAddCardio = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: cardioCount > 0 ? "plus.circle.fill" : "figure.run")
                            .font(.system(size: 14))
                        Text(cardioCount > 0 ? "Cardio ×\(cardioCount) — Ajouter +" : "Ajouter Cardio")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(cardioCount > 0 ? Color.green.opacity(0.12) : Color(hex: "11111c"))
                    .foregroundColor(cardioCount > 0 ? .green : .blue)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        cardioCount > 0 ? Color.green.opacity(0.3) : Color.blue.opacity(0.2), lineWidth: 1))
                }

                Button(action: { showAddHIIT = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: hiitCount > 0 ? "plus.circle.fill" : "bolt.fill")
                            .font(.system(size: 14))
                        Text(hiitCount > 0 ? "HIIT ×\(hiitCount) — Ajouter +" : "Ajouter HIIT")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(hiitCount > 0 ? Color.green.opacity(0.12) : Color(hex: "11111c"))
                    .foregroundColor(hiitCount > 0 ? .green : .red)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        hiitCount > 0 ? Color.green.opacity(0.3) : Color.red.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.today.uppercased())
                                .font(.system(size: 13, weight: .black))
                                .tracking(3)
                                .foregroundColor(.orange)
                            Text("Semaine \(data.week)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        TimelineView(.periodic(from: vm.sessionStart, by: 60)) { ctx in
                            let elapsed = Int(ctx.date.timeIntervalSince(vm.sessionStart) / 60)
                            HStack(spacing: 3) {
                                Image(systemName: "clock").font(.system(size: 10))
                                Text("\(elapsed) min")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.cyan.opacity(0.75))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.08))
                            .cornerRadius(6)
                        }
                        Button {
                            withAnimation { showSummary.toggle() }
                        } label: {
                            Image(systemName: showSummary ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                                .font(.system(size: 20))
                                .foregroundColor(showSummary ? .cyan : .cyan.opacity(0.5))
                        }
                        .padding(.leading, 8)
                        Button {
                            withAnimation { isEditMode.toggle() }
                        } label: {
                            Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                                .font(.system(size: 20))
                                .foregroundColor(isEditMode ? .green : .orange)
                        }
                        .padding(.leading, 8)
                    }
                    // Progress
                    let done = vm.logResults.count
                    let total = exercises.count
                    HStack {
                        Text(done == total && total > 0 ? "Tous les exercices loggés ✓" : "\(done) / \(total) exercices")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(done == total && total > 0 ? .green : .gray)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)
                        .overlay(
                            GeometryReader { g in
                                let fraction: CGFloat = total > 0 ? CGFloat(done) / CGFloat(total) : 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(done == total && total > 0 ? Color.green : Color.orange)
                                    .frame(width: g.size.width * fraction)
                                    .animation(.spring(response: 0.5), value: done)
                            },
                            alignment: .leading
                        )

                    // Énergie inline — remplace la modal bloquante
                    HStack(spacing: 6) {
                        Text("ÉNERGIE")
                            .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        ForEach(1...5, id: \.self) { val in
                            Button {
                                withAnimation { energyPre = val }
                                energyPreDate = data.todayDate
                            } label: {
                                Image(systemName: val <= energyPre ? "bolt.fill" : "bolt")
                                    .font(.system(size: 15))
                                    .foregroundColor(val <= energyPre ? .yellow : .gray.opacity(0.25))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        if energyPreDate == data.todayDate {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10)).foregroundColor(.green.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.yellow.opacity(0.04))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Resume banner — shown when exercises were already logged (partial prior session)
                if vm.isResuming {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.cyan)
                        Text("Continuer la séance — \(vm.logResults.count) exercice(s) déjà loggué(s)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }

                // Ghost mode banner
                if showGhost, let ghost = ghostData {
                    GhostBanner(
                        ghost: ghost,
                        currentVolume: currentVolume,
                        beaten: ghostBeaten,
                        onDismiss: { withAnimation { showGhost = false } }
                    )
                    .padding(.horizontal, 16)
                    .onChange(of: currentVolume) {
                        if !ghostBeaten && currentVolume >= ghost.volume {
                            ghostBeaten = true
                        }
                    }
                }

                // Volume cumulé temps réel
                if !vm.logResults.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 12)).foregroundColor(.orange)
                        Text("Volume total")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(currentVolume)) \(UnitSettings.shared.label)")
                            .font(.system(size: 14, weight: .black)).foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.07))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.4), value: currentVolume)
                }

                exerciseSection

                optionalAddonsSection

                // Live RPE — visible dès qu'un exercice est loggé
                if !vm.logResults.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 14))
                            .foregroundColor(rpeColor(computedSessionRPE))
                        Text("RPE séance")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.1f", computedSessionRPE))
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(rpeColor(computedSessionRPE))
                        Text("/ 10")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(rpeColor(computedSessionRPE).opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }

                Button(action: { showFinish = true }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Terminer la séance").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .padding(.bottom, timer.isVisible ? 90 : 0)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("workoutScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "workoutScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            guard let last = lastScrollY else { lastScrollY = offset; return }
            if abs(offset - last) > 4, timer.isVisible {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    timer.isVisible = false
                }
            }
            lastScrollY = offset
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showFinish) {
            FinishSessionSheet(
                exercises: exercises.map(\.0),
                logResults: vm.logResults,
                elapsedMin: Date().timeIntervalSince(vm.sessionStart) / 60,
                rpe: $rpe,
                comment: $comment,
                preEnergy: energyPre,
                onSubmit: { _ in
                    let dur = Date().timeIntervalSince(vm.sessionStart) / 60
                    recapSnapshot = SessionRecapSnapshot(
                        sessionName: data.today,
                        durationMin: dur,
                        logResults: vm.logResults,
                        exercises: exercises.map(\.0),
                        rpe: rpe,
                        comment: comment,
                        energyPre: energyPre
                    )
                    Task { await vm.finish(rpe: rpe, comment: comment, durationMin: dur, energyPre: energyPre, sessionName: data.today, bonusSession: isBonusSession) }
                }
            )
            .presentationDetents([.medium, .large])
            .onAppear { rpe = computedSessionRPE }
        }
        .onChange(of: vm.showSuccess) { success in
            guard success else { return }
            triggerNotificationFeedback(.success)
            vm.showSuccess = false
            showRecap = true
        }
        .sheet(isPresented: $showRecap, onDismiss: {
            Task {
                let sType = isSecondSession ? "evening" : "morning"
                let todayStr = data.todayDate
                if let suggestions = try? await APIService.shared.fetchProgressionSuggestions(
                    date: todayStr, sessionType: sType, sessionName: data.today
                ), !suggestions.filter({ $0.suggestionType != "maintain" }).isEmpty {
                    progressionSuggestions = suggestions
                    showProgressionSheet = true
                } else {
                    await vm.load()
                }
            }
        }) {
            if let snap = recapSnapshot {
                SessionRecapSheet(snapshot: snap)
            }
        }
        .sheet(isPresented: $showProgressionSheet) {
            ProgressionSuggestionsSheet(
                suggestions: progressionSuggestions,
                sessionName: data.today
            ) {
                showProgressionSheet = false
                Task { await vm.load() }
            }
        }
        .alert("Erreur", isPresented: Binding(
            get: { vm.submitError != nil },
            set: { if !$0 { vm.submitError = nil } }
        )) {
            Button("OK") { vm.submitError = nil }
        } message: {
            Text(vm.submitError ?? "")
        }
        .alert("Séance enregistrée ⚠️", isPresented: Binding(
            get: { vm.commitWarning != nil },
            set: { if !$0 { vm.commitWarning = nil } }
        )) {
            Button("OK") { vm.commitWarning = nil }
        } message: {
            Text(vm.commitWarning ?? "")
        }
        .sheet(item: $addTarget) { (sn: SeanceName) in
            AddExerciseSheet(seance: sn.id, inventory: inventory, inventorySchemes: [:]) { ex, scheme in
                Task { await addExercise(ex, scheme: scheme) }
            }
        }
        .sheet(item: $editTarget) { target in
            EditSchemeSheet(target: target) { newName, newScheme in
                Task { await editExercise(oldName: target.exercise, newName: newName, scheme: newScheme) }
            }
        }
        .sheet(isPresented: $showAddCardio) {
            AddCardioSheet { cardioCount += 1 }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddHIIT) {
            AddHIITSheet { hiitCount += 1 }
                .presentationDetents([.large])
        }
        .onAppear {
            Task { await loadInventory() }
            computeGhost()
            guard !didLoadPreCoaching else { return }
            didLoadPreCoaching = true
            Task {
                let sType = isSecondSession ? "evening" : "morning"
                if let sug = try? await APIService.shared.fetchProgressionSuggestions(
                    date: data.todayDate, sessionType: sType, sessionName: data.today
                ), !sug.filter({ $0.suggestionType != "maintain" }).isEmpty {
                    progressionSuggestions = sug
                    showProgressionSheet = true
                }
            }
        }
        .onChange(of: data.inventoryTypes) { fresh in
            if !fresh.isEmpty { inventoryTypes = fresh }
        }
        .onChange(of: data.inventoryTracking) { fresh in
            if !fresh.isEmpty { inventoryTracking = fresh }
        }
        .onChange(of: data.inventoryRest) { fresh in
            inventoryRest = fresh
        }
        .onChange(of: data.inventoryHints) { fresh in
            if !fresh.isEmpty { inventoryHints = fresh }
        }
    }
    
    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }; if v <= 6 { return .yellow }; if v <= 8 { return .orange }; return .red
    }

    // Lookup equipment type with fuzzy name matching.
    // Handles e.g. program "Deadlift" matching inventory "Barbell Deadlift".
    private func equipmentType(for name: String) -> String {
        let types = inventoryTypes.isEmpty ? data.inventoryTypes : inventoryTypes
        return types[name] ?? "machine"
    }

    private func trackingType(for name: String) -> String {
        let tracking = inventoryTracking.isEmpty ? data.inventoryTracking : inventoryTracking
        return tracking[name] ?? "reps"
    }

    private func restSeconds(for name: String) -> Int? {
        let rest = inventoryRest.isEmpty ? data.inventoryRest : inventoryRest
        return rest[name]
    }

    // MARK: - Programme mutations
    
    private func loadInventory() async {
        // Seed immediately from already-loaded seanceData
        let fromCache  = data.fullProgram[data.today]?.mapValues { $0.value } ?? [:]
        let orderCache = data.exerciseOrder[data.today] ?? fromCache.keys.sorted()
        await MainActor.run {
            self.localProgram   = fromCache
            self.exerciseOrder  = orderCache
            self.inventoryTypes    = data.inventoryTypes
            self.inventoryTracking = data.inventoryTracking
            self.inventoryRest     = data.inventoryRest
            self.inventoryHints    = data.inventoryHints
            self.sessionSupersets  = data.exerciseSupersets[data.today] ?? [:]
        }

        // Fetch fresh programme + inventory types from network
        guard let url = URL(string: "\(APIService.shared.baseURL)/api/programme_data"),
              let (networkData, _) = try? await URLSession.authed.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: networkData) as? [String: Any]
        else { return }

        let inv         = (json["inventory"] as? [String]) ?? []
        let fromNetwork = (json["full_program"] as? [String: [String: String]])?[data.today]
        let orderNet    = (json["exercise_order"] as? [String: [String]])?[data.today]
        let types    = (json["inventory_types"] as? [String: String]) ?? [:]
        let tracking = (json["inventory_tracking"] as? [String: String]) ?? [:]
        let rest     = (json["inventory_rest"] as? [String: Int]) ?? [:]
        await MainActor.run {
            self.inventory = inv
            if !types.isEmpty    { self.inventoryTypes    = types }
            if !tracking.isEmpty { self.inventoryTracking = tracking }
            self.inventoryRest = rest
            if let fresh = fromNetwork {
                self.localProgram  = fresh
                self.exerciseOrder = orderNet ?? self.exerciseOrder
            }
        }
    }
        
        @discardableResult
        private func postProgramme(_ body: [String: Any]) async -> Bool {
            guard let url = URL(string: "\(APIService.shared.baseURL)/api/programme") else { return false }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                let (_, resp) = try await URLSession.authed.data(for: req)
                return (resp as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }

        private func saveOrder(_ order: [String]) async {
            guard order.count >= localProgram.count else { return }
            let ok = await postProgramme(["action": "reorder", "jour": data.today, "ordre": order])
            if !ok {
                await MainActor.run { orderSaveError = true }
            }
        }

        private func addExercise(_ name: String, scheme: String) async {
            await postProgramme(["action": "add", "jour": data.today, "exercise": name, "scheme": scheme, "block_type": "strength"])
            await MainActor.run { localProgram[name] = scheme }
        }
        
        private func deleteExercise(_ name: String) async {
            // Local-only: remove from this session view without touching the database
            await MainActor.run { localProgram.removeValue(forKey: name) }
        }
        
        private func editExercise(oldName: String, newName: String, scheme: String) async {
            if oldName != newName {
                // rename synce tous les jours du programme + inventaire
                await postProgramme(["action": "rename", "jour": data.today, "old_exercise": oldName, "new_exercise": newName])
                await postProgramme(["action": "scheme", "jour": data.today, "exercise": newName, "scheme": scheme])
                await MainActor.run {
                    localProgram.removeValue(forKey: oldName)
                    localProgram[newName] = scheme
                }
            } else {
                await postProgramme(["action": "scheme", "jour": data.today, "exercise": oldName, "scheme": scheme])
                await MainActor.run { localProgram[oldName] = scheme }
            }
        }
}

// MARK: - Ghost Banner
struct GhostBanner: View {
    let ghost: GhostData
    let currentVolume: Double
    let beaten: Bool
    var onDismiss: () -> Void

    private var progress: Double {
        guard ghost.volume > 0 else { return 0 }
        return min(currentVolume / ghost.volume, 1.0)
    }

    private func shortDate(_ s: String) -> String {
        String(s.suffix(5))  // MM-DD
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("👻")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("GHOST · \(shortDate(ghost.date))")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    HStack(spacing: 6) {
                        Text(beaten ? "Battu ! 🔥" : "\(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(beaten ? .orange : .white)
                        if let rpe = ghost.rpe {
                            Text("RPE \(String(format: "%.1f", rpe))")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                        if let sets = ghost.sets {
                            Text("\(sets) sets")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                    Capsule()
                        .fill(beaten
                            ? LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * progress, height: 5)
                        .animation(.spring(response: 0.5), value: progress)
                }
            }
            .frame(height: 5)

            HStack {
                Text(currentVolume > 0
                    ? "\(UnitSettings.shared.display(currentVolume), specifier: "%.0f") / \(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)"
                    : "Commence à logger pour suivre ta progression")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(beaten ? .orange : .purple)
            }
        }
        .padding(12)
        .background(Color(hex: "0e0e1c"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            beaten ? Color.orange.opacity(0.5) : Color.purple.opacity(0.25), lineWidth: 1
        ))
    }
}

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

    private var hasUnsavedData: Bool { !durationMin.isEmpty || !notes.isEmpty || rpe != 7 }

    private let types = ["Course", "Vélo", "Natation", "Elliptique", "Rameur", "Marche", "Autre"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
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
                                            .background(cardioType == t ? Color.blue.opacity(0.2) : Color(hex: "191926"))
                                            .foregroundColor(cardioType == t ? .blue : .gray)
                                            .cornerRadius(8)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                }
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Durée + Distance
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DURÉE (MIN)").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("30", text: $durationMin).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DISTANCE (KM)").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $distanceKm).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // RPE
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 18, weight: .black)).foregroundColor(rpeColor(rpe))
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(rpeColor(rpe))
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes...", text: $notes, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.white).tint(.blue)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        Button(action: submit) {
                            HStack {
                                if isLogging { ProgressView().tint(.white) }
                                else { Image(systemName: "checkmark.circle.fill") }
                                Text("Enregistrer Cardio").font(.system(size: 15, weight: .semibold))
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
            }
        }
    }

    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }; if v <= 6 { return .yellow }; if v <= 8 { return .orange }; return .red
    }

    private func submit() {
        isLogging = true
        Task {
            try? await APIService.shared.logCardio(
                type: cardioType,
                durationMin: Double(durationMin.replacingOccurrences(of: ",", with: ".")),
                distanceKm: Double(distanceKm.replacingOccurrences(of: ",", with: ".")),
                avgPace: nil, avgHr: nil, cadence: nil, calories: nil,
                rpe: rpe, notes: notes
            )
            await MainActor.run { isLogging = false; onDone(); dismiss() }
        }
    }
}

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

    @AppStorage("hiit_templates") private var templatesData: String = "[]"

    private var templates: [HIITTemplate] {
        (try? JSONDecoder().decode([HIITTemplate].self, from: Data(templatesData.utf8))) ?? []
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
                Color(hex: "080810").ignoresSafeArea()
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
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.red)
                                                Button {
                                                    saveTemplates(templates.filter { $0.id != t.id })
                                                } label: {
                                                    Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.gray)
                                                }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color(hex: "1c1c2e")).cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding(14).background(Color(hex: "11111c")).cornerRadius(14)
                        }

                        // Session type
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TYPE DE SESSION").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("HIIT", text: $sessionType)
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Rounds / Work / Rest
                        HStack(spacing: 10) {
                            ForEach([("RONDES", $rounds), ("TRAVAIL (s)", $workTime), ("REPOS (s)", $restTime)], id: \.0) { label, binding in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                    TextField("—", text: binding).keyboardType(.numberPad)
                                        .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                                }
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // RPE
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 18, weight: .black)).foregroundColor(rpeColor(rpe))
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(rpeColor(rpe))
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes...", text: $notes, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.white).tint(.red)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Save template button
                        Button {
                            templateName = sessionType.isEmpty ? "HIIT" : sessionType
                            showSavePrompt = true
                        } label: {
                            Label("Sauvegarder comme template", systemImage: "bookmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color(hex: "1c1c2e")).cornerRadius(10)
                        }

                        Button(action: submit) {
                            HStack {
                                if isLogging { ProgressView().tint(.white) }
                                else { Image(systemName: "bolt.fill") }
                                Text("Enregistrer HIIT").font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.red).foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isLogging)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("HIIT").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
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
        }
    }

    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }; if v <= 6 { return .yellow }; if v <= 8 { return .orange }; return .red
    }

    private func submit() {
        isLogging = true
        Task {
            try? await APIService.shared.logHIIT(
                sessionType: sessionType.isEmpty ? "HIIT" : sessionType,
                rounds:     Int(rounds)   ?? 10,
                workTime:   Int(workTime) ?? 20,
                restTime:   Int(restTime) ?? 10,
                rpe:        rpe,
                notes:      notes,
                secondSession: true
            )
            await MainActor.run { isLogging = false; onDone(); dismiss() }
        }
    }
}


    // MARK: - Summary Sheet (confirmation before commit)
    struct WorkoutSummarySheet: View {
        let exercises: [String]
        let logResults: [String: ExerciseLogResult]
        var onConfirm: () -> Void
        @Environment(\.dismiss) private var dismiss

        var loggedExercises: [(String, ExerciseLogResult)] {
            exercises.compactMap { name in
                guard let r = logResults[name] else { return nil }
                return (name, r)
            }
        }
        var unloggedExercises: [String] {
            exercises.filter { logResults[$0] == nil }
        }

        var body: some View {
            NavigationStack {
                ZStack {
                    Color(hex: "080810").ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 16) {
                            // Header
                            VStack(spacing: 6) {
                                Image(systemName: loggedExercises.count == exercises.count
                                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(loggedExercises.count == exercises.count ? .green : .orange)
                                Text("Récapitulatif")
                                    .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                                Text("\(loggedExercises.count) / \(exercises.count) exercices loggués")
                                    .font(.system(size: 14)).foregroundColor(.gray)
                            }
                            .padding(.top, 20)

                            // Logged exercises
                            if !loggedExercises.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("LOGGUÉS")
                                        .font(.system(size: 10, weight: .bold)).tracking(2)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 16).padding(.bottom, 8)
                                    VStack(spacing: 0) {
                                        ForEach(loggedExercises, id: \.0) { name, result in
                                            HStack {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.green)
                                                Text(name)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Text("\(String(format: "%.0f", result.weight))lbs · \(result.reps)")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.gray)
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            if name != loggedExercises.last?.0 {
                                                Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 16)
                                            }
                                        }
                                    }
                                    .background(Color(hex: "11111c")).cornerRadius(14)
                                    .padding(.horizontal, 20)
                                }
                            }

                            // Unlogged exercises warning
                            if !unloggedExercises.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("NON LOGGUÉS")
                                        .font(.system(size: 10, weight: .bold)).tracking(2)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 16).padding(.bottom, 8)
                                    VStack(spacing: 0) {
                                        ForEach(unloggedExercises, id: \.self) { name in
                                            HStack {
                                                Image(systemName: "minus.circle")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.orange.opacity(0.7))
                                                Text(name)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.gray)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            if name != unloggedExercises.last {
                                                Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 16)
                                            }
                                        }
                                    }
                                    .background(Color(hex: "11111c")).cornerRadius(14)
                                    .padding(.horizontal, 20)
                                }
                            }

                            // CTA
                            VStack(spacing: 10) {
                                Button(action: {
                                    dismiss()
                                    onConfirm()
                                }) {
                                    Text(loggedExercises.isEmpty
                                         ? "Terminer sans exercices"
                                         : "Confirmer et logger ces \(loggedExercises.count) exercice(s)")
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                                        .background(loggedExercises.isEmpty ? Color.gray.opacity(0.3) : Color.orange)
                                        .foregroundColor(.white).cornerRadius(14)
                                }
                                .padding(.horizontal, 20)

                                Button("Continuer la séance", action: { dismiss() })
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .padding(.bottom, 32)
                        }
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
        var preEnergy: Int? = nil          // pre-filled from EnergyPreWorkoutSheet (nil = show picker)
        var onSubmit: (Int?) -> Void
        @Environment(\.dismiss) private var dismiss

        @State private var energyPre: Int = 3   // 1–5, used only when preEnergy == nil
        @State private var confirmDiscard = false
        @State private var aiAnalysis: String? = nil
        @State private var isLoadingAI = false

        private var hasUnsavedData: Bool { !comment.isEmpty || energyPre != 3 }

        var loggedCount: Int { logResults.count }
        
        var body: some View {
            NavigationStack {
                ZStack {
                    Color(hex: "080810").ignoresSafeArea()
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
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)

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
                            .background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)

                            // Énergie pré-séance — affichage si pré-rempli, saisie sinon
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
                                .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)
                            } else {
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
                                .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)
                            }
                            
                            // RPE — pré-rempli depuis la moyenne des RPE par exercice
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("RPE SÉANCE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Text("Moy. RPE exercices")
                                            .font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
                                    }
                                    Spacer()
                                    Text("\(rpe, specifier: "%.1f")").font(.system(size: 24, weight: .black)).foregroundColor(.orange)
                                }
                                Slider(value: $rpe, in: 1...10, step: 0.5).tint(.orange)
                            }
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)
                            
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
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)

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

                            // Soumission partielle — visible si des exercices ne sont pas loggués
                            if loggedCount < exercises.count && loggedCount > 0 {
                                Button(action: {
                                    onSubmit(preEnergy ?? energyPre)
                                    dismiss()
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
                                onSubmit(preEnergy ?? energyPre)
                                dismiss()
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
                .onAppear { loadAIAnalysis() }
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
                    Color(hex: "080810").ignoresSafeArea()
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
                                .background(Color(hex: "11111c")).cornerRadius(14)
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
                            .background(Color(hex: "11111c")).cornerRadius(14)
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
                                .background(Color(hex: "11111c")).cornerRadius(14)

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
                                .background(Color(hex: "11111c")).cornerRadius(14)
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
                                .background(Color(hex: "11111c")).cornerRadius(14)
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

        private func rpeColor(_ v: Double) -> Color {
            switch v {
            case ..<5: return .green
            case ..<7: return .yellow
            case ..<9: return .orange
            default:   return .red
            }
        }

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
            .background(Color(hex: "080810"))
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
                    .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                        TextField("Notes optionnelles...", text: $notes, axis: .vertical)
                            .foregroundColor(.white).lineLimit(3, reservesSpace: true)
                    }
                    .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)
                    
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
        }
        
        private func logHIIT() {
            Task {
                try? await APIService.shared.logHIIT(
                    sessionType: sessionType, rounds: rounds,
                    workTime: workTime, restTime: restTime, rpe: rpe, notes: notes
                )
                await vm.load()
                await APIService.shared.fetchDashboard()
                vm.showSuccess = true
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
                            applied = true
                            triggerImpact(style: .light)
                            Task {
                                try? await APIService.shared.applyProgression(
                                    exerciseName: suggestion.exerciseName,
                                    suggestedWeight: w,
                                    suggestedScheme: suggestion.suggestedScheme
                                )
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
                        .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Comment c'était ?", text: $comment, axis: .vertical)
                                .foregroundColor(.white).tint(.orange)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)

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
            .padding(14).background(Color(hex: "11111c")).cornerRadius(12)
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
    





// MARK: - Confetti
private struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var color: Color
    var angle: Double
    var size: CGFloat
}

private struct ConfettiView: View {
    private let colors: [Color] = [.orange, .green, .cyan, .yellow, .pink, .purple]
    @State private var pieces: [ConfettiPiece] = []
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 0.5)
                        .position(x: p.x, y: animate ? geo.size.height + 40 : p.y)
                        .rotationEffect(.degrees(p.angle + (animate ? 360 : 0)))
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeIn(duration: Double.random(in: 1.4...2.4))
                            .delay(Double.random(in: 0...0.5)),
                            value: animate
                        )
                }
            }
            .onAppear {
                pieces = (0..<60).map { _ in
                    ConfettiPiece(
                        x: CGFloat.random(in: 0...geo.size.width),
                        y: CGFloat.random(in: -20...geo.size.height * 0.4),
                        color: colors.randomElement()!,
                        angle: Double.random(in: 0...360),
                        size: CGFloat.random(in: 6...12)
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    animate = true
                }
            }
        }
    }
}

// MARK: - Floating Rest Timer Card
struct FloatingRestTimerCard: View {
    @ObservedObject private var timer = RestTimerManager.shared

    private var ringColor: Color {
        if timer.progress > 0.6 { return .green }
        if timer.progress > 0.3 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 22) {
            if let name = timer.exerciseName {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            // Circular clock
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 18)
                    .frame(width: 200, height: 200)

                // Glow arc
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(ringColor.opacity(0.28), style: StrokeStyle(lineWidth: 28, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)
                    .blur(radius: 8)

                // Main arc
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)

                Text(formatTime(timer.remaining))
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            // Controls
            HStack(spacing: 28) {
                Button { timer.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.09))
                        .clipShape(Circle())
                }

                Button {
                    if timer.isRunning { timer.stop() } else { timer.resume() }
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 68, height: 68)
                        .background(ringColor)
                        .clipShape(Circle())
                        .shadow(color: ringColor.opacity(0.55), radius: 14, y: 5)
                }
                .animation(.easeInOut(duration: 0.25), value: timer.isRunning)

                // Close — stops and dismisses the timer completely
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        timer.dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 36)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(hex: "080810").opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(ringColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 32, x: 0, y: -8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

/// MARK: - Card Height Preference Key
private struct CardHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
