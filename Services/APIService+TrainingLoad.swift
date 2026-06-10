import Foundation

extension APIService {
    func fetchTrainingLoad() async throws -> TrainingLoadData {
        let url  = try buildURL(path: "/api/training_load")
        let data = try await fetchWithCache(url: url, key: "training_load")
        return try APIService.decoder.decode(TrainingLoadData.self, from: data)
    }

    func fetchDeloadData() async throws -> DeloadReport {
        let url  = try buildURL(path: "/api/deload_status")
        let data = try await fetchWithCache(url: url, key: "deload_status")
        return try APIService.decoder.decode(DeloadReport.self, from: data)
    }

    func fetchACWR() async throws -> ACWRData {
        let url  = try buildURL(path: "/api/acwr")
        let data = try await fetchWithCache(url: url, key: "acwr")
        return try APIService.decoder.decode(ACWRData.self, from: data)
    }
}
