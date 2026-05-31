import Foundation

extension APIService {
    // MARK: - Mood
    func fetchMoodEmotions() async throws -> [MoodEmotion] {
        let url = try buildURL(path: "/api/mood/emotions")
        let data = try await fetchWithCache(url: url, key: "mood_emotions")
        return try JSONDecoder().decode([MoodEmotion].self, from: data)
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
        return try JSONDecoder().decode(MoodEntry.self, from: data)
    }

    func fetchMoodHistory(days: Int = 90, limit: Int = 20,
                          offset: Int = 0) async throws -> PagedResponse<MoodEntry> {
        let cacheKey = offset == 0 ? "mood_history" : "mood_history_\(offset)"
        let url = try buildURL(path: "/api/mood/history", queryItems: [
            URLQueryItem(name: "days", value: "\(days)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try JSONDecoder().decode(PagedResponse<MoodEntry>.self, from: data)
    }

    func checkMoodDue() async throws -> MoodDueStatus {
        let url = try buildURL(path: "/api/mood/check_due")
        let data = try await fetchWithCache(url: url, key: "mood_check_due")
        return try JSONDecoder().decode(MoodDueStatus.self, from: data)
    }

    // MARK: - Journal
    func fetchJournalPrompt() async throws -> String {
        let url = try buildURL(path: "/api/journal/today_prompt")
        let data = try await fetchWithCache(url: url, key: "journal_prompt")
        let obj = try JSONDecoder().decode([String: String].self, from: data)
        return obj["prompt"] ?? ""
    }

    func submitJournalEntry(prompt: String, content: String,
                            moodScore: Int? = nil) async throws -> JournalEntry {
        var body: [String: Any] = ["prompt": prompt, "content": content]
        if let m = moodScore { body["mood_score"] = m }
        guard let data = try await offlinePost(endpoint: "/api/journal/save", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheInvalidation.journalLogged.invalidate()
        return try JSONDecoder().decode(JournalEntry.self, from: data)
    }

    func fetchJournalEntries(limit: Int = 20,
                             offset: Int = 0) async throws -> PagedResponse<JournalEntry> {
        let cacheKey = offset == 0 ? "journal_entries" : "journal_entries_\(offset)"
        let url = try buildURL(path: "/api/journal/entries", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try JSONDecoder().decode(PagedResponse<JournalEntry>.self, from: data)
    }

    // MARK: - Breathwork
    func fetchBreathworkTechniques() async throws -> [BreathworkTechnique] {
        let url = try buildURL(path: "/api/breathwork/techniques")
        let data = try await fetchWithCache(url: url, key: "breathwork_techniques")
        return try JSONDecoder().decode([BreathworkTechnique].self, from: data)
    }

    func submitBreathworkSession(techniqueId: String, durationSec: Int,
                                 cycles: Int) async throws -> BreathworkSession {
        guard let data = try await offlinePost(endpoint: "/api/breathwork/log", payload: [
            "technique_id": techniqueId, "duration_sec": durationSec, "cycles": cycles,
        ]) else { throw APIError.queuedOffline }
        CacheInvalidation.breathworkLogged.invalidate()
        return try JSONDecoder().decode(BreathworkSession.self, from: data)
    }

    func fetchBreathworkStats(days: Int = 7) async throws -> BreathworkStats {
        let url = try buildURL(path: "/api/breathwork/stats", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: "breathwork_stats")
        return try JSONDecoder().decode(BreathworkStats.self, from: data)
    }

    // MARK: - Self-Care
    func fetchSelfCareHabits() async throws -> [SelfCareHabit] {
        let url = try buildURL(path: "/api/self_care/habits")
        let data = try await fetchWithCache(url: url, key: "self_care_habits")
        return try JSONDecoder().decode([SelfCareHabit].self, from: data)
    }

    func fetchSelfCareToday() async throws -> SelfCareToday {
        let url = try buildURL(path: "/api/self_care/today")
        let data = try await fetchWithCache(url: url, key: "self_care_today")
        return try JSONDecoder().decode(SelfCareToday.self, from: data)
    }

    func submitSelfCareLog(habitIds: [String]) async throws -> SelfCareToday {
        guard let data = try await offlinePost(endpoint: "/api/self_care/log",
                                               payload: ["habit_ids": habitIds])
        else { throw APIError.queuedOffline }
        CacheInvalidation.selfCareLogged.invalidate()
        return try JSONDecoder().decode(SelfCareToday.self, from: data)
    }

    func fetchSelfCareStreaks() async throws -> [SelfCareStreak] {
        let url = try buildURL(path: "/api/self_care/streaks")
        let data = try await fetchWithCache(url: url, key: "self_care_streaks")
        return try JSONDecoder().decode([SelfCareStreak].self, from: data)
    }

    func addSelfCareHabit(name: String, icon: String,
                          category: String) async throws -> SelfCareHabit {
        guard let data = try await offlinePost(endpoint: "/api/self_care/habits",
                                               payload: ["name": name, "icon": icon,
                                                         "category": category])
        else { throw APIError.queuedOffline }
        CacheInvalidation.selfCareHabitsUpdated.invalidate()
        return try JSONDecoder().decode(SelfCareHabit.self, from: data)
    }

    // MARK: - Mental Health Dashboard
    func fetchMentalHealthSummary(days: Int = 7) async throws -> MentalHealthSummary {
        let url = try buildURL(path: "/api/mental_health/summary", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: "mental_health_summary_\(days)")
        return try JSONDecoder().decode(MentalHealthSummary.self, from: data)
    }
}
