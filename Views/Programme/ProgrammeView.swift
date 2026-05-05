import SwiftUI

private let kBaseURL = "https://training-os-rho.vercel.app"

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
        case .hypertrophie: return .orange
        case .force:        return .red
        case .peak:         return .yellow
        case .deload:       return .green
        }
    }

    @State private var mutationCount = 0
    @State private var lastSaveError = false

    // Session reorder
    @State private var sessionOrder: [String] = []
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
        let key = "session_order_\(selectedProgramId.isEmpty ? "default" : selectedProgramId)"
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            var ordered = saved.filter { existing.contains($0) }
            let missing = orderedSeances.filter { !ordered.contains($0) }
            ordered += missing
            sessionOrder = ordered
        } else {
            sessionOrder = orderedSeances
        }
    }

    private func saveSessionOrder() {
        let key = "session_order_\(selectedProgramId.isEmpty ? "default" : selectedProgramId)"
        UserDefaults.standard.set(sessionOrder, forKey: key)
    }

    struct UndoDeleteItem {
        let seance: String
        let name: String
        let scheme: String
        let orderIndex: Int
    }
    @State private var undoDeleteItem: UndoDeleteItem? = nil
    @State private var undoDeleteTask: Task<Void, Never>? = nil

    // Multi-programmes
    @State private var programs: [ProgramInfo] = []
    @State private var selectedProgramId: String = ""
    @State private var allSessions: [String] = []         // toutes les sessions, tous programmes
    @State private var showCreateProgram = false
    @State private var newProgramName = ""
    @State private var renameProgramTarget: ProgramInfo? = nil
    @State private var renameProgramName = ""
    @State private var deleteProgramTarget: ProgramInfo? = nil
    @State private var confirmDeleteProgram = false

    private let dayNames    = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    private let seanceOrder = ["Push A", "Pull A", "Legs", "Push B", "Pull B + Full Body", "Yoga / Tai Chi", "Recovery"]

    /// Known seances in canonical order, then any custom seances alphabetically.
    var orderedSeances: [String] {
        let known  = seanceOrder.filter { fullProgram[$0] != nil }
        let custom = fullProgram.keys.filter { !seanceOrder.contains($0) }.sorted()
        return known + custom
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.orange)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // ── Onglets programmes ────────────────────────
                            if !programs.isEmpty {
                                ProgramTabsView(
                                    programs: programs,
                                    selectedId: $selectedProgramId,
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
                                        .font(.system(size: 13))
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Clipboard")
                                            .font(.system(size: 10, weight: .bold))
                                            .tracking(1)
                                            .foregroundColor(.gray)
                                        Text(clipboardLabel)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    Button {
                                        clipboardData = "{}"
                                        clipboardName = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.orange.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                                .transition(.opacity.combined(with: .move(edge: .top)))
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
                            Text("\"\(item.name)\" supprimé")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Button("Annuler") { undoDelete() }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(hex: "1c1c2e"))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: undoDeleteItem != nil)
                    .zIndex(10)
                }
            }
            .navigationTitle("Programme")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        if mutationCount > 0 {
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.7).tint(.orange)
                                Text("Sauvegarde…")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        } else if lastSaveError {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                Text("Erreur réseau")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .transition(.opacity)
                        }
                        Button { showCreateSeance = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
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
        .task { await loadData() }
        .onChange(of: selectedProgramId) { _, newId in
            guard !newId.isEmpty else { return }
            Task { await loadData(programId: newId) }
        }
    }

    // MARK: – Body helpers (extracted to keep type-checker happy)

    private var sessionsList: [String] { allSessions.isEmpty ? orderedSeances : allSessions }

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
            onEdit:       { ex, scheme in editTarget = ExerciseTarget(seance: seance, exercise: ex, scheme: scheme) },
            onDelete:     { ex in deleteWithUndo(seance: seance, exercise: ex) },
            onReorder:    { order in Task { await reorderExercises(seance: seance, order: order) } },
            onDeleteSeance: {
                deleteSeanceTarget = seance
                confirmDeleteSeance = true
            },
            onCopy:  { copySeance(name: seance, exercises: fullProgram[seance] ?? [:]) },
            onPaste: pasteAction,
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
            }
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
        // Programs
        if let rawPrograms = json["programs"] as? [[String: Any]] {
            programs = rawPrograms.compactMap { d in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return ProgramInfo(id: id, name: name)
            }
        }
        if let pid = json["current_program_id"] as? String, !pid.isEmpty {
            if selectedProgramId.isEmpty { selectedProgramId = pid }
        }
        if let sessions = json["all_sessions"] as? [String] {
            allSessions = sessions
        }
        refreshSessionOrder()
    }

    private func loadData(programId: String? = nil) async {
        var urlStr = "\(kBaseURL)/api/programme_data"
        let pid = programId ?? (selectedProgramId.isEmpty ? nil : selectedProgramId)
        if let pid = pid { urlStr += "?program_id=\(pid)" }
        let url = URL(string: urlStr)!
        // Affichage immédiat depuis cache
        if let cached = CacheService.shared.load(for: "programme_data"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            await MainActor.run { applyJSON(json); isLoading = false }
        }
        // Fetch programme + evening schedule en parallèle
        async let progFetch = URLSession.authed.data(from: url)
        async let eveningFetch = URLSession.authed.data(from: URL(string: "\(kBaseURL)/api/evening_schedule")!)
        if let (data, _) = try? await progFetch,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            CacheService.shared.save(data, for: "programme_data")
            await MainActor.run { applyJSON(json); isLoading = false }
        } else {
            await MainActor.run { isLoading = false }
        }
        if let (eData, _) = try? await eveningFetch,
           let eJson = try? JSONSerialization.jsonObject(with: eData) as? [String: String] {
            await MainActor.run { eveningSchedule = eJson }
        }
    }

    private func saveEveningSchedule() async {
        guard let url = URL(string: "\(kBaseURL)/api/evening_schedule") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: eveningSchedule)
        _ = try? await URLSession.authed.data(for: req)
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
        _ = try? await URLSession.authed.data(for: req)
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
        guard let (data, _) = try? await URLSession.authed.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid  = json["id"] as? String else { return }
        CacheService.shared.clear(for: "programme_data")
        await MainActor.run {
            let p = ProgramInfo(id: pid, name: name)
            programs.append(p)
            selectedProgramId = pid
            fullProgram = [:]
            exerciseOrder = [:]
        }
    }

    private func renameProgram(id: String, name: String) async {
        guard let url = URL(string: "\(kBaseURL)/api/programs") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "rename", "program_id": id, "name": name])
        _ = try? await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "programme_data")
        await MainActor.run {
            if let idx = programs.firstIndex(where: { $0.id == id }) {
                programs[idx] = ProgramInfo(id: id, name: name)
            }
        }
    }

    private func deleteProgram(id: String) async {
        guard let url = URL(string: "\(kBaseURL)/api/programs") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "delete", "program_id": id])
        _ = try? await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "programme_data")
        await MainActor.run {
            programs.removeAll { $0.id == id }
            if selectedProgramId == id { selectedProgramId = programs.first?.id ?? "" }
        }
        await loadData(programId: selectedProgramId.isEmpty ? nil : selectedProgramId)
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

    private let totalWeeks = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(color)
                    .font(.system(size: 13, weight: .bold))
                Text("Périodisation")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                if started {
                    Button(action: onReset) {
                        Text("Nouveau mésocycle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(color)
                    }
                    .buttonStyle(.plain)
                }
            }

            if started {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(phase)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(color)
                    Text("— Semaine \(week)/\(totalWeeks)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(min(week, totalWeeks)) / CGFloat(totalWeeks), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Label(scheme, systemImage: "dumbbell")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                    Spacer()
                    Text("→ \(next)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }

                if let apply = onApply {
                    Button(action: apply) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                            Text("Appliquer à tout le programme")
                                .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 13, weight: .semibold))
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
        .background(Color(hex: "11111c"))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
        .cornerRadius(14)
    }
}

// MARK: - ProgramTabsView

private struct ProgramTabsView: View {
    let programs: [ProgramInfo]
    @Binding var selectedId: String
    let onAdd: () -> Void
    let onRename: (ProgramInfo) -> Void
    let onDelete: (ProgramInfo) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(programs) { prog in
                    let isSelected = selectedId == prog.id
                    Text(prog.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isSelected ? Color.orange : Color.white.opacity(0.08))
                        )
                        .onTapGesture { selectedId = prog.id }
                        .contextMenu {
                            Button("Renommer") { onRename(prog) }
                            Button("Supprimer", role: .destructive) { onDelete(prog) }
                        }
                }
                // Bouton "+"
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
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
    var onSessionDragChanged: ((CGFloat) -> Void)? = nil
    var onSessionDragEnded:   (() -> Void)? = nil

    @State private var expanded    = true
    @State private var dragging:   String? = nil
    @State private var dragY:      CGFloat = 0
    @State private var rowHeights: [String: CGFloat] = [:]

    var color: Color {
        switch seance {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .gray
        }
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
                        .font(.system(size: 14))
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
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(color)
                    )
                Text(seance)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(color)
                Spacer()
                Text("\(exercises.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(8)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                        .padding(7)
                        .background(color.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                if let copy = onCopy {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundColor(.orange.opacity(0.7))
                            .padding(7)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                if let paste = onPaste {
                    Button(action: paste) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13))
                            .foregroundColor(.cyan.opacity(0.7))
                            .padding(7)
                            .background(Color.cyan.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                if let del = onDeleteSeance {
                    Button(action: del) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.red.opacity(0.6))
                            .padding(7)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }

            if expanded {
                Divider().background(Color.white.opacity(0.07))

                if orderedPairs.isEmpty {
                    HStack {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundColor(color.opacity(0.5))
                        Text("Aucun exercice — tape + pour en ajouter")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }

                ForEach(orderedPairs, id: \.0) { name, scheme in
                    let isDragging = dragging == name
                    HStack(spacing: 0) {
                        // ≡ Drag handle
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.5))
                            .frame(width: 40)
                            .contentShape(Rectangle())
                            .gesture(dragGesture(for: name))

                        // Exercise row (tap → edit, trash → delete)
                        ExerciseRow(
                            name:     name,
                            scheme:   scheme,
                            color:    color,
                            onTap:    { onEdit(name, scheme) },
                            onDelete: { onDelete(name) }
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
                        Divider().background(Color.white.opacity(0.04)).padding(.leading, 40)
                    }
                }
                .onPreferenceChange(ProgramRowHeightKey.self) { rowHeights.merge($0) { $1 } }
            }
        }
        .background(Color(hex: "11111c"))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
        .cornerRadius(14)
    }
}

struct ExerciseRow: View {
    let name: String
    let scheme: String
    let color: Color
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(scheme)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.15))
                    .cornerRadius(6)
                    .lineLimit(1)
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.6))
                        .padding(6)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
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
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scheme = "3x8-12"

    private var filtered: [String] {
        name.isEmpty ? inventory : inventory.filter { $0.localizedCaseInsensitiveContains(name) }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !scheme.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 0) {
                    // Name field (also filters inventory)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Nom de l'exercice...", text: $name)
                            .foregroundColor(.white)
                        if !name.isEmpty {
                            Button { name = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(hex: "11111c"))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Scheme field
                    HStack {
                        Text("Schéma :")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        TextField("ex: 4x6-8", text: $scheme)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color(hex: "11111c"))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

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
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                    Spacer()
                                    if name == ex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color(hex: "11111c"))
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
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !scheme.isEmpty else { return }
                        onAdd(trimmed, scheme)
                        dismiss()
                    }
                    .foregroundColor(canSave ? .orange : .gray)
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Edit Scheme Sheet

struct EditSchemeSheet: View {
    let target: ExerciseTarget
    let onSave: (String, String) -> Void  // (newName, newScheme)

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var scheme: String = ""

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !scheme.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810")
                    .ignoresSafeArea()
                    .onTapGesture { hideKeyboard() }
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nom de l'exercice")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("Nom", text: $name)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(hex: "11111c"))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schéma de sets/reps")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("ex: 4x6-8", text: $scheme)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(hex: "11111c"))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    // Suggestions rapides
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["3x5", "4x5-7", "3x8-10", "4x8-10", "3x10-12", "4x12-15", "3x15"], id: \.self) { s in
                                Button { scheme = s } label: {
                                    Text(s)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(scheme == s ? .black : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(scheme == s ? Color.orange : Color(hex: "11111c"))
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
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !scheme.isEmpty else { return }
                        onSave(trimmed, scheme)
                        dismiss()
                    }
                    .foregroundColor(canSave ? .orange : .gray)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear { name = target.exercise; scheme = target.scheme }
    }
}

// MARK: - Editable Week Schedule Card

struct EditableWeekScheduleCard: View {
    @Binding var schedule: [String: String]
    let dayNames: [String]
    let sessions: [String]
    let onSave: () -> Void

    private let none = "Repos"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                    Text("MATIN")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Semaine type")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Appuie sur un jour pour changer la séance")
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(dayNames, id: \.self) { day in
                    let current = schedule[day] ?? none
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
                            Text(day)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                            Text(seanceShort(current))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(current == none ? Color.gray.opacity(0.4) : seanceColor(current))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background((current == none ? Color.gray : seanceColor(current)).opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2), lineWidth: 1))
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

    private func seanceColor(_ s: String) -> Color {
        switch s {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .orange
        }
    }
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
                        .font(.system(size: 12))
                        .foregroundColor(.indigo)
                    Text("SOIR")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2)
                        .foregroundColor(.indigo)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.indigo.opacity(0.12))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Séance du soir")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Optionnel — apparaît sur le dashboard le soir")
                        .font(.system(size: 11))
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
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                            Text(shortLabel(current))
                                .font(.system(size: 11, weight: .bold))
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
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.25), lineWidth: 1))
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

    private func sessionColor(_ s: String) -> Color {
        switch s {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .indigo
        }
    }
}

// MARK: - Create Seance Sheet

struct CreateSeanceSheet: View {
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOM DE LA SÉANCE")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("ex: Upper A, Core, Mobility…", text: $name)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(hex: "11111c"))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    // Quick name chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["Upper A", "Upper B", "Lower A", "Lower B", "Core", "Mobility", "Full Body", "Cardio"], id: \.self) { preset in
                                Button { name = preset } label: {
                                    Text(preset)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(name == preset ? .black : .white)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(name == preset ? Color.orange : Color(hex: "11111c"))
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
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed)
                        dismiss()
                    }
                    .foregroundColor(canSave ? .orange : .gray)
                    .disabled(!canSave)
                }
            }
        }
    }
}
