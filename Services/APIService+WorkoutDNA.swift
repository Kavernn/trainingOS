import Foundation

extension APIService {
    func fetchWorkoutDNA() async throws -> WorkoutDNAResponse {
        let url  = try buildURL(path: "/api/workout_dna")
        let data = try await fetchWithCache(url: url, key: "workout_dna")
        return try APIService.decoder.decode(WorkoutDNAResponse.self, from: data)
    }
}
