import Foundation

extension APIService {
    func fetchTrainingHeatmap() async throws -> TrainingHeatmapData {
        let url  = try buildURL(path: "/api/training-heatmap")
        let data = try await fetchWithCache(url: url, key: "training_heatmap")
        return try APIService.decoder.decode(TrainingHeatmapData.self, from: data)
    }
}
