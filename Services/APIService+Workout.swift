import Foundation
import OSLog

private let workoutLogger = Logger(subsystem: "TrainingOS", category: "api+workout")

// Étape 3 — signal posté par les writers d'overrides (move/clear). Les vues
// listen pour refetch leur payload (source unique backend). Ancien nom
// .seanceSplitStoreDidChange renommé au retrait de SeanceSplitStore (commit 3).
extension Notification.Name {
    static let planOverridesDidChange = Notification.Name("planOverridesDidChange")
}

extension APIService {
    // MARK: - Seance Data
    func fetchSeanceData() async throws -> SeanceData {
        let url = try buildURL(path: "/api/seance_data")
        let data = try await fetchWithCache(url: url, key: "seance_data")
        return try APIService.decoder.decode(SeanceData.self, from: data)
    }

    func fetchSeanceData(sessionName: String) async throws -> SeanceData {
        let url = try buildURL(path: "/api/seance_data",
                               queryItems: [URLQueryItem(name: "session_name", value: sessionName)])
        let (data, _) = try await URLSession.authed.data(from: url)
        return try APIService.decoder.decode(SeanceData.self, from: data)
    }

    func logExercise(exercise: String, weight: Double, reps: String,
                     rpe: Double? = nil, sets: [[String: Any]] = [],
                     force: Bool = false, isSecond: Bool = false, isBonus: Bool = false,
                     equipmentType: String = "", painZone: String = "", notes: String = "",
                     invalidate: Bool = true) async throws -> LogExerciseResponse {
        var body: [String: Any] = ["exercise": exercise, "weight": weight, "reps": reps]
        if let rpe { body["rpe"] = rpe }
        if !sets.isEmpty { body["sets"] = sets }
        if force    { body["force"] = true }
        if isSecond { body["is_second"] = true }
        if isBonus  { body["is_bonus"] = true }
        if !equipmentType.isEmpty { body["equipment_type"] = equipmentType }
        if !painZone.isEmpty { body["pain_zone"] = painZone }
        if !notes.isEmpty { body["notes"] = notes }
        guard let data = try await offlinePost(endpoint: "/api/log", payload: body) else {
            return LogExerciseResponse(success: nil, newWeight: nil, oneRM: nil, isPR: nil, baselineCount: nil, confidence: nil)
        }
        if invalidate { CacheInvalidation.exerciseLogged(isSecond: isSecond, isBonus: isBonus).invalidate() }
        do {
            return try APIService.decoder.decode(LogExerciseResponse.self, from: data)
        } catch {
            workoutLogger.error("❌ logExercise decode failed: \(error, privacy: .public)")
            throw APIError.decodingFailed(endpoint: "/api/log", error: error)
        }
    }

    func logSession(exos: [String], rpe: Double, comment: String,
                    durationMin: Double? = nil, energyPre: Int? = nil,
                    secondSession: Bool = false, bonusSession: Bool = false,
                    sessionName: String? = nil,
                    exerciseLogs: [[String: Any]] = [],
                    date: String? = nil) async throws {
        var body: [String: Any] = ["exos": exos, "rpe": rpe, "comment": comment]
        if let d = durationMin  { body["duration_min"] = d }
        if let e = energyPre    { body["energy_pre"] = e }
        if secondSession        { body["second_session"] = true }
        if bonusSession         { body["bonus_session"] = true }
        if let n = sessionName, !n.isEmpty { body["session_name"] = n }
        if !exerciseLogs.isEmpty { body["exercise_logs"] = exerciseLogs }
        if let d = date         { body["date"] = d }
        if !secondSession && !bonusSession && date == nil {
            await MainActor.run { sessionLoggedToday = true }
        }
        if try await offlinePost(endpoint: "/api/log_session", payload: body) != nil {
            CacheInvalidation.sessionLogged(isSecond: secondSession, isBonus: bonusSession).invalidate()
        }
        if !secondSession && !bonusSession { NotificationService.cancelSessionReminders() }
    }

    func fetchSeanceSoirData() async throws -> SeanceSoirData {
        let url = try buildURL(path: "/api/seance_soir_data")
        let data = try await fetchWithCache(url: url, key: "seance_soir_data")
        return try APIService.decoder.decode(SeanceSoirData.self, from: data)
    }

    /// POST programs.cycle_start_date. Structure = throw, jamais offlinePost
    /// (pas de replay silencieux d'une date fantôme au réseau).
    func saveCycleStartDate(_ date: String) async throws {
        let url = try buildURL(path: "/api/cycle_start_date")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["date": date])
        _ = try await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "dashboard")
    }

    func deleteSession(date: String, sessionType: String = "morning") async throws {
        if try await offlinePost(endpoint: "/api/session/delete",
                                 payload: ["date": date, "session_type": sessionType]) != nil {
            CacheInvalidation.sessionMutated.invalidate()
        }
    }

    func updateSession(date: String, rpe: Double?, comment: String, sessionType: String = "morning") async throws {
        var body: [String: Any] = ["date": date, "comment": comment, "session_type": sessionType]
        if let rpe { body["rpe"] = rpe }
        if try await offlinePost(endpoint: "/api/update_session", payload: body) != nil {
            CacheInvalidation.sessionMutated.invalidate()
        }
    }

    func editSession(date: String, rpe: Double?, comment: String, sessionType: String = "morning",
                     exercises: [[String: Any]]? = nil) async throws {
        var body: [String: Any] = ["date": date, "comment": comment, "session_type": sessionType]
        if let rpe { body["rpe"] = rpe }
        if let exercises { body["exercises"] = exercises }
        if try await offlinePost(endpoint: "/api/session/edit", payload: body) != nil {
            CacheInvalidation.sessionMutated.invalidate()
        }
    }

    // MARK: - HIIT
    func fetchHIITData() async throws -> [HIITEntry] {
        let url = try buildURL(path: "/api/hiit_data")
        let data = try await fetchWithCache(url: url, key: "hiit_data")
        struct HIITResponse: Codable {
            let hiitLog: [HIITEntry]
            enum CodingKeys: String, CodingKey { case hiitLog = "hiit_log" }
        }
        return try APIService.decoder.decode(HIITResponse.self, from: data).hiitLog
    }

    func logHIIT(sessionType: String, rounds: Int, workTime: Int, restTime: Int,
                 rpe: Double, notes: String, secondSession: Bool = false) async throws {
        let body: [String: Any] = [
            "session_type": sessionType, "rounds": rounds,
            "work_time": workTime, "rest_time": restTime,
            "rpe": rpe, "notes": notes, "second_session": secondSession
        ]
        _ = try await offlinePost(endpoint: "/api/log_hiit", payload: body)
        CacheInvalidation.hiitLogged.invalidate()
    }

    // MARK: - Inventaire mutations

    func saveExercise(_ body: [String: Any]) async throws {
        _ = try await offlinePost(endpoint: "/api/save_exercise", payload: body)
        CacheInvalidation.inventaireMutated.invalidate()
    }

    func deleteExerciseItem(name: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_exercise", payload: ["name": name])
        CacheInvalidation.inventaireMutated.invalidate()
    }

    func classifyExercise(_ body: [String: Any]) async throws {
        _ = try await offlinePost(endpoint: "/api/exercises/classify", payload: body)
        CacheInvalidation.inventaireMutated.invalidate()
    }

    // MARK: - Programme mutations

    /// POST direct sur le module PROGRAMME (structure : programme, schedules, création).
    /// offlinePost interdit ici : un replay silencieux dupliquerait ou fantômerait la
    /// mutation (précédent budget, précédent create_seance qui a nécessité
    /// l'idempotence backend 954fcd3). Erreur → throw APIError → le call site remonte
    /// au badge lastSaveError existant. Doctrine CLAUDE.md :
    /// mutations de STRUCTURE = POST direct + throw ; logs de TERRAIN (exercice,
    /// séance, recovery) = offlinePost toléré (gym hors-ligne).
    private func postProgrammeDirect(endpoint: String, payload: [String: Any]) async throws -> Data {
        guard let url = URL(string: APIConfig.base + endpoint) else {
            throw APIError.invalidURL(path: endpoint)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.authed.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                      ?? "erreur réseau"
            throw APIError.serverError(code, msg)
        }
        return data
    }

    func saveEveningSchedule(_ schedule: [String: String]) async throws {
        _ = try await postProgrammeDirect(endpoint: "/api/evening_schedule", payload: schedule as [String: Any])
        CacheInvalidation.programmeMutated.invalidate()
    }

    // MARK: - Bonus session creation (étape 2b)
    // POST direct + throw (doctrine STRUCTURE) — la création d'une séance est
    // une mutation structurelle, pas un log de terrain. Idempotent côté backend
    // via UNIQUE(date, session_type='bonus') + get_workout_session_bonus check.
    struct CreateBonusSessionResponse: Codable {
        let created: Bool
        let session: WorkoutSessionRow
        struct WorkoutSessionRow: Codable {
            let id: String
            let date: String
            let sessionType: String
            let sessionName: String?
            enum CodingKeys: String, CodingKey {
                case id, date
                case sessionType = "session_type"
                case sessionName = "session_name"
            }
        }
    }

    func createBonusSession(date: String? = nil) async throws -> CreateBonusSessionResponse {
        var payload: [String: Any] = [:]
        if let date = date { payload["date"] = date }
        let data = try await postProgrammeDirect(endpoint: "/api/create_bonus_session", payload: payload)
        return try JSONDecoder().decode(CreateBonusSessionResponse.self, from: data)
    }

    // MARK: - Plan overrides (étape 3b — déplacement d'exos planifiés)
    // POST direct + throw (doctrine STRUCTURE). Le 409 exercise_already_logged
    // remonte via APIError.serverError — le call site affiche l'alert. UNIQUE
    // (date, exercise_id) côté backend → re-move idempotent.

    func movePlannedExercise(date: String, exerciseId: String, to: SessionKind) async throws {
        let payload: [String: Any] = [
            "date": date,
            "exercise_id": exerciseId,
            "to_session_type": to.rawValue,
        ]
        _ = try await postProgrammeDirect(endpoint: "/api/move_planned_exercise", payload: payload)
        CacheInvalidation.sessionMutated.invalidate()
    }

    func clearPlanOverrides(date: String? = nil) async throws -> Int {
        var payload: [String: Any] = [:]
        if let date = date { payload["date"] = date }
        let data = try await postProgrammeDirect(endpoint: "/api/clear_plan_overrides", payload: payload)
        CacheInvalidation.sessionMutated.invalidate()
        struct ClearResponse: Codable { let deleted: Int }
        return (try? JSONDecoder().decode(ClearResponse.self, from: data).deleted) ?? 0
    }

    func saveMorningSchedule(_ schedule: [String: String]) async throws {
        _ = try await postProgrammeDirect(endpoint: "/api/morning_schedule", payload: ["schedule": schedule])
        CacheInvalidation.programmeMutated.invalidate()
    }

    func postProgrammeMutation(_ body: [String: Any]) async throws {
        _ = try await postProgrammeDirect(endpoint: "/api/programme", payload: body)
        CacheInvalidation.programmeMutated.invalidate()
    }

    func createProgram(name: String) async throws -> String {
        let data = try await postProgrammeDirect(endpoint: "/api/programs",
                                                  payload: ["action": "create", "name": name])
        CacheInvalidation.programmeMutated.invalidate()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid  = json["id"] as? String else {
            throw APIError.decodingFailed(endpoint: "/api/programs",
                                          error: NSError(domain: "programs", code: 0))
        }
        return pid
    }

    func setActiveProgram(id: String) async throws {
        _ = try await postProgrammeDirect(endpoint: "/api/programs",
                                           payload: ["action": "set_active", "program_id": id])
        CacheInvalidation.programmeMutated.invalidate()
    }

    func renameProgram(id: String, name: String) async throws {
        _ = try await postProgrammeDirect(endpoint: "/api/programs",
                                           payload: ["action": "rename", "program_id": id, "name": name])
        CacheInvalidation.programmeMutated.invalidate()
    }

    func deleteProgram(id: String) async throws {
        _ = try await postProgrammeDirect(endpoint: "/api/programs",
                                           payload: ["action": "delete", "program_id": id])
        CacheInvalidation.programmeMutated.invalidate()
    }

    func deleteHIIT(date: String, sessionType: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_hiit",
                                  payload: ["date": date, "session_type": sessionType])
        CacheInvalidation.hiitLogged.invalidate()
    }

    func hiitEdit(body: [String: Any]) async throws -> Data {
        guard let data = try await offlinePost(endpoint: "/api/hiit/edit", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheInvalidation.hiitLogged.invalidate()
        return data
    }

    func fetchProgressionSuggestions(date: String, sessionType: String,
                                     sessionName: String = "") async throws -> [ProgressionSuggestion] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "session_type", value: sessionType)
        ]
        if !sessionName.isEmpty { items.append(URLQueryItem(name: "session_name", value: sessionName)) }
        let url = try buildURL(path: "/api/progression_suggestions", queryItems: items)
        let key = "progression_suggestions_\(date)_\(sessionType)_\(sessionName)"
        let data = try await fetchWithCache(url: url, key: key)
        return try APIService.decoder.decode(ProgressionSuggestionsResponse.self, from: data).suggestions
    }

    func applyProgression(exerciseName: String, suggestedWeight: Double,
                          suggestedScheme: String?) async throws {
        var payload: [String: Any] = [
            "exercise_name": exerciseName,
            "suggested_weight": suggestedWeight
        ]
        if let scheme = suggestedScheme { payload["suggested_scheme"] = scheme }
        _ = try await offlinePost(endpoint: "/api/apply_progression", payload: payload)
    }

    func fetchSmartDay() async throws -> SmartDayRecommendation {
        let url = try buildURL(path: "/api/smart_day")
        let data = try await fetchWithCache(url: url, key: "smart_day")
        return try APIService.decoder.decode(SmartDayRecommendation.self, from: data)
    }

    func fetchWeeklyReport() async throws -> WeeklyReport {
        let url = try buildURL(path: "/api/weekly_report")
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.authed.data(for: req)
        return try APIService.decoder.decode(WeeklyReport.self, from: data)
    }

    func fetchDeloadData() async throws -> DeloadReport {
        let url = try buildURL(path: "/api/deload")
        let data = try await fetchWithCache(url: url, key: "deload")
        return try APIService.decoder.decode(DeloadReport.self, from: data)
    }

    func fetchACWR() async throws -> ACWRData {
        let url = try buildURL(path: "/api/acwr")
        let data = try await fetchWithCache(url: url, key: "acwr")
        return try APIService.decoder.decode(ACWRData.self, from: data)
    }

    func applyDeload(poidsDeload: [String: Double]) async throws {
        let url = try buildURL(path: "/api/apply_deload")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["poids_deload": poidsDeload])
        req.timeoutInterval = 15
        let (_, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "Impossible d'appliquer le déload pour le moment.")
        }
        CacheInvalidation.deloadApplied.invalidate()
    }

    // MARK: - Stats Data
    func fetchStatsData() async throws {
        let url = try buildURL(path: "/api/stats_data")
        var req = URLRequest(url: url); req.timeoutInterval = 15
        let (data, _) = try await URLSession.authed.data(for: req)
        CacheService.shared.save(data, for: "stats_data")
    }

}
