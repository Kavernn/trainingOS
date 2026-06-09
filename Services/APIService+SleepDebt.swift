import Foundation

extension APIService {
    func fetchSleepDebt() async throws -> SleepDebtData {
        let url  = try buildURL(path: "/api/sleep_debt")
        let data = try await fetchWithCache(url: url, key: "sleep_debt")
        return try APIService.decoder.decode(SleepDebtData.self, from: data)
    }
}
