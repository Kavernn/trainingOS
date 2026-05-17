import Foundation

extension APIService {
    func fetchGraveyard() async throws -> GraveyardResponse {
        let url  = URL(string: "\(baseURL)/api/graveyard")!
        let data = try await fetchWithCache(url: url, key: "graveyard")
        return try JSONDecoder().decode(GraveyardResponse.self, from: data)
    }
}
