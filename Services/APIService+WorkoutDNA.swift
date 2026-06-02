import Foundation

extension APIService {
    func fetchWorkoutDNA(period: Int = 90) async throws -> WorkoutDNAResponse {
        let url = try buildURL(path: "/api/workout_dna",
                               queryItems: [URLQueryItem(name: "period", value: "\(period)")])
        let data = try await fetchWithCache(url: url, key: "workout_dna_\(period)")
        return try APIService.decoder.decode(WorkoutDNAResponse.self, from: data)
    }
}
