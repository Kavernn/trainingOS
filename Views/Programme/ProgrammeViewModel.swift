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
///  - saveSessionOrder throws + rollback apiSessionOrder sur échec (65e77c2).
@MainActor
final class ProgrammeViewModel: ObservableObject {

    // MARK: - Inventaire (SERVEUR — hydraté par applyJSON)

    @Published var fullProgram: [String: [String: String]] = [:]
    @Published var exerciseOrder: [String: [String]] = [:]
    @Published var schedule: [String: String] = [:]
    @Published var eveningSchedule: [String: String] = [:]
    @Published var inventory: [String] = []
    @Published var inventorySchemes: [String: String] = [:]
    @Published var inventoryMuscleGroups: [String: String] = [:]
    @Published var inventoryPatterns: [String: String] = [:]
    @Published var inventoryOneRM: [String: Double] = [:]
    @Published var exerciseSupersets: [String: [String: SupersetEntry]] = [:]

    /// Miroir de l'ordre serveur des séances (drag persisté). Hydraté par
    /// applyJSON, écrasé optimistement par saveSessionOrder puis rollback en cas
    /// d'échec. La vue en dérive son sessionOrder local (drag) via .onChange sur
    /// orderedSeances — seul le round-trip serveur (saveSessionOrder) écrit ici.
    @Published var apiSessionOrder: [String] = []

    // MARK: - Multi-programmes (SERVEUR)

    @Published var programs: [ProgramInfo] = []
    @Published var selectedProgramId: String = ""
    @Published var activeProgramId: String = ""
    @Published var allSessions: [String] = []

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

    /// Ordre d'affichage des séances. Deux régimes :
    ///  - apiSessionOrder non-vide (drag persisté serveur) : cet ordre prime.
    ///    Les séances disparues du programme sont filtrées, les nouvelles séances
    ///    (créées après le dernier reorder serveur) sont ajoutées en fin dans
    ///    l'ordre canonique+alpha.
    ///  - apiSessionOrder vide (premier launch, jamais dragé) : fallback sur
    ///    canonique + custom alpha (doctrine pure).
    ///
    /// Reproduit la sémantique de refreshSessionOrder() d'avant Lot 2. Sans ça,
    /// un drag persisté serait perdu à la prochaine hydratation (relance app).
    var orderedSeances: [String] {
        let known  = TrainingDoctrine.canonicalSeanceOrder.filter { fullProgram[$0] != nil }
        let custom = fullProgram.keys.filter { !TrainingDoctrine.canonicalSeanceOrder.contains($0) }.sorted()
        let canonicalPlusCustom = known + custom

        guard !apiSessionOrder.isEmpty else { return canonicalPlusCustom }

        let existing = Set(fullProgram.keys)
        let base = apiSessionOrder.filter { existing.contains($0) }
        let missing = canonicalPlusCustom.filter { !base.contains($0) }
        return base + missing
    }

    /// Fréquence hebdo par séance (schedule.values, hors "Repos").
    private var weeklySessionFrequency: [String: Int] {
        var freq: [String: Int] = [:]
        for session in schedule.values where session != "Repos" {
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
        // Plus de refreshSessionOrder() : orderedSeances est computed. La vue s'y
        // resynchronise via .onChange (sync explicite VM ↔ vue, commit 1).
    }

    /// Charge /api/programme_data (cache d'abord, puis réseau), puis
    /// /api/evening_schedule et /api/seance_data. Séquentiel : async let LIFO crash
    /// sur iOS 26 beta (lessons.md).
    func loadData(programId: String? = nil) async {
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
        if let eURL = URL(string: "\(APIConfig.base)/api/evening_schedule"),
           let (eData, _) = try? await URLSession.authed.data(from: eURL),
           let eJson = try? JSONSerialization.jsonObject(with: eData) as? [String: String] {
            eveningSchedule = eJson
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
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: Date())
        var result: [String: [String: ProgressionSuggestion]] = [:]
        for seance in orderedSeances {
            if let list = try? await APIService.shared.fetchProgressionSuggestions(
                date: dateStr, sessionType: "morning", sessionName: seance
            ) {
                result[seance] = Dictionary(uniqueKeysWithValues: list.map { ($0.exerciseName, $0) })
            }
        }
        programSuggestions = result
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
    //    rollback moi-même sur throw". Utilisé par saveSessionOrder qui a besoin
    //    de rollback apiSessionOrder + propagation d'erreur à la vue (chip
    //    lastSaveError positionné au call site du drop, pas ici).
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

    /// Push l'ordre des séances au serveur. Throws — la vue attrape et set
    /// lastSaveError. Sans ça un drag échoué laisserait apiSessionOrder mentir
    /// jusqu'au prochain loadData (écrasement optimiste jamais rollback).
    func saveSessionOrder(_ order: [String]) async throws {
        let previous = apiSessionOrder
        mutationCount += 1
        lastSaveError = false
        apiSessionOrder = order
        defer { mutationCount = max(0, mutationCount - 1) }
        do {
            try await postProgrammeThrowing([
                "action": "reorder_sessions",
                "order": order,
            ])
        } catch {
            apiSessionOrder = previous
            throw error
        }
    }

    // MARK: - Mutations programme

    func createProgram(name: String) async {
        do {
            let pid = try await APIService.shared.createProgram(name: name)
            let p = ProgramInfo(id: pid, name: name)
            programs.append(p)
            selectedProgramId = pid
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
