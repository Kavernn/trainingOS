import Foundation

extension APIService {
    func fetchMuscleBalance() async throws -> MuscleBalanceData {
        let url  = try buildURL(path: "/api/muscle_balance")
        let data = try await fetchWithCache(url: url, key: "muscle_balance")
        return try APIService.decoder.decode(MuscleBalanceData.self, from: data)
    }

}
