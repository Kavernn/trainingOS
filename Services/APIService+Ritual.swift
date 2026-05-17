import Foundation

extension APIService {

    func fetchRitualToday() async throws -> RitualToday {
        let url  = URL(string: "\(baseURL)/api/ritual/today")!
        let data = try await fetchWithCache(url: url, key: "ritual_today")
        return try JSONDecoder().decode(RitualToday.self, from: data)
    }

    func fetchPhoenixStats() async throws -> PhoenixStats {
        let url  = URL(string: "\(baseURL)/api/ritual/streak")!
        let data = try await fetchWithCache(url: url, key: "ritual_streak")
        return try JSONDecoder().decode(PhoenixStats.self, from: data)
    }

    func saveRitualMorning(intention: String, carryCount: Int = 0, carriedFrom: String? = nil) async throws {
        var payload: [String: Any] = ["intention": intention, "carry_count": carryCount]
        if let f = carriedFrom { payload["carried_from"] = f }
        _ = try await offlinePost(endpoint: "/api/ritual/morning", payload: payload)
        CacheService.shared.clear(for: "ritual_today")
        CacheService.shared.clear(for: "ritual_streak")
    }

    func saveRitualEvening(outcome: String) async throws -> RitualEveningResult {
        let data = try await offlinePost(endpoint: "/api/ritual/evening", payload: ["outcome": outcome])
        CacheService.shared.clear(for: "ritual_today")
        CacheService.shared.clear(for: "ritual_streak")
        guard let data else { throw APIError.queuedOffline }
        return try JSONDecoder().decode(RitualEveningResult.self, from: data)
    }
}
