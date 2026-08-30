import Foundation

extension APIService {
    func fetchWorkoutDNA(period: Int = 90) async throws -> WorkoutDNAResponse {
        let url = try buildURL(path: "/api/workout_dna",
                               queryItems: [URLQueryItem(name: "period", value: "\(period)")])
        return try await fetchWithCacheDecoded(url: url, key: "workout_dna_\(period)", as: WorkoutDNAResponse.self)
    }
}
