import Foundation
import OSLog

private let workoutLogger = Logger(subsystem: "TrainingOS", category: "api+workout")

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

    func deleteHIIT(date: String, sessionType: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_hiit",
                                  payload: ["date": date, "session_type": sessionType])
    }

    func hiitEdit(body: [String: Any]) async throws -> Data {
        guard let data = try await offlinePost(endpoint: "/api/hiit/edit", payload: body) else {
            throw APIError.queuedOffline
        }
        return data
    }

    // MARK: - Generated Program
    func generateProgram() async throws -> GeneratedProgram {
        let url = try buildURL(path: "/api/ai/generate_program")
        var req = URLRequest(url: url)
        req.httpMethod  = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        let (data, response) = try await URLSession.authed.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "API", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "Erreur \(http.statusCode)"])
        }
        return try APIService.decoder.decode(GeneratedProgram.self, from: data)
    }

    func fetchLatestGeneratedProgram() async throws -> GeneratedProgram? {
        let url = try buildURL(path: "/api/ai/generated_program/latest")
        let (data, response) = try await URLSession.authed.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try APIService.decoder.decode(GeneratedProgram.self, from: data)
    }

    func approveGeneratedProgram(_ gp: GeneratedProgram) async throws -> String {
        let content = gp.programJson
        let week1   = content.weeks.first

        let progUrl = try buildURL(path: "/api/programs")
        var progReq = URLRequest(url: progUrl)
        progReq.httpMethod = "POST"
        progReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let dateStr = DateFormatter.isoDate.string(from: Date())
        progReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "create",
            "name": "\(content.name) — \(dateStr)"
        ])
        let (progData, _) = try await URLSession.authed.data(for: progReq)
        guard let progJson = try JSONSerialization.jsonObject(with: progData) as? [String: Any],
              let programmeId = progJson["id"] as? String else {
            throw NSError(domain: "API", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Impossible de créer le programme"])
        }

        let days = week1?.days ?? []
        let programmeURL = try buildURL(path: "/api/programme")

        var failedSeances: [String] = []
        await withTaskGroup(of: (String, Bool).self) { group in
            for day in days {
                let name = day.name; let pid = programmeId
                group.addTask {
                    var req = URLRequest(url: programmeURL)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: [
                        "action": "create_seance", "jour": name, "program_id": pid
                    ])
                    do {
                        let (_, resp) = try await URLSession.authed.data(for: req)
                        return (name, (200...299).contains((resp as? HTTPURLResponse)?.statusCode ?? 0))
                    } catch {
                        workoutLogger.warning("create_seance failed [\(name)]: \(error)")
                        return (name, false)
                    }
                }
            }
            for await (name, ok) in group where !ok { failedSeances.append(name) }
        }
        guard failedSeances.isEmpty else {
            throw NSError(domain: "API", code: 500, userInfo: [NSLocalizedDescriptionKey:
                "Séances non créées : \(failedSeances.sorted().joined(separator: ", "))"])
        }

        var failedExercises: [String] = []
        await withTaskGroup(of: (String, Bool).self) { group in
            for day in days {
                for ex in day.exercises {
                    let dayName = day.name; let exName = ex.name
                    let scheme = "\(ex.sets)x\(ex.reps)"; let pid = programmeId
                    group.addTask {
                        var req = URLRequest(url: programmeURL)
                        req.httpMethod = "POST"
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        req.httpBody = try? JSONSerialization.data(withJSONObject: [
                            "action": "add", "jour": dayName,
                            "exercise": exName, "scheme": scheme, "program_id": pid
                        ])
                        do {
                            let (_, resp) = try await URLSession.authed.data(for: req)
                            return ("\(exName) (\(dayName))", (200...299).contains((resp as? HTTPURLResponse)?.statusCode ?? 0))
                        } catch {
                            workoutLogger.warning("add_exercise failed [\(exName)/\(dayName)]: \(error)")
                            return ("\(exName) (\(dayName))", false)
                        }
                    }
                }
            }
            for await (label, ok) in group where !ok { failedExercises.append(label) }
        }
        guard failedExercises.isEmpty else {
            throw NSError(domain: "API", code: 500, userInfo: [NSLocalizedDescriptionKey:
                "Exercices non ajoutés : \(failedExercises.sorted().joined(separator: ", "))"])
        }

        if !content.schedule.isEmpty {
            var schedReq = URLRequest(url: try buildURL(path: "/api/morning_schedule"))
            schedReq.httpMethod = "POST"
            schedReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            schedReq.httpBody = try JSONSerialization.data(withJSONObject: ["schedule": content.schedule])
            let (_, schedResp) = try await URLSession.authed.data(for: schedReq)
            if let http = schedResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                workoutLogger.warning("morning_schedule update failed: HTTP \(http.statusCode) — planning à reconfigurer manuellement")
            }
        }

        var approveReq = URLRequest(url: try buildURL(path: "/api/ai/generated_program/approve"))
        approveReq.httpMethod = "POST"
        approveReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        approveReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": gp.id,
            "programme_id": programmeId
        ])
        let (_, approveResp) = try await URLSession.authed.data(for: approveReq)
        if let http = approveResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "API", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey:
                "Approbation programme échouée : HTTP \(http.statusCode)"])
        }

        CacheInvalidation.programmeApproved.invalidate()
        return programmeId
    }

    func fetchPostWorkoutBrief(sessionType: String, rpe: Double?, exos: [String],
                               comment: String?, date: String) async throws -> String {
        let url = try buildURL(path: "/api/ai/post_workout")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        var body: [String: Any] = ["session_type": sessionType, "exos": exos, "date": date]
        if let rpe { body["rpe"] = rpe }
        if let comment, !comment.isEmpty { body["comment"] = comment }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.authed.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let brief = json["brief"] as? String else {
            throw URLError(.badServerResponse)
        }
        return brief
    }

    func fetchWeeklyNarrative(context: String, weekKey: String) async throws -> String {
        let url = try buildURL(path: "/api/ai/narrative")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["context": context, "week": weekKey])
        let (data, _) = try await URLSession.authed.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let narrative = json["narrative"] as? String else {
            throw URLError(.badServerResponse)
        }
        return narrative
    }

    func fetchProgressionSuggestions(date: String, sessionType: String,
                                     sessionName: String = "") async throws -> [ProgressionSuggestion] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "session_type", value: sessionType)
        ]
        if !sessionName.isEmpty { items.append(URLQueryItem(name: "session_name", value: sessionName)) }
        let url = try buildURL(path: "/api/progression_suggestions", queryItems: items)
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.authed.data(for: req)
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
