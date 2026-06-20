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

    func fetchDeloadStatus() async throws -> DeloadStatus {
        guard let url = try? buildURL(path: "/api/deload/status") else { throw APIError.invalidURL }
        let data = try await URLSession.authed.data(from: url).0
        return try APIService.decoder.decode(DeloadStatus.self, from: data)
    }

    func activateDeload(reason: String = "Repos volontaire", durationDays: Int = 7) async throws {
        guard let url = URL(string: "\(baseURL)/api/deload/activate") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["reason": reason, "duration_days": durationDays])
        let (_, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode, "Activation deload échouée : HTTP \(http.statusCode)")
        }
        UserDefaults.standard.set(true, forKey: "deload_active")
        NotificationService.cancelDeloadNotifications()
    }

    func deactivateDeload() async throws {
        guard let url = URL(string: "\(baseURL)/api/deload/deactivate") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode, "Désactivation deload échouée : HTTP \(http.statusCode)")
        }
        UserDefaults.standard.set(false, forKey: "deload_active")
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
