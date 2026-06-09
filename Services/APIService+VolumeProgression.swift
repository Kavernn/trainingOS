import Foundation

extension APIService {
    func fetchVolumeProgression() async throws -> VolumeProgressionData {
        let url  = try buildURL(path: "/api/volume-progression")
        let data = try await fetchWithCache(url: url, key: "volume_progression")
        return try APIService.decoder.decode(VolumeProgressionData.self, from: data)
    }
}
