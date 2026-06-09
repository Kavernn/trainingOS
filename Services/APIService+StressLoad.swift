import Foundation

extension APIService {
    func fetchStressLoad() async throws -> StressLoadData {
        let url  = try buildURL(path: "/api/stress-load")
        let data = try await fetchWithCache(url: url, key: "stress_load")
        return try APIService.decoder.decode(StressLoadData.self, from: data)
    }
}
