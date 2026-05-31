import Foundation

extension APIService {

    func fetchRitualToday() async throws -> RitualToday {
        let url  = try buildURL(path: "/api/ritual/today")
        let data = try await fetchWithCache(url: url, key: "ritual_today")
        return try JSONDecoder().decode(RitualToday.self, from: data)
    }

    func fetchPhoenixStats() async throws -> PhoenixStats {
        let url  = try buildURL(path: "/api/ritual/streak")
        let data = try await fetchWithCache(url: url, key: "ritual_streak")
        return try JSONDecoder().decode(PhoenixStats.self, from: data)
    }

    func saveRitualMorning(intention: String, carryCount: Int = 0, carriedFrom: String? = nil) async throws {
        var payload: [String: Any] = ["intention": intention, "carry_count": carryCount]
        if let f = carriedFrom { payload["carried_from"] = f }
        _ = try await offlinePost(endpoint: "/api/ritual/morning", payload: payload)
        CacheInvalidation.ritualActioned.invalidate()
    }

    func saveRitualEvening(outcome: String) async throws -> RitualEveningResult {
        let data = try await offlinePost(endpoint: "/api/ritual/evening", payload: ["outcome": outcome])
        CacheInvalidation.ritualActioned.invalidate()
        guard let data else { throw APIError.queuedOffline }
        return try JSONDecoder().decode(RitualEveningResult.self, from: data)
    }

    func killDemon(date: String) async throws {
        _ = try await offlinePost(endpoint: "/api/ritual/kill-demon", payload: ["date": date])
        CacheInvalidation.ritualUpdated.invalidate()
    }

    func fetchRitualStats() async throws -> RitualStats {
        let url  = try buildURL(path: "/api/ritual/stats")
        let data = try await fetchWithCache(url: url, key: "ritual_stats")
        return try JSONDecoder().decode(RitualStats.self, from: data)
    }

    func fetchRitualCorrelations() async throws -> RitualCorrelations {
        let url  = try buildURL(path: "/api/ritual/correlations")
        let data = try await fetchWithCache(url: url, key: "ritual_correlations")
        return try JSONDecoder().decode(RitualCorrelations.self, from: data)
    }

    func fetchRitualHistoryFull(limit: Int = 90, offset: Int = 0) async throws -> RitualHistoryPage {
        guard let url = URL(string: "\(baseURL)/api/ritual/history-full?limit=\(limit)&offset=\(offset)") else {
            throw URLError(.badURL)
        }
        let (data, resp) = try await URLSession.authed.data(for: URLRequest(url: url))
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "fetchRitualHistoryFull HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(RitualHistoryPage.self, from: data)
    }

    func saveRitualChecklist(weightLogged: Bool? = nil, hydrationDone: Bool? = nil,
                             mobilityDone: Bool? = nil, proteinDone: Bool? = nil) async throws {
        var payload: [String: Any] = [:]
        if let v = weightLogged  { payload["weight_logged"]   = v }
        if let v = hydrationDone { payload["hydration_done"]  = v }
        if let v = mobilityDone  { payload["mobility_done"]   = v }
        if let v = proteinDone   { payload["protein_done"]    = v }
        guard !payload.isEmpty else { return }
        _ = try await offlinePost(endpoint: "/api/ritual/checklist", payload: payload)
        CacheInvalidation.ritualItemActioned.invalidate()
    }

    func saveRitualEveningFull(outcome: String, reflection: String? = nil,
                               winddownDone: Bool? = nil, coldDone: Bool? = nil,
                               gratitude: String? = nil) async throws -> RitualEveningResult {
        var payload: [String: Any] = ["outcome": outcome]
        if let r = reflection, !r.isEmpty { payload["reflection"]    = r }
        if let v = winddownDone            { payload["winddown_done"] = v }
        if let v = coldDone                { payload["cold_done"]     = v }
        if let g = gratitude, !g.isEmpty  { payload["gratitude"]     = g }

        let data = try await offlinePost(endpoint: "/api/ritual/evening", payload: payload)
        CacheInvalidation.ritualUpdated.invalidate()
        guard let data else { throw APIError.queuedOffline }
        return try JSONDecoder().decode(RitualEveningResult.self, from: data)
    }
}
