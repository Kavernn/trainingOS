import Foundation

extension APIService {
    func fetchBodyWeightTrend() async throws -> BodyWeightTrendData {
        let url  = try buildURL(path: "/api/body-weight-trend")
        let data = try await fetchWithCache(url: url, key: "body_weight_trend")
        return try APIService.decoder.decode(BodyWeightTrendData.self, from: data)
    }
}
