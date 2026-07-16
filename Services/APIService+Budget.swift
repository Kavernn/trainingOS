import Foundation

extension APIService {

    /// GET /api/budget/status
    func fetchBudgetStatus() async throws -> BudgetStatus {
        guard let url = URL(string: APIConfig.base + "/api/budget/status") else {
            throw APIError.invalidURL(path: "/api/budget/status")
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

    /// GET /api/budget/logs?month=YYYY-MM — registre chronologique (lecture seule).
    /// Retourne les money_logs du mois demandé, triés date DESC id DESC.
    func fetchBudgetLogs(month: String) async throws -> [BudgetLog] {
        guard let url = URL(string: APIConfig.base + "/api/budget/logs?month=\(month)") else {
            throw APIError.invalidURL(path: "/api/budget/logs")
        }
        let (data, resp) = try await URLSession.authed.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.serverError(code, "GET /api/budget/logs")
        }
        struct Wrapper: Decodable { let logs: [BudgetLog] }
        return try JSONDecoder().decode(Wrapper.self, from: data).logs
    }

    /// POST /api/budget/log — POST direct, PAS d'offlinePost.
    /// Un replay de queue produirait un log doublé (pas de contrainte d'unicité serveur
    /// sur les expenses), faussant les enveloppes silencieusement. Échec → erreur affichée,
    /// utilisateur réessaie manuellement.
    func logBudget(_ entry: BudgetLogEntry) async throws {
        guard let url = URL(string: APIConfig.base + "/api/budget/log") else {
            throw APIError.invalidURL(path: "/api/budget/log")
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
