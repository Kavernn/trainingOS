import Foundation

extension APIService {
    func fetchWorkoutDuration() async throws -> WorkoutDurationData {
        let url  = try buildURL(path: "/api/workout-duration")
        let data = try await fetchWithCache(url: url, key: "workout_duration")
        return try APIService.decoder.decode(WorkoutDurationData.self, from: data)
    }
}
