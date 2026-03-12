import Foundation
import Combine

class APIService: ObservableObject {
    static let shared = APIService()

    private let baseURL = "https://training-os-rho.vercel.app"

    @Published var dashboard: DashboardData?
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - Dashboard

    func fetchDashboard() async {
        await MainActor.run { isLoading = true; error = nil }
        do {
            let url = URL(string: "\(baseURL)/api/dashboard")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(DashboardData.self, from: data)
            await MainActor.run {
                self.dashboard = decoded
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Session Logging

    /// Log a full workout session.
    ///
    /// - Parameters:
    ///   - exos:    Legacy flat list of exercise names (kept for backward compat).
    ///   - blocks:  Ordered list of logged workout blocks (strength / hiit / cardio).
    ///              When provided, this is the authoritative representation.
    func logSession(
        exos: [String] = [],
        rpe: Double,
        comment: String,
        blocks: [[String: Any]]? = nil
    ) async throws {
        var body: [String: Any] = ["exos": exos, "rpe": rpe, "comment": comment]
        if let blocks { body["blocks"] = blocks }
        try await post(path: "/api/log_session", body: body)
    }

    // MARK: - Programme / Block Management

    /// Add a new block to a session in the program.
    func addBlock(
        jour: String,
        blockType: BlockType,
        exercises: [String: String] = [:],
        hiitConfig: [String: Any]? = nil,
        cardioConfig: [String: Any]? = nil
    ) async throws {
        var body: [String: Any] = [
            "action": "add_block",
            "jour": jour,
            "block_type": blockType.rawValue,
            "exercises": exercises,
        ]
        if let hiitConfig   { body["hiit_config"]   = hiitConfig }
        if let cardioConfig { body["cardio_config"]  = cardioConfig }
        try await post(path: "/api/programme", body: body)
    }

    /// Remove a block by type from a session.
    func removeBlock(jour: String, blockType: BlockType) async throws {
        try await post(path: "/api/programme", body: [
            "action": "remove_block",
            "jour": jour,
            "block_type": blockType.rawValue,
        ])
    }

    /// Reorder the blocks within a session.
    ///
    /// - Parameter order: Array of `BlockType.rawValue` strings in desired order,
    ///                    e.g. `["strength", "hiit", "cardio"]`.
    func reorderBlocks(jour: String, order: [BlockType]) async throws {
        try await post(path: "/api/programme", body: [
            "action": "reorder_blocks",
            "jour": jour,
            "order": order.map(\.rawValue),
        ])
    }

    // MARK: - Exercise-level Programme Actions

    func addExercise(jour: String, exercise: String, scheme: String) async throws {
        try await post(path: "/api/programme", body: [
            "action": "add", "jour": jour,
            "exercise": exercise, "scheme": scheme,
        ])
    }

    func removeExercise(jour: String, exercise: String) async throws {
        try await post(path: "/api/programme", body: [
            "action": "remove", "jour": jour, "exercise": exercise,
        ])
    }

    func updateScheme(jour: String, exercise: String, scheme: String) async throws {
        try await post(path: "/api/programme", body: [
            "action": "scheme", "jour": jour,
            "exercise": exercise, "scheme": scheme,
        ])
    }

    func reorderExercises(jour: String, ordre: [String]) async throws {
        try await post(path: "/api/programme", body: [
            "action": "reorder", "jour": jour, "ordre": ordre,
        ])
    }

    // MARK: - Helpers

    @discardableResult
    private func post(path: String, body: [String: Any]) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
