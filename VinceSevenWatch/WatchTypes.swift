import Foundation

// Types du contrat Watch ↔ iOS (dupliqués dans Services/WatchConnectivityManager.swift)
struct WatchActiveSession: Codable {
    let sessionName: String
    let exercises: [WatchExercise]
}

struct WatchExercise: Codable, Identifiable {
    let id: String
    let name: String
    let targetSets: Int
    let targetReps: String
    let defaultWeightLbs: Double
    let restSeconds: Int
}

struct WatchSetLog: Codable {
    let exerciseId: String
    let exerciseName: String
    let weightLbs: Double
    let reps: Int
    let rpe: Double?
    let timestamp: Date
}

struct WatchRecoveryLog: Codable {
    let energy: Int     // 1–10
    let soreness: Int   // 1–10
    let mood: String    // "low" | "neutral" | "good" | "great"
    let date: String    // yyyy-MM-dd
}

// Queue offline persistée dans UserDefaults
struct PendingWatchLog: Codable {
    let id: UUID
    let type: String    // "set" | "recovery"
    let payload: Data
    let timestamp: Date
    var synced: Bool
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
