import Foundation

extension APIService {
    func fetchPhoenixScore() async throws -> PhoenixScore {
        let url  = URL(string: "\(baseURL)/api/phoenix_score")!
        let data = try await fetchWithCache(url: url, key: "phoenix_score")
        return try JSONDecoder().decode(PhoenixScore.self, from: data)
    }
}
