import Foundation

extension APIService {
    func fetchEnergyPerformance() async throws -> EnergyPerformanceData {
        let url  = try buildURL(path: "/api/energy-performance")
        let data = try await fetchWithCache(url: url, key: "energy_performance")
        return try APIService.decoder.decode(EnergyPerformanceData.self, from: data)
    }
}
