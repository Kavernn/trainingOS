import Foundation

extension APIService {
    func fetchBodyBudget() async throws -> BodyBudgetResponse {
        let url = URL(string: "\(baseURL)/api/body_budget")!
        let data = try await fetchWithCache(url: url, key: "body_budget")
        return try JSONDecoder().decode(BodyBudgetResponse.self, from: data)
    }
}
