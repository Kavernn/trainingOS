import Foundation

extension APIService {
    func fetchMuscleBalance() async throws -> MuscleBalanceData {
        let url  = try buildURL(path: "/api/muscle_balance")
        let data = try await fetchWithCache(url: url, key: "muscle_balance")
        return try APIService.decoder.decode(MuscleBalanceData.self, from: data)
    }

    func fetchMuscleImbalance(days: Int = 90) async throws -> MuscleImbalanceData {
        let url  = try buildURL(path: "/api/muscle_imbalance",
                                queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: "muscle_imbalance_\(days)")
        return try APIService.decoder.decode(MuscleImbalanceData.self, from: data)
    }

    func fetchMuscleVolume(daysCurrent: Int = 7, daysTrend: Int = 28) async throws -> MuscleVolumeData {
        let url  = try buildURL(path: "/api/muscle_volume", queryItems: [
            URLQueryItem(name: "days_current", value: "\(daysCurrent)"),
            URLQueryItem(name: "days_trend",   value: "\(daysTrend)"),
        ])
        let data = try await fetchWithCache(url: url, key: "muscle_volume_\(daysCurrent)_\(daysTrend)")
        return try APIService.decoder.decode(MuscleVolumeData.self, from: data)
    }
}
