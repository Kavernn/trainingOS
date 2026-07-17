import Foundation
import Combine

/// ViewModel de ProgrammeView — Lot 2/3 (extraction data serveur + hydratation).
///
/// Commit 1 : état SERVEUR (inventaire, programmes, planning), runtime nécessaire
/// au chargement (isLoading, programSuggestions, exerciseWeights), hydratation
/// atomique via applyJSON, chargement (loadData + loadSuggestions).
///
/// Handlers de mutation restent dans la vue jusqu'au commit 2 — ils lisent/écrivent
/// vm.xxx via @Published. Commit 2 : migration des handlers + propagation throw
/// pour saveSessionOrder (échec drop → vue → vm.lastSaveError).
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

    /// Ordre serveur des séances. Hydraté par applyJSON, écrasé par saveSessionOrder
    /// (côté vue commit 1 — migre commit 2). La vue en dérive son sessionOrder local
    /// (drag) via .onChange sur orderedSeances. Jamais muter depuis le drag : le
    /// round-trip serveur est l'unique voie d'écriture.
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
}
