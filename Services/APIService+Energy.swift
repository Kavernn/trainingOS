import Foundation

extension APIService {
    func fetchEnergyDaily(date: String? = nil) async throws -> EnergyDaily {
        var items: [URLQueryItem] = []
        if let d = date { items.append(URLQueryItem(name: "date", value: d)) }
        let cacheKey = date.map { "energy_daily_\($0)" } ?? "energy_daily_today"
        let url = try buildURL(path: "/api/energy/daily", queryItems: items)
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try APIService.decoder.decode(EnergyDaily.self, from: data)
    }

    func fetchEnergyHistory(days: Int = 7) async throws -> [EnergyHistoryDay] {
        let url = try buildURL(path: "/api/energy/history", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: "energy_history_\(days)")
        return try APIService.decoder.decode([EnergyHistoryDay].self, from: data)
    }

}
