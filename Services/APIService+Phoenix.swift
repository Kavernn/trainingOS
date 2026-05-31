import Foundation

extension APIService {
    func fetchPhoenixScore() async throws -> PhoenixScore {
        let url  = try buildURL(path: "/api/phoenix_score")
        let data = try await fetchWithCache(url: url, key: "phoenix_score")
        return try APIService.decoder.decode(PhoenixScore.self, from: data)
    }
}
