import Foundation

extension APIService {
    func fetchConsistency() async throws -> ConsistencyData {
        let url  = try buildURL(path: "/api/consistency")
        let data = try await fetchWithCache(url: url, key: "consistency")
        return try APIService.decoder.decode(ConsistencyData.self, from: data)
    }
}
