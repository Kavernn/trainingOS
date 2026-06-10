import Foundation

extension APIService {
    // MARK: - Recovery
    func fetchRecoveryData() async throws -> [RecoveryEntry] {
        let url = try buildURL(path: "/api/recovery_data")
        let data = try await fetchWithCache(url: url, key: "recovery_data")
        struct Resp: Codable {
            let recoveryLog: [RecoveryEntry]
            enum CodingKeys: String, CodingKey { case recoveryLog = "recovery_log" }
        }
        return try APIService.decoder.decode(Resp.self, from: data).recoveryLog
    }

    func logRecovery(sleepHours: Double?, sleepQuality: Double?, restingHr: Double?,
                     hrv: Double?, steps: Int?, soreness: Double?,
                     fatigue: Double? = nil, energyPre: Double? = nil,
                     activeEnergy: Double? = nil, hrMorning: Double? = nil,
                     hrPostWorkout: Double? = nil, hrEvening: Double? = nil,
                     notes: String, date: String? = nil,
                     bedtime: String? = nil, wakeTime: String? = nil) async throws {
        var body: [String: Any] = ["notes": notes]
        if let v = sleepHours    { body["sleep_hours"]        = v }
        if let v = sleepQuality  { body["sleep_quality"]      = v }
        if let v = restingHr     { body["resting_hr"]         = v }
        if let v = hrv           { body["hrv"]                = v }
        if let v = steps         { body["steps"]              = v }
        if let v = soreness      { body["soreness"]           = v }
        if let v = fatigue       { body["fatigue_perceived"]  = Int(v) }
        if let v = energyPre     { body["energy_pre"]         = Int(v) }
        if let v = activeEnergy  { body["active_energy"]      = v }
        if let v = hrMorning     { body["hr_morning"]         = Int(v) }
        if let v = hrPostWorkout { body["hr_post_workout"]    = Int(v) }
        if let v = hrEvening     { body["hr_evening"]         = Int(v) }
        if let d = date          { body["date"]               = d }
        if let v = bedtime       { body["bedtime"]            = v }
        if let v = wakeTime      { body["wake_time"]          = v }
        _ = try await offlinePost(endpoint: "/api/log_recovery", payload: body)
        CacheInvalidation.recoveryLogged.invalidate()
    }

    // MARK: - iOS-side manual > HK protection

    /// Construit le payload HK en excluant les champs déjà saisis manuellement.
    ///
    /// Règle : si `existingEntry.source == "manual"` ET que le champ a déjà une valeur,
    /// on ne l'envoie pas — la saisie manuelle prime sur HealthKit des deux côtés.
    /// Les champs cumulatifs (steps, active_energy) sont toujours inclus car ils
    /// croissent dans la journée ; le backend les protège aussi si source="manual".
    static func buildHKPayload(
        snapshot: WearableSnapshot,
        existingEntry: RecoveryEntry?
    ) -> [String: Any] {
        let isManual = existingEntry?.source == "manual"

        // Retourne la valeur HK seulement si on ne risque pas d'écraser une valeur manuelle.
        func hk<T>(_ existing: T?, _ fromHK: T?) -> T? {
            guard let v = fromHK else { return nil }
            if isManual && existing != nil { return nil }
            return v
        }

        var body: [String: Any] = [:]
        if let v = hk(existingEntry?.sleepHours,    snapshot.sleepHours)    { body["sleep_hours"]       = v }
        if let v = hk(existingEntry?.restingHr,     snapshot.restingHr)     { body["resting_hr"]        = v }
        if let v = hk(existingEntry?.hrv,           snapshot.hrv)           { body["hrv"]               = v }
        if let v = hk(existingEntry?.hrMorning,     snapshot.hrMorning)     { body["hr_morning"]        = Int(v) }
        if let v = hk(existingEntry?.hrPostWorkout, snapshot.hrPostWorkout) { body["hr_post_workout"]   = Int(v) }
        if let v = hk(existingEntry?.hrEvening,     snapshot.hrEvening)     { body["hr_evening"]        = Int(v) }
        // Cumulatifs — toujours inclus (le backend protège si source=manual)
        if let v = snapshot.steps        { body["steps"]         = v }
        if let v = snapshot.activeEnergy { body["active_energy"] = v }
        return body
    }

    /// Envoie le snapshot HealthKit du jour à /api/healthkit_sync.
    /// Règle merge : manual > HK des deux côtés (iOS + backend).
    /// `existingEntry` = entrée courante en DB — permet le filtre iOS-side.
    /// Retourne l'entrée après merge ou nil si rien à syncer / offline.
    func syncHealthKitToday(
        snapshot: WearableSnapshot,
        existingEntry: RecoveryEntry? = nil
    ) async throws -> RecoveryEntry? {
        let body = APIService.buildHKPayload(snapshot: snapshot, existingEntry: existingEntry)
        guard !body.isEmpty else { return nil }
        guard let data = try await offlinePost(endpoint: "/api/healthkit_sync", payload: body) else {
            return nil
        }
        CacheInvalidation.recoveryLogged.invalidate()
        struct Resp: Codable {
            let ok: Bool
            let entry: RecoveryEntry?
            let msg: String?
        }
        let resp = try? APIService.decoder.decode(Resp.self, from: data)
        return resp?.ok == true ? resp?.entry : nil
    }

    func deleteRecovery(date: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_recovery", payload: ["date": date])
    }

    func fetchDailySummary(date: String? = nil) async throws -> DailySummary {
        var items: [URLQueryItem] = []
        if let d = date { items.append(URLQueryItem(name: "date", value: d)) }
        let url = try buildURL(path: "/api/health/daily_summary", queryItems: items)
        let data = try await fetchWithCache(url: url, key: "daily_summary_\(date ?? "today")")
        return try APIService.decoder.decode(DailySummary.self, from: data)
    }

    // MARK: - HRV Analysis
    func fetchHRVAnalysis() async throws -> HRVAnalysis {
        let url  = try buildURL(path: "/api/hrv/analysis")
        let data = try await fetchWithCache(url: url, key: "hrv_analysis")
        return try APIService.decoder.decode(HRVAnalysis.self, from: data)
    }

    // MARK: - PSS
    func fetchPSSQuestions(isShort: Bool = false) async throws -> [PSSQuestion] {
        let url = try buildURL(path: "/api/pss/questions", queryItems: [URLQueryItem(name: "short", value: "\(isShort)")])
        let data = try await fetchWithCache(url: url, key: "pss_questions_\(isShort)")
        return try APIService.decoder.decode([PSSQuestion].self, from: data)
    }

    func submitPSS(responses: [Int], isShort: Bool = false, notes: String? = nil,
                   triggers: [String] = [], triggerRatings: [String: Int] = [:]) async throws -> PSSRecord {
        var body: [String: Any] = ["responses": responses, "is_short": isShort]
        if let notes { body["notes"] = notes }
        if !triggers.isEmpty { body["triggers"] = triggers }
        if !triggerRatings.isEmpty { body["trigger_ratings"] = triggerRatings }
        guard let data = try await offlinePost(endpoint: "/api/pss/submit", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheInvalidation.pssSubmitted.invalidate()
        NotificationService.cancelPSSReminder()
        return try APIService.decoder.decode(PSSRecord.self, from: data)
    }

    func fetchPSSHistory(type: String? = nil) async throws -> [PSSRecord] {
        var items: [URLQueryItem] = []
        if let type { items.append(URLQueryItem(name: "type", value: type)) }
        let url = try buildURL(path: "/api/pss/history", queryItems: items)
        let data = try await fetchWithCache(url: url, key: "pss_history")
        return try APIService.decoder.decode([PSSRecord].self, from: data)
    }

    func checkPSSDue(type: String = "full") async throws -> PSSDueStatus {
        let url = try buildURL(path: "/api/pss/check_due", queryItems: [URLQueryItem(name: "type", value: type)])
        let data = try await fetchWithCache(url: url, key: "pss_check_due_\(type)")
        return try APIService.decoder.decode(PSSDueStatus.self, from: data)
    }

    // MARK: - Life Stress Engine
    func fetchLifeStressScore(date: String? = nil, forceRefresh: Bool = false) async throws -> LifeStressScore {
        var items: [URLQueryItem] = []
        if let date { items.append(URLQueryItem(name: "date", value: date)) }
        if forceRefresh { items.append(URLQueryItem(name: "refresh", value: "true")) }
        let url = try buildURL(path: "/api/life_stress/score", queryItems: items)
        let data = try await fetchWithCache(url: url, key: "life_stress_\(date ?? "today")")
        return try APIService.decoder.decode(LifeStressScore.self, from: data)
    }

    func fetchLifeStressTrend(days: Int = 7) async throws -> [LifeStressScore] {
        let url = try buildURL(path: "/api/life_stress/trend", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: "life_stress_trend_\(days)")
        return try APIService.decoder.decode([LifeStressScore].self, from: data)
    }

    // MARK: - Coach / Morning Brief
    func fetchDailyCoachTip() async throws -> CoachTip {
        let today = DateFormatter.isoDate.string(from: Date())
        let url = try buildURL(path: "/api/coach/daily_tip")
        let data = try await fetchWithCache(url: url, key: "coach_tip_\(today)")
        return try APIService.decoder.decode(CoachTip.self, from: data)
    }

    func fetchMorningBrief() async throws -> MorningBriefData {
        let url = try buildURL(path: "/api/coach/morning_brief")
        let data = try await fetchWithCache(url: url, key: "morning_brief")
        return try APIService.decoder.decode(MorningBriefData.self, from: data)
    }

    // MARK: - Smart Alarm
    func logBedtimeTap(_ bedtimeDate: Date) async throws {
        let url = try buildURL(path: "/api/smart_alarm/bedtime")
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let body: [String: String] = [
            "bedtime_tap": fmt.string(from: bedtimeDate),
            "date":        dateFmt.string(from: bedtimeDate),
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        _ = try await URLSession.authed.data(for: req)
    }
}
