import SwiftUI

private let kBaseURL = APIConfig.base

private enum SessionType {
    case pushA, pushB, pullA, pullB, legs, yoga, recovery, custom

    init(_ name: String) {
        switch name {
        case "Push A":             self = .pushA
        case "Push B":             self = .pushB
        case "Pull A":             self = .pullA
        case "Pull B + Full Body": self = .pullB
        case "Legs":               self = .legs
        case "Yoga / Tai Chi":     self = .yoga
        case "Recovery":           self = .recovery
        default:                   self = .custom
        }
    }

    var color: Color {
        switch self {
        case .pushA, .pushB: return .statusOrange
        case .pullA, .pullB: return .statusCyan
        case .legs:          return .statusYellow
        case .yoga:          return .statusPurple
        case .recovery:      return .appSuccess
        case .custom:        return .gray
        }
    }
}

struct ProgrammeView: View {
    @State private var fullProgram: [String: [String: String]] = [:]
    @State private var exerciseOrder: [String: [String]] = [:]
    @State private var schedule: [String: String] = [:]
    @State private var eveningSchedule: [String: String] = [:]
    @State private var inventory: [String] = []
    @State private var inventorySchemes: [String: String] = [:]
    @State private var isLoading = true
    @State private var addTarget: SeanceName?
    @State private var editTarget: ExerciseTarget?
    @State private var showCreateSeance = false
    @State private var deleteSeanceTarget: String? = nil
    @State private var confirmDeleteSeance = false
    @AppStorage("programme_clipboard")      private var clipboardData: String = "{}"
    @AppStorage("programme_clipboard_name") private var clipboardName: String = ""
    @AppStorage("periodisation_start") private var periodisationStart: String = ""
    @State private var showResetMesocycle = false
    @State private var showApplyPhaseConfirm = false

    private var clipboard: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(clipboardData.utf8))) ?? [:]
    }
    private func copySeance(name: String, exercises: [String: String]) {
        if let d = try? JSONEncoder().encode(exercises), let s = String(data: d, encoding: .utf8) {
            clipboardData = s
            clipboardName = name
            triggerNotificationFeedback(.success)
        }
    }
    private func pasteSeance(into seance: String) {
        let pasted = clipboard
        guard !pasted.isEmpty else { return }
        var prog = fullProgram[seance] ?? [:]
        for (ex, scheme) in pasted { prog[ex] = scheme }
        fullProgram[seance] = prog
        clipboardData = "{}"
        clipboardName = ""
        Task {
            for (ex, scheme) in pasted {
                await addExercise(seance: seance, exercise: ex, scheme: scheme)
            }
        }
    }

    // MARK: - Périodisation
    private enum Phase: String {
        case hypertrophie = "Hypertrophie"
        case force        = "Force"
        case peak         = "Peak"
        case deload       = "Deload"
    }
    private var mesocycleWeek: Int {
        guard !periodisationStart.isEmpty,
              let start = DateFormatter.isoDate.date(from: periodisationStart) else { return 0 }
        let days = Int(Date().timeIntervalSince(start) / 86400)
        return max(1, days / 7 + 1)
    }
    private var currentPhase: Phase {
        let w = mesocycleWeek
        if w <= 4 { return .hypertrophie }
        if w <= 8 { return .force }
        if w <= 10 { return .peak }
        return .deload
    }
    private var phaseScheme: String {
        switch currentPhase {
        case .hypertrophie: return "3-4 × 8-12 reps — 65–75% 1RM"
        case .force:        return "4-5 × 4-6 reps — 80–90% 1RM"
        case .peak:         return "5 × 1-3 reps — 90–95% 1RM"
        case .deload:       return "3 × 10-12 reps — 50–60% 1RM"
        }
    }

    private var phaseShortScheme: String {
        switch currentPhase {
        case .hypertrophie: return "3x10"
        case .force:        return "4x5"
        case .peak:         return "5x2"
        case .deload:       return "3x12"
        }
    }

    private func applyPhaseScheme() async {
        let scheme = phaseShortScheme
        for (seance, exercises) in fullProgram {
            for exercise in exercises.keys {
                await editExercise(seance: seance, oldName: exercise, newName: exercise, scheme: scheme)
            }
        }
    }
    private var nextPhase: Phase {
        switch currentPhase {
        case .hypertrophie: return .force
        case .force:        return .peak
        case .peak:         return .deload
        case .deload:       return .hypertrophie
        }
    }
    private var phaseColor: Color {
        switch currentPhase {
        case .hypertrophie: return .statusOrange
        case .force:        return .appDanger
        case .peak:         return .statusYellow
        case .deload:       return .appSuccess
        }
    }

    @State private var exerciseWeights: [String: (weight: Double?, reps: String?, date: String?)] = [:]
    @State private var exerciseSupersets: [String: [String: SupersetEntry]] = [:]
    @State private var programSuggestions: [String: [String: ProgressionSuggestion]] = [:]
    @State private var mutationCount = 0
    @State private var lastSaveError = false

    // Session reorder
    @State private var sessionOrder: [String] = []
    @State private var apiSessionOrder: [String] = []
    @State private var draggingSession: String? = nil
    @State private var sessionDragY: CGFloat = 0
    @State private var sessionCardHeights: [String: CGFloat] = [:]

    private var proposedSessionDrop: Int {
        guard let name = draggingSession,
              let from = sessionOrder.firstIndex(of: name) else { return 0 }
        let h = sessionCardHeights[name] ?? 80
        let steps = Int((sessionDragY / h).rounded())
        return max(0, min(sessionOrder.count - 1, from + steps))
    }

    private func sessionShiftFor(_ name: String) -> CGFloat {
        guard let dr = draggingSession, dr != name,
              let from = sessionOrder.firstIndex(of: dr),
              let idx  = sessionOrder.firstIndex(of: name) else { return 0 }
        let to = proposedSessionDrop
        let h  = sessionCardHeights[dr] ?? 80
        if from < to, idx > from, idx <= to { return -h }
        if from > to, idx >= to,  idx < from { return  h }
        return 0
    }

    private func refreshSessionOrder() {
        let existing = Set(fullProgram.keys)
        let base = apiSessionOrder.isEmpty ? orderedSeances : apiSessionOrder
        var ordered = base.filter { existing.contains($0) }
        let missing = orderedSeances.filter { !ordered.contains($0) }
        ordered += missing
        sessionOrder = ordered
    }

    private func saveSessionOrder() {
        apiSessionOrder = sessionOrder
        let order = sessionOrder
        Task { await postProgramme(["action": "reorder_sessions", "order": order]) }
    }

    struct UndoDeleteItem {
        let seance: String
        let name: String
        let scheme: String
        let orderIndex: Int
    }
    @State private var undoDeleteItem: UndoDeleteItem? = nil
    @State private var undoDeleteTask: Task<Void, Never>? = nil
    @State private var saveSuccessMsg: String? = nil

    // Multi-programmes
    @State private var programs: [ProgramInfo] = []
    @State private var selectedProgramId: String = ""
    @State private var activeProgramId: String = ""
    @State private var isSettingActive = false
    @State private var allSessions: [String] = []         // toutes les sessions, tous programmes
    @State private var showCreateProgram = false
    @State private var newProgramName = ""
    @State private var renameProgramTarget: ProgramInfo? = nil
    @State private var renameProgramName = ""
    @State private var deleteProgramTarget: ProgramInfo? = nil
    @State private var confirmDeleteProgram = false

    private let dayNames    = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    private let seanceOrder = ["Push A", "Pull A", "Legs", "Push B", "Pull B + Full Body", "Yoga / Tai Chi", "Recovery"]

    // MARK: - Volume MEV/MAV
    private let muscleMEV: [String: Int] = ["Pecs": 10, "Dos": 10, "Épaules": 8, "Biceps": 6, "Triceps": 6, "Jambes": 8, "Fessiers": 6, "Core": 6]
    private let muscleMAV: [String: Int] = ["Pecs": 16, "Dos": 16, "Épaules": 14, "Biceps": 12, "Triceps": 12, "Jambes": 14, "Fessiers": 10, "Core": 12]

    private func muscleGroup(for exercise: String) -> String {
        let e = exercise.lowercased()
        if ["bench","fly","chest","dip","pec","incline"].contains(where: { e.contains($0) }) { return "Pecs" }
        if ["row","pulldown","pull-up","pull up","lat","deadlift","rdl","back"].contains(where: { e.contains($0) }) { return "Dos" }
        if ["squat","leg press","lunge","quad","hack"].contains(where: { e.contains($0) }) { return "Jambes" }
        if ["curl","bicep"].contains(where: { e.contains($0) }) { return "Biceps" }
        if ["tricep","pushdown","skull","extension"].contains(where: { e.contains($0) }) { return "Triceps" }
        if ["press","lateral","shoulder","delt","ohp"].contains(where: { e.contains($0) }) { return "Épaules" }
        if ["glute","hip thrust","fessier"].contains(where: { e.contains($0) }) { return "Fessiers" }
        if ["plank","core","ab","crunch"].contains(where: { e.contains($0) }) { return "Core" }
        return "Autre"
    }

    private func parseSets(from scheme: String) -> Int {
        guard let xRange = scheme.range(of: "x", options: .caseInsensitive) else { return 3 }
        let setsPart = String(scheme[scheme.startIndex..<xRange.lowerBound])
        return Int(setsPart.trimmingCharacters(in: .whitespaces)) ?? 3
    }

    private var weeklySessionFrequency: [String: Int] {
        var freq: [String: Int] = [:]
        for session in schedule.values where session != "Repos" {
            freq[session, default: 0] += 1
        }
        return freq
    }

    private var weeklyVolumeByMuscle: [String: Int] {
        let freq = weeklySessionFrequency
        var vol: [String: Int] = [:]
        for (seance, exercises) in fullProgram {
            let f = freq[seance] ?? 0
            guard f > 0 else { continue }
            for (exercise, scheme) in exercises {
                let muscle = muscleGroup(for: exercise)
                guard muscle != "Autre" else { continue }
                let sets = parseSets(from: scheme)
                vol[muscle, default: 0] += sets * f
            }
        }
        return vol
    }

    private var volumeAlerts: [String] {
        weeklyVolumeByMuscle.compactMap { muscle, sets in
            guard let mev = muscleMEV[muscle], sets < mev else { return nil }
            return "\(muscle) — \(sets)/\(mev) sets min."
        }.sorted()
    }

    private func isScheduledThisWeek(_ s: String) -> Bool {
        schedule.values.contains(s) || eveningSchedule.values.contains(s)
    }

    private var todaySessionName: String? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let idx = (weekday + 5) % 7  // 1=Sun → idx=6, 2=Mon → idx=0, …, 7=Sat → idx=5
        guard idx < dayNames.count else { return nil }
        let day = dayNames[idx]
        return schedule[day].flatMap { $0 == "Repos" ? nil : $0 }
    }

    private var activeProgrammeName: String {
        programs.first { $0.id == activeProgramId }?.name ?? ""
    }

    /// Known seances in canonical order, then any custom seances alphabetically.
    var orderedSeances: [String] {
        let known  = seanceOrder.filter { fullProgram[$0] != nil }
        let custom = fullProgram.keys.filter { !seanceOrder.contains($0) }.sorted()
        return known + custom
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(Color.forge)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // ── Onglets programmes ────────────────────────
                            if programs.count > 1 {
                                ProgramTabsView(
                                    programs: programs,
                                    selectedId: $selectedProgramId,
                                    activeId: activeProgramId,
                                    onAdd: { showCreateProgram = true },
                                    onRename: { p in
                                        renameProgramTarget = p
                                        renameProgramName   = p.name
                                    },
                                    onDelete: { p in
                                        deleteProgramTarget  = p
                                        confirmDeleteProgram = true
                                    }
                                )
                                .padding(.horizontal, 16)

                                if !selectedProgramId.isEmpty, selectedProgramId != activeProgramId {
                                    Button {
                                        Task { await setActiveProgramme() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isSettingActive {
                                                ProgressView().tint(.appSuccess).scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .font(.appLabel.weight(.regular))
                                            }
                                            Text("Définir comme programme actif")
                                                .font(.appLabel.weight(.semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.appSuccess.opacity(0.15))
                                        .foregroundColor(.appSuccess)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appSuccess.opacity(0.3), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSettingActive)
                                    .padding(.horizontal, 16)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }

                            if !activeProgrammeName.isEmpty || !periodisationStart.isEmpty {
                                ActiveProgrammeBanner(
                                    programmeName:  activeProgrammeName,
                                    phase:          currentPhase.rawValue,
                                    phaseColor:     phaseColor,
                                    week:           mesocycleWeek,
                                    totalWeeks:     11,
                                    started:        !periodisationStart.isEmpty,
                                    todaySession:   todaySessionName
                                )
                                .padding(.horizontal, 16)
                            }

                            EditableWeekScheduleCard(
                                schedule: $schedule,
                                dayNames: dayNames,
                                sessions: sessionsList,
                                onSave: { Task { await saveSchedule() } }
                            )
                            .padding(.horizontal, 16)

                            EveningScheduleCard(
                                eveningSchedule: $eveningSchedule,
                                dayNames: dayNames,
                                sessions: sessionsList,
                                onSave: { Task { await saveEveningSchedule() } }
                            )
                            .padding(.horizontal, 16)

                            let applyAction: (() -> Void)? = periodisationStart.isEmpty ? nil : { showApplyPhaseConfirm = true }
                            PeriodisationCard(
                                week: mesocycleWeek,
                                phase: currentPhase.rawValue,
                                scheme: phaseScheme,
                                next: nextPhase.rawValue,
                                color: phaseColor,
                                started: !periodisationStart.isEmpty,
                                onStart: {
                                    periodisationStart = DateFormatter.isoDate.string(from: Date())
                                },
                                onReset: { showResetMesocycle = true },
                                onApply: applyAction
                            )
                            .padding(.horizontal, 16)

                            if !clipboard.isEmpty {
                                let clipboardLabel: String = clipboardName.isEmpty
                                    ? "\(clipboard.count) exos"
                                    : "\(clipboardName) · \(clipboard.count) exos"
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.on.clipboard.fill")
                                        .font(.appLabel.weight(.regular))
                                        .foregroundColor(Color.forge)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Clipboard")
                                            .font(.appCaption.weight(.bold))
                                            .tracking(1)
                                            .foregroundColor(.gray)
                                        Text(clipboardLabel)
                                            .font(.appLabel.weight(.semibold))
                                            .foregroundColor(.appTextPrimary)
                                    }
                                    Spacer()
                                    Button {
                                        clipboardData = "{}"
                                        clipboardName = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.appBody)
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.forge.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.forge.opacity(0.2), lineWidth: 1))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            let volData = weeklyVolumeByMuscle
                            if !volData.isEmpty {
                                VolumeCard(
                                    volumeByMuscle: volData,
                                    mev: muscleMEV,
                                    mav: muscleMAV,
                                    alerts: volumeAlerts
                                )
                                .padding(.horizontal, 16)
                            }

                            if sessionOrder.isEmpty {
                                VStack(spacing: 20) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "list.bullet.clipboard")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray.opacity(0.4))
                                        Text("Aucun programme actif.")
                                            .font(.appBody.weight(.semibold))
                                            .foregroundColor(Color.appOnBackground.opacity(0.75))
                                        Text("Importe ton programme ou démarre une séance libre.")
                                            .font(.appLabel.weight(.regular))
                                            .foregroundColor(.gray)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 16)
                                    }
                                    VStack(spacing: 12) {
                                        Button { showCreateProgram = true } label: {
                                            Text("Importer un programme")
                                                .font(.appBody.weight(.semibold))
                                                .foregroundColor(Color.onAccent)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                                .background(Color.forge)
                                                .cornerRadius(14)
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            NotificationCenter.default.post(name: .navigateToSeance, object: nil)
                                        } label: {
                                            Text("Séance libre")
                                                .font(.appBody.weight(.medium))
                                                .foregroundColor(Color.forge)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                                .background(Color.forge.opacity(0.10))
                                                .cornerRadius(14)
                                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .padding(.vertical, 40)
                            }

                            ForEach(sessionOrder, id: \.self) { seance in
                                sessionCard(for: seance)
                            }
                            .onPreferenceChange(SessionCardHeightKey.self) { sessionCardHeights.merge($0) { $1 } }
                        }
                        .padding(.vertical, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        CacheService.shared.clear(for: "programme_data")
                        await loadData(programId: selectedProgramId.isEmpty ? nil : selectedProgramId)
                    }
                }

                // Undo toast
                if let item = undoDeleteItem {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\"\(item.name)\" retiré du programme")
                                    .font(.appLabel)
                                    .foregroundColor(.appTextPrimary)
                                Text("L'inventaire n'est pas affecté")
                                    .font(.appCaption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Button("Annuler") { undoDelete() }
                                .font(.appLabel.weight(.bold))
                                .foregroundColor(Color.forge)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.appCard)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, fabBottomPadding)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: undoDeleteItem != nil)
                    .zIndex(10)
                }

                if let msg = saveSuccessMsg {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.forge)
                            Text(msg)
                                .font(.appLabel.weight(.medium))
                                .foregroundColor(.appTextPrimary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.appCard)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, fabBottomPadding)
                    }
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: saveSuccessMsg != nil)
                    .zIndex(9)
                }
            }
            .navigationTitle("Programme")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        if mutationCount > 0 {
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.7).tint(Color.forge)
                                Text("Sauvegarde…")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(Color.forge)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        } else if lastSaveError {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.appCaption)
                                Text("Erreur réseau")
                                    .font(.appCaption.weight(.semibold))
                            }
                            .foregroundColor(Color.appDanger)
                            .transition(.opacity)
                        }
                        Button { showCreateSeance = true } label: {
                            Image(systemName: "plus")
                                .font(.appBody.weight(.semibold))
                                .foregroundColor(Color.forge)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: mutationCount)
                    .animation(.easeInOut(duration: 0.2), value: lastSaveError)
                }
            }
            .sheet(isPresented: $showCreateSeance) {
                CreateSeanceSheet { name in
                    Task { await createSeance(name: name) }
                }
            }
            .sheet(item: $addTarget) { sn in
                AddExerciseSheet(seance: sn.id, inventory: inventory, inventorySchemes: inventorySchemes) { ex, scheme in
                    Task { await addExercise(seance: sn.id, exercise: ex, scheme: scheme) }
                }
            }
            .sheet(item: $editTarget) { target in
                EditSchemeSheet(target: target) { newName, newScheme in
                    Task { await editExercise(seance: target.seance, oldName: target.exercise, newName: newName, scheme: newScheme) }
                }
            }
            .alert(deleteSeanceTitle, isPresented: $confirmDeleteSeance) {
                Button("Supprimer", role: .destructive) {
                    if let target = deleteSeanceTarget {
                        Task { await deleteSeance(name: target) }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tous les exercices de cette séance seront supprimés. Cette action est irréversible.")
            }
            .alert(applyPhaseTitle, isPresented: $showApplyPhaseConfirm) {
                Button("Appliquer", role: .destructive) {
                    Task { await applyPhaseScheme() }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tous les exercices du programme passeront au scheme \(phaseShortScheme). Cette action est réversible exercice par exercice.")
            }
            .alert("Nouveau mésocycle ?", isPresented: $showResetMesocycle) {
                Button("Recommencer", role: .destructive) {
                    periodisationStart = DateFormatter.isoDate.string(from: Date())
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La semaine 1 recommencera à partir d'aujourd'hui.")
            }
            // ── Créer programme ──────────────────────────────────
            .alert("Nouveau programme", isPresented: $showCreateProgram) {
                TextField("Nom du programme", text: $newProgramName)
                Button("Créer") {
                    let name = newProgramName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task { await createProgram(name: name) }
                    newProgramName = ""
                }
                Button("Annuler", role: .cancel) { newProgramName = "" }
            }
            // ── Renommer programme ───────────────────────────────
            .alert("Renommer", isPresented: renameAlertBinding) {
                TextField("Nouveau nom", text: $renameProgramName)
                Button("Renommer") {
                    let name = renameProgramName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, let target = renameProgramTarget else { return }
                    Task { await renameProgram(id: target.id, name: name) }
                    renameProgramTarget = nil
                }
                Button("Annuler", role: .cancel) { renameProgramTarget = nil }
            }
            // ── Supprimer programme ──────────────────────────────
            .alert(deleteProgramTitle, isPresented: $confirmDeleteProgram) {
                Button("Supprimer", role: .destructive) {
                    if let target = deleteProgramTarget {
                        Task { await deleteProgram(id: target.id) }
                    }
                    deleteProgramTarget = nil
                }
                Button("Annuler", role: .cancel) { deleteProgramTarget = nil }
            } message: {
                Text("Toutes les séances de ce programme seront supprimées. Cette action est irréversible.")
            }
        }
        .task { await loadData(); await loadSuggestions() }
        .onChange(of: selectedProgramId) { _, newId in
            guard !newId.isEmpty else { return }
            Task { await loadData(programId: newId); await loadSuggestions() }
        }
    }

    // MARK: – Body helpers (extracted to keep type-checker happy)

    private var sessionsList: [String] {
        let list = allSessions.isEmpty ? orderedSeances : allSessions
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameProgramTarget != nil },
            set: { if !$0 { renameProgramTarget = nil } }
        )
    }

    private var deleteSeanceTitle: String  { "Supprimer \(deleteSeanceTarget ?? "") ?" }
    private var applyPhaseTitle: String    { "Appliquer \(currentPhase.rawValue) (\(phaseShortScheme)) ?" }
    private var deleteProgramTitle: String { "Supprimer \(deleteProgramTarget?.name ?? "") ?" }

    @ViewBuilder
    private func sessionCard(for seance: String) -> some View {
        let isSessionDragging: Bool = draggingSession == seance
        let exercisesBinding = Binding<[String: String]>(
            get: { self.fullProgram[seance] ?? [:] },
            set: { self.fullProgram[seance] = $0 }
        )
        let orderedNamesBinding = Binding<[String]>(
            get: {
                if let names = self.exerciseOrder[seance] { return names }
                return self.fullProgram[seance]?.keys.sorted() ?? []
            },
            set: { self.exerciseOrder[seance] = $0 }
        )
        let pasteAction: Optional<() -> Void> = clipboard.isEmpty
            ? Optional<() -> Void>.none
            : Optional<() -> Void>.some({ self.pasteSeance(into: seance) })
        let shift: CGFloat = isSessionDragging ? sessionDragY : sessionShiftFor(seance)
        let scale: CGFloat = isSessionDragging ? 1.02 : 1.0
        let zIdx: Double   = isSessionDragging ? 1 : 0
        EditableSeanceProgramCard(
            seance:       seance,
            exercises:    exercisesBinding,
            orderedNames: orderedNamesBinding,
            onAdd:        { addTarget = SeanceName(id: seance) },
            onEdit:       { ex, scheme in
                let w = exerciseWeights[ex]
                editTarget = ExerciseTarget(seance: seance, exercise: ex, scheme: scheme, lastWeight: w?.weight, lastReps: w?.reps, lastDate: w?.date)
            },
            onDelete:     { ex in deleteWithUndo(seance: seance, exercise: ex) },
            onReorder:    { order in Task { await reorderExercises(seance: seance, order: order) } },
            onDeleteSeance: {
                deleteSeanceTarget = seance
                confirmDeleteSeance = true
            },
            onCopy:  { copySeance(name: seance, exercises: fullProgram[seance] ?? [:]) },
            onPaste: pasteAction,
            isToday: seance == todaySessionName,
            onSessionDragChanged: { dy in
                if draggingSession == nil { triggerImpact(style: .light) }
                draggingSession = seance
                sessionDragY = dy
            },
            onSessionDragEnded: {
                let to = proposedSessionDrop
                if let from = sessionOrder.firstIndex(of: seance), from != to {
                    withAnimation(.spring(response: 0.25)) {
                        sessionOrder.move(fromOffsets: IndexSet(integer: from),
                                          toOffset: to > from ? to + 1 : to)
                    }
                    saveSessionOrder()
                }
                withAnimation(.spring(response: 0.25)) {
                    draggingSession = nil
                    sessionDragY = 0
                }
            },
            supersets:       exerciseSupersets[seance] ?? [:],
            exerciseWeights: exerciseWeights,
            suggestions:     programSuggestions[seance] ?? [:]
        )
        .padding(.horizontal, 16)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SessionCardHeightKey.self,
                    value: [seance: geo.size.height]
                )
            }
        )
        .offset(y: shift)
        .scaleEffect(scale, anchor: .center)
        .zIndex(zIdx)
        .opacity(isScheduledThisWeek(seance) ? 1.0 : 0.55)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: sessionShiftFor(seance))
    }

    // MARK: – Load

    private func applyJSON(_ json: [String: Any]) {
        if let raw = json["full_program"] as? [String: [String: Any]] {
            fullProgram = raw.mapValues { $0.compactMapValues { $0 as? String } }
        }
        schedule         = (json["schedule"] as? [String: String]) ?? [:]
        inventory        = (json["inventory"] as? [String]) ?? []
        inventorySchemes = (json["inventory_schemes"] as? [String: String]) ?? [:]
        if let order = json["exercise_order"] as? [String: [String]] {
            exerciseOrder = order
        }
        if let order = json["session_order"] as? [String] {
            apiSessionOrder = order
        }
        if let ss = json["exercise_supersets"] as? [String: [String: [String: Any]]] {
            var parsed: [String: [String: SupersetEntry]] = [:]
            for (seance, pairs) in ss {
                var seanceMap: [String: SupersetEntry] = [:]
                for (exName, entry) in pairs {
                    if let a = entry["A"] as? String, let b = entry["B"] as? String {
                        let r = entry["rest"] as? Int
                        seanceMap[exName] = SupersetEntry(a: a, b: b, rest: r)
                    }
                }
                parsed[seance] = seanceMap
            }
            exerciseSupersets = parsed
        }
        // Programs
        if let rawPrograms = json["programs"] as? [[String: Any]] {
            programs = rawPrograms.compactMap { d in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return ProgramInfo(id: id, name: name)
            }
        }
        if let pid = json["current_program_id"] as? String, !pid.isEmpty {
            if selectedProgramId.isEmpty { selectedProgramId = pid }
            activeProgramId = pid
        }
        if let sessions = json["all_sessions"] as? [String] {
            allSessions = sessions
        }
        refreshSessionOrder()
    }

    private func loadSuggestions() async {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: Date())
        var result: [String: [String: ProgressionSuggestion]] = [:]
        for seance in sessionOrder {
            if let list = try? await APIService.shared.fetchProgressionSuggestions(
                date: dateStr, sessionType: "morning", sessionName: seance
            ) {
                result[seance] = Dictionary(uniqueKeysWithValues: list.map { ($0.exerciseName, $0) })
            }
        }
        await MainActor.run { programSuggestions = result }
    }

    private func loadData(programId: String? = nil) async {
        var urlStr = "\(kBaseURL)/api/programme_data"
        let pid = programId ?? (selectedProgramId.isEmpty ? nil : selectedProgramId)
        if let pid = pid { urlStr += "?program_id=\(pid)" }
        guard let url = URL(string: urlStr) else { await MainActor.run { isLoading = false }; return }
        // Affichage immédiat depuis cache
        if let cached = CacheService.shared.load(for: "programme_data"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            await MainActor.run { applyJSON(json); isLoading = false }
        }
        // sequential — async let LIFO crash on iOS 26 beta
        if let (data, _) = try? await URLSession.authed.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            CacheService.shared.save(data, for: "programme_data")
            await MainActor.run { applyJSON(json); isLoading = false }
        } else {
            await MainActor.run { isLoading = false }
        }
        if let eURL = URL(string: "\(kBaseURL)/api/evening_schedule"),
           let (eData, _) = try? await URLSession.authed.data(from: eURL),
           let eJson = try? JSONSerialization.jsonObject(with: eData) as? [String: String] {
            await MainActor.run { eveningSchedule = eJson }
        }
        if let wURL = URL(string: "\(kBaseURL)/api/seance_data"),
           let (wData, _) = try? await URLSession.authed.data(from: wURL),
           let wJson = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
           let weights = wJson["weights"] as? [String: [String: Any]] {
            await MainActor.run {
                exerciseWeights = weights.compactMapValues { d in
                    let w  = d["current_weight"] as? Double
                    let r  = d["last_reps"]      as? String
                    let dt = d["last_logged"]    as? String
                    return (w, r, dt)
                }
            }
        }
    }

    private func saveEveningSchedule() async {
        guard let url = URL(string: "\(kBaseURL)/api/evening_schedule") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: eveningSchedule)
        do {
            let (_, resp) = try await URLSession.authed.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                await MainActor.run { lastSaveError = true }
            }
        } catch {
            await MainActor.run { lastSaveError = true }
        }
        CacheService.shared.clear(for: "seance_soir_data")
    }

    // MARK: – Mutations

    private func postProgramme(_ body: [String: Any]) async {
        await MainActor.run { mutationCount += 1; lastSaveError = false }
        defer { Task { @MainActor in mutationCount = max(0, mutationCount - 1) } }
        guard let url = URL(string: "\(kBaseURL)/api/programme") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var enrichedBody = body
        if !selectedProgramId.isEmpty, enrichedBody["program_id"] == nil {
            enrichedBody["program_id"] = selectedProgramId
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: enrichedBody)
        do {
            let (_, resp) = try await URLSession.authed.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                await MainActor.run { lastSaveError = true }
            }
        } catch {
            await MainActor.run { lastSaveError = true }
        }
        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "seance_data")
    }

    private func addExercise(seance: String, exercise: String, scheme: String) async {
        await postProgramme(["action": "add", "jour": seance, "exercise": exercise, "scheme": scheme])
        await MainActor.run {
            fullProgram[seance, default: [:]][exercise] = scheme
            exerciseOrder[seance, default: []].append(exercise)
            if !lastSaveError { showSaveSuccess("Exercice ajouté") }
        }
    }

    private func deleteExercise(seance: String, exercise: String) async {
        await postProgramme(["action": "remove", "jour": seance, "exercise": exercise])
    }

    private func deleteWithUndo(seance: String, exercise: String) {
        // Commit any previous pending delete immediately
        if let prev = undoDeleteItem {
            undoDeleteTask?.cancel()
            undoDeleteTask = nil
            Task { await deleteExercise(seance: prev.seance, exercise: prev.name) }
        }
        // Snapshot for undo
        let idx = exerciseOrder[seance]?.firstIndex(of: exercise) ?? 0
        let scheme = fullProgram[seance]?[exercise] ?? ""
        // Optimistic local removal
        fullProgram[seance]?.removeValue(forKey: exercise)
        exerciseOrder[seance]?.removeAll { $0 == exercise }
        // Show undo toast
        withAnimation { undoDeleteItem = UndoDeleteItem(seance: seance, name: exercise, scheme: scheme, orderIndex: idx) }
        // Auto-commit after 4 s
        undoDeleteTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await deleteExercise(seance: seance, exercise: exercise)
            await MainActor.run { withAnimation { undoDeleteItem = nil } }
        }
    }

    private func undoDelete() {
        guard let item = undoDeleteItem else { return }
        undoDeleteTask?.cancel()
        undoDeleteTask = nil
        // Restore local state
        fullProgram[item.seance, default: [:]][item.name] = item.scheme
        let idx = min(item.orderIndex, exerciseOrder[item.seance]?.count ?? 0)
        exerciseOrder[item.seance, default: []].insert(item.name, at: idx)
        withAnimation { undoDeleteItem = nil }
    }

    private func reorderExercises(seance: String, order: [String]) async {
        // Guard: don't send if order is a subset of the actual exercises
        // (incomplete orderedNames would silently drop missing exercises)
        let actual = fullProgram[seance]?.count ?? 0
        guard order.count >= actual else { return }
        await postProgramme(["action": "reorder", "jour": seance, "ordre": order])
    }

    private func saveSchedule() async {
        guard let url = URL(string: "\(kBaseURL)/api/morning_schedule") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["schedule": schedule])
        do {
            let (_, resp) = try await URLSession.authed.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                await MainActor.run { lastSaveError = true }
            }
        } catch {
            await MainActor.run { lastSaveError = true }
        }
        CacheService.shared.clear(for: "seance_data")
        CacheService.shared.clear(for: "programme_data")
    }

    private func createSeance(name: String) async {
        var body: [String: Any] = ["action": "create_seance", "jour": name]
        if !selectedProgramId.isEmpty { body["program_id"] = selectedProgramId }
        await postProgramme(body)
        await MainActor.run {
            fullProgram[name] = [:]
            exerciseOrder[name] = []
        }
    }

    // MARK: – Programme CRUD

    private func createProgram(name: String) async {
        guard let url = URL(string: "\(kBaseURL)/api/programs") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "create", "name": name])
        do {
            let (data, resp) = try await URLSession.authed.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                await MainActor.run { lastSaveError = true }
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid  = json["id"] as? String else {
                await MainActor.run { lastSaveError = true }
                return
            }
            CacheService.shared.clear(for: "programme_data")
            await MainActor.run {
                let p = ProgramInfo(id: pid, name: name)
                programs.append(p)
                selectedProgramId = pid
                fullProgram = [:]
                exerciseOrder = [:]
            }
        } catch {
            await MainActor.run { lastSaveError = true }
        }
    }

    private func setActiveProgramme() async {
        guard !selectedProgramId.isEmpty else { return }
        await MainActor.run { isSettingActive = true }
        defer { Task { @MainActor in isSettingActive = false } }
        guard let url = URL(string: "\(kBaseURL)/api/programs") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "set_active", "program_id": selectedProgramId])
        do {
            let (_, resp) = try await URLSession.authed.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode < 400 else {
                await MainActor.run { lastSaveError = true }
                return
            }
            CacheService.shared.clear(for: "seance_data")
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    activeProgramId = selectedProgramId
                }
            }
        } catch {
            await MainActor.run { lastSaveError = true }
        }
    }

    private func renameProgram(id: String, name: String) async {
        guard let url = URL(string: "\(kBaseURL)/api/programs") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "rename", "program_id": id, "name": name])
        do {
            let (_, resp) = try await URLSession.authed.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                await MainActor.run { lastSaveError = true }
                return
            }
            CacheService.shared.clear(for: "programme_data")
            await MainActor.run {
                if let idx = programs.firstIndex(where: { $0.id == id }) {
                    programs[idx] = ProgramInfo(id: id, name: name)
                }
            }
        } catch {
            await MainActor.run { lastSaveError = true }
        }
    }

    private func deleteProgram(id: String) async {
        guard let url = URL(string: "\(kBaseURL)/api/programs") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "delete", "program_id": id])
        do {
            let (_, resp) = try await URLSession.authed.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                await MainActor.run { lastSaveError = true }
                return
            }
            CacheService.shared.clear(for: "programme_data")
            await MainActor.run {
                programs.removeAll { $0.id == id }
                if selectedProgramId == id { selectedProgramId = programs.first?.id ?? "" }
            }
            await loadData(programId: selectedProgramId.isEmpty ? nil : selectedProgramId)
        } catch {
            await MainActor.run { lastSaveError = true }
        }
    }

    private func deleteSeance(name: String) async {
        await postProgramme(["action": "delete_seance", "jour": name])
        await MainActor.run {
            fullProgram.removeValue(forKey: name)
            exerciseOrder.removeValue(forKey: name)
            // Clear from schedule if assigned
            for (day, seance) in schedule where seance == name {
                schedule.removeValue(forKey: day)
            }
        }
    }

    private func showSaveSuccess(_ msg: String) {
        withAnimation { saveSuccessMsg = msg }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { saveSuccessMsg = nil } }
        }
    }

    private func editExercise(seance: String, oldName: String, newName: String, scheme: String) async {
        if oldName != newName {
            // rename synce tous les jours du programme + inventaire
            await postProgramme(["action": "rename", "jour": seance, "old_exercise": oldName, "new_exercise": newName])
            await postProgramme(["action": "scheme", "jour": seance, "exercise": newName, "scheme": scheme])
            await MainActor.run {
                // Swift Dicts are value types — must read, mutate, then write back
                for key in fullProgram.keys {
                    if let oldScheme = fullProgram[key]?[oldName] {
                        fullProgram[key]?[newName] = oldScheme
                        fullProgram[key]?.removeValue(forKey: oldName)
                    }
                }
                fullProgram[seance]?[newName] = scheme
            }
        } else {
            await postProgramme(["action": "scheme", "jour": seance, "exercise": oldName, "scheme": scheme])
            await MainActor.run { fullProgram[seance]?[oldName] = scheme }
        }
        await MainActor.run { if !lastSaveError { showSaveSuccess("Exercice modifié") } }
    }
}

// MARK: - PeriodisationCard

struct PeriodisationCard: View {
    let week: Int
    let phase: String
    let scheme: String
    let next: String
    let color: Color
    let started: Bool
    let onStart: () -> Void
    let onReset: () -> Void
    var onApply: (() -> Void)? = nil

    @State private var showTimeline = false

    private let totalWeeks = 11

    private struct PhaseSegment {
        let name: String
        let shortScheme: String
        let color: Color
        let weeks: ClosedRange<Int>
    }

    private let segments: [PhaseSegment] = [
        PhaseSegment(name: "Hypertrophie", shortScheme: "3-4×8-12", color: .statusOrange, weeks: 1...4),
        PhaseSegment(name: "Force",        shortScheme: "4-5×4-6",  color: .appDanger,    weeks: 5...8),
        PhaseSegment(name: "Peak",         shortScheme: "5×1-3",    color: .statusYellow, weeks: 9...10),
        PhaseSegment(name: "Deload",       shortScheme: "3×10-12",  color: .appSuccess,   weeks: 11...11),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(color)
                    .font(.appLabel.weight(.bold))
                Text("Périodisation")
                    .font(.appLabel.weight(.bold))
                    .foregroundColor(Color.appOnSurface.opacity(0.8))
                Spacer()
                if started {
                    Button(action: onReset) {
                        Text("Nouveau mésocycle")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(color)
                    }
                    .buttonStyle(.plain)
                }
            }

            if started {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(phase)
                        .font(.appTitle.weight(.black))
                        .foregroundColor(color)
                    Text("— Semaine \(week)/\(totalWeeks)")
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.gray)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.appSeparatorSubtle)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(min(week, totalWeeks)) / CGFloat(totalWeeks), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Label(scheme, systemImage: "dumbbell")
                        .font(.appCaption)
                        .foregroundColor(Color.appOnSurface.opacity(0.65))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showTimeline.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showTimeline ? "Masquer" : "Plan complet")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.gray)
                            Image(systemName: showTimeline ? "chevron.up" : "chevron.down")
                                .font(.appMicro.weight(.semibold))
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Timeline expandable
                if showTimeline {
                    VStack(spacing: 8) {
                        // Barre segmentée
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(segments, id: \.name) { seg in
                                    let segCount = CGFloat(seg.weeks.count)
                                    let totalCount = CGFloat(totalWeeks)
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(seg.color.opacity(0.18))
                                            .frame(width: geo.size.width * segCount / totalCount - 2)
                                        HStack(spacing: 0) {
                                            ForEach(seg.weeks, id: \.self) { w in
                                                let isCurrentWeek = w == week
                                                ZStack {
                                                    if isCurrentWeek {
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .fill(seg.color.opacity(0.5))
                                                    }
                                                    Text("\(w)")
                                                        .font(.appMicro.weight(isCurrentWeek ? .black : .regular))
                                                        .foregroundColor(isCurrentWeek ? .white : seg.color.opacity(0.7))
                                                }
                                                .frame(maxWidth: .infinity)
                                            }
                                        }
                                        .frame(width: geo.size.width * segCount / totalCount - 2)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(seg.weeks.contains(week) ? seg.color.opacity(0.7) : Color.clear, lineWidth: 1.5)
                                    )
                                }
                            }
                        }
                        .frame(height: 28)

                        // Légende
                        HStack(spacing: 0) {
                            ForEach(segments, id: \.name) { seg in
                                VStack(alignment: .center, spacing: 2) {
                                    Text(seg.name)
                                        .font(.appMicro.weight(.bold))
                                        .foregroundColor(seg.color.opacity(0.85))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text(seg.shortScheme)
                                        .font(.appMicro)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let apply = onApply {
                    Button(action: apply) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.appCaption.weight(.bold))
                            Text("Appliquer à tout le programme")
                                .font(.appCaption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.12))
                        .foregroundColor(color)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: onStart) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Démarrer un mésocycle")
                    }
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(color.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
        .cornerRadius(14)
    }
}

// MARK: - ProgramTabsView

private struct ProgramTabsView: View {
    let programs: [ProgramInfo]
    @Binding var selectedId: String
    let activeId: String
    let onAdd: () -> Void
    let onRename: (ProgramInfo) -> Void
    let onDelete: (ProgramInfo) -> Void

    private var sortedPrograms: [ProgramInfo] {
        programs.sorted { a, _ in a.id == activeId }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedPrograms) { prog in
                    let isSelected = selectedId == prog.id
                    let isActive   = prog.id == activeId

                    HStack(spacing: 5) {
                        if isActive {
                            Circle()
                                .fill(Color.appSuccess)
                                .frame(width: 6, height: 6)
                        }
                        Text(prog.name)
                            .font(.appLabel.weight(isSelected ? .semibold : .regular))
                            .foregroundColor(
                                isSelected ? .onAccent
                                : isActive  ? .appOnSurface
                                            : Color.appOnSurface.opacity(0.55)
                            )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isSelected ? Color.forge : Color.appSurfaceInset)
                    )
                    .onTapGesture { selectedId = prog.id }
                    .contextMenu {
                        Button("Renommer") { onRename(prog) }
                        Button("Supprimer", role: .destructive) { onDelete(prog) }
                    }
                }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.forge)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.forge.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Models

struct SeanceName: Identifiable {
    let id: String   // id == seance name
}

struct ExerciseTarget: Identifiable {
    var id: String { "\(seance)/\(exercise)" }
    let seance: String
    let exercise: String
    let scheme: String
    var lastWeight: Double? = nil
    var lastReps: String? = nil
    var lastDate: String? = nil
}

// MARK: - Editable Seance Card

private struct ProgramRowHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct SessionCardHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct EditableSeanceProgramCard: View {
    let seance: String
    @Binding var exercises: [String: String]
    @Binding var orderedNames: [String]
    let onAdd:          () -> Void
    let onEdit:         (String, String) -> Void
    let onDelete:       (String) -> Void
    let onReorder:      ([String]) -> Void
    var onDeleteSeance:       (() -> Void)? = nil
    var onCopy:               (() -> Void)? = nil
    var onPaste:              (() -> Void)? = nil
    var isToday:              Bool = false
    var onSessionDragChanged: ((CGFloat) -> Void)? = nil
    var onSessionDragEnded:   (() -> Void)? = nil
    var supersets: [String: SupersetEntry] = [:]
    var exerciseWeights: [String: (weight: Double?, reps: String?, date: String?)] = [:]
    var suggestions: [String: ProgressionSuggestion] = [:]

    @State private var expanded    = true
    @State private var dragging:   String? = nil
    @State private var dragY:      CGFloat = 0
    @State private var rowHeights: [String: CGFloat] = [:]

    var color: Color { SessionType(seance).color }

    private func trendFor(_ name: String) -> String? {
        guard let entry = exerciseWeights[name], entry.weight != nil else { return nil }
        guard let dateStr = entry.date, !dateStr.isEmpty else { return "→" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return "→" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 999
        return days <= 7 ? "↑" : "→"
    }

    /// Exercises in user-defined order; unordered extras appended alphabetically.
    var orderedPairs: [(String, String)] {
        let named = orderedNames.compactMap { n -> (String, String)? in
            guard let s = exercises[n] else { return nil }
            return (n, s)
        }
        let extra = exercises.keys.filter { !orderedNames.contains($0) }.sorted()
        return named + extra.map { ($0, exercises[$0]!) }
    }

    private var proposedDrop: Int {
        guard let name = dragging,
              let from = orderedNames.firstIndex(of: name) else { return 0 }
        let h = (rowHeights[name] ?? 46)
        let steps = Int((dragY / h).rounded())
        return max(0, min(orderedNames.count - 1, from + steps))
    }

    private func shiftFor(_ cardName: String) -> CGFloat {
        guard let dr = dragging, dr != cardName,
              let from = orderedNames.firstIndex(of: dr),
              let idx  = orderedNames.firstIndex(of: cardName) else { return 0 }
        let to = proposedDrop
        let h  = rowHeights[dr] ?? 46
        if from < to, idx > from, idx <= to { return -h }
        if from > to, idx >= to,  idx < from { return  h }
        return 0
    }

    private func dragGesture(for name: String) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { val in
                if dragging == nil {
                    dragging = name
                    triggerImpact(style: .light)
                }
                dragY = val.translation.height
            }
            .onEnded { _ in
                if let dr = dragging {
                    let to = proposedDrop
                    if let from = orderedNames.firstIndex(of: dr), from != to {
                        withAnimation(.spring(response: 0.25)) {
                            orderedNames.move(fromOffsets: IndexSet(integer: from),
                                              toOffset: to > from ? to + 1 : to)
                        }
                        onReorder(orderedNames)
                    }
                }
                withAnimation(.spring(response: 0.25)) { dragging = nil; dragY = 0 }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                if onSessionDragChanged != nil {
                    Image(systemName: "line.3.horizontal")
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.gray.opacity(0.4))
                        .frame(width: 24)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { val in onSessionDragChanged?(val.translation.height) }
                                .onEnded { _ in onSessionDragEnded?() }
                        )
                }
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(seance.prefix(1)))
                            .font(.appLabel.weight(.black))
                            .foregroundColor(color)
                    )
                Text(seance)
                    .font(.appBody.weight(.bold))
                    .foregroundColor(color)
                if isToday {
                    Text("AUJOURD'HUI")
                        .font(.appMicro.weight(.black)).tracking(1)
                        .foregroundColor(Color.forge)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.forge.opacity(0.12))
                        .cornerRadius(5)
                }
                Spacer()
                Text("\(exercises.count)")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(8)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(color)
                        .padding(7)
                        .background(color.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                if let copy = onCopy {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(Color.forge.opacity(0.7))
                            .padding(7)
                            .background(Color.forge.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                if let paste = onPaste {
                    Button(action: paste) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(Color.statusCyan.opacity(0.7))
                            .padding(7)
                            .background(Color.statusCyan.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                if let del = onDeleteSeance {
                    Button(action: del) {
                        Image(systemName: "trash")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(Color.appDanger.opacity(0.6))
                            .padding(7)
                            .background(Color.appDanger.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }

            if expanded {
                Divider().background(Color.appSeparator)

                if orderedPairs.isEmpty {
                    HStack {
                        Image(systemName: "plus.circle")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(color.opacity(0.5))
                        Text("Aucun exercice — tape + pour en ajouter")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }

                ForEach(orderedPairs, id: \.0) { name, scheme in
                    let isDragging = dragging == name
                    HStack(spacing: 0) {
                        // ≡ Drag handle
                        Image(systemName: "line.3.horizontal")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(.gray.opacity(0.5))
                            .frame(width: 40)
                            .contentShape(Rectangle())
                            .gesture(dragGesture(for: name))

                        // Exercise row (tap → edit, trash → delete)
                        ExerciseRow(
                            name:          name,
                            scheme:        scheme,
                            color:         color,
                            onTap:         { onEdit(name, scheme) },
                            onDelete:      { onDelete(name) },
                            isSupersetted: supersets[name] != nil,
                            trend:         trendFor(name),
                            suggestion:    suggestions[name]
                        )
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ProgramRowHeightKey.self,
                                value: [name: geo.size.height]
                            )
                        }
                    )
                    .scaleEffect(isDragging ? 1.02 : 1.0, anchor: .center)
                    .background(isDragging ? color.opacity(0.06) : Color.clear)
                    .offset(y: isDragging ? dragY : shiftFor(name))
                    .zIndex(isDragging ? 1 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: shiftFor(name))
                    .animation(.spring(response: 0.2,  dampingFraction: 0.9),  value: isDragging)

                    if name != orderedPairs.last?.0 {
                        Divider().background(Color.appSeparatorSubtle).padding(.leading, 40)
                    }
                }
                .onPreferenceChange(ProgramRowHeightKey.self) { rowHeights.merge($0) { $1 } }
            }
        }
        .background(Color.appCard)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isToday ? Color.forge.opacity(0.7) : color.opacity(0.2), lineWidth: isToday ? 1.5 : 1))
        .cornerRadius(14)
        .shadow(color: isToday ? Color.forge.opacity(0.18) : .clear, radius: 14, y: 4)
    }
}

struct ExerciseRow: View {
    let name: String
    let scheme: String
    let color: Color
    let onTap: () -> Void
    let onDelete: () -> Void
    var isSupersetted: Bool = false
    var trend: String? = nil
    var suggestion: ProgressionSuggestion? = nil

    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(name)
                    .font(.appLabel.weight(.medium))
                    .foregroundColor(.appTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSupersetted {
                    Text("SS")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color.forge)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(Color.forge.opacity(0.15))
                        .cornerRadius(4)
                }
                if let t = trend {
                    Text(t)
                        .font(.appCaption.weight(.bold))
                        .foregroundColor(t == "↑" ? Color.appSuccess : t == "↓" ? Color.appDanger : Color(white: 0.5))
                }
                Text(scheme)
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.15))
                    .cornerRadius(6)
                    .lineLimit(1)
                if let sug = suggestion,
                   sug.suggestionType == "increase_weight",
                   let sw = sug.suggestedWeight {
                    Text("→ \(units.format(sw, decimals: 0))")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.appSuccess)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.appSuccess.opacity(0.12))
                        .cornerRadius(5)
                }
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(Color.appDanger.opacity(0.6))
                        .padding(6)
                        .background(Color.appDanger.opacity(0.08))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    let seance: String
    let inventory: [String]
    let inventorySchemes: [String: String]
    var recentExercises: [String] = []
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scheme = "3x8-12"
    @State private var selectedGroup: String? = nil
    @State private var confirmDiscard = false

    private var isDirty: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private let muscleGroupOrder = ["Pecs", "Dos", "Jambes", "Épaules", "Biceps", "Triceps", "Fessiers", "Core"]

    private func muscleGroup(for exercise: String) -> String {
        let e = exercise.lowercased()
        if ["bench","fly","chest","dip","pec","incline","pec"].contains(where: { e.contains($0) }) { return "Pecs" }
        if ["row","pulldown","pull-up","pull up","lat","deadlift","rdl","back"].contains(where: { e.contains($0) }) { return "Dos" }
        if ["squat","leg press","lunge","quad","hack"].contains(where: { e.contains($0) }) { return "Jambes" }
        if ["curl","bicep"].contains(where: { e.contains($0) }) { return "Biceps" }
        if ["tricep","pushdown","skull","extension"].contains(where: { e.contains($0) }) { return "Triceps" }
        if ["press","lateral","shoulder","delt","ohp"].contains(where: { e.contains($0) }) { return "Épaules" }
        if ["glute","hip thrust","fessier","hip hinge"].contains(where: { e.contains($0) }) { return "Fessiers" }
        if ["plank","core","ab","crunch","sit-up"].contains(where: { e.contains($0) }) { return "Core" }
        return "Autre"
    }

    private var filtered: [String] {
        var result = name.isEmpty ? inventory : inventory.filter { $0.localizedCaseInsensitiveContains(name) }
        if let grp = selectedGroup {
            result = result.filter { muscleGroup(for: $0) == grp }
        }
        return result
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !scheme.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Name field (also filters inventory)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Nom de l'exercice...", text: $name)
                            .foregroundColor(.appTextPrimary)
                        if !name.isEmpty {
                            Button { name = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.appCard)
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Muscle group filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button {
                                selectedGroup = nil
                            } label: {
                                Text("Tous")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(selectedGroup == nil ? .onAccent : Color.appOnSurface.opacity(0.7))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(selectedGroup == nil ? Color.forge : Color.appSurfaceInset)
                                    .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                            ForEach(muscleGroupOrder, id: \.self) { grp in
                                let active = selectedGroup == grp
                                Button {
                                    selectedGroup = active ? nil : grp
                                } label: {
                                    Text(grp)
                                        .font(.appCaption.weight(.semibold))
                                        .foregroundColor(active ? .onAccent : Color.appOnSurface.opacity(0.7))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(active ? Color.forge : Color.appSurfaceInset)
                                        .cornerRadius(14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    // Récents — exercices ajoutés à la volée dans les séances précédentes
                    if !recentExercises.isEmpty && name.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RÉCENTS")
                                .font(.appCaption.weight(.bold))
                                .tracking(1.5)
                                .foregroundColor(.gray.opacity(0.55))
                                .padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(recentExercises, id: \.self) { ex in
                                        Button {
                                            onAdd(ex, inventorySchemes[ex] ?? "3x8-12")
                                            dismiss()
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .font(.appCaption)
                                                    .foregroundColor(Color.forge.opacity(0.7))
                                                Text(ex)
                                                    .font(.appLabel)
                                                    .foregroundColor(.appTextPrimary)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Color.forge.opacity(0.1))
                                            .cornerRadius(10)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.forge.opacity(0.22), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            Divider()
                                .background(Color.appSeparatorSubtle)
                                .padding(.horizontal, 16)
                                .padding(.top, 2)
                        }
                        .padding(.bottom, 6)
                    }

                    // Scheme field
                    HStack {
                        Text("Schéma :")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(.gray)
                        TextField("ex: 4x6-8", text: $scheme)
                            .font(.appLabel)
                            .foregroundColor(.appTextPrimary)
                            .padding(8)
                            .background(Color.appCard)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    // Inventory suggestions
                    if !filtered.isEmpty {
                        List(filtered, id: \.self) { ex in
                            Button {
                                name = ex
                                // Hérite le default_scheme de l'inventaire
                                if let defaultScheme = inventorySchemes[ex] {
                                    scheme = defaultScheme
                                }
                            } label: {
                                HStack {
                                    Text(ex)
                                        .foregroundColor(.appTextPrimary)
                                        .font(.appLabel.weight(.regular))
                                    Spacer()
                                    Text(muscleGroup(for: ex))
                                        .font(.appCaption)
                                        .foregroundColor(.gray.opacity(0.6))
                                    if name == ex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color.forge)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.appCard)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("Ajouter à \(seance)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !scheme.isEmpty else { return }
                        onAdd(trimmed, scheme)
                        dismiss()
                    }
                    .foregroundColor(canSave ? Color.forge : .gray)
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Les valeurs saisies seront perdues.")
            }
        }
    }
}

// MARK: - Edit Scheme Sheet

struct EditSchemeSheet: View {
    let target: ExerciseTarget
    let onSave: (String, String) -> Void  // (newName, newScheme)

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared
    @State private var name: String = ""
    @State private var scheme: String = ""
    @State private var initialName: String = ""
    @State private var initialScheme: String = ""
    @State private var confirmDiscard = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !scheme.isEmpty }
    private var isDirty: Bool { name != initialName || scheme != initialScheme }

    private var lastLogLabel: String? {
        guard let w = target.lastWeight else { return nil }
        let wStr = units.format(w, decimals: 0)
        if let r = target.lastReps, !r.isEmpty {
            return "\(wStr) × \(r)"
        }
        return wStr
    }

    private var lastDateLabel: String? {
        guard let dt = target.lastDate, !dt.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dt) else { return dt }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "aujourd'hui" }
        if days == 1 { return "hier" }
        return "il y a \(days) j"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg
                    .ignoresSafeArea()
                    .onTapGesture { hideKeyboard() }
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nom de l'exercice")
                            .font(.appCaption.weight(.bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("Nom", text: $name)
                            .font(.appHeadline.weight(.regular))
                            .foregroundColor(.appTextPrimary)
                            .padding()
                            .background(Color.appCard)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schéma de sets/reps")
                            .font(.appCaption.weight(.bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("ex: 4x6-8", text: $scheme)
                            .font(.appHeadline.weight(.regular))
                            .foregroundColor(.appTextPrimary)
                            .padding()
                            .background(Color.appCard)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    // Dernier log
                    if let logLabel = lastLogLabel {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.appCaption)
                                .foregroundColor(.gray)
                            Text("Dernier : \(logLabel)")
                                .font(.appCaption.weight(.medium))
                                .foregroundColor(.gray)
                            if let dateLabel = lastDateLabel {
                                Text("· \(dateLabel)")
                                    .font(.appCaption)
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    // Suggestions rapides
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["3x5", "4x5-7", "3x8-10", "4x8-10", "3x10-12", "4x12-15", "3x15"], id: \.self) { s in
                                Button { scheme = s } label: {
                                    Text(s)
                                        .font(.appCaption.weight(.medium))
                                        .foregroundColor(scheme == s ? .onAccent : .appOnSurface)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(scheme == s ? Color.forge : Color.appCard)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Modifier l'exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !scheme.isEmpty else { return }
                        onSave(trimmed, scheme)
                        dismiss()
                    }
                    .foregroundColor(canSave ? Color.forge : .gray)
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Les valeurs saisies seront perdues.")
            }
        }
        .onAppear {
            name = target.exercise
            scheme = target.scheme
            initialName = target.exercise
            initialScheme = target.scheme
        }
    }
}

// MARK: - Editable Week Schedule Card

struct EditableWeekScheduleCard: View {
    @Binding var schedule: [String: String]
    let dayNames: [String]
    let sessions: [String]
    let onSave: () -> Void

    private let none = "Repos"

    private var todayDayName: String {
        let idx = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        return ["Lun","Mar","Mer","Jeu","Ven","Sam","Dim"][idx]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(Color.forge)
                    Text("MATIN")
                        .font(.appCaption.weight(.black))
                        .tracking(2)
                        .foregroundColor(Color.forge)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.forge.opacity(0.1))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Semaine type")
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(Color.appOnSurface.opacity(0.85))
                    Text("Appuie sur un jour pour changer la séance")
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(dayNames, id: \.self) { day in
                    let current = schedule[day] ?? none
                    let isToday = day == todayDayName
                    Menu {
                        Button(none) {
                            schedule[day] = none
                            onSave()
                        }
                        ForEach(sessions, id: \.self) { s in
                            Button(s) {
                                schedule[day] = s
                                onSave()
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 3) {
                                Text(day)
                                    .font(.appCaption.weight(isToday ? .bold : .medium))
                                    .foregroundColor(isToday ? Color.forge : .gray)
                                if isToday {
                                    Circle()
                                        .fill(Color.forge)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            Text(seanceShort(current))
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(current == none ? Color.gray.opacity(0.4) : seanceColor(current))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background((current == none ? Color.gray : seanceColor(current)).opacity(isToday ? 0.18 : 0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isToday ? Color.forge.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.forge.opacity(0.2), lineWidth: 1))
    }

    private func seanceShort(_ s: String) -> String {
        switch s {
        case "Push A":             return "PSH A"
        case "Pull A":             return "PLL A"
        case "Legs":               return "LEGS"
        case "Push B":             return "PSH B"
        case "Pull B + Full Body": return "PLL B"
        case "Yoga / Tai Chi":     return "YOGA"
        case "Recovery":           return "REC"
        default:
            // First 4 chars for custom seances
            return s.count > 4 ? String(s.prefix(4)).uppercased() : s.uppercased()
        }
    }

    private func seanceColor(_ s: String) -> Color { SessionType(s).color }
}

// MARK: - Evening Schedule Card

struct EveningScheduleCard: View {
    @Binding var eveningSchedule: [String: String]
    let dayNames: [String]
    let sessions: [String]
    let onSave: () -> Void

    private let none = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.appCaption)
                        .foregroundColor(Color.statusBlue)
                    Text("SOIR")
                        .font(.appCaption.weight(.black))
                        .tracking(2)
                        .foregroundColor(Color.statusBlue)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.statusBlue.opacity(0.12))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Séance du soir")
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(Color.appOnSurface.opacity(0.85))
                    Text("Optionnel — apparaît sur le dashboard le soir")
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(dayNames, id: \.self) { day in
                    let current = eveningSchedule[day] ?? none
                    Menu {
                        Button(none) {
                            eveningSchedule.removeValue(forKey: day)
                            onSave()
                        }
                        ForEach(sessions, id: \.self) { s in
                            Button(s) {
                                eveningSchedule[day] = s
                                onSave()
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day)
                                .font(.appCaption.weight(.medium))
                                .foregroundColor(.gray)
                            Text(shortLabel(current))
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(current == none ? Color.gray.opacity(0.4) : sessionColor(current))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background((current == none ? Color.gray : sessionColor(current)).opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusBlue.opacity(0.25), lineWidth: 1))
    }

    private func shortLabel(_ s: String) -> String {
        switch s {
        case "Push A":             return "PSH A"
        case "Pull A":             return "PLL A"
        case "Legs":               return "LEGS"
        case "Push B":             return "PSH B"
        case "Pull B + Full Body": return "PLL B"
        case "Yoga / Tai Chi":     return "YOGA"
        case "Recovery":           return "REC"
        default:                   return "—"
        }
    }

    private func sessionColor(_ s: String) -> Color { SessionType(s).color }
}

/// MARK: - Volume Card

private struct VolumeCard: View {
    let volumeByMuscle: [String: Int]
    let mev: [String: Int]
    let mav: [String: Int]
    let alerts: [String]

    @State private var expanded = false

    private let muscleOrder = ["Pecs", "Dos", "Jambes", "Épaules", "Biceps", "Triceps", "Fessiers", "Core"]

    private var sortedMuscles: [(String, Int)] {
        muscleOrder.compactMap { m in
            guard let v = volumeByMuscle[m] else { return nil }
            return (m, v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.appCaption.weight(.bold))
                        .foregroundColor(Color.statusPurple)
                    Text("VOLUME HEBDO")
                        .font(.appCaption.weight(.black))
                        .tracking(1.5)
                        .foregroundColor(Color.statusPurple)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.statusPurple.opacity(0.1))
                .cornerRadius(6)

                Spacer()

                if !alerts.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.appCaption)
                            .foregroundColor(Color.forge)
                        Text("\(alerts.count) sous MEV")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.forge)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                        .padding(.leading, 6)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(sortedMuscles, id: \.0) { muscle, sets in
                        let mevVal = mev[muscle] ?? 0
                        let mavVal = mav[muscle] ?? 12
                        let fraction = CGFloat(min(sets, mavVal)) / CGFloat(mavVal)
                        let barColor: Color = sets < mevVal ? .appDanger : sets <= mavVal ? .appSuccess : .appWarning

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(muscle)
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(Color.appOnSurface.opacity(0.85))
                                Spacer()
                                Text("\(sets) sets")
                                    .font(.appCaption.weight(.bold))
                                    .foregroundColor(barColor)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.appSeparatorSubtle)
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .frame(width: geo.size.width * fraction, height: 5)
                                    // MEV marker
                                    let mevX = geo.size.width * CGFloat(mevVal) / CGFloat(mavVal)
                                    Rectangle()
                                        .fill(Color.appOnSurface.opacity(0.3))
                                        .frame(width: 1, height: 7)
                                        .offset(x: min(mevX, geo.size.width - 1), y: -1)
                                }
                            }
                            .frame(height: 5)
                            HStack {
                                Text("MEV \(mevVal)")
                                    .font(.appMicro)
                                    .foregroundColor(.gray.opacity(0.5))
                                Spacer()
                                Text("MAV \(mavVal)")
                                    .font(.appMicro)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        }
                        .padding(8)
                        .background(barColor.opacity(0.06))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(barColor.opacity(0.2), lineWidth: 1))
                    }
                }

                if !alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(alerts, id: \.self) { alert in
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.appCaption)
                                    .foregroundColor(Color.forge)
                                Text(alert)
                                    .font(.appCaption)
                                    .foregroundColor(Color.forge.opacity(0.85))
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.forge.opacity(0.07))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.forge.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusPurple.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Create Seance Sheet

struct CreateSeanceSheet: View {
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmDiscard = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isDirty: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOM DE LA SÉANCE")
                            .font(.appCaption.weight(.bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("ex: Upper A, Core, Mobility…", text: $name)
                            .font(.appHeadline.weight(.regular))
                            .foregroundColor(.appTextPrimary)
                            .padding()
                            .background(Color.appCard)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    // Quick name chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["Upper A", "Upper B", "Lower A", "Lower B", "Core", "Mobility", "Full Body", "Cardio"], id: \.self) { preset in
                                Button { name = preset } label: {
                                    Text(preset)
                                        .font(.appCaption.weight(.medium))
                                        .foregroundColor(name == preset ? .onAccent : .appOnSurface)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(name == preset ? Color.forge : Color.appCard)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Nouvelle séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed)
                        dismiss()
                    }
                    .foregroundColor(canSave ? Color.forge : .gray)
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Les valeurs saisies seront perdues.")
            }
        }
    }
}

// MARK: - Active Programme Banner

private struct ActiveProgrammeBanner: View {
    let programmeName: String
    let phase: String
    let phaseColor: Color
    let week: Int
    let totalWeeks: Int
    let started: Bool
    let todaySession: String?

    private var progress: Double {
        guard started, totalWeeks > 0 else { return 0 }
        return min(Double(week) / Double(totalWeeks), 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if !programmeName.isEmpty {
                        Text(programmeName.uppercased())
                            .font(.appMicro.weight(.black)).tracking(1.5)
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    HStack(spacing: 8) {
                        Text(phase)
                            .font(.appLabel.weight(.bold))
                            .foregroundColor(phaseColor)
                        if started {
                            Text("·")
                                .foregroundColor(.gray.opacity(0.4))
                                .font(.appLabel)
                            Text("Semaine \(week)")
                                .font(.appLabel.weight(.regular))
                                .foregroundColor(Color.appOnSurface.opacity(0.7))
                        }
                    }
                    if let session = todaySession {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.appMicro)
                                .foregroundColor(Color.forge)
                            Text(session)
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(Color.forge.opacity(0.9))
                        }
                    }
                }
                Spacer()
                if started {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(phaseColor)
                        Text("du cycle")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, started ? 10 : 14)

            if started {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appSeparatorSubtle).frame(height: 3)
                        Capsule()
                            .fill(LinearGradient(colors: [phaseColor.opacity(0.6), phaseColor],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
        .background(Color.appCard)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(phaseColor.opacity(0.15), lineWidth: 1))
        .cornerRadius(12)
    }
}
