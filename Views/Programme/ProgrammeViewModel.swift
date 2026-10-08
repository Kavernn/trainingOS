import SwiftUI
import Combine

/// ViewModel de ProgrammeView — source de vérité pour les données serveur du
/// programme (inventaire, planning, multi-progs), l'état runtime de chargement
/// et de mutation, et la doctrine dérivée testable (orderedSeances, volume MEV).
///
/// Séparation vue/VM :
///  - VM : données serveur (@Published), handlers de mutation async, computed
///    doctrine dérivée. @MainActor : les mutations passent toutes par le main.
///  - Vue : UI-LOCAL strict (sheets, alerts, drag transitoire, clipboard
///    @AppStorage, undo delete, périodisation @AppStorage), délègue toute
///    mutation serveur au VM via vm.<handler>.
///
/// Contrats non-négociables :
///  - Mutations de structure (setActiveProgram, rename, delete) = POST direct
///    via APIService+Workout postProgrammeDirect + throw (cf. df2b648).
///  - applyJSON atomique : une seule séquence de mutations groupées.
///  - orderedSeances dérive du planning (schedule Lun→Dim première apparition,
///    non-planifiées alpha ensuite). Source unique — plus de drag persisté
///    serveur ni de miroir apiSessionOrder (supprimés D5).
@MainActor
final class ProgrammeViewModel: ObservableObject {
    private let transport: (URLRequest) async throws -> (Data, URLResponse)
    private let cache: CacheService
    private let now: () -> Date

    init(transport: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.authed.data(for: $0)
    }, cache: CacheService = .shared, now: @escaping () -> Date = { Date() }) {
        self.transport = transport
        self.cache = cache
        self.now = now
    }

    private func read(_ url: URL) async throws -> (Data, URLResponse) {
        let result = try await transport(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        try Task.checkCancellation()
        guard let response = result.1 as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return result
    }

    /// The same path is used by Programme's pull-to-refresh and context updates.
    func refreshActiveProgramme(invalidate: Bool = false) async {
        await loadData(programId: nil, mode: .refresh, invalidate: invalidate)
    }

    func plannedMorning(on date: Date) -> String? {
        // Programme presents planning, not a dated execution override/recovery.
        // This is the same active/date/weekly identity used by DashboardPlan.
        guard !activeProgramId.isEmpty, loadedProgramId == activeProgramId,
              let name = schedule[TrainingDoctrine.dayName(on: date)],
              !name.isEmpty, name != "Repos", fullProgram[name] != nil else { return nil }
        return name
    }

    // Today's cards use the dated execution endpoints, never the editable template.
    @Published private(set) var todayPlans: [String: SeanceData] = [:]

    func todayPlan(session: String, source: DayComposerSource) -> SeanceData? {
        guard loadedProgramId == activeProgramId, let plan = todayPlans[source.rawValue],
              plan.today == session, plan.todayDate == DateFormatter.isoDate.string(from: now()) else { return nil }
        return plan
    }

    // MARK: - Inventaire (SERVEUR — hydraté par applyJSON)

    @Published var fullProgram: [String: [String: String]] = [:]
    @Published var exerciseOrder: [String: [String]] = [:]
    @Published var schedule: [String: String] = [:]
    @Published var eveningSchedule: [String: String] = [:]
    /// Date début mésocycle (YYYY-MM-DD) — source serveur (programs.cycle_start_date).
    /// Hydratée par applyJSON depuis /api/programme_data. Écrite via
    /// saveCycleStartDate() qui POST /api/cycle_start_date.
    @Published var cycleStartDate: String? = nil
    @Published var inventory: [String] = []
    @Published var inventorySchemes: [String: String] = [:]
    @Published var inventoryMuscleGroups: [String: String] = [:]
    @Published var inventoryPatterns: [String: String] = [:]
    @Published var inventoryOneRM: [String: Double] = [:]
    @Published var exerciseSupersets: [String: [String: SupersetEntry]] = [:]

    // MARK: - Multi-programmes (SERVEUR)

    @Published var programs: [ProgramInfo] = []
    /// Programme dont le contenu est actuellement hydraté dans fullProgram.
    /// Distinct de l'actif backend et de la sélection Structure.
    @Published private(set) var loadedProgramId: String = ""
    @Published var selectedProgramId: String = ""
    @Published var activeProgramId: String = ""
    @Published var allSessions: [String] = []
    /// Vrai quand l'utilisateur a exprimé une préférence explicite sur la
    /// sélection (tap picker ou createProgram). Bloque le rattrapage
    /// applyJSON tant qu'il est vrai. Reset à false par
    /// ProgrammeView.onAppear (chaque apparition de la vue) — la sélection
    /// de consultation ne survit pas à une réouverture de l'onglet.
    var userDidSelect: Bool = false

    // MARK: - Runtime chargement

    @Published var isLoading = true
    @Published private(set) var planningRevision = 0
    @Published private(set) var dayComposerCandidate: DayComposerPreparationCandidate?
    @Published var programSuggestions: [String: [String: ProgressionSuggestion]] = [:]
    @Published var exerciseWeights: [String: (weight: Double?, reps: String?, date: String?)] = [:]

    // MARK: - Runtime mutations

    /// Compteur de mutations en vol — chip "Sauvegarde…" en toolbar.
    @Published var mutationCount: Int = 0
    /// Flag "dernière mutation en erreur" — chip "Erreur réseau" en toolbar.
    @Published var lastSaveError: Bool = false
    /// Flag "activation de programme en cours" — disable le bouton.
    @Published var isSettingActive: Bool = false
    /// Toast success 1.5s — muté par showSaveSuccess.
    @Published var saveSuccessMsg: String?
    /// Invalide les réponses tardives lors d'un switch rapide d'onglet/programme.
    private var loadGeneration = 0
    private var pendingLoad: (id: UUID, key: String, task: Task<Void, Never>)?
    enum LoadMode { case initial, refresh }

    // MARK: - Doctrine dérivée

    /// Ordre d'affichage des séances : dérivé du planning, source unique.
    ///  - Base : ordre chronologique Lun→Dim, AM avant PM à l'intérieur d'un
    ///    jour (schedule puis eveningSchedule). Première occurrence d'une
    ///    séance donnée l'ancre à ce slot.
    ///  - Ensuite : les séances de fullProgram non planifiées, triées alpha.
    ///
    /// D5 : remplace le régime dual apiSessionOrder+drag persisté serveur. Le
    /// planning devient la vérité — plus de double source à réconcilier. Un
    /// utilisateur qui veut réordonner ses séances déplace le planning.
    var orderedSeances: [String] {
        // Le planning est global et appartient uniquement au programme actif.
        // Un programme consulté non actif expose donc toutes ses séances comme
        // non planifiées, sans emprunter l'ordre du planning actif.
        guard selectedProgramId == activeProgramId else {
            return fullProgram.keys.sorted()
        }
        var scheduled: [String] = []
        var seen = Set<String>()
        for day in TrainingDoctrine.dayNames {
            for dict in [schedule, eveningSchedule] {
                guard let s = dict[day], s != "Repos", fullProgram[s] != nil else { continue }
                if seen.insert(s).inserted { scheduled.append(s) }
            }
        }
        let unscheduled = fullProgram.keys.filter { !seen.contains($0) }.sorted()
        return scheduled + unscheduled
    }

    /// Fréquence hebdo par séance (union additive matin+soir, hors "Repos").
    /// Chaque occurrence compte : une séance planifiée matin ET soir un même jour
    /// = 2× son volume (Vince la ferait 2 fois). L'héritage visuel matin→soir
    /// (résolu à la volée dans la vue) n'est PAS compté ici — seules les entrées
    /// explicites de eveningSchedule ajoutent au volume.
    private var weeklySessionFrequency: [String: Int] {
        var freq: [String: Int] = [:]
        for session in schedule.values where !session.isEmpty && session != "Repos" {
            freq[session, default: 0] += 1
        }
        for session in eveningSchedule.values where !session.isEmpty && session != "Repos" {
            freq[session, default: 0] += 1
        }
        return freq
    }

    /// Volume hebdo par groupe musculaire doctrinal.
    /// Formule : sets(scheme) × fréquence hebdo, groupé via
    /// TrainingDoctrine.doctrinalMuscleGroup (mapping muscle DB → doctrinal).
    /// Muscle DB inconnu = skip silencieux (robustesse — nouvelle valeur DB pas
    /// encore mappée n'explose pas la card Volume).
    var weeklyVolumeByMuscle: [String: Int] {
        let freq = weeklySessionFrequency
        var vol: [String: Int] = [:]
        for (seance, exercises) in fullProgram {
            let f = freq[seance] ?? 0
            guard f > 0 else { continue }
            for (exercise, scheme) in exercises {
                guard let dbMuscle = inventoryMuscleGroups[exercise] else { continue }
                guard let doctrinal = TrainingDoctrine.doctrinalMuscleGroup(for: dbMuscle) else { continue }
                let sets = Self.parseSets(from: scheme)
                vol[doctrinal, default: 0] += sets * f
            }
        }
        return vol
    }

    /// Alertes "muscle sous MEV". Retour trié alpha pour affichage stable.
    var volumeAlerts: [String] {
        weeklyVolumeByMuscle.compactMap { muscle, sets in
            guard let mev = TrainingDoctrine.muscleMEV[muscle], sets < mev else { return nil }
            return "\(muscle) — \(sets)/\(mev) sets min."
        }.sorted()
    }

    /// Parse "3x8" → 3, "5x1-3" → 5, "3-4 × 8-12" (× unicode) → 3 (défaut).
    /// Robuste aux schemes malformés — pas de nil, valeur défaut.
    private static func parseSets(from scheme: String) -> Int {
        guard let xRange = scheme.range(of: "x", options: .caseInsensitive) else { return 3 }
        let setsPart = String(scheme[scheme.startIndex..<xRange.lowerBound])
        return Int(setsPart.trimmingCharacters(in: .whitespaces)) ?? 3
    }

    // MARK: - Chargement

    /// Hydratation atomique du payload /api/programme_data. Contrat : une seule
    /// séquence de mutations groupées. Clés absentes = valeurs par défaut, jamais
    /// crash. Testé par ProgrammeViewModelTests.
    func applyJSON(_ json: [String: Any]) {
        let incomingSchedule = (json["schedule"] as? [String: String]) ?? [:]
        if let raw = json["full_program"] as? [String: [String: Any]] {
            fullProgram = raw.mapValues { $0.compactMapValues { $0 as? String } }
        }
        inventory             = (json["inventory"] as? [String]) ?? []
        inventorySchemes      = (json["inventory_schemes"]  as? [String: String]) ?? [:]
        inventoryMuscleGroups = (json["inventory_muscle_groups"] as? [String: String]) ?? [:]
        inventoryPatterns     = (json["inventory_patterns"] as? [String: String]) ?? [:]
        if let raw = json["inventory_1rm"] as? [String: Any] {
            inventoryOneRM = raw.compactMapValues { $0 as? Double }
        }
        if let order = json["exercise_order"] as? [String: [String]] {
            exerciseOrder = order
        }
        // json["session_order"] : lu par le backend mais plus consommé côté iOS
        // depuis D5 (l'ordre dérive du planning, cf. orderedSeances). Colonne SQL
        // conservée pour l'historique ; endpoint reorder_sessions orphelin.
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
        if let rawPrograms = json["programs"] as? [[String: Any]] {
            programs = rawPrograms.compactMap { d in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return ProgramInfo(id: id, name: name)
            }
        }
        if json["current_program_id"] != nil {
            let loadedId = json["current_program_id"] as? String ?? ""
            loadedProgramId = loadedId
            if !userDidSelect { selectedProgramId = loadedId }
        }
        if json["active_program_id"] != nil {
            activeProgramId = json["active_program_id"] as? String ?? ""
        }
        if json["programs"] != nil, programs.isEmpty {
            selectedProgramId = ""
            userDidSelect = false
        } else if !programs.isEmpty,
           !programs.contains(where: { $0.id == selectedProgramId }),
           programs.contains(where: { $0.id == activeProgramId }) {
            selectedProgramId = activeProgramId
            userDidSelect = false
        }
        // Le planning global peut encore référencer les sessions de l'ancien
        // actif juste après un changement. Dans le contexte actif chargé, ces
        // références étrangères ne doivent jamais apparaître comme exécutables.
        schedule = loadedProgramId == activeProgramId
            ? incomingSchedule.mapValues { session in
                session == "Repos" || fullProgram[session] != nil ? session : "Repos"
            }
            : incomingSchedule
        if let sessions = json["all_sessions"] as? [String] {
            allSessions = sessions
        }
        // Cycle mésocycle serveur — nil-safe : null explicite ou clé absente = pas
        // de cycle démarré. iOS reader (mesocycleCard) affichera "Non démarré".
        cycleStartDate = json["cycle_start_date"] as? String
        // Plus de refreshSessionOrder() : orderedSeances est computed. La vue s'y
        // resynchronise via .onChange (sync explicite VM ↔ vue, commit 1).
    }

    /// Local single-flight. Context/mutation notifications explicitly supersede
    /// a pending read; routine appearance/refresh callers share it.
    func loadData(programId: String? = nil, mode: LoadMode = .initial, invalidate: Bool = false) async {
        let date = DateFormatter.isoDate.string(from: now())
        let key = "\(programId.map { "selected:\($0)" } ?? "active"):\(date)"
        if !invalidate, let pendingLoad, pendingLoad.key == key {
            await pendingLoad.task.value
            return
        }
        pendingLoad?.task.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let id = UUID()
        let task = Task { await self.performLoad(programId: programId, mode: mode, generation: generation) }
        pendingLoad = (id, key, task)
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if pendingLoad?.id == id { pendingLoad = nil }
    }

    private func performLoad(programId: String?, mode: LoadMode, generation: Int) async {
        let capturedDate = now()
        let date = DateFormatter.isoDate.string(from: now())
        func current() -> Bool {
            generation == loadGeneration && !Task.isCancelled && date == DateFormatter.isoDate.string(from: now())
        }
        // No placeholder or cache replay over an already coherent presentation.
        isLoading = loadedProgramId.isEmpty || (mode == .initial && programId != nil && programId != loadedProgramId)
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let url = try APIService.shared.buildURL(path: "/api/programme_data",
                queryItems: programId.map { [URLQueryItem(name: "program_id", value: $0)] } ?? [])
            let eveningURL = try APIService.shared.buildURL(path: "/api/evening_schedule")
            // Independent reads, explicit task lifetimes (no async-let beta issue).
            let programmeRead = Task { try await self.read(url).0 }
            let eveningRead = Task { try await self.read(eveningURL).0 }
            let (data, eveningData) = try await withTaskCancellationHandler {
                defer { programmeRead.cancel(); eveningRead.cancel() }
                return try await (programmeRead.value, eveningRead.value)
            } onCancel: { programmeRead.cancel(); eveningRead.cancel() }
            guard current(), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let currentId = json["current_program_id"] as? String,
                  let activeId = json["active_program_id"] as? String,
                  currentId == (programId ?? activeId) else { return }
            let evening = try JSONDecoder().decode([String: String].self, from: eveningData)
            let preview = try DayComposerLoader.preparationPreview(programme: data, evening: evening, date: capturedDate)
            var query = [URLQueryItem(name: "date", value: date), URLQueryItem(name: "program_id", value: activeId)]
            if let preview { query.append(URLQueryItem(name: "session_name", value: preview.morning.session)) }
            let weightsURL = try APIService.shared.buildURL(path: "/api/seance_data", queryItems: query)
            let morning = Task { try await self.read(weightsURL).0 }
            let pmName = currentId == activeId ? evening[TrainingDoctrine.dayName(on: capturedDate)] : nil
            let pmURL = try pmName.map { name in
                try APIService.shared.buildURL(path: "/api/seance_data", queryItems: [
                    URLQueryItem(name: "date", value: date), URLQueryItem(name: "program_id", value: activeId),
                    URLQueryItem(name: "session_name", value: name)])
            }
            let eveningPlan = Task<Data?, Never> {
                guard let pmURL else { return nil }
                return try? await self.read(pmURL).0
            }
            // Publish the whole planning replacement on MainActor, without an
            // intervening await. Supporting weights cannot clear the candidate.
            if loadedProgramId != currentId { programSuggestions = [:] }
            applyJSON(json)
            todayPlans = [:]
            eveningSchedule = currentId == activeId ? evening.filter { fullProgram[$0.value] != nil } : evening
            if let preview {
                let transport = self.transport
                let enrich = {
                    try await DayComposerLoader.enrichPreparation(preview: preview, programme: data,
                        morning: morning, transport: transport)
                }
                if let existing = dayComposerCandidate, existing.matches(preview) {
                    existing.updateEnrichment(enrich)
                } else { dayComposerCandidate = DayComposerPreparationCandidate(preview: preview, enrich: enrich) }
            } else { dayComposerCandidate = nil }
            planningRevision += 1
            isLoading = false
            if currentId == activeId { cache.save(data, for: "programme_data") }
            // No cancellation of this shared read by a disappearing refresh
            // waiter: the preparation may already be using its result.
            let morningData = try? await morning.value
            let eveningPlanData = await eveningPlan.value
            if current(), currentId == activeId {
                var plans: [String: SeanceData] = [:]
                for (source, bytes) in [("morning", morningData), ("evening", eveningPlanData)] {
                    if let bytes, let plan = try? APIService.decoder.decode(SeanceData.self, from: bytes),
                       plan.todayDate == date { plans[source] = plan }
                }
                todayPlans = plans
            }
            if let wData = morningData, current(),
               let wJson = try JSONSerialization.jsonObject(with: wData) as? [String: Any],
               let weights = wJson["weights"] as? [String: [String: Any]] {
                exerciseWeights = weights.compactMapValues { d in
                    (d["current_weight"] as? Double, d["last_reps"] as? String, d["last_logged"] as? String)
                }
            }
            if current() { await migrateLegacyCycleStartDateIfNeeded() }
        } catch { /* A cancelled/failed refresh retains the entire last presentation. */ }
    }

    func loadSuggestions() async {
        // Les suggestions backend suivent le programme actif. Ne jamais les
        // présenter dans l'éditeur d'un programme seulement consulté.
        guard loadedProgramId == activeProgramId else { return }
        // Guard anti-rafale : .task + onChange peuvent firer quasi-simultanément
        // à l'ouverture. Le remplissage progressif ci-dessous fait office de
        // sémaphore — dès la 1ère séance écrite, un loadSuggestions concurrent
        // trouve programSuggestions non vide et retourne. Reset : loadData(programId:)
        // sur switch de programme + invalidation cache (sessionLogged/programmeMutated).
        guard programSuggestions.isEmpty else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: Date())
        let amNames = Set(schedule.values)
        let pmNames = Set(eveningSchedule.values)
        for seance in orderedSeances {
            // Slot réel de la séance : morning si planifiée AM (ou fallback
            // non-planifiée), evening si uniquement PM. AM gagne en cas
            // d'ambiguïté AM+PM, cohérent avec priorité 1 par nom du backend
            // (get_previous_session_by_name ignore session_type). "morning" en
            // dur cassait la précharge des séances PM neuves : mauvais slot en
            // workout_schedule.py (exos du matin chargés) + fallback historique
            // filtré sur le mauvais type.
            let sessionType: String = amNames.contains(seance) ? "morning"
                                    : pmNames.contains(seance) ? "evening"
                                    : "morning"
            if let list = try? await APIService.shared.fetchProgressionSuggestions(
                date: dateStr, sessionType: sessionType, sessionName: seance
            ) {
                programSuggestions[seance] = Dictionary(uniqueKeysWithValues: list.map { ($0.exerciseName, $0) })
            }
        }
    }

    // MARK: - Mutations — wrapper
    //
    // Deux chemins d'écriture coexistent volontairement — contrats distincts,
    // pas un doublon accidentel :
    //
    //  - postProgramme (silencieux) : contrat "mute mon état local APRÈS le POST,
    //    optimistement uniquement si succès". Incrémente mutationCount (chip
    //    toolbar), attrape l'erreur dans lastSaveError. Le handler lit ensuite
    //    lastSaveError pour décider (ex: showSaveSuccess). Utilisé par 6
    //    handlers : addExercise, deleteExercise, reorderExercises, editExercise,
    //    createSeance, deleteSeance.
    //
    //  - postProgrammeThrowing (raw) : contrat "je mute AVANT le POST, je
    //    rollback moi-même sur throw". Conservé pour un futur handler qui
    //    a besoin de propager l'erreur au call site — plus consommé depuis
    //    la suppression de saveSessionOrder (D5).
    //
    // Fusion possible mais anti-lazy : 6 handlers dupliqueraient le try/catch +
    // mutationCount + lastSaveError. Duplication supérieure au coût de 2
    // wrappers privés.

    private func postProgrammeThrowing(_ body: [String: Any]) async throws {
        var enrichedBody = body
        if !selectedProgramId.isEmpty, enrichedBody["program_id"] == nil {
            enrichedBody["program_id"] = selectedProgramId
        }
        try await APIService.shared.postProgrammeMutation(enrichedBody)
    }

    private func postProgramme(_ body: [String: Any]) async {
        mutationCount += 1
        lastSaveError = false
        defer { mutationCount = max(0, mutationCount - 1) }
        do { try await postProgrammeThrowing(body) }
        catch { lastSaveError = true }
    }

    // MARK: - Mutations exercice

    func addExercise(seance: String, exercise: String, scheme: String) async {
        await postProgramme(["action": "add", "jour": seance, "exercise": exercise, "scheme": scheme])
        fullProgram[seance, default: [:]][exercise] = scheme
        exerciseOrder[seance, default: []].append(exercise)
        if !lastSaveError { showSaveSuccess("Exercice ajouté") }
    }

    /// Ajout multiple séquentiel — une intention côté VM (au lieu d'une boucle
    /// côté vue comme pasteSeance). Filtre les exos déjà présents (fullProgram
    /// est source de vérité, la sheet ne le voit pas). Mutation locale
    /// CONDITIONNÉE au succès du POST (évite l'optimiste non conditionné :
    /// un exo qui n'est pas persisté ne doit pas apparaître à l'affichage).
    /// Option 1 continue-on-error : un échec n'interrompt pas le batch.
    func addExercises(seance: String, exercises: [(String, String)]) async {
        guard !exercises.isEmpty else { return }
        let existing: Set<String> = fullProgram[seance].map { Set($0.keys) } ?? []
        let toAdd = exercises.filter { !existing.contains($0.0) }
        guard !toAdd.isEmpty else { return }

        mutationCount += 1
        lastSaveError = false
        defer { mutationCount = max(0, mutationCount - 1) }

        var added = 0
        var failed = 0
        for (ex, scheme) in toAdd {
            do {
                try await postProgrammeThrowing(["action": "add", "jour": seance, "exercise": ex, "scheme": scheme])
                fullProgram[seance, default: [:]][ex] = scheme
                exerciseOrder[seance, default: []].append(ex)
                added += 1
            } catch {
                failed += 1
            }
        }
        if failed > 0 { lastSaveError = true }
        if added > 0 && failed == 0 {
            showSaveSuccess(added == 1 ? "1 exercice ajouté" : "\(added) exercices ajoutés")
        } else if added > 0 {
            showSaveSuccess("\(added) ajouté(s), \(failed) échec(s)")
        }
    }

    func deleteExercise(seance: String, exercise: String) async {
        await postProgramme(["action": "remove", "jour": seance, "exercise": exercise])
    }

    func reorderExercises(seance: String, order: [String]) async {
        // Guard : orderedNames incomplet dropperait silencieusement des exercices.
        let actual = fullProgram[seance]?.count ?? 0
        guard order.count >= actual else { return }
        await postProgramme(["action": "reorder", "jour": seance, "ordre": order])
    }

    func editExercise(seance: String, oldName: String, newName: String, scheme: String) async {
        if oldName != newName {
            // rename synce tous les jours du programme + inventaire
            await postProgramme(["action": "rename", "jour": seance, "old_exercise": oldName, "new_exercise": newName])
            await postProgramme(["action": "scheme", "jour": seance, "exercise": newName, "scheme": scheme])
            // Swift Dicts sont value types — read, mutate, write back
            for key in fullProgram.keys {
                if let oldScheme = fullProgram[key]?[oldName] {
                    fullProgram[key]?[newName] = oldScheme
                    fullProgram[key]?.removeValue(forKey: oldName)
                }
            }
            fullProgram[seance]?[newName] = scheme
        } else {
            await postProgramme(["action": "scheme", "jour": seance, "exercise": oldName, "scheme": scheme])
            fullProgram[seance]?[oldName] = scheme
        }
        if !lastSaveError { showSaveSuccess("Exercice modifié") }
    }

    // MARK: - Mutations planning

    func saveSchedule() async {
        do {
            try await APIService.shared.saveMorningSchedule(schedule)
        } catch {
            lastSaveError = true
        }
    }

    func saveEveningSchedule() async {
        do {
            try await APIService.shared.saveEveningSchedule(eveningSchedule)
        } catch {
            lastSaveError = true
        }
    }

    /// Écrit programs.cycle_start_date serveur puis met à jour l'état local.
    /// Optimiste + rollback sur throw — cohérent avec les autres save*.
    func saveCycleStartDate(_ date: String) async {
        let previous = cycleStartDate
        cycleStartDate = date
        do {
            let programId = loadedProgramId.isEmpty ? nil : loadedProgramId
            try await APIService.shared.saveCycleStartDate(date, programId: programId)
        } catch {
            cycleStartDate = previous
            lastSaveError = true
        }
    }

    /// Migration one-shot du @AppStorage local "periodisation_start" vers le
    /// serveur (programs.cycle_start_date). Le local gagne sur le serveur SI il
    /// existe et diverge — préserve la date que Vince avait fixée sur son
    /// iPhone avant le passage à la source serveur. Après POST succès, la clé
    /// legacy est supprimée. En cas d'échec réseau, retente au prochain load.
    /// À retirer une fois la migration confirmée (~mi-2027).
    private func migrateLegacyCycleStartDateIfNeeded() async {
        let defaults = UserDefaults.standard
        guard let localCache = defaults.string(forKey: "periodisation_start"),
              !localCache.isEmpty,
              localCache != cycleStartDate else { return }
        let priorErr = lastSaveError
        await saveCycleStartDate(localCache)
        if !lastSaveError {
            defaults.removeObject(forKey: "periodisation_start")
        }
        lastSaveError = priorErr  // ne pas polluer le chip toolbar avec la migration
    }

    // MARK: - Mutations séance

    func createSeance(name: String) async {
        var body: [String: Any] = ["action": "create_seance", "jour": name]
        if !selectedProgramId.isEmpty { body["program_id"] = selectedProgramId }
        await postProgramme(body)
        fullProgram[name] = [:]
        exerciseOrder[name] = []
    }

    func deleteSeance(name: String) async {
        await postProgramme(["action": "delete_seance", "jour": name])
        fullProgram.removeValue(forKey: name)
        exerciseOrder.removeValue(forKey: name)
        // Clear from schedule if assigned
        for (day, seance) in schedule where seance == name {
            schedule.removeValue(forKey: day)
        }
    }

    // saveSessionOrder supprimé D5 — l'ordre des séances dérive du planning
    // (cf. orderedSeances). Le backend reorder_sessions reste orphelin (dead
    // code documenté) pour une passe hygiène future.

    // MARK: - Mutations programme

    func createProgram(name: String) async {
        do {
            let pid = try await APIService.shared.createProgram(name: name)
            let p = ProgramInfo(id: pid, name: name)
            programs.append(p)
            selectedProgramId = pid
            userDidSelect = true
            fullProgram = [:]
            exerciseOrder = [:]
        } catch {
            lastSaveError = true
        }
    }

    func setActiveProgramme() async {
        guard !selectedProgramId.isEmpty else { return }
        isSettingActive = true
        defer { isSettingActive = false }
        do {
            try await APIService.shared.setActiveProgram(id: selectedProgramId)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeProgramId = selectedProgramId
            }
            // Réhydrate immédiatement le contenu actif et filtre les anciennes
            // références du planning global qui appartenaient à l'actif précédent.
            await loadData(programId: selectedProgramId)
            await loadSuggestions()
        } catch {
            lastSaveError = true
        }
    }

    func renameProgram(id: String, name: String) async {
        do {
            try await APIService.shared.renameProgram(id: id, name: name)
            if let idx = programs.firstIndex(where: { $0.id == id }) {
                programs[idx] = ProgramInfo(id: id, name: name)
            }
        } catch {
            lastSaveError = true
        }
    }

    func deleteProgram(id: String) async {
        do {
            try await APIService.shared.deleteProgram(id: id)
            programs.removeAll { $0.id == id }
            if selectedProgramId == id { selectedProgramId = programs.first?.id ?? "" }
            await loadData(programId: selectedProgramId.isEmpty ? nil : selectedProgramId)
        } catch {
            lastSaveError = true
        }
    }

    // MARK: - Toast success

    func showSaveSuccess(_ msg: String) {
        withAnimation { saveSuccessMsg = msg }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { self.saveSuccessMsg = nil }
        }
    }
}
