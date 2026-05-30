import Foundation

extension APIService {
    func fetchEnergyDaily(date: String? = nil) async throws -> EnergyDaily {
        var urlStr = "\(baseURL)/api/energy/daily"
        if let d = date { urlStr += "?date=\(d)" }
        let cacheKey = date.map { "energy_daily_\($0)" } ?? "energy_daily_today"
        let url = URL(string: urlStr)!
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try JSONDecoder().decode(EnergyDaily.self, from: data)
    }

    func fetchEnergyHistory(days: Int = 7) async throws -> [EnergyHistoryDay] {
        let url = URL(string: "\(baseURL)/api/energy/history?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "energy_history_\(days)")
        return try JSONDecoder().decode([EnergyHistoryDay].self, from: data)
    }

    func invalidateEnergyCache() {
        CacheService.shared.clear(for: "energy_daily_today")
        CacheService.shared.clear(for: "energy_history_7")
    }
}
