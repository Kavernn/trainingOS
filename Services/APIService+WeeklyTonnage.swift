import Foundation

struct WeeklyTonnageData: Codable {
    let volume: Int
}

extension APIService {
    func fetchWeeklyTonnage() async throws -> WeeklyTonnageData {
        let url  = try buildURL(path: "/api/weekly-tonnage")
        let data = try await fetchWithCache(url: url, key: "weekly_tonnage")
        return try APIService.decoder.decode(WeeklyTonnageData.self, from: data)
    }

    /// Timeline force/accessory (~6 mois par défaut).
    /// Le hero Stats consomme 26 semaines : les 12 dernières pour la courbe,
    /// W1 vs W26 pour le delta "+X% vs il y a 6 mois".
    func fetchForceVsAccessory(weeks: Int = 26) async throws -> ForceAccessoryTimeline {
        let url  = try buildURL(path: "/api/stats/force-vs-accessory",
                                queryItems: [URLQueryItem(name: "weeks", value: "\(weeks)")])
        let data = try await fetchWithCache(url: url, key: "force_vs_accessory_\(weeks)")
        return try APIService.decoder.decode(ForceAccessoryTimeline.self, from: data)
    }
}
