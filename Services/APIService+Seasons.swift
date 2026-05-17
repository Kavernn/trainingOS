import Foundation

extension APIService {

    func getActiveSeasonRaw() async throws -> Data {
        let url = URL(string: "\(baseURL)/api/seasons/active")!
        return try await fetchWithCache(url: url, key: "season_active")
    }

    func getActiveSeason() async throws -> Season? {
        let data = try await getActiveSeasonRaw()
        if data.isEmpty || data == Data("{}".utf8) { return nil }
        return try? JSONDecoder().decode(Season.self, from: data)
    }

    func getAllSeasons() async throws -> [Season] {
        let url  = URL(string: "\(baseURL)/api/seasons")!
        let data = try await fetchWithCache(url: url, key: "seasons_list")
        return (try? JSONDecoder().decode([Season].self, from: data)) ?? []
    }

    func startSeason() async throws -> Season? {
        guard let data = try await offlinePost(endpoint: "/api/seasons/start", payload: [:]) else { return nil }
        CacheService.shared.clear(for: "season_active")
        CacheService.shared.clear(for: "seasons_list")
        return try? JSONDecoder().decode(Season.self, from: data)
    }

    func closeSeason(id: String) async throws -> SeasonReport? {
        guard let data = try await offlinePost(endpoint: "/api/seasons/\(id)/close", payload: [:]) else { return nil }
        CacheService.shared.clear(for: "season_active")
        CacheService.shared.clear(for: "seasons_list")
        return try? JSONDecoder().decode(SeasonReport.self, from: data)
    }

    func updateSeason(id: String, fields: [String: Any]) async throws -> Season? {
        var req = URLRequest(url: URL(string: "\(baseURL)/api/seasons/\(id)")!)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: fields)
        req.timeoutInterval = 20
        req.setValue("Bearer \(APIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "seasons_list")
        return try? JSONDecoder().decode(Season.self, from: data)
    }
}
