import Foundation

extension APIService {
    func fetchPlateauAlerts(force: Bool = false) async throws -> PlateauResponse {
        let urlStr = force
            ? "\(baseURL)/api/plateau_alerts?force=1"
            : "\(baseURL)/api/plateau_alerts"
        let url  = URL(string: urlStr)!
        let data = try await fetchWithCache(url: url, key: "plateau_alerts")
        return try JSONDecoder().decode(PlateauResponse.self, from: data)
    }

    func updatePlateauStatus(id: String, status: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/plateau_alerts/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        _ = try await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "plateau_alerts")
    }
}
