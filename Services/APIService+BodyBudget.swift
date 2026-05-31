import Foundation

extension APIService {
    func fetchBodyBudget() async throws -> BodyBudgetResponse {
        let url = try buildURL(path: "/api/body_budget")
        let data = try await fetchWithCache(url: url, key: "body_budget")
        return try APIService.decoder.decode(BodyBudgetResponse.self, from: data)
    }
}
