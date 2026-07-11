import Foundation

extension APIService {

    /// GET /api/budget/status
    func fetchBudgetStatus() async throws -> BudgetStatus {
        guard let url = URL(string: APIConfig.base + "/api/budget/status") else {
            throw APIError.invalidURL
        }
        let (data, resp) = try await URLSession.authed.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.serverError(code, "GET /api/budget/status")
        }
        // JSONDecoder() local — PAS APIService.decoder (dateDecodingStrategy=.iso8601
        // parserait les strings "YYYY-MM-DD" incorrectement). Modèles utilisent String.
        return try JSONDecoder().decode(BudgetStatus.self, from: data)
    }

    /// POST /api/budget/log — POST direct, PAS d'offlinePost.
    /// Un replay de queue produirait un log doublé (pas de contrainte d'unicité serveur
    /// sur les expenses), faussant les enveloppes silencieusement. Échec → erreur affichée,
    /// utilisateur réessaie manuellement.
    func logBudget(_ entry: BudgetLogEntry) async throws {
        guard let url = URL(string: APIConfig.base + "/api/budget/log") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(entry)

        let (data, resp) = try await URLSession.authed.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let msg  = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                       ?? "erreur réseau"
            throw APIError.serverError(code, msg)
        }
    }
}
