import Foundation

extension APIService {
    func fetchGraveyard() async throws -> GraveyardResponse {
        let url  = try buildURL(path: "/api/graveyard")
        let data = try await fetchWithCache(url: url, key: "graveyard")
        return try APIService.decoder.decode(GraveyardResponse.self, from: data)
    }
}
