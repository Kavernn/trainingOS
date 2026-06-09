import Foundation

extension APIService {
    func fetchPerformanceConditions() async throws -> PerformanceConditionsData {
        let url  = try buildURL(path: "/api/performance_conditions")
        let data = try await fetchWithCache(url: url, key: "performance_conditions")
        return try APIService.decoder.decode(PerformanceConditionsData.self, from: data)
    }
}
