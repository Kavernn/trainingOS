import Foundation

extension APIService {
    func fetchPlateauAlerts(force: Bool = false) async throws -> PlateauResponse {
        var items: [URLQueryItem] = []
        if force { items.append(URLQueryItem(name: "force", value: "1")) }
        let url  = try buildURL(path: "/api/plateau_alerts", queryItems: items)
        let data = try await fetchWithCache(url: url, key: "plateau_alerts")
        return try APIService.decoder.decode(PlateauResponse.self, from: data)
    }

    func updatePlateauStatus(id: String, status: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/plateau_alerts/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        let (_, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode, "Mise à jour plateau échouée : HTTP \(http.statusCode)")
        }
        CacheInvalidation.plateauDismissed.invalidate()
    }
}
