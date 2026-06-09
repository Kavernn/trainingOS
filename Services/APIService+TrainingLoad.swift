import Foundation

extension APIService {
    func fetchTrainingLoad() async throws -> TrainingLoadData {
        let url  = try buildURL(path: "/api/training_load")
        let data = try await fetchWithCache(url: url, key: "training_load")
        return try APIService.decoder.decode(TrainingLoadData.self, from: data)
    }
}
