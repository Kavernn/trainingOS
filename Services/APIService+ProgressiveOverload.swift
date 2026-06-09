import Foundation

extension APIService {
    func fetchProgressiveOverload() async throws -> ProgressiveOverloadData {
        let url  = try buildURL(path: "/api/progressive-overload")
        let data = try await fetchWithCache(url: url, key: "progressive_overload")
        return try APIService.decoder.decode(ProgressiveOverloadData.self, from: data)
    }
}
