import Foundation

extension APIService {
    // MARK: - Seance Data
    func fetchSeanceData() async throws -> SeanceData {
        let url = URL(string: "\(baseURL)/api/seance_data")!
        let data = try await fetchWithCache(url: url, key: "seance_data")
        return try JSONDecoder().decode(SeanceData.self, from: data)
    }

    func fetchSeanceData(sessionName: String) async throws -> SeanceData {
        var comps = URLComponents(string: "\(baseURL)/api/seance_data")!
        comps.queryItems = [URLQueryItem(name: "session_name", value: sessionName)]
        let (data, _) = try await URLSession.authed.data(from: comps.url!)
        return try JSONDecoder().decode(SeanceData.self, from: data)
    }

    func logExercise(exercise: String, weight: Double, reps: String,
                     rpe: Double? = nil, sets: [[String: Any]] = [],
                     force: Bool = false, isSecond: Bool = false, isBonus: Bool = false,
                     equipmentType: String = "", painZone: String = "") async throws -> LogExerciseResponse {
        var body: [String: Any] = ["exercise": exercise, "weight": weight, "reps": reps]
        if let rpe { body["rpe"] = rpe }
        if !sets.isEmpty { body["sets"] = sets }
        if force    { body["force"] = true }
        if isSecond { body["is_second"] = true }
        if isBonus  { body["is_bonus"] = true }
        if !equipmentType.isEmpty { body["equipment_type"] = equipmentType }
        if !painZone.isEmpty { body["pain_zone"] = painZone }
        guard let data = try await offlinePost(endpoint: "/api/log", payload: body) else {
            return LogExerciseResponse(success: nil, newWeight: nil, oneRM: nil, isPR: nil)
        }
        if !isBonus { CacheService.shared.clear(for: isSecond ? "seance_soir_data" : "seance_data") }
        CacheService.shared.clear(for: "dashboard")
        CacheService.shared.clear(for: "stats_data")
        return (try? JSONDecoder().decode(LogExerciseResponse.self, from: data))
            ?? LogExerciseResponse(success: nil, newWeight: nil, oneRM: nil, isPR: nil)
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
            CacheService.shared.clear(for: "dashboard")
            CacheService.shared.clear(for: "historique_data")
            if !bonusSession {
                CacheService.shared.clear(for: secondSession ? "seance_soir_data" : "seance_data")
            }
            CacheService.shared.clear(for: "stats_data")
        }
    }

    func fetchSeanceSoirData() async throws -> SeanceSoirData {
        let url = URL(string: "\(baseURL)/api/seance_soir_data")!
        let data = try await fetchWithCache(url: url, key: "seance_soir_data")
        return try JSONDecoder().decode(SeanceSoirData.self, from: data)
    }

    func deleteSession(date: String, sessionType: String = "morning") async throws {
        if try await offlinePost(endpoint: "/api/session/delete",
                                 payload: ["date": date, "session_type": sessionType]) != nil {
            CacheService.shared.clear(for: "historique_data")
            CacheService.shared.clear(for: "dashboard")
        }
    }

    func updateSession(date: String, rpe: Double?, comment: String, sessionType: String = "morning") async throws {
        var body: [String: Any] = ["date": date, "comment": comment, "session_type": sessionType]
        if let rpe { body["rpe"] = rpe }
        if try await offlinePost(endpoint: "/api/update_session", payload: body) != nil {
            CacheService.shared.clear(for: "historique_data")
            CacheService.shared.clear(for: "dashboard")
        }
    }

    func editSession(date: String, rpe: Double?, comment: String, sessionType: String = "morning",
                     exercises: [[String: Any]]? = nil) async throws {
        var body: [String: Any] = ["date": date, "comment": comment, "session_type": sessionType]
        if let rpe { body["rpe"] = rpe }
        if let exercises { body["exercises"] = exercises }
        if try await offlinePost(endpoint: "/api/session/edit", payload: body) != nil {
            CacheService.shared.clear(for: "historique_data")
            CacheService.shared.clear(for: "dashboard")
        }
    }

    // MARK: - HIIT
    func fetchHIITData() async throws -> [HIITEntry] {
        let url = URL(string: "\(baseURL)/api/hiit_data")!
        let data = try await fetchWithCache(url: url, key: "hiit_data")
        struct HIITResponse: Codable {
            let hiitLog: [HIITEntry]
            enum CodingKeys: String, CodingKey { case hiitLog = "hiit_log" }
        }
        return try JSONDecoder().decode(HIITResponse.self, from: data).hiitLog
    }

    func logHIIT(sessionType: String, rounds: Int, workTime: Int, restTime: Int,
                 rpe: Double, notes: String, secondSession: Bool = false) async throws {
        let body: [String: Any] = [
            "session_type": sessionType, "rounds": rounds,
            "work_time": workTime, "rest_time": restTime,
            "rpe": rpe, "notes": notes, "second_session": secondSession
        ]
        _ = try await offlinePost(endpoint: "/api/log_hiit", payload: body)
        CacheService.shared.clear(for: "dashboard")
        CacheService.shared.clear(for: "hiit_data")
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
        let url = URL(string: "\(baseURL)/api/ai/generate_program")!
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
        return try JSONDecoder().decode(GeneratedProgram.self, from: data)
    }

    func fetchLatestGeneratedProgram() async throws -> GeneratedProgram? {
        let url = URL(string: "\(baseURL)/api/ai/generated_program/latest")!
        let (data, response) = try await URLSession.authed.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(GeneratedProgram.self, from: data)
    }

    func approveGeneratedProgram(_ gp: GeneratedProgram) async throws -> String {
        let content = gp.programJson
        let week1   = content.weeks.first

        let progUrl = URL(string: "\(baseURL)/api/programs")!
        var progReq = URLRequest(url: progUrl)
        progReq.httpMethod = "POST"
        progReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
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
        let base = baseURL
        await withTaskGroup(of: Void.self) { group in
            for day in days {
                let name = day.name; let pid = programmeId
                group.addTask {
                    var req = URLRequest(url: URL(string: "\(base)/api/programme")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: [
                        "action": "create_seance", "jour": name, "program_id": pid
                    ])
                    _ = try? await URLSession.authed.data(for: req)
                }
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for day in days {
                for ex in day.exercises {
                    let dayName = day.name; let exName = ex.name
                    let scheme = "\(ex.sets)x\(ex.reps)"; let pid = programmeId
                    group.addTask {
                        var req = URLRequest(url: URL(string: "\(base)/api/programme")!)
                        req.httpMethod = "POST"
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        req.httpBody = try? JSONSerialization.data(withJSONObject: [
                            "action": "add", "jour": dayName,
                            "exercise": exName, "scheme": scheme, "program_id": pid
                        ])
                        _ = try? await URLSession.authed.data(for: req)
                    }
                }
            }
        }

        if !content.schedule.isEmpty {
            var schedReq = URLRequest(url: URL(string: "\(baseURL)/api/morning_schedule")!)
            schedReq.httpMethod = "POST"
            schedReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            schedReq.httpBody = try JSONSerialization.data(withJSONObject: ["schedule": content.schedule])
            _ = try? await URLSession.authed.data(for: schedReq)
        }

        var approveReq = URLRequest(url: URL(string: "\(baseURL)/api/ai/generated_program/approve")!)
        approveReq.httpMethod = "POST"
        approveReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        approveReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": gp.id,
            "programme_id": programmeId
        ])
        _ = try? await URLSession.authed.data(for: approveReq)

        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "stats_data")
        return programmeId
    }

    func fetchPostWorkoutBrief(sessionType: String, rpe: Double?, exos: [String],
                               comment: String?, date: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/ai/post_workout")!
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
        let url = URL(string: "\(baseURL)/api/ai/narrative")!
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

    func fetchPeakPrediction() async throws -> PeakPredictionResponse {
        let url = URL(string: "\(baseURL)/api/peak_prediction")!
        let data = try await fetchWithCache(url: url, key: "peak_prediction")
        return try JSONDecoder().decode(PeakPredictionResponse.self, from: data)
    }

    func fetchProgressionSuggestions(date: String, sessionType: String,
                                     sessionName: String = "") async throws -> [ProgressionSuggestion] {
        var urlStr = "\(baseURL)/api/progression_suggestions?date=\(date)&session_type=\(sessionType)"
        if !sessionName.isEmpty,
           let encoded = sessionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlStr += "&session_name=\(encoded)"
        }
        let url = URL(string: urlStr)!
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.authed.data(for: req)
        return try JSONDecoder().decode(ProgressionSuggestionsResponse.self, from: data).suggestions
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
        let url = URL(string: "\(baseURL)/api/smart_day")!
        let data = try await fetchWithCache(url: url, key: "smart_day")
        return try JSONDecoder().decode(SmartDayRecommendation.self, from: data)
    }

    func fetchWeeklyReport() async throws -> WeeklyReport {
        let url = URL(string: "\(baseURL)/api/weekly_report")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.authed.data(for: req)
        return try JSONDecoder().decode(WeeklyReport.self, from: data)
    }

    func applyDeload(poidsDeload: [String: Double]) async throws {
        let url = URL(string: "\(baseURL)/api/apply_deload")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["poids_deload": poidsDeload])
        req.timeoutInterval = 15
        let (_, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "Impossible d'appliquer le déload pour le moment.")
        }
        CacheService.shared.clear(for: "seance_data")
        CacheService.shared.clear(for: "dashboard")
    }

    // MARK: - Stats Data
    func fetchStatsData() async throws {
        let url = URL(string: "\(baseURL)/api/stats_data")!
        var req = URLRequest(url: url); req.timeoutInterval = 15
        let (data, _) = try await URLSession.authed.data(for: req)
        CacheService.shared.save(data, for: "stats_data")
    }

    func fetchStatsWellness() async throws -> Data {
        let url = URL(string: "\(baseURL)/api/stats_wellness")!
        var req = URLRequest(url: url); req.timeoutInterval = 20
        let (data, _) = try await URLSession.authed.data(for: req)
        CacheService.shared.save(data, for: "stats_wellness")
        return data
    }
}
