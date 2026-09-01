import SwiftUI

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

// MARK: - Périodisation (source unique 5 phases)
// Une seule définition : cases, semaines, verbe, spec chiffrée, repos, pourquoi,
// short scheme, rôle badge. Tout consommateur (mesocycleCard, mesocycleRow,
// mesocycleActions) dérive d'ici.
fileprivate enum Phase: String, CaseIterable {
    case accumulation    = "Accumulation"
    case intensification = "Intensification"
    case force           = "Force"
    case peak            = "Peak"
    case deload          = "Deload"
    case completed       = "Cycle terminé"

    var weeks: ClosedRange<Int> {
        switch self {
        case .accumulation:    return 1...2
        case .intensification: return 3...4
        case .force:           return 5...8
        case .peak:            return 9...10
        case .deload:          return 11...11
        case .completed:       return 12...Int.max
        }
    }

    var verb: String {
        switch self {
        case .accumulation:    return "Empile le volume"
        case .intensification: return "Monte la charge"
        case .force:           return "Pousse tes charges"
        case .peak:            return "Vise le PR"
        case .deload:          return "Récupère"
        case .completed:       return "Cycle terminé"
        }
    }

    var scheme: String {
        switch self {
        case .accumulation:    return "4 × 10-12, 65-70% 1RM"
        case .intensification: return "4 × 6-8, 75-82% 1RM"
        case .force:           return "4-5 × 4-6, 82-90% 1RM"
        case .peak:            return "5 × 1-3, 90-95% 1RM"
        case .deload:          return "3 × 8-10, 55-65% 1RM"
        case .completed:       return "Démarre le prochain."
        }
    }

    var shortScheme: String {
        switch self {
        case .accumulation:    return "4x11"
        case .intensification: return "4x7"
        case .force:           return "5x5"
        case .peak:            return "5x2"
        case .deload:          return "3x9"
        case .completed:       return "—"
        }
    }

    var rest: String {
        switch self {
        case .accumulation:    return "90s"
        case .intensification: return "2min"
        case .force:           return "3min"
        case .peak:            return "4min"
        case .deload:          return "90s"
        case .completed:       return "—"
        }
    }

    var why: String {
        switch self {
        case .accumulation:    return "Poser la base — préparer les tissus."
        case .intensification: return "Adapter le système nerveux."
        case .force:           return "Recruter les fibres, gagner du kilo."
        case .peak:            return "Test max, expression de la force."
        case .deload:          return "Vider la fatigue, préparer le prochain cycle."
        case .completed:       return "Nouveau cycle = nouvelle base à décider."
        }
    }

    var badgeRole: BadgeRole {
        switch self {
        case .accumulation:    return .info
        case .intensification: return .warning
        case .force:           return .alert
        case .peak:            return .evening
        case .deload:          return .success
        case .completed:       return .neutral
        }
    }

    var color: Color { badgeRole.color }

    var next: Phase {
        let all = Phase.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    static func at(week: Int) -> Phase {
        let w = max(1, week)
        // Fallback .completed (pas .deload) — au-delà de S11, le cycle est fini.
        // Pas d'auto-wrap : le prochain cycle démarre par un geste utilisateur
        // explicite (bouton POST cycle_start_date).
        return Phase.allCases.first { $0.weeks.contains(w) } ?? .completed
    }
}

struct ProgrammeView: View {
    // Toute donnée serveur + runtime mutation vit dans le VM (@Published). La vue
    // lit vm.xxx et écrit via bindings/setters directs. Seuls les états UI-LOCAL
    // (sheets, alerts, drag transitoire, clipboard @AppStorage, undo, périodisation)
    // restent ici.
    @StateObject private var vm = ProgrammeViewModel()
    // Sert au flush du delete-undo en attente si l'app quitte < 4 s
    // (cf. commitPendingDelete + .onChange(of: scenePhase)).
    @Environment(\.scenePhase) private var scenePhase

    private enum ProgrammeTab: String, CaseIterable, Identifiable {
        case today = "Aujourd'hui"
        case week = "Semaine"
        case structure = "Structure"
        var id: String { rawValue }
    }
    @State private var selectedTab: ProgrammeTab = .today
    @State private var showSeanceSoirSheet = false
    @State private var seance2ExosToday: Set<String> = []
    @State private var addTarget: SeanceName?
    @State private var editTarget: ExerciseTarget?
    @State private var showCreateSeance = false
    @State private var deleteSeanceTarget: String? = nil
    @State private var confirmDeleteSeance = false
    @AppStorage("programme_clipboard")      private var clipboardData: String = "{}"
    @AppStorage("programme_clipboard_name") private var clipboardName: String = ""
    // Source unique : vm.cycleStartDate (@Published, hydraté depuis /api/programme_data).
    // Le @AppStorage("periodisation_start") legacy est migré au premier load via
    // ProgrammeViewModel.migrateLegacyCycleStartDateIfNeeded — cette computed
    // laisse les 4 readers inchangés (ils lisent .isEmpty comme avant).
    private var periodisationStart: String { vm.cycleStartDate ?? "" }
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
        var prog = vm.fullProgram[seance] ?? [:]
        for (ex, scheme) in pasted { prog[ex] = scheme }
        vm.fullProgram[seance] = prog
        clipboardData = "{}"
        clipboardName = ""
        Task {
            for (ex, scheme) in pasted {
                await vm.addExercise(seance: seance, exercise: ex, scheme: scheme)
            }
        }
    }

    // MARK: - Périodisation (enum Phase = source unique au niveau fichier)
    private var mesocycleWeek: Int {
        guard !periodisationStart.isEmpty,
              let start = DateFormatter.isoDate.date(from: periodisationStart) else { return 0 }
        let days = Int(Date().timeIntervalSince(start) / 86400)
        return max(1, days / 7 + 1)
    }
    private var currentPhase: Phase { Phase.at(week: mesocycleWeek) }

    /// true si le cycle a dépassé S11 sans nouveau démarrage. Fin explicite —
    /// pas d'auto-wrap (fantôme éradiqué). Le prochain cycle démarre par le
    /// bouton "Démarrer un nouveau cycle" qui POST cycle_start_date.
    private var isCycleComplete: Bool {
        !periodisationStart.isEmpty && mesocycleWeek > TrainingDoctrine.mesocycleWeeks
    }

    private func applyPhaseScheme() async {
        let scheme = currentPhase.shortScheme
        for (seance, exercises) in vm.fullProgram {
            for exercise in exercises.keys {
                await vm.editExercise(seance: seance, oldName: exercise, newName: exercise, scheme: scheme)
            }
        }
    }

    // Accordion Structure : une seule séance dépliée à la fois. nil = tout replié
    // (défaut). Rempli par tap header, ou auto après createSeance pour amener
    // Vince direct sur la nouvelle carte + AddExerciseSheet.
    @State private var expandedSeance: String? = nil

    struct UndoDeleteItem {
        let seance: String
        let name: String
        let scheme: String
        let orderIndex: Int
    }
    @State private var undoDeleteItem: UndoDeleteItem? = nil
    @State private var undoDeleteTask: Task<Void, Never>? = nil

    // Structure tab : jour sélectionné dans la barre 7-pills. Init au jour courant
    // MTL. Aucun guard — un jour vide (Sam en repos, par ex.) est sélectionnable
    // et affiche ses 2 DaySessionCard en état "Aucune séance / + Assigner".
    @State private var selectedDay: String = {
        let names = TrainingDoctrine.dayNames
        let idx = (Calendar.mtl.component(.weekday, from: Date()) + 5) % 7
        return idx < names.count ? names[idx] : (names.first ?? "Lun")
    }()

    // Multi-programmes : programs, selectedProgramId, activeProgramId, allSessions,
    // isSettingActive migrés dans vm.
    @State private var showCreateProgram = false
    @State private var newProgramName = ""
    @State private var renameProgramTarget: ProgramInfo? = nil
    @State private var renameProgramName = ""
    @State private var deleteProgramTarget: ProgramInfo? = nil
    @State private var confirmDeleteProgram = false

    // MARK: - Helpers d'affichage
    // Volume MEV/MAV (weeklyVolumeByMuscle, volumeAlerts) et doctrine ordre
    // (orderedSeances) sont testables dans le VM. Constantes doctrinales
    // (dayNames, canonicalSeanceOrder, muscleMEV/MAV) dans TrainingDoctrine.swift.

    private func isScheduledThisWeek(_ s: String) -> Bool {
        vm.schedule.values.contains(s) || vm.eveningSchedule.values.contains(s)
    }

    private var todaySessionName: String? {
        let weekday = Calendar.mtl.component(.weekday, from: Date())
        let idx = (weekday + 5) % 7  // 1=Sun → idx=6, 2=Mon → idx=0, …, 7=Sat → idx=5
        guard idx < TrainingDoctrine.dayNames.count else { return nil }
        let day = TrainingDoctrine.dayNames[idx]
        return vm.schedule[day].flatMap { $0 == "Repos" ? nil : $0 }
    }

    private var todayDateStr: String {
        DateFormatter.isoDate.string(from: Date())
    }

    private var activeProgrammeName: String {
        vm.programs.first { $0.id == vm.activeProgramId }?.name ?? ""
    }

    // MARK: - Planning UI helpers (structure tab)
    // Note : `todayDayName` déjà défini plus bas (utilisé aussi par weekContent).

    // "Repos" ou nil → nil (état "aucune séance"). Autre → nom séance.
    private var amSeanceForSelectedDay: String? {
        let s = vm.schedule[selectedDay] ?? "Repos"
        return s == "Repos" ? nil : s
    }
    private var pmSeanceForSelectedDay: String? { vm.eveningSchedule[selectedDay] }

    private var amExercisesForSelectedDay: [String: String] {
        amSeanceForSelectedDay.flatMap { vm.fullProgram[$0] } ?? [:]
    }
    private var pmExercisesForSelectedDay: [String: String] {
        pmSeanceForSelectedDay.flatMap { vm.fullProgram[$0] } ?? [:]
    }

    // Assignation AM/PM depuis DaySessionCard. nil = vider le créneau.
    // AM : "Repos" est la convention "pas de séance" côté schedule ; PM : suppression clé.
    private func assignAM(seance: String?) {
        vm.schedule[selectedDay] = seance ?? "Repos"
        Task { await vm.saveSchedule() }
    }
    private func assignPM(seance: String?) {
        if let s = seance { vm.eveningSchedule[selectedDay] = s }
        else { vm.eveningSchedule.removeValue(forKey: selectedDay) }
        Task { await vm.saveEveningSchedule() }
    }

    // orderedSeances migré dans vm — computed sur vm.fullProgram + TrainingDoctrine.

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if vm.isLoading {
                    ProgressView().tint(Color.forge)
                } else {
                    VStack(spacing: 0) {
                        segmentedControl
                        switch selectedTab {
                        case .today:     todayContent
                        case .week:      weekContent
                        case .structure: structureContent
                        }
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
                        .padding(.horizontal, .appCardInsetH).padding(.vertical, .appCardInsetV)
                        .glassCard()
                        .padding(.horizontal, .appPagePadding)
                        .padding(.bottom, fabBottomPadding)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: undoDeleteItem != nil)
                    .zIndex(10)
                }

                if let msg = vm.saveSuccessMsg {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.forge)
                            Text(msg)
                                .font(.appLabel.weight(.medium))
                                .foregroundColor(.appTextPrimary)
                        }
                        .padding(.horizontal, .appCardInsetH).padding(.vertical, .appCardInsetV)
                        .glassCard()
                        .padding(.horizontal, .appPagePadding)
                        .padding(.bottom, fabBottomPadding)
                    }
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.saveSuccessMsg != nil)
                    .zIndex(9)
                }
            }
            .navigationTitle("Programme")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        if vm.mutationCount > 0 {
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.7).tint(Color.forge)
                                Text("Sauvegarde…")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(Color.forge)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        } else if vm.lastSaveError {
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
                    .animation(.easeInOut(duration: 0.2), value: vm.mutationCount)
                    .animation(.easeInOut(duration: 0.2), value: vm.lastSaveError)
                }
            }
            .sheet(isPresented: $showCreateSeance) {
                CreateSeanceSheet { name in
                    Task {
                        await vm.createSeance(name: name)
                        // Focus auto : accordion sur la nouvelle carte + sheet
                        // ajout exercice direct (elle vient d'être créée vide).
                        expandedSeance = name
                        addTarget = SeanceName(id: name)
                    }
                }
            }
            // Doctrine SeanceSoirView : toujours .sheet, jamais push
            // (SeanceSoirView.swift:97-102).
            .sheet(isPresented: $showSeanceSoirSheet) {
                SeanceSoirView(sessionName: manualEveningSessionName)
            }
            .sheet(item: $addTarget) { sn in
                AddExerciseSheet(seance: sn.id, inventory: vm.inventory, inventorySchemes: vm.inventorySchemes, inventoryMuscleGroups: vm.inventoryMuscleGroups) { list in
                    Task { await vm.addExercises(seance: sn.id, exercises: list) }
                }
            }
            .sheet(item: $editTarget) { target in
                EditSchemeSheet(target: target) { newName, newScheme in
                    Task { await vm.editExercise(seance: target.seance, oldName: target.exercise, newName: newName, scheme: newScheme) }
                }
            }
            .alert(deleteSeanceTitle, isPresented: $confirmDeleteSeance) {
                Button("Supprimer", role: .destructive) {
                    if let target = deleteSeanceTarget {
                        Task { await vm.deleteSeance(name: target) }
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
                Text("Tous les exercices du programme passeront au scheme \(currentPhase.shortScheme). Cette action est réversible exercice par exercice.")
            }
            .alert("Nouveau mésocycle ?", isPresented: $showResetMesocycle) {
                Button("Recommencer", role: .destructive) {
                    Task { await vm.saveCycleStartDate(DateFormatter.isoDate.string(from: Date())) }
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
                    Task { await vm.createProgram(name: name) }
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
                    Task { await vm.renameProgram(id: target.id, name: name) }
                    renameProgramTarget = nil
                }
                Button("Annuler", role: .cancel) { renameProgramTarget = nil }
            }
            // ── Supprimer programme ──────────────────────────────
            .alert(deleteProgramTitle, isPresented: $confirmDeleteProgram) {
                Button("Supprimer", role: .destructive) {
                    if let target = deleteProgramTarget {
                        Task { await vm.deleteProgram(id: target.id) }
                    }
                    deleteProgramTarget = nil
                }
                Button("Annuler", role: .cancel) { deleteProgramTarget = nil }
            } message: {
                Text("Toutes les séances de ce programme seront supprimées. Cette action est irréversible.")
            }
        }
        .onAppear {
            seance2ExosToday = APIService.shared.dashboard?.pushedToEvening ?? []
            // Reset synchrone AVANT le Task → applyJSON du refresh lira false.
            // Consolidé avec le loadData ici (au lieu de .task séparé) car
            // .task ne re-fire pas au retour d'onglet en TabView ; .onAppear si.
            // loadData(programId: nil) : à chaque réouverture, charge l'actif
            // serveur (cohérent avec reset). Une consultation en cours ne
            // survit pas à un aller-retour d'onglet — comportement voulu.
            vm.userDidSelect = false
            Task {
                await vm.loadData(programId: nil)
                await vm.loadSuggestions()
            }
        }
        .onDisappear { commitPendingDelete() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commitPendingDelete() }
        }
        .onChange(of: vm.selectedProgramId) { _, newId in
            guard !newId.isEmpty else { return }
            Task { await vm.loadData(programId: newId); await vm.loadSuggestions() }
        }
        // Rafraîchit inventory/inventorySchemes à l'ouverture d'AddExerciseSheet.
        // Résout le cas "exo fraîchement créé au catalogue absent du mapping local"
        // (racine du prefill scheme=nil et du muscle affiché par déduction).
        // Pattern budget : refresh au call site du bouton, pas d'infra de publisher.
        .onChange(of: addTarget?.id) { _, newId in
            guard newId != nil else { return }
            Task { await vm.loadData() }
        }
    }

    // MARK: – Body helpers (extracted to keep type-checker happy)

    private var sessionsList: [String] {
        // Source unique = orderedSeances (dérivé du programme actif via
        // fullProgram.keys + planning). vm.allSessions retirée du picker :
        // c'était un dump cross-programmes qui polluait avec des séances legacy
        // (Legs / Legs B / Lower A) d'anciens programmes archivés.
        // vm.allSessions reste peuplée (VM L47/181) mais sans consommateur
        // runtime — dead-code candidat pour lot de nettoyage futur :
        //   - VM L47 (@Published) + L181 (assignation dans applyJSON)
        //   - backend api/db_programs.py:248 get_all_session_names
        //   - test TrainingOSTests/ProgrammeViewModelTests.swift:39
        //     (vert aujourd'hui mais protège plus rien — à retirer AVEC allSessions,
        //     pas à « réparer » machinalement).
        var seen = Set<String>()
        return vm.orderedSeances.filter { seen.insert($0).inserted }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameProgramTarget != nil },
            set: { if !$0 { renameProgramTarget = nil } }
        )
    }

    private var deleteSeanceTitle: String  { "Supprimer \(deleteSeanceTarget ?? "") ?" }
    private var applyPhaseTitle: String    { "Appliquer \(currentPhase.rawValue) (\(currentPhase.shortScheme)) ?" }
    private var deleteProgramTitle: String { "Supprimer \(deleteProgramTarget?.name ?? "") ?" }

    @ViewBuilder
    private func sessionCard(for seance: String) -> some View {
        // Binding proxy vers vm.fullProgram[seance] : la sous-vue reçoit un slice
        // du dict racine, écrit via setter. Publish sur mutation logique (add/delete/
        // edit) uniquement — pas de perte de focus car les sous-vues (Add/EditSheet)
        // ont leur propre @State pour la frappe.
        let exercisesBinding = Binding<[String: String]>(
            get: { self.vm.fullProgram[seance] ?? [:] },
            set: { self.vm.fullProgram[seance] = $0 }
        )
        let orderedNamesBinding = Binding<[String]>(
            get: {
                if let names = self.vm.exerciseOrder[seance] { return names }
                return self.vm.fullProgram[seance]?.keys.sorted() ?? []
            },
            set: { self.vm.exerciseOrder[seance] = $0 }
        )
        let pasteAction: Optional<() -> Void> = clipboard.isEmpty
            ? Optional<() -> Void>.none
            : Optional<() -> Void>.some({ self.pasteSeance(into: seance) })
        // Accordion single-open : ce binding traduit le tap header en toggle
        // dans expandedSeance (nil ↔ seance). Une seule carte dépliée à la fois.
        let expandedBinding = Binding<Bool>(
            get: { self.expandedSeance == seance },
            set: { open in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.expandedSeance = open ? seance : nil
                }
            }
        )
        EditableSeanceProgramCard(
            seance:       seance,
            exercises:    exercisesBinding,
            orderedNames: orderedNamesBinding,
            isExpanded:   expandedBinding,
            onAdd:        { addTarget = SeanceName(id: seance) },
            onEdit:       { ex, scheme in
                let w = vm.exerciseWeights[ex]
                editTarget = ExerciseTarget(seance: seance, exercise: ex, scheme: scheme, lastWeight: w?.weight, lastReps: w?.reps, lastDate: w?.date)
            },
            onDelete:     { ex in deleteWithUndo(seance: seance, exercise: ex) },
            onReorder:    { order in Task { await vm.reorderExercises(seance: seance, order: order) } },
            onDeleteSeance: {
                deleteSeanceTarget = seance
                confirmDeleteSeance = true
            },
            onCopy:  { copySeance(name: seance, exercises: vm.fullProgram[seance] ?? [:]) },
            onPaste: pasteAction,
            isToday: seance == todaySessionName,
            seance2ExosToday: seance == todaySessionName ? seance2ExosToday : [],
            supersets:        vm.exerciseSupersets[seance] ?? [:],
            exerciseWeights:  vm.exerciseWeights,
            suggestions:      vm.programSuggestions[seance] ?? [:],
            inventoryPatterns: vm.inventoryPatterns,
            inventoryMuscleGroups: vm.inventoryMuscleGroups,
            inventoryOneRM:    vm.inventoryOneRM
        )
        .padding(.horizontal, .appPagePadding)
        .opacity(isScheduledThisWeek(seance) ? 1.0 : 0.55)
    }

    // MARK: – Undo delete (UI)
    //
    // Seuls handlers async encore en vue : delegate au VM après logique UI-locale.
    //  - deleteWithUndo : delete local optimiste + task 4s → vm.deleteExercise.
    //  - undoDelete : cancel task + restore local, zéro POST.
    //  - applyPhaseScheme (plus haut) : loop → vm.editExercise.
    //  - pasteSeance (plus haut) : clipboard @AppStorage → boucle vm.addExercise.

    /// Flush immédiat du delete-undo en attente : cancel le Task différé et
    /// POST tout de suite. Anti-double-POST par construction : le Task original,
    /// s'il se réveille après cancel, voit `!Task.isCancelled == false` et
    /// return (cf. sleep+guard L637-642). Idempotent : 2e invocation quasi-
    /// simultanée voit undoDeleteItem=nil et no-op.
    ///
    /// Appelé depuis 3 sites :
    ///  - deleteWithUndo (nouveau delete pendant qu'un précédent attend)
    ///  - .onDisappear (l'onglet Programme quitte)
    ///  - .onChange(of: scenePhase) quand phase ≠ .active (app background/inactive)
    private func commitPendingDelete() {
        guard let item = undoDeleteItem else { return }
        undoDeleteTask?.cancel()
        undoDeleteTask = nil
        undoDeleteItem = nil
        Task { await vm.deleteExercise(seance: item.seance, exercise: item.name) }
    }

    /// Delete local optimiste + POST tardif via Task { sleep 4s }. Le cancel
    /// (undoDelete) restaure l'état local ET annule le task avant le POST — zéro
    /// trafic serveur si annulé dans les 4s.
    private func deleteWithUndo(seance: String, exercise: String) {
        // Commit any previous pending delete immediately
        commitPendingDelete()
        // Snapshot for undo
        let idx = vm.exerciseOrder[seance]?.firstIndex(of: exercise) ?? 0
        let scheme = vm.fullProgram[seance]?[exercise] ?? ""
        // Optimistic local removal
        vm.fullProgram[seance]?.removeValue(forKey: exercise)
        vm.exerciseOrder[seance]?.removeAll { $0 == exercise }
        // Show undo toast
        withAnimation { undoDeleteItem = UndoDeleteItem(seance: seance, name: exercise, scheme: scheme, orderIndex: idx) }
        // Auto-commit after 4 s
        undoDeleteTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await vm.deleteExercise(seance: seance, exercise: exercise)
            await MainActor.run { withAnimation { undoDeleteItem = nil } }
        }
    }

    private func undoDelete() {
        guard let item = undoDeleteItem else { return }
        undoDeleteTask?.cancel()
        undoDeleteTask = nil
        // Restore local state
        vm.fullProgram[item.seance, default: [:]][item.name] = item.scheme
        let idx = min(item.orderIndex, vm.exerciseOrder[item.seance]?.count ?? 0)
        vm.exerciseOrder[item.seance, default: []].insert(item.name, at: idx)
        withAnimation { undoDeleteItem = nil }
    }
    // MARK: - Direction B — tab helpers

    // Résolution du soir : override manuel > héritage du matin > rien.
    // isInherited=true si le nom vient du planning matin (soir non peuplé sauf via
    // SeanceSplitStore). Miroir iOS du fallback backend get_today_evening().
    private var todayEveningResolved: (name: String, isInherited: Bool)? {
        let weekday = Calendar.mtl.component(.weekday, from: Date())
        let idx = (weekday + 5) % 7
        guard idx < TrainingDoctrine.dayNames.count else { return nil }
        let day = TrainingDoctrine.dayNames[idx]
        if let manual = vm.eveningSchedule[day], !manual.isEmpty, manual != "Repos" {
            return (manual, false)
        }
        if let morning = vm.schedule[day], !morning.isEmpty, morning != "Repos" {
            return (morning, true)
        }
        return nil
    }

    private var todayEveningSessionName: String? { todayEveningResolved?.name }

    // Nom soir à passer au sheet SeanceSoirView : uniquement si override manuel
    // (evening_schedule set explicitement). Héritage matin = nil → SeanceSoirView
    // charge le matin et affiche « — suite ». Cf. fix override.
    private var manualEveningSessionName: String? {
        guard let r = todayEveningResolved, !r.isInherited else { return nil }
        return r.name
    }

    @ViewBuilder
    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(ProgrammeTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(selectedTab == tab ? .appTextPrimary : .appTextSecondary)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(selectedTab == tab ? .forge : .clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, .appPagePadding)
        .padding(.top, 4)
    }

    // MARK: - Tab Aujourd'hui

    private var todayContent: some View {
        ScrollView {
            if vm.fullProgram.isEmpty {
                emptyProgrammePlaceholder
            } else {
                VStack(spacing: .appSectionSpacing) {
                    heroMatin
                    heroSoir
                    volumeRow
                    mesocycleRow
                }
                .padding(.vertical, 16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            CacheService.shared.clear(for: "programme_data")
            seance2ExosToday = APIService.shared.dashboard?.pushedToEvening ?? []
            await vm.loadData(programId: vm.selectedProgramId.isEmpty ? nil : vm.selectedProgramId)
        }
    }

    @ViewBuilder
    private var heroMatin: some View {
        if let name = todaySessionName {
            heroCard(sessionName: name, badge: "MATIN", role: .info) {
                NavigationLink(destination: SeanceView()) {
                    heroCTA
                }
                .buttonStyle(.plain)
            }
        } else {
            restCard(text: "Repos aujourd'hui")
        }
    }

    @ViewBuilder
    private var heroSoir: some View {
        if let resolved = todayEveningResolved {
            if resolved.isInherited {
                inheritedHeroSoir(morningName: resolved.name)
            } else {
                heroCard(sessionName: resolved.name, badge: "SOIR", role: .evening) {
                    Button {
                        showSeanceSoirSheet = true
                    } label: {
                        heroCTA
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            restCard(text: "Repos ce soir")
        }
    }

    // Hero SOIR hérité — non peuplé par défaut. Le sous-titre reflète les exos
    // que Vince a envoyés depuis la séance matin via SeanceSplitStore (flèche →
    // dans WorkoutActiveView). "Rien d'envoyé pour l'instant" = état vide sobre.
    // On n'affiche pas la liste des exos matin ici : l'invariant est "un exo
    // matin OU soir, jamais les deux" — le soir hérite du NOM, pas du CONTENU.
    @ViewBuilder
    private func inheritedHeroSoir(morningName: String) -> some View {
        let n = seance2ExosToday.count
        let subtitle = n > 0
            ? "\(n) exercice\(n > 1 ? "s" : "") envoyé\(n > 1 ? "s" : "") ce matin"
            : "Rien d'envoyé pour l'instant"
        VStack(alignment: .leading, spacing: 16) {
            AppBadge("SOIR", role: .evening)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(morningName) (suite)").font(.appHero).foregroundColor(.appTextPrimary)
                Text(subtitle).font(.appLabel).foregroundColor(.appTextSecondary)
            }
            Button {
                showSeanceSoirSheet = true
            } label: {
                heroCTA
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, .appCardInsetH).padding(.vertical, .appCardInsetV)
        .glassCard()
        .padding(.horizontal, .appPagePadding)
    }

    private var heroCTA: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
            Text("COMMENCER")
        }
        .font(.appLabel.weight(.bold))
        .tracking(1.5)
        .foregroundColor(.onAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.forge)
        .cornerRadius(.appCardRadius)
    }

    @ViewBuilder
    private func heroCard<Cta: View>(
        sessionName: String,
        badge: String,
        role: BadgeRole,
        @ViewBuilder cta: () -> Cta
    ) -> some View {
        let exercises = vm.fullProgram[sessionName] ?? [:]
        let ordered = vm.exerciseOrder[sessionName] ?? exercises.keys.sorted()
        VStack(alignment: .leading, spacing: 16) {
            AppBadge(badge, role: role)
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionName).font(.appHero).foregroundColor(.appTextPrimary)
                Text(exercisesCountLabel(exercises.count))
                    .font(.appLabel).foregroundColor(.appTextSecondary)
            }
            if exercises.isEmpty {
                Text("Aucun exercice programmé.")
                    .font(.appLabel).foregroundColor(.appTextSecondary)
                Button {
                    withAnimation { selectedTab = .structure }
                } label: {
                    HStack(spacing: 6) {
                        Text("Voir dans Structure")
                        Image(systemName: "arrow.right")
                    }
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.forge)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 10) {
                    ForEach(ordered, id: \.self) { ex in
                        if let scheme = exercises[ex] {
                            HStack {
                                Text(ex).font(.appBody).foregroundColor(.appTextPrimary)
                                Spacer()
                                Text(scheme).font(.appLabel.weight(.medium)).foregroundColor(.appTextSecondary)
                            }
                        }
                    }
                }
                cta()
            }
        }
        .padding(.horizontal, .appCardInsetH).padding(.vertical, .appCardInsetV)
        .glassCard()
        .padding(.horizontal, .appPagePadding)
    }

    private func restCard(text: String) -> some View {
        HStack(spacing: 12) {
            AppBadge("REPOS", role: .evening)
            Text(text).font(.appLabel).foregroundColor(.appTextSecondary)
            Spacer()
        }
        .padding(.horizontal, .appCardInsetH).padding(.vertical, .appCardInsetV)
        .glassCard()
        .padding(.horizontal, .appPagePadding)
    }

    private func exercisesCountLabel(_ count: Int) -> String {
        count == 0 ? "Aucun exercice" : "\(count) exercice\(count > 1 ? "s" : "")"
    }

    private var volumeRow: some View {
        Button {
            withAnimation { selectedTab = .week }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill").foregroundColor(.forge)
                Text("Volume").font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                Spacer()
                if vm.volumeAlerts.isEmpty {
                    Text("Ok").font(.appLabel).foregroundColor(.appTextSecondary)
                    Image(systemName: "checkmark").foregroundColor(.appSuccess)
                } else {
                    AppBadge("\(vm.volumeAlerts.count) sous MEV", role: .warning)
                }
                Image(systemName: "chevron.right").foregroundColor(.appTextSecondary)
            }
            .frame(height: 44)
            .padding(.horizontal, .appPagePadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var mesocycleRow: some View {
        Button {
            withAnimation { selectedTab = .week }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg").foregroundColor(.forge)
                Text("Mésocycle").font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                Spacer()
                if periodisationStart.isEmpty {
                    Text("Non démarré").font(.appLabel).foregroundColor(.appTextSecondary)
                } else if isCycleComplete {
                    Text("Cycle terminé").font(.appLabel).foregroundColor(.appTextSecondary)
                } else {
                    Text("\(currentPhase.verb) · S\(mesocycleWeek)/\(TrainingDoctrine.mesocycleWeeks)")
                        .font(.appLabel).foregroundColor(.appTextSecondary)
                }
                Image(systemName: "chevron.right").foregroundColor(.appTextSecondary)
            }
            .frame(height: 44)
            .padding(.horizontal, .appPagePadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyProgrammePlaceholder: some View {
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
                    .padding(.horizontal, .appPagePadding)
            }
            VStack(spacing: 12) {
                Button { showCreateProgram = true } label: {
                    Text("Importer un programme")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.forge)
                        .cornerRadius(.appCardRadius)
                }
                .buttonStyle(.plain)
                Button {
                    AppState.shared.pendingDeepLink = "seance"
                } label: {
                    Text("Séance libre")
                        .font(.appBody.weight(.medium))
                        .foregroundColor(Color.forge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.forge.opacity(0.10))
                        .cornerRadius(.appCardRadius)
                        .overlay(RoundedRectangle(cornerRadius: .appCardRadius).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Tab Semaine (14 cartes AM/PM ouvrables + volume + mésocycle)
    // Consultation pure : chaque carte est repliée par défaut, dépli local
    // pour voir les exos, bouton "Modifier →" qui bascule vers Structure et
    // déplie la bonne séance (expandedSeance + selectedTab).

    private var weekContent: some View {
        ScrollView {
            VStack(spacing: .appSectionSpacing) {
                weekAgendaSection
                volumeSection
                mesocycleSection
            }
            .padding(.vertical, 16)
            .padding(.horizontal, .appPagePadding)
        }
    }

    private var todayDayName: String {
        let weekday = Calendar.mtl.component(.weekday, from: Date())
        let idx = (weekday + 5) % 7
        guard idx < TrainingDoctrine.dayNames.count else { return "" }
        return TrainingDoctrine.dayNames[idx]
    }

    private func openInStructure(_ seance: String?) {
        guard let s = seance else { return }
        expandedSeance = s
        withAnimation { selectedTab = .structure }
    }

    private var weekAgendaSection: some View {
        VStack(spacing: 10) {
            ForEach(TrainingDoctrine.dayNames, id: \.self) { day in
                let am = vm.schedule[day]
                let pm = vm.eveningSchedule[day]
                DaySessionCard(
                    moment: .am,
                    day: day,
                    isToday: day == todayDayName,
                    seance: am,
                    exercises: vm.fullProgram[am ?? ""] ?? [:],
                    sessionsList: sessionsList,
                    onPick: { _ in },
                    onEdit: { openInStructure(am) }
                )
                DaySessionCard(
                    moment: .pm,
                    day: day,
                    isToday: day == todayDayName,
                    seance: pm,
                    exercises: vm.fullProgram[pm ?? ""] ?? [:],
                    sessionsList: sessionsList,
                    onPick: { _ in },
                    onEdit: { openInStructure(pm) }
                )
            }
        }
    }

    // Volume — 11 barres doctrinales pleine largeur + alertes pied MEV+ / MAV+.
    // volumeExcessAlerts calculé localement dans la vue (zéro logique VM nouvelle).

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSectionHeader("VOLUME HEBDOMADAIRE")
            volumeCardView
        }
    }

    private var volumeExcessAlerts: [String] {
        vm.weeklyVolumeByMuscle.compactMap { muscle, sets in
            guard let mav = TrainingDoctrine.muscleMAV[muscle], sets > mav else { return nil }
            return "\(muscle) — \(sets)/\(mav) sets max."
        }.sorted()
    }

    private var volumeCardView: some View {
        let vol = vm.weeklyVolumeByMuscle
        let underMEV = vm.volumeAlerts
        let overMAV = volumeExcessAlerts
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(TrainingDoctrine.canonicalMuscleOrder, id: \.self) { muscle in
                volumeBar(
                    muscle: muscle,
                    sets: vol[muscle] ?? 0,
                    mev: TrainingDoctrine.muscleMEV[muscle],
                    mav: TrainingDoctrine.muscleMAV[muscle]
                )
            }
            if !underMEV.isEmpty || !overMAV.isEmpty {
                Rectangle()
                    .fill(Color.appTextSecondary.opacity(0.10))
                    .frame(height: .appHairline)
                    .padding(.top, 4)
            }
            if !underMEV.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(underMEV, id: \.self) { alert in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.appCaption)
                                .foregroundColor(.statusOrange)
                            Text(alert).font(.appLabel).foregroundColor(.statusOrange)
                        }
                    }
                }
            }
            if !overMAV.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(overMAV, id: \.self) { alert in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.appCaption)
                                .foregroundColor(.appDanger)
                            Text(alert).font(.appLabel).foregroundColor(.appDanger)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, .appCardInsetH)
        .padding(.vertical, .appCardInsetV)
        .glassCard()
    }

    private func volumeBar(muscle: String, sets: Int, mev: Int?, mav: Int?) -> some View {
        // Palette 3 zones : sous MEV = déficit stimulant (warning), fenêtre = cible
        // (success), au-dessus MAV = volume junk (alert — le rouge est mérité).
        // Fill ratio = sets/mav clampé, valeur textuelle = "sets/mav".
        let mavVal = mav ?? max(sets, 1)
        let ratio = min(1.0, Double(sets) / Double(mavVal))
        let color: Color = {
            guard let mev = mev, let mav = mav else { return .appTextSecondary }
            if sets < mev { return .statusOrange }
            if sets > mav { return .appDanger }
            return .appSuccess
        }()
        return HStack(spacing: 12) {
            Text(muscle)
                .frame(width: 110, alignment: .leading)
                .font(.appLabel)
                .foregroundColor(.appTextPrimary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appTextSecondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * ratio))
                }
            }
            .frame(height: 8)
            Text("\(sets)/\(mav ?? sets)")
                .frame(width: 56, alignment: .trailing)
                .font(.appLabel.weight(.medium))
                .foregroundColor(.appTextSecondary)
                .monospacedDigit()
        }
    }

    // Mésocycle — lecture pure. Les actions (démarrer, reset, appliquer scheme)
    // vivent dans le tab Structure (mesocycleActions).

    private var mesocycleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSectionHeader("MÉSOCYCLE")
            mesocycleCard
        }
    }

    private var deloadHorizon: String {
        let w = mesocycleWeek
        if w >= 11 { return "en cours" }
        let remaining = TrainingDoctrine.mesocycleWeeks - w
        if remaining <= 0 { return "cycle terminé" }
        if remaining == 1 { return "la semaine prochaine" }
        return "dans \(remaining) semaines"
    }

    @ViewBuilder
    private var mesocycleCard: some View {
        if periodisationStart.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.appTextSecondary)
                Text("Aucun mésocycle en cours.")
                    .font(.appLabel)
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, .appCardInsetH)
            .padding(.vertical, .appCardInsetV)
            .glassCard()
        } else if isCycleComplete {
            let phase = Phase.completed
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Cycle terminé")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    AppBadge(phase.rawValue.uppercased(), role: phase.badgeRole)
                }
                Text(phase.verb).font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                Text(phase.why).font(.appLabel).italic().foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, .appCardInsetH)
            .padding(.vertical, .appCardInsetV)
            .glassCard()
        } else {
            let phase = currentPhase
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Semaine \(mesocycleWeek) sur \(TrainingDoctrine.mesocycleWeeks)")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    AppBadge(phase.rawValue.uppercased(), role: phase.badgeRole)
                }
                Text(phase.verb)
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(phase.scheme)
                    .font(.appLabel)
                    .foregroundColor(.appTextSecondary)
                Text("Repos \(phase.rest)")
                    .font(.appLabel)
                    .foregroundColor(.appTextSecondary)
                Rectangle()
                    .fill(Color.appTextSecondary.opacity(0.10))
                    .frame(height: .appHairline)
                Text(phase.why)
                    .font(.appLabel)
                    .italic()
                    .foregroundColor(.appTextSecondary)
                Rectangle()
                    .fill(Color.appTextSecondary.opacity(0.10))
                    .frame(height: .appHairline)
                Text("Deload \(deloadHorizon)")
                    .font(.appLabel)
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, .appCardInsetH)
            .padding(.vertical, .appCardInsetV)
            .glassCard()
        }
    }

    // MARK: - Tab Structure (édition pure — clôture Direction B)

    private var totalExoCount: Int {
        vm.fullProgram.values.reduce(0) { $0 + $1.count }
    }

    private var deletableProgram: ProgramInfo? {
        vm.programs.first { $0.id == vm.activeProgramId } ?? vm.programs.first
    }

    @ViewBuilder
    private var mesocycleActions: some View {
        if periodisationStart.isEmpty {
            PrimaryButton(title: "Démarrer un mésocycle", icon: "play.fill") {
                Task { await vm.saveCycleStartDate(DateFormatter.isoDate.string(from: Date())) }
            }
            .padding(.horizontal, .appPagePadding)
        } else if isCycleComplete {
            PrimaryButton(title: "Démarrer un nouveau cycle", icon: "play.fill") {
                Task { await vm.saveCycleStartDate(DateFormatter.isoDate.string(from: Date())) }
            }
            .padding(.horizontal, .appPagePadding)
        } else {
            PrimaryButton(title: "Appliquer \(currentPhase.shortScheme) aux \(totalExoCount) exercices",
                          icon: "arrow.triangle.2.circlepath") {
                showApplyPhaseConfirm = true
            }
            .padding(.horizontal, .appPagePadding)
            PrimaryButton(title: "Réinitialiser le mésocycle",
                          style: .ghost, size: .medium) {
                showResetMesocycle = true
            }
            .padding(.horizontal, .appPagePadding)
        }
    }

    private var structureContent: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: .appSectionSpacing) {
                // ── Onglets programmes (multi-progs seulement) ────
                if vm.programs.count > 1 {
                    ProgramTabsView(
                        programs: vm.programs,
                        selectedId: $vm.selectedProgramId,
                        activeId: vm.activeProgramId,
                        onSelect: { vm.userDidSelect = true },
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
                    .padding(.horizontal, .appPagePadding)

                    if !vm.selectedProgramId.isEmpty, vm.selectedProgramId != vm.activeProgramId {
                        Button {
                            Task { await vm.setActiveProgramme() }
                        } label: {
                            HStack(spacing: 8) {
                                if vm.isSettingActive {
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
                            .cornerRadius(.appCardRadius)
                            .overlay(RoundedRectangle(cornerRadius: .appCardRadius).stroke(Color.appSuccess.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isSettingActive)
                        .padding(.horizontal, .appPagePadding)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                // ── Clipboard (si non-vide) ───────────────────────
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
                    .padding(.horizontal, .appCardInsetH).padding(.vertical, .appCardInsetV)
                    .background(Color.forge.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: .appCardRadius).stroke(Color.forge.opacity(0.2), lineWidth: 1))
                    .cornerRadius(.appCardRadius)
                    .padding(.horizontal, .appPagePadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // ── PLANNING (barre semaine + 2 cartes du jour sélectionné) ──
                VStack(alignment: .leading, spacing: 12) {
                    AppSectionHeader("PLANNING")
                        .padding(.horizontal, .appPagePadding)
                    WeekPillsCard(
                        schedule: vm.schedule,
                        eveningSchedule: vm.eveningSchedule,
                        dayNames: TrainingDoctrine.dayNames,
                        todayDayName: todayDayName,
                        selectedDay: $selectedDay
                    )
                    .padding(.horizontal, .appPagePadding)

                    DaySessionCard(
                        moment: .am,
                        day: selectedDay,
                        isToday: selectedDay == todayDayName,
                        seance: amSeanceForSelectedDay,
                        exercises: amExercisesForSelectedDay,
                        sessionsList: sessionsList,
                        onPick: { assignAM(seance: $0) }
                    )
                    .padding(.horizontal, .appPagePadding)

                    DaySessionCard(
                        moment: .pm,
                        day: selectedDay,
                        isToday: selectedDay == todayDayName,
                        seance: pmSeanceForSelectedDay,
                        exercises: pmExercisesForSelectedDay,
                        sessionsList: sessionsList,
                        onPick: { assignPM(seance: $0) }
                    )
                    .padding(.horizontal, .appPagePadding)
                }

                // ── SÉANCES ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    AppSectionHeader("SÉANCES")
                        .padding(.horizontal, .appPagePadding)
                    if vm.orderedSeances.isEmpty {
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
                                    .padding(.horizontal, .appPagePadding)
                            }
                            VStack(spacing: 12) {
                                Button { showCreateProgram = true } label: {
                                    Text("Importer un programme")
                                        .font(.appBody.weight(.semibold))
                                        .foregroundColor(Color.onAccent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.forge)
                                        .cornerRadius(.appCardRadius)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    AppState.shared.pendingDeepLink = "seance"
                                } label: {
                                    Text("Séance libre")
                                        .font(.appBody.weight(.medium))
                                        .foregroundColor(Color.forge)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.forge.opacity(0.10))
                                        .cornerRadius(.appCardRadius)
                                        .overlay(RoundedRectangle(cornerRadius: .appCardRadius).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(vm.orderedSeances, id: \.self) { seance in
                            sessionCard(for: seance)
                                .id(seance)
                        }
                        PrimaryButton(title: "Nouvelle séance", icon: "plus",
                                      style: .outlined, size: .medium) {
                            showCreateSeance = true
                        }
                        .padding(.horizontal, .appPagePadding)
                    }
                }

                // ── MÉSOCYCLE — actions pures ─────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    AppSectionHeader("MÉSOCYCLE")
                        .padding(.horizontal, .appPagePadding)
                    mesocycleActions
                }

                // ── DANGER ────────────────────────────────────────
                if let target = deletableProgram {
                    VStack(alignment: .leading, spacing: 12) {
                        AppSectionHeader("DANGER")
                            .padding(.horizontal, .appPagePadding)
                        PrimaryButton(title: "Supprimer \(target.name)", icon: "trash.fill",
                                      style: .destructive, size: .medium) {
                            deleteProgramTarget = target
                            confirmDeleteProgram = true
                        }
                        .padding(.horizontal, .appPagePadding)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            CacheService.shared.clear(for: "programme_data")
            seance2ExosToday = APIService.shared.dashboard?.pushedToEvening ?? []
            await vm.loadData(programId: vm.selectedProgramId.isEmpty ? nil : vm.selectedProgramId)
        }
        .onChange(of: expandedSeance) { _, new in
            guard let s = new else { return }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation { proxy.scrollTo(s, anchor: .top) }
            }
        }
        }
    }

}

// MARK: - ProgramTabsView

private struct ProgramTabsView: View {
    let programs: [ProgramInfo]
    @Binding var selectedId: String
    let activeId: String
    let onSelect: () -> Void
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
                    .onTapGesture { onSelect(); selectedId = prog.id }
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

struct EditableSeanceProgramCard: View {
    let seance: String
    @Binding var exercises: [String: String]
    @Binding var orderedNames: [String]
    @Binding var isExpanded: Bool
    let onAdd:          () -> Void
    let onEdit:         (String, String) -> Void
    let onDelete:       (String) -> Void
    let onReorder:      ([String]) -> Void
    var onDeleteSeance:       (() -> Void)? = nil
    var onCopy:               (() -> Void)? = nil
    var onPaste:              (() -> Void)? = nil
    var isToday:              Bool = false
    var seance2ExosToday:     Set<String> = []
    var supersets: [String: SupersetEntry] = [:]
    var exerciseWeights: [String: (weight: Double?, reps: String?, date: String?)] = [:]
    var suggestions: [String: ProgressionSuggestion] = [:]
    var inventoryPatterns: [String: String] = [:]
    var inventoryMuscleGroups: [String: String] = [:]
    var inventoryOneRM: [String: Double] = [:]

    @State private var dragging:   String? = nil
    @State private var dragY:      CGFloat = 0
    @State private var rowHeights: [String: CGFloat] = [:]

    /// Résumé muscles pour le header replié : 3 groupes doctrinaux max,
    /// « +N » si plus. Dérivé de inventoryMuscleGroups filtré sur les exos
    /// de la séance, ordonnancement d'apparition dans orderedPairs.
    private var muscleSummary: String {
        var seen: [String] = []
        for (name, _) in orderedPairs {
            guard let db = inventoryMuscleGroups[name],
                  let doctrinal = TrainingDoctrine.doctrinalMuscleGroup(for: db) else { continue }
            if !seen.contains(doctrinal) { seen.append(doctrinal) }
        }
        if seen.isEmpty { return "" }
        if seen.count <= 3 { return seen.joined(separator: " · ") }
        return seen.prefix(2).joined(separator: " · ") + " +\(seen.count - 2)"
    }

    /// Split "Mardi PM — Puissance + bras + pelvien" en préfixe contextuel
    /// (jour+moment, gris caption) + focus (bold pleine largeur). Nom sans " — "
    /// (ex héritages "Push A") → prefix nil, focus = seance.
    private var titleParts: (prefix: String?, focus: String) {
        guard let r = seance.range(of: " — ") else { return (nil, seance) }
        return (String(seance[..<r.lowerBound]), String(seance[r.upperBound...]))
    }

    var color: Color { SessionType(seance).color }

    /// CTA pied de carte dépliée + empty state (même expression, deux emplois).
    /// Plein largeur, ghost avec accent séance. Cible tap 48pt garantie.
    @ViewBuilder
    private var addExerciseFooter: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.appLabel.weight(.semibold))
                Text("Ajouter un exercice")
                    .font(.appLabel.weight(.semibold))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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

    private static let compoundPatterns: Set<String> = [
        "squat", "hinge", "horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull"
    ]
    private var firstCompoundName: String? {
        orderedPairs.first { Self.compoundPatterns.contains(inventoryPatterns[$0.0] ?? "") }?.0
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
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(seance.prefix(1)))
                            .font(.appLabel.weight(.black))
                            .foregroundColor(color)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    if let prefix = titleParts.prefix {
                        Text(prefix)
                            .font(.appCaption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    Text(titleParts.focus)
                        .font(.appBody.weight(.bold))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !muscleSummary.isEmpty {
                        Text(muscleSummary)
                            .font(.appCaption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
                if isToday {
                    Text("AUJOURD'HUI")
                        .font(.appMicro.weight(.black)).tracking(1)
                        .foregroundColor(Color.forge)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.forge.opacity(0.12))
                        .cornerRadius(5)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer()
                Text("\(exercises.count)")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(8)
                if onCopy != nil || onPaste != nil || onDeleteSeance != nil {
                    Menu {
                        if let copy = onCopy {
                            Button { copy() } label: {
                                Label("Copier", systemImage: "doc.on.doc")
                            }
                        }
                        if let paste = onPaste {
                            Button { paste() } label: {
                                Label("Coller", systemImage: "doc.on.clipboard")
                            }
                        }
                        if let del = onDeleteSeance {
                            Button(role: .destructive) { del() } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(Color.forge.opacity(0.7))
                            .padding(7)
                            .background(Color.forge.opacity(0.08))
                            .cornerRadius(8)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, .appPagePadding).padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                Divider().background(Color.appSeparator)

                if orderedPairs.isEmpty {
                    addExerciseFooter
                } else {
                    ForEach(orderedPairs, id: \.0) { name, scheme in
                        let isDragging = dragging == name
                        SwipeToDeleteRow(onDelete: { onDelete(name) }) {
                            HStack(spacing: 0) {
                                // ≡ Drag handle (reorder vertical — zone dédiée 40pt)
                                Image(systemName: "line.3.horizontal")
                                    .font(.appLabel.weight(.regular))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .frame(width: 40)
                                    .contentShape(Rectangle())
                                    .gesture(dragGesture(for: name))

                                ExerciseRow(
                                    name:          name,
                                    scheme:        scheme,
                                    color:         color,
                                    onTap:         { onEdit(name, scheme) },
                                    isSupersetted: supersets[name] != nil,
                                    trend:         trendFor(name),
                                    suggestion:    suggestions[name],
                                    isCompound:    name == firstCompoundName,
                                    e1rm:          inventoryOneRM[name],
                                    isSeance2:     seance2ExosToday.contains(name)
                                )
                            }
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
                            Divider().background(Color.appSeparatorSubtle)
                        }
                    }
                    .onPreferenceChange(ProgramRowHeightKey.self) { rowHeights.merge($0) { $1 } }

                    Divider().background(Color.appSeparator)
                    addExerciseFooter
                }
            }
        }
        .background(Color.appCard)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isToday ? Color.forge.opacity(0.7) : color.opacity(0.2), lineWidth: isToday ? 1.5 : 1))
        .cornerRadius(.appCardRadius)
        .shadow(color: isToday ? Color.forge.opacity(0.18) : .clear, radius: 14, y: 4)
    }
}

/// Wrap une row d'exercice avec swipe-to-delete horizontal. La zone du swipe
/// est le CONTENU (donc le corps de la row + son handle ≡), pas les zones
/// filles avec gestures déjà attachées : la dragGesture(for:) du handle vit
/// sur l'Image intérieure et reste prioritaire sur son 40pt (résolution
/// SwiftUI : geste enfant gagne le touch qui démarre sur lui). Résultat :
///  - Touch sur ≡ → reorder vertical (dragGesture handle)
///  - Touch ailleurs sur la row → swipe horizontal (ce composant)
/// Départage par zone, pas par direction — jamais ambigu.
///
/// Seuil 90pt : au-delà, delete + undo 4s via onDelete (call site =
/// deleteWithUndo). Sous le seuil, spring-back. Pas d'état intermédiaire
/// « open » — un seul geste, deleteWithUndo est le safety net.
struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    let content: Content
    @State private var offset: CGFloat = 0
    // Position reposée : 0 fermé, openOffset ouvert (corbeille révélée tap-actionnable).
    // Visuel = offset (drag en cours) + restingOffset (position stable).
    @State private var restingOffset: CGFloat = 0

    private let deleteThreshold: CGFloat = 60
    private let openOffset: CGFloat = -80

    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }

    private var visualOffset: CGFloat { offset + restingOffset }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offset = 0
            restingOffset = 0
        }
    }

    private func triggerDelete() {
        triggerImpact(style: .medium)
        withAnimation(.easeOut(duration: 0.22)) {
            offset = -600
            restingOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDelete() }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Fond rouge révélé au swipe. En état open (restingOffset != 0), tap = delete.
            // allowsHitTesting gate : fermé = pas de bouton tapable (couvert par content).
            Button(action: triggerDelete) {
                HStack {
                    Spacer()
                    Image(systemName: "trash.fill")
                        .foregroundColor(.white)
                        .font(.appBody.weight(.semibold))
                        .padding(.trailing, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.appDanger)
            .opacity(visualOffset < -10 ? min(1, -visualOffset / 40) : 0)
            .allowsHitTesting(restingOffset != 0)

            content
                .background(Color.appCard)
                .offset(x: visualOffset)
                .overlay(
                    // Tap-close en état open UNIQUEMENT. Overlay conditionnel :
                    // absent quand fermé → taps passent au Button interne (ExerciseRow
                    // → EditSchemeSheet). Zéro vol de tap en état fermé.
                    Group {
                        if restingOffset != 0 {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { close() }
                        }
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { val in
                            let dx = val.translation.width
                            let dy = val.translation.height
                            // Tolérance 1.0 (45°) : accepte les diagonales au pouce.
                            // Scroll vertical parent capture avant nous les gestes clairement verticaux.
                            guard abs(dx) > abs(dy) else { return }
                            offset = min(0, dx)
                        }
                        .onEnded { val in
                            let dx = val.translation.width
                            let dy = val.translation.height
                            let horiz = abs(dx) > abs(dy)
                            if horiz && dx < -deleteThreshold {
                                triggerDelete()
                            } else if horiz && dx < -30 {
                                // Swipe partiel : snap open, corbeille tap-actionnable.
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                    offset = 0
                                    restingOffset = openOffset
                                }
                            } else {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                    offset = 0
                                    restingOffset = 0
                                }
                            }
                        }
                )
        }
        .clipped()
    }
}

struct ExerciseRow: View {
    let name: String
    let scheme: String
    let color: Color
    let onTap: () -> Void
    var isSupersetted: Bool = false
    var trend: String? = nil
    var suggestion: ProgressionSuggestion? = nil
    var isCompound: Bool = false
    var e1rm: Double? = nil
    var isSeance2: Bool = false

    @ObservedObject private var units = UnitSettings.shared

    /// "↑ 4×5-7" si trend positif, "4×5-7" sinon. → (neutre) n'est pas préfixé
    /// pour ne pas confondre avec la flèche de suggestion (→ 185).
    private var displayScheme: String {
        trend == "↑" ? "↑ \(scheme)" : scheme
    }

    /// Sous-titre méta ligne 2 (SS · e1rm), un seul point-median.
    /// Vide → ligne 2 non rendue, row à 46pt. Peuplée → ~60pt (hauteur assumée).
    /// Séance 2 sortie de metaLine — rendue en badge capsule inline (voir body)
    /// pour restaurer la saillance perdue en D6 (sous-titre gris peu visible).
    private var metaLine: String {
        var parts: [String] = []
        if isSupersetted { parts.append("SS") }
        if let e = e1rm  { parts.append("~\(units.format(e, decimals: 0)) max") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(isCompound ? .appBody.weight(.semibold) : .appLabel.weight(.medium))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if isSeance2 {
                            Text("Séance 2")
                                .font(.appMicro.weight(.semibold))
                                .foregroundColor(.onAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.forge)
                                .cornerRadius(4)
                        }
                    }
                    if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(.appMicro)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Colonne scheme 86pt — anchor trailing, alignement vertical stable.
                Text(displayScheme)
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.15))
                    .cornerRadius(6)
                    .lineLimit(1)
                    .frame(width: 86, alignment: .trailing)

                // Colonne suggestion 64pt — frame réservée même vide pour que
                // le trailing edge du scheme reste aligné entre toutes les rows.
                Group {
                    if let sug = suggestion,
                       sug.suggestionType == "increase_weight",
                       let sw = sug.suggestedWeight {
                        Text("→ \(units.format(sw, decimals: 0))")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.appSuccess)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.appSuccess.opacity(0.12))
                            .cornerRadius(5)
                            .lineLimit(1)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, .appPagePadding).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    let seance: String
    let inventory: [String]
    let inventorySchemes: [String: String]
    let inventoryMuscleGroups: [String: String]
    var recentExercises: [String] = []
    /// Callback multi : la sheet collecte la sélection, le VM boucle séquentiellement
    /// (une intention côté VM, cf. addExercises). Schemes = défauts inventaire,
    /// ajustables ensuite via EditSchemeSheet (tap row en carte).
    let onAddMultiple: ([(String, String)]) -> Void

    @Environment(\.dismiss) private var dismiss
    // query = recherche pure (ex-name qui servait double rôle recherche/valeur).
    // selected = Set → dédup naturel (récents ∪ liste = 1 seule entrée).
    @State private var query = ""
    @State private var selected: Set<String> = []
    @State private var selectedGroup: String? = nil
    @State private var confirmDiscard = false

    private var isDirty: Bool { !selected.isEmpty }

    // Ordre canonique + append trié des nouveaux groupes (Cou, Hanches, etc.)
    // que le catalogue peut porter — évite un sorted() alphabétique pur qui
    // casserait l'ergonomie du picker.
    private let canonicalMuscleOrder = ["Pecs", "Dos", "Jambes", "Épaules", "Biceps", "Triceps", "Fessiers", "Core"]
    private var muscleGroupOrder: [String] {
        let present = Set(inventoryMuscleGroups.values)
        let canonical = canonicalMuscleOrder.filter { present.contains($0) }
        let extras = present.subtracting(canonicalMuscleOrder).sorted()
        return canonical + extras
    }

    private var filtered: [String] {
        var result = query.isEmpty ? inventory : inventory.filter { $0.localizedCaseInsensitiveContains(query) }
        if let grp = selectedGroup {
            result = result.filter { (inventoryMuscleGroups[$0] ?? "Autre") == grp }
        }
        return result
    }

    /// Label CTA bas : pluriel géré, "Ajouter des exercices" en état vide (disabled).
    private var ctaLabel: String {
        switch selected.count {
        case 0: return "Ajouter des exercices"
        case 1: return "Ajouter 1 exercice"
        default: return "Ajouter \(selected.count) exercices"
        }
    }

    private func toggle(_ ex: String) {
        if selected.contains(ex) { selected.remove(ex) } else { selected.insert(ex) }
    }

    // Sections extraites en @ViewBuilder pour dénouer le type-check du body.
    // Le module avait franchi le seuil du solver Swift (cf. lessons.md /
    // feedback_swiftui_typechecker) — chaque section type-check en isolation.

    @ViewBuilder private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Rechercher un exercice...", text: $query)
                .foregroundColor(.appTextPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color.appCard)
        .cornerRadius(10)
        .padding(.horizontal, .appPagePadding)
        .padding(.top, 8)
    }

    @ViewBuilder private var muscleChips: some View {
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
                        .cornerRadius(.appCardRadius)
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
                            .cornerRadius(.appCardRadius)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, .appPagePadding)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var recentsSection: some View {
        if !recentExercises.isEmpty && query.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("RÉCENTS")
                    .font(.appCaption.weight(.bold))
                    .tracking(1.5)
                    .foregroundColor(.gray.opacity(0.55))
                    .padding(.horizontal, .appPagePadding)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentExercises, id: \.self) { ex in
                            recentChip(ex)
                        }
                    }
                    .padding(.horizontal, .appPagePadding)
                }
                Divider()
                    .background(Color.appSeparatorSubtle)
                    .padding(.horizontal, .appPagePadding)
                    .padding(.top, 2)
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder private func recentChip(_ ex: String) -> some View {
        let isSelected = selected.contains(ex)
        let iconName: String = isSelected ? "checkmark.circle.fill" : "clock.arrow.circlepath"
        let iconColor: Color = isSelected ? Color.forge : Color.forge.opacity(0.7)
        let bgColor: Color = isSelected ? Color.forge.opacity(0.25) : Color.forge.opacity(0.1)
        let strokeColor: Color = isSelected ? Color.forge : Color.forge.opacity(0.22)
        let strokeWidth: CGFloat = isSelected ? 1.5 : 1
        Button {
            toggle(ex)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.appCaption)
                    .foregroundColor(iconColor)
                Text(ex)
                    .font(.appLabel)
                    .foregroundColor(.appTextPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(bgColor)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeColor, lineWidth: strokeWidth))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var inventoryList: some View {
        if !filtered.isEmpty {
            List(filtered, id: \.self) { ex in
                let isSelected = selected.contains(ex)
                Button {
                    toggle(ex)
                } label: {
                    HStack {
                        Text(ex)
                            .foregroundColor(.appTextPrimary)
                            .font(.appLabel.weight(.regular))
                        Spacer()
                        Text(inventoryMuscleGroups[ex] ?? "Autre")
                            .font(.appCaption)
                            .foregroundColor(.gray.opacity(0.6))
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? Color.forge : .gray.opacity(0.4))
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

    @ViewBuilder private var bottomCTA: some View {
        let isEmpty = selected.isEmpty
        let ctaFg: Color = isEmpty ? .gray : .onAccent
        let ctaBg: Color = isEmpty ? Color.appSurfaceInset : Color.forge
        VStack(spacing: 0) {
            Divider().background(Color.appSeparatorSubtle)
            Button {
                // Ordre alphabétique stable (Set → sorted). Ordre visuel final
                // dans la séance = ordre d'append côté VM ; ré-ordonnançable
                // via handle ≡ après ajout.
                let list = selected.sorted().map { ($0, inventorySchemes[$0] ?? "3x8-12") }
                onAddMultiple(list)
                dismiss()
            } label: {
                Text(ctaLabel)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(ctaFg)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(ctaBg)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .padding(.horizontal, .appPagePadding)
            .padding(.vertical, 10)
        }
        .background(Color.appCard)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    muscleChips
                    recentsSection
                    inventoryList
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
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomCTA }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Les exercices cochés seront perdus.")
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

// MARK: - Planning (Week Pills + Day Session Cards)

private enum DayMoment {
    case am, pm
    var color: Color { self == .am ? .forge : .statusBlue }
    var label: String { self == .am ? "AM" : "PM" }
    var icon: String  { self == .am ? "sun.max.fill" : "moon.stars.fill" }
}

/// Barre semaine unifiée : 7 pills en une seule rangée, 2 indicateurs
/// AM (forge) + PM (statusBlue) par pill, un point discret sous les
/// indicateurs pour aujourd'hui. Jour actif = anneau forge + fond teinté.
/// Aucun texte pivoté, aucun blob marron. Tap = sélection uniquement.
private struct WeekPillsCard: View {
    let schedule: [String: String]
    let eveningSchedule: [String: String]
    let dayNames: [String]
    let todayDayName: String
    @Binding var selectedDay: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(dayNames, id: \.self) { day in
                pill(for: day)
            }
        }
        .padding(12)
        .glassCard()
    }

    @ViewBuilder
    private func pill(for day: String) -> some View {
        let isSelected = day == selectedDay
        let isToday    = day == todayDayName
        let hasAM      = (schedule[day] ?? "Repos") != "Repos"
        let hasPM      = eveningSchedule[day] != nil

        Button {
            selectedDay = day
        } label: {
            VStack(spacing: 6) {
                Text(day.uppercased())
                    .font(.appMicro.weight(.bold))
                    .tracking(0.5)
                    .foregroundColor(isSelected ? .appOnSurface : Color.appOnSurface.opacity(0.55))
                HStack(spacing: 4) {
                    Circle().fill(Color.forge).frame(width: 5, height: 5)
                        .opacity(hasAM ? 1 : 0.15)
                    Circle().fill(Color.statusBlue).frame(width: 5, height: 5)
                        .opacity(hasPM ? 1 : 0.15)
                }
                // Signal aujourd'hui = point discret (le mot "AUJOURD'HUI"
                // vit sur le header de DaySessionCard, où il y a la place).
                Circle().fill(Color.forge).frame(width: 3, height: 3)
                    .opacity(isToday ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.forge.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.forge : Color.clear, lineWidth: 1.5)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

/// Carte AM ou PM du jour sélectionné. Rail latéral coloré (forge / statusBlue),
/// chip AM|PM, header "JOUR · AUJOURD'HUI" (si aujourd'hui, chip horizontale),
/// menu ⋯ (assigner/vider), preview des exos avec chip scheme (repli/dépli).
/// `seance == nil` = état vide propre (bouton "+ Assigner"), aucun accès à
/// fullProgram[nil]. Samedi sans planning affiche 2 cartes vides.
private struct DaySessionCard: View {
    let moment: DayMoment
    let day: String
    let isToday: Bool
    let seance: String?
    let exercises: [String: String]
    let sessionsList: [String]
    let onPick: (String?) -> Void
    // nil = mode édition inline (menu ⋯ assigner/vider, onglet Aujourd'hui).
    // Non-nil = mode lecture (menu caché, bouton "Modifier →" dans filledBody,
    // onglet Semaine → pont vers Structure).
    var onEdit: (() -> Void)? = nil

    @State private var isExpanded = false

    private static let fullDayNames: [String: String] = [
        "Lun": "LUNDI", "Mar": "MARDI", "Mer": "MERCREDI", "Jeu": "JEUDI",
        "Ven": "VENDREDI", "Sam": "SAMEDI", "Dim": "DIMANCHE"
    ]
    private var fullDayName: String {
        Self.fullDayNames[day] ?? day.uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(moment.color.opacity(seance == nil ? 0.35 : 0.9))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 10) {
                header
                if let s = seance {
                    filledBody(seance: s)
                } else {
                    emptyBody
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appCard)
        .cornerRadius(.appCardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: .appCardRadius)
                .stroke(moment.color.opacity(seance == nil ? 0.12 : 0.28), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: moment.icon)
                    .font(.appMicro.weight(.regular))
                Text(moment.label)
                    .font(.appMicro.weight(.black))
                    .tracking(1)
            }
            .foregroundColor(moment.color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(moment.color.opacity(0.12))
            .cornerRadius(4)

            Text(isToday ? "\(fullDayName) · AUJOURD'HUI" : fullDayName)
                .font(.appMicro.weight(.bold))
                .tracking(1)
                .foregroundColor(isToday ? Color.forge : Color.appOnSurface.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if onEdit == nil { menu }
        }
    }

    private var menu: some View {
        Menu {
            if seance != nil {
                Button(role: .destructive) {
                    isExpanded = false
                    onPick(nil)
                } label: {
                    Label("Vider ce créneau", systemImage: "xmark.circle")
                }
                Divider()
            }
            Section("Assigner") {
                ForEach(sessionsList, id: \.self) { s in
                    Button(s) { onPick(s) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.appBody)
                .foregroundColor(.gray)
                .padding(6)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func filledBody(seance: String) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(seance)
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("\(exercises.count) exercice\(exercises.count > 1 ? "s" : "")")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            if let onEdit {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Text("Modifier")
                            .font(.appMicro.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.appMicro.weight(.semibold))
                    }
                    .foregroundColor(moment.color)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(moment.color.opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }

        if isExpanded && !exercises.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(exercises.sorted(by: { $0.key < $1.key }).prefix(6)), id: \.key) { ex, scheme in
                    HStack(spacing: 8) {
                        Text(ex)
                            .font(.appCaption)
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(scheme)
                            .font(.appMicro.weight(.semibold))
                            .foregroundColor(moment.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(moment.color.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                if exercises.count > 6 {
                    Text("+ \(exercises.count - 6) autres")
                        .font(.appMicro)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("— Aucune séance —")
                .font(.appCaption)
                .foregroundColor(.gray)
            Menu {
                ForEach(sessionsList, id: \.self) { s in
                    Button(s) { onPick(s) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.appCaption.weight(.bold))
                    Text("Assigner")
                        .font(.appLabel.weight(.semibold))
                }
                .foregroundColor(moment.color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(moment.color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(moment.color.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Create Seance Sheet

struct CreateSeanceSheet: View {
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmDiscard = false
    @State private var hasSubmitted = false

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
                        hasSubmitted = true
                        onCreate(trimmed)
                        dismiss()
                    }
                    .foregroundColor(canSave ? Color.forge : .gray)
                    .disabled(!canSave || hasSubmitted)
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
