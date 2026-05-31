import Foundation

extension APIService {
    // MARK: - Objectifs
    func fetchObjectifsData() async throws -> [ObjectifEntry] {
        let url = try buildURL(path: "/api/objectifs_data")
        let data = try await fetchWithCache(url: url, key: "objectifs_data")
        struct ObjResponse: Codable { let goals: [String: ObjData] }
        struct ObjData: Codable {
            let current: Double; let goal: Double; let achieved: Bool
            let deadline: String?; let note: String?; let archived: Bool?
        }
        let r = try JSONDecoder().decode(ObjResponse.self, from: data)
        return r.goals.map { ex, d in
            ObjectifEntry(exercise: ex, current: d.current, goal: d.goal,
                          achieved: d.achieved, deadline: d.deadline ?? "",
                          note: d.note ?? "", archived: d.archived ?? false)
        }.sorted { $0.exercise < $1.exercise }
    }

    func archiveObjectif(exercise: String) async throws {
        _ = try await offlinePost(endpoint: "/api/archive_objectif", payload: ["exercise": exercise])
    }

    func setGoal(exercise: String, goalWeight: Double, deadline: String) async throws {
        _ = try await offlinePost(endpoint: "/api/set_goal", payload: [
            "exercise": exercise, "goal_weight": goalWeight, "deadline": deadline
        ])
    }

    // MARK: - Smart Goals
    func fetchSmartGoals() async throws -> [SmartGoalEntry] {
        let url = try buildURL(path: "/api/smart_goals")
        let data = try await fetchWithCache(url: url, key: "smart_goals")
        struct R: Codable { let smart_goals: [SmartGoalEntry] }
        return try JSONDecoder().decode(R.self, from: data).smart_goals
    }

    func saveSmartGoal(type: String, targetValue: Double, targetDate: String,
                       id: String? = nil) async throws {
        var payload: [String: Any] = ["type": type, "target_value": targetValue,
                                       "target_date": targetDate]
        if let id { payload["id"] = id }
        _ = try await offlinePost(endpoint: "/api/smart_goals/save", payload: payload)
    }

    func deleteSmartGoal(id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/smart_goals/delete", payload: ["id": id])
    }

    // MARK: - Insights / ACWR / Deload / Correlations
    func fetchInsights() async throws -> [InsightEntry] {
        let url = try buildURL(path: "/api/insights")
        let data = try await fetchWithCache(url: url, key: "insights")
        struct R: Codable { let insights: [InsightEntry] }
        return try JSONDecoder().decode(R.self, from: data).insights
    }

    func fetchDeloadData() async throws -> DeloadReport {
        let url = try buildURL(path: "/api/deload")
        let data = try await fetchWithCache(url: url, key: "deload")
        return try JSONDecoder().decode(DeloadReport.self, from: data)
    }

    func fetchACWR() async throws -> ACWRData {
        let url = try buildURL(path: "/api/acwr")
        let data = try await fetchWithCache(url: url, key: "acwr")
        return try JSONDecoder().decode(ACWRData.self, from: data)
    }

    func fetchCorrelations(days: Int = 60) async throws -> CorrelationsData {
        let url = try buildURL(path: "/api/insights/correlations", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
        let data = try await fetchWithCache(url: url, key: "correlations")
        return try JSONDecoder().decode(CorrelationsData.self, from: data)
    }
}
