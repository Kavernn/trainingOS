import Foundation

extension APIService {
    func fetchNutritionPerformance() async throws -> NutritionPerformanceData {
        let url  = try buildURL(path: "/api/nutrition_performance")
        let data = try await fetchWithCache(url: url, key: "nutrition_performance")
        return try APIService.decoder.decode(NutritionPerformanceData.self, from: data)
    }
}
