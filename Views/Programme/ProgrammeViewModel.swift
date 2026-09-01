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
        if let raw = json["full_program"] as? [String: [String: Any]] {
            fullProgram = raw.mapValues { $0.compactMapValues { $0 as? String } }
        }
        schedule              = (json["schedule"] as? [String: String]) ?? [:]
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
        if let pid = json["current_program_id"] as? String, !pid.isEmpty {
            if !userDidSelect { selectedProgramId = pid }
            activeProgramId = pid
        }
        if let sessions = json["all_sessions"] as? [String] {
            allSessions = sessions
        }
        // Cycle mésocycle serveur — nil-safe : null explicite ou clé absente = pas
        // de cycle démarré. iOS reader (mesocycleCard) affichera "Non démarré".
        cycleStartDate = json["cycle_start_date"] as? String
        // Plus de refreshSessionOrder() : orderedSeances est computed. La vue s'y
        // resynchronise via .onChange (sync explicite VM ↔ vue, commit 1).
    }

    /// Charge /api/programme_data (cache d'abord, puis réseau), puis
    /// /api/evening_schedule et /api/seance_data. Séquentiel : async let LIFO crash
    /// sur iOS 26 beta (lessons.md).
    func loadData(programId: String? = nil) async {
        // Switch explicite de programme → suggestions du programme précédent
        // sont stale (autres séances). Reset le guard de loadSuggestions.
        if programId != nil { programSuggestions = [:] }
        var urlStr = "\(APIConfig.base)/api/programme_data"
        let pid = programId ?? (selectedProgramId.isEmpty ? nil : selectedProgramId)
        if let pid = pid { urlStr += "?program_id=\(pid)" }
        guard let url = URL(string: urlStr) else { isLoading = false; return }
        if let cached = CacheService.shared.load(for: "programme_data"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            applyJSON(json); isLoading = false
        }
        if let (data, _) = try? await URLSession.authed.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            CacheService.shared.save(data, for: "programme_data")
            applyJSON(json); isLoading = false
        } else {
            isLoading = false
        }
        await migrateLegacyCycleStartDateIfNeeded()
        if let eURL = URL(string: "\(APIConfig.base)/api/evening_schedule") {
            do {
                let (eData, _) = try await URLSession.authed.data(from: eURL)
                eveningSchedule = try JSONDecoder().decode([String: String].self, from: eData)
            } catch {
                print("⚠️ evening_schedule decode failed: \(error)")
            }
        }
        if let wURL = URL(string: "\(APIConfig.base)/api/seance_data"),
           let (wData, _) = try? await URLSession.authed.data(from: wURL),
           let wJson = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
           let weights = wJson["weights"] as? [String: [String: Any]] {
            exerciseWeights = weights.compactMapValues { d in
                let w  = d["current_weight"] as? Double
                let r  = d["last_reps"]      as? String
                let dt = d["last_logged"]    as? String
                return (w, r, dt)
            }
        }
    }

    func loadSuggestions() async {
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
            try await APIService.shared.saveCycleStartDate(date)
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
