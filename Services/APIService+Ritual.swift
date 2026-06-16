import Foundation

extension APIService {

    func fetchRitualToday() async throws -> RitualToday {
        let url  = try buildURL(path: "/api/ritual/today")
        let data = try await fetchWithCache(url: url, key: "ritual_today")
        return try APIService.decoder.decode(RitualToday.self, from: data)
    }

    func fetchPhoenixStats() async throws -> PhoenixStats {
        let url  = try buildURL(path: "/api/ritual/streak")
        let data = try await fetchWithCache(url: url, key: "ritual_streak")
        return try APIService.decoder.decode(PhoenixStats.self, from: data)
    }

    func killDemon(date: String) async throws {
        _ = try await offlinePost(endpoint: "/api/ritual/kill-demon", payload: ["date": date])
        CacheInvalidation.ritualUpdated.invalidate()
    }

    func fetchRitualHistoryFull(limit: Int = 90, offset: Int = 0) async throws -> RitualHistoryPage {
        guard let url = URL(string: "\(baseURL)/api/ritual/history-full?limit=\(limit)&offset=\(offset)") else {
            throw URLError(.badURL)
        }
        let (data, resp) = try await URLSession.authed.data(for: URLRequest(url: url))
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "fetchRitualHistoryFull HTTP \(http.statusCode)")
        }
        return try APIService.decoder.decode(RitualHistoryPage.self, from: data)
    }

    func saveEveningRoutineItem(_ field: String, value: Bool) async throws {
        _ = try await offlinePost(endpoint: "/api/ritual/evening_routine", payload: [field: value])
        CacheInvalidation.ritualItemActioned.invalidate()
    }

    // MARK: - Engagement flow

    func createEngagements(date: String, texts: [String]) async throws {
        let payload: [String: Any] = ["date": date, "engagements": texts]
        _ = try await offlinePost(endpoint: "/api/ritual/engagements", payload: payload)
        CacheInvalidation.ritualUpdated.invalidate()
    }

    func updateEngagementStatus(id: String, status: String) async throws {
        let url = try buildURL(path: "/api/ritual/engagements/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        let (_, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "updateEngagementStatus HTTP \(http.statusCode)")
        }
        CacheInvalidation.ritualItemActioned.invalidate()
    }

}
