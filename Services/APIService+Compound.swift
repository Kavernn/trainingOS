import Foundation

extension APIService {
    func fetchCompoundScore() async throws -> CompoundScore {
        let url  = try buildURL(path: "/api/compound_score")
        let data = try await fetchWithCache(url: url, key: "compound_score")
        return try APIService.decoder.decode(CompoundScore.self, from: data)
    }
}
