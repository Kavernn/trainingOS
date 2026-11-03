import Foundation

extension APIService {
    static func energyDailyCacheKey(date: String? = nil) -> String {
        date.map { "energy_daily_\($0)" } ?? "energy_daily_today"
    }

    static func energyHistoryCacheKey(days: Int = 7) -> String {
        "energy_history_\(days)"
    }

    func fetchEnergyDaily(date: String? = nil, forceRefresh: Bool = false) async throws -> EnergyDaily {
        var items: [URLQueryItem] = []
        if let d = date { items.append(URLQueryItem(name: "date", value: d)) }
        let url = try buildURL(path: "/api/energy/daily", queryItems: items)
        let data = try await fetchWithCache(url: url, key: Self.energyDailyCacheKey(date: date), forceRefresh: forceRefresh)
        return try APIService.decoder.decode(EnergyDaily.self, from: data)
    }

    func fetchEnergyHistory(days: Int = 7, forceRefresh: Bool = false) async throws -> [EnergyHistoryDay] {
        let url = try buildURL(path: "/api/energy/history", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: Self.energyHistoryCacheKey(days: days), forceRefresh: forceRefresh)
        return try APIService.decoder.decode([EnergyHistoryDay].self, from: data)
    }

}
