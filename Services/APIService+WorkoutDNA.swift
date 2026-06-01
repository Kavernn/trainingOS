import Foundation

extension APIService {
    func fetchWorkoutDNA(period: Int = 90) async throws -> WorkoutDNAResponse {
        var comps = URLComponents(url: try buildURL(path: "/api/workout_dna"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "period", value: "\(period)")]
        let url  = comps.url!
        let data = try await fetchWithCache(url: url, key: "workout_dna_\(period)")
        return try APIService.decoder.decode(WorkoutDNAResponse.self, from: data)
    }
}
