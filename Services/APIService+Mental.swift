import Foundation

extension APIService {
    static let moodEmotionsCacheKey = "mood_emotions"

    static func moodHistoryCacheKey(offset: Int = 0) -> String {
        offset == 0 ? "mood_history" : "mood_history_\(offset)"
    }

    // MARK: - Mood
    func fetchMoodEmotions(forceRefresh: Bool = false) async throws -> [MoodEmotion] {
        let url = try buildURL(path: "/api/mood/emotions")
        let data = try await fetchWithCache(url: url, key: Self.moodEmotionsCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode([MoodEmotion].self, from: data)
    }

    func submitMood(score: Int, emotions: [String], notes: String?,
                    triggers: [String], date: String? = nil) async throws -> MoodEntry {
        var body: [String: Any] = ["score": score, "emotions": emotions, "triggers": triggers]
        if let notes { body["notes"] = notes }
        if let d = date { body["date"] = d }
        guard let data = try await offlinePost(endpoint: "/api/mood/log", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheInvalidation.moodLogged.invalidate()
        return try APIService.decoder.decode(MoodEntry.self, from: data)
    }

    func fetchMoodHistory(days: Int = 90, limit: Int = 20,
                          offset: Int = 0,
                          forceRefresh: Bool = false) async throws -> PagedResponse<MoodEntry> {
        let url = try buildURL(path: "/api/mood/history", queryItems: [
            URLQueryItem(name: "days", value: "\(days)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        let data = try await fetchWithCache(url: url, key: Self.moodHistoryCacheKey(offset: offset), forceRefresh: forceRefresh)
        return try APIService.decoder.decode(PagedResponse<MoodEntry>.self, from: data)
    }

    /// Alimente un chart affiché (corrélation Mood × RPE) — un échec DOIT remonter
    /// à l'UI, pas être masqué par `[:]`. Les callers passent par un `Loadable`
    /// qui surface l'erreur dans `SectionErrorView`.
    func fetchMoodRPE(days: Int = 90, session: URLSession = .authed) async throws -> [String: Double] {
        let url = try buildURL(path: "/api/mood/rpe", queryItems: [
            URLQueryItem(name: "days", value: "\(days)")
        ])
        let (data, response) = try await session.data(from: url)
        guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try APIService.decoder.decode(MoodRPEResponse.self, from: data)
        return decoded.rpeByDate
    }

    static let moodCheckDueCacheKey = "mood_check_due"

    func checkMoodDue(forceRefresh: Bool = false) async throws -> MoodDueStatus {
        let url = try buildURL(path: "/api/mood/check_due")
        let data = try await fetchWithCache(url: url, key: Self.moodCheckDueCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode(MoodDueStatus.self, from: data)
    }

    // MARK: - Journal
    func submitJournalEntry(prompt: String, content: String,
                            moodScore: Int? = nil) async throws -> JournalEntry {
        var body: [String: Any] = ["prompt": prompt, "content": content]
        if let m = moodScore { body["mood_score"] = m }
        guard let data = try await offlinePost(endpoint: "/api/journal/save", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheInvalidation.journalLogged.invalidate()
        return try APIService.decoder.decode(JournalEntry.self, from: data)
    }

    func fetchJournalEntries(limit: Int = 20,
                             offset: Int = 0) async throws -> PagedResponse<JournalEntry> {
        let cacheKey = offset == 0 ? "journal_entries" : "journal_entries_\(offset)"
        let url = try buildURL(path: "/api/journal/entries", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try APIService.decoder.decode(PagedResponse<JournalEntry>.self, from: data)
    }

    // MARK: - Breathwork
    static let breathworkTechniquesCacheKey = "breathwork_techniques"
    static func breathworkHistoryCacheKey(days: Int = 30) -> String { "breathwork_history_\(days)" }

    func fetchBreathworkTechniques(forceRefresh: Bool = false) async throws -> [BreathworkTechnique] {
        let url = try buildURL(path: "/api/breathwork/techniques")
        let data = try await fetchWithCache(url: url, key: Self.breathworkTechniquesCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode([BreathworkTechnique].self, from: data)
    }

    func submitBreathworkSession(techniqueId: String, durationSec: Int,
                                 cycles: Int, startedAt: Date) async throws -> BreathworkSession {
        let iso = ISO8601DateFormatter().string(from: startedAt)
        guard let data = try await offlinePost(endpoint: "/api/breathwork/log", payload: [
            "technique_id": techniqueId,
            "duration_sec": durationSec,
            "cycles":       cycles,
            "started_at":   iso,
        ]) else { throw APIError.queuedOffline }
        CacheInvalidation.breathworkLogged.invalidate()
        return try APIService.decoder.decode(BreathworkSession.self, from: data)
    }

    func fetchBreathworkHistory(days: Int = 30, forceRefresh: Bool = false) async throws -> [BreathworkSession] {
        let url = try buildURL(path: "/api/breathwork/history", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: Self.breathworkHistoryCacheKey(days: days), forceRefresh: forceRefresh)
        return try APIService.decoder.decode([BreathworkSession].self, from: data)
    }

    // MARK: - Self-Care
    static let selfCareTodayCacheKey   = "self_care_today"
    static let selfCareStreaksCacheKey = "self_care_streaks"

    func fetchSelfCareToday(forceRefresh: Bool = false) async throws -> SelfCareToday {
        let url = try buildURL(path: "/api/self_care/today")
        let data = try await fetchWithCache(url: url, key: Self.selfCareTodayCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode(SelfCareToday.self, from: data)
    }

    /// `date` = jour civil MTL capturé au tap (figé dans payloadData du SyncManager,
    /// stable à travers un replay cross-midnight). Backend valide [today, today-7j].
    func submitSelfCareLog(date: String, habitIds: [String]) async throws -> SelfCareToday {
        guard let data = try await offlinePost(endpoint: "/api/self_care/log",
                                               payload: ["date": date, "habit_ids": habitIds])
        else { throw APIError.queuedOffline }
        CacheInvalidation.selfCareLogged.invalidate()
        return try APIService.decoder.decode(SelfCareToday.self, from: data)
    }

    func fetchSelfCareStreaks(forceRefresh: Bool = false) async throws -> [SelfCareStreak] {
        let url = try buildURL(path: "/api/self_care/streaks")
        let data = try await fetchWithCache(url: url, key: Self.selfCareStreaksCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode([SelfCareStreak].self, from: data)
    }

    func addSelfCareHabit(name: String, icon: String,
                          category: String) async throws -> SelfCareHabit {
        guard let data = try await offlinePost(endpoint: "/api/self_care/habits",
                                               payload: ["name": name, "icon": icon,
                                                         "category": category])
        else { throw APIError.queuedOffline }
        CacheInvalidation.selfCareHabitsUpdated.invalidate()
        return try APIService.decoder.decode(SelfCareHabit.self, from: data)
    }

    // MARK: - Mental Health Dashboard
    static func mentalHealthSummaryCacheKey(days: Int = 7) -> String {
        "mental_health_summary_\(days)"
    }

    func fetchMentalHealthSummary(days: Int = 7, forceRefresh: Bool = false) async throws -> MentalHealthSummary {
        let url = try buildURL(path: "/api/mental_health/summary", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: Self.mentalHealthSummaryCacheKey(days: days), forceRefresh: forceRefresh)
        return try APIService.decoder.decode(MentalHealthSummary.self, from: data)
    }
}
