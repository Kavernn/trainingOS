import Foundation
import UserNotifications

extension APIService {
    /// Synchronise le flag deload_active en UserDefaults depuis le serveur.
    /// Annule immédiatement les notifs culpabilisantes si le deload vient de s'activer.
    @discardableResult
    func syncDeloadFlag() async -> Bool {
        guard let url = try? buildURL(path: "/api/deload/status"),
              let data = try? await URLSession.authed.data(from: url).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let active = json["active"] as? Bool ?? false
        let wasActive = UserDefaults.standard.bool(forKey: "deload_active")
        UserDefaults.standard.set(active, forKey: "deload_active")
        if active && !wasActive {
            NotificationService.cancelDeloadNotifications()
        }
        return active
    }

    func fetchReadiness() async throws -> ReadinessResponse {
        let url  = try buildURL(path: "/api/readiness")
        let data = try await fetchWithCache(url: url, key: "readiness")
        return try APIService.decoder.decode(ReadinessResponse.self, from: data)
    }

    func fetchStreaks(date: String? = nil) async throws -> StreakResponse {
        let items: [URLQueryItem] = date.map { [URLQueryItem(name: "date", value: $0)] } ?? []
        let url  = try buildURL(path: "/api/stats/streaks", queryItems: items)
        let data = try await fetchWithCache(url: url, key: "streak_data")
        return try APIService.decoder.decode(StreakResponse.self, from: data)
    }
}
