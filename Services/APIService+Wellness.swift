import Foundation

/// Enveloppe du cache `recovery_data` (clé historique). Exposée pour que le
/// seed d'un `Loadable<[RecoveryEntry]>` puisse decoder le payload stocké et
/// extraire `.recoveryLog` côté appelant.
struct RecoveryDataResponse: Codable {
    let recoveryLog: [RecoveryEntry]
    enum CodingKeys: String, CodingKey { case recoveryLog = "recovery_log" }
}

extension APIService {
    static let recoveryDataCacheKey = "recovery_data"

    // MARK: - Recovery
    func fetchRecoveryData(forceRefresh: Bool = false) async throws -> [RecoveryEntry] {
        let url = try buildURL(path: "/api/recovery_data")
        let data = try await fetchWithCache(url: url, key: Self.recoveryDataCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode(RecoveryDataResponse.self, from: data).recoveryLog
    }

    /// Retourne `true` si l'écriture a atteint le serveur, `false` si elle a été
    /// mise en file offline (le serveur n'a PAS recalculé readiness/brief).
    /// Les callers qui dépendent d'un recalcul serveur-side (ex: refetch du
    /// morning brief) doivent vérifier le retour.
    @discardableResult
    func logRecovery(sleepHours: Double?, sleepQuality: Double?, restingHr: Double?,
                     hrv: Double?, steps: Int?, soreness: Double?,
                     fatigue: Double? = nil, energyPre: Double? = nil,
                     activeEnergy: Double? = nil, hrMorning: Double? = nil,
                     hrPostWorkout: Double? = nil, hrEvening: Double? = nil,
                     notes: String? = nil, date: String? = nil,
                     bedtime: String? = nil, wakeTime: String? = nil) async throws -> Bool {
        var body: [String: Any] = [:]
        if let v = notes         { body["notes"]              = v }
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
        let data = try await offlinePost(endpoint: "/api/log_recovery", payload: body)
        CacheInvalidation.recoveryLogged.invalidate()
        CacheInvalidation.energyLogged.invalidate()
        return data != nil
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

    func deleteRecovery(date: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_recovery", payload: ["date": date])
        CacheInvalidation.recoveryLogged.invalidate()
    }

    static let hrvAnalysisCacheKey = "hrv_analysis"

    // MARK: - HRV Analysis
    func fetchHRVAnalysis(forceRefresh: Bool = false) async throws -> HRVAnalysis {
        let url  = try buildURL(path: "/api/hrv/analysis")
        let data = try await fetchWithCache(url: url, key: Self.hrvAnalysisCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode(HRVAnalysis.self, from: data)
    }

    // MARK: - PSS
    static func pssQuestionsCacheKey(isShort: Bool = false) -> String {
        "pss_questions_\(isShort)"
    }

    func fetchPSSQuestions(isShort: Bool = false, forceRefresh: Bool = false) async throws -> [PSSQuestion] {
        let url = try buildURL(path: "/api/pss/questions", queryItems: [URLQueryItem(name: "short", value: "\(isShort)")])
        let data = try await fetchWithCache(url: url, key: Self.pssQuestionsCacheKey(isShort: isShort), forceRefresh: forceRefresh)
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

    static let pssHistoryCacheKey = "pss_history"

    /// Note : la clé cache ignore `type` (pré-existant). Un commutateur de type
    /// qui écraserait le cache de l'autre type est un risque connu — hors scope
    /// de la migration Loadable Santé, chantier dédié si besoin.
    func fetchPSSHistory(type: String? = nil, forceRefresh: Bool = false) async throws -> [PSSRecord] {
        var items: [URLQueryItem] = []
        if let type { items.append(URLQueryItem(name: "type", value: type)) }
        let url = try buildURL(path: "/api/pss/history", queryItems: items)
        let data = try await fetchWithCache(url: url, key: Self.pssHistoryCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode([PSSRecord].self, from: data)
    }

    static func pssCheckDueCacheKey(type: String = "full") -> String {
        "pss_check_due_\(type)"
    }

    func checkPSSDue(type: String = "full", forceRefresh: Bool = false) async throws -> PSSDueStatus {
        let url = try buildURL(path: "/api/pss/check_due", queryItems: [URLQueryItem(name: "type", value: type)])
        let data = try await fetchWithCache(url: url, key: Self.pssCheckDueCacheKey(type: type), forceRefresh: forceRefresh)
        return try APIService.decoder.decode(PSSDueStatus.self, from: data)
    }

    // MARK: - Life Stress Engine
    static func lifeStressScoreCacheKey(date: String? = nil) -> String {
        "life_stress_\(date ?? "today")"
    }

    static func lifeStressTrendCacheKey(days: Int = 7) -> String {
        "life_stress_trend_\(days)"
    }

    /// `forceRefresh` : (1) ajoute `?refresh=true` pour que le serveur
    /// recalcule le score sans l'enveloppe cache serveur et (2) bypass
    /// le cache CLIENT (appel réseau direct, lève en cas d'échec, hydrate
    /// le cache local sur succès). Ancien comportement = (1) seulement.
    func fetchLifeStressScore(date: String? = nil, forceRefresh: Bool = false) async throws -> LifeStressScore {
        var items: [URLQueryItem] = []
        if let date { items.append(URLQueryItem(name: "date", value: date)) }
        if forceRefresh { items.append(URLQueryItem(name: "refresh", value: "true")) }
        let url = try buildURL(path: "/api/life_stress/score", queryItems: items)
        let data = try await fetchWithCache(url: url, key: Self.lifeStressScoreCacheKey(date: date), forceRefresh: forceRefresh)
        return try APIService.decoder.decode(LifeStressScore.self, from: data)
    }

    func fetchLifeStressTrend(days: Int = 7, forceRefresh: Bool = false) async throws -> [LifeStressScore] {
        let url = try buildURL(path: "/api/life_stress/trend", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: Self.lifeStressTrendCacheKey(days: days), forceRefresh: forceRefresh)
        return try APIService.decoder.decode([LifeStressScore].self, from: data)
    }

    // MARK: - Coach / Morning Brief
    func fetchMorningBrief() async throws -> MorningBriefData {
        let url = try buildURL(path: "/api/coach/morning_brief")
        let data = try await fetchWithCache(url: url, key: "morning_brief")
        return try APIService.decoder.decode(MorningBriefData.self, from: data)
    }

    // MARK: - Smart Alarm
    // Écrit dans smart_alarm_sessions (lu uniquement par /api/smart_alarm/latency
    // non cachée + sync HK pour calibration) — aucun impact sur les clés cachées.
    func logBedtimeTap(_ bedtimeDate: Date) async throws {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        _ = try await offlinePost(endpoint: "/api/smart_alarm/bedtime", payload: [
            "bedtime_tap": fmt.string(from: bedtimeDate),
            "date":        dateFmt.string(from: bedtimeDate),
        ])
    }
}
