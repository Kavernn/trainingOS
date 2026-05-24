import Foundation

struct Season: Codable, Identifiable {
    let id: String
    let number: Int
    let startedAt: String
    let endedAt: String?
    let status: String
    let generatedTitle: String?
    let customTitle: String?
    let dominantArc: String?
    let personalNote: String?

    let ritualCompletionRate: Double?

    var displayTitle: String { customTitle ?? generatedTitle ?? "SEASON \(number)" }
    var isActive: Bool { status == "active" }

    var dayNumber: Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let start = f.date(from: String(startedAt.prefix(10))) else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(1, days + 1)
    }

    var startFormatted: String { _fmtDate(startedAt) }
    var endFormatted: String   { endedAt.map { _fmtDate($0) } ?? "" }

    private func _fmtDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateStyle = .medium
        out.locale = Locale(identifier: "fr_CA")
        return out.string(from: d)
    }

    enum CodingKeys: String, CodingKey {
        case id, number, status
        case startedAt    = "started_at"
        case endedAt      = "ended_at"
        case generatedTitle = "generated_title"
        case customTitle  = "custom_title"
        case dominantArc  = "dominant_arc"
        case personalNote = "personal_note"
        case ritualCompletionRate = "ritual_completion_rate"
    }
}

struct SeasonSnapshot: Codable {
    let id: String?
    let seasonId: String?
    let type: String
    let capturedAt: String?
    let weightLbs: Double?
    let bodyFatPct: Double?
    let phoenixAvg: Double?
    let phoenixWorkoutAvg: Double?
    let phoenixStressAvg: Double?
    let phoenixNutritionAvg: Double?
    let phoenixResilienceAvg: Double?
    let phoenixSpiritAvg: Double?
    let pssScore: Int?
    let warRoomStreak: Int?
    let topPrs: [PRSnapshot]?
    let ritualCompletionRate: Double?
    let avgSleepHrs: Double?
    let avgCalories: Double?
    let breathworkSessionsTotal: Int?
    let meditationMinutesTotal: Int?
    let journalEntriesTotal: Int?

    enum CodingKeys: String, CodingKey {
        case id, type
        case seasonId           = "season_id"
        case capturedAt         = "captured_at"
        case weightLbs          = "weight_lbs"
        case bodyFatPct         = "body_fat_pct"
        case phoenixAvg         = "phoenix_avg"
        case phoenixWorkoutAvg  = "phoenix_workout_avg"
        case phoenixStressAvg   = "phoenix_stress_avg"
        case phoenixNutritionAvg = "phoenix_nutrition_avg"
        case phoenixResilienceAvg = "phoenix_resilience_avg"
        case phoenixSpiritAvg   = "phoenix_spirit_avg"
        case pssScore           = "pss_score"
        case warRoomStreak      = "war_room_streak"
        case topPrs             = "top_prs"
        case ritualCompletionRate = "ritual_completion_rate"
        case avgSleepHrs        = "avg_sleep_hrs"
        case avgCalories        = "avg_calories"
        case breathworkSessionsTotal = "breathwork_sessions_total"
        case meditationMinutesTotal  = "meditation_minutes_total"
        case journalEntriesTotal     = "journal_entries_total"
    }
}

struct PRSnapshot: Codable {
    let exercise: String
    let weightLbs: Double
    let reps: Int?

    enum CodingKeys: String, CodingKey {
        case exercise, reps
        case weightLbs = "weight_lbs"
    }
}

struct PRBroken: Codable {
    let exercise: String
    let oldWeightLbs: Double
    let newWeightLbs: Double

    var delta: Double { newWeightLbs - oldWeightLbs }

    enum CodingKeys: String, CodingKey {
        case exercise
        case oldWeightLbs = "old_weight_lbs"
        case newWeightLbs = "new_weight_lbs"
    }
}

struct SeasonStats: Codable {
    let warRoomVictories: Int
    let warRoomBattles: Int
    let warRoomBestStreak: Int
    let warRoomResets: Int
    let prsBrokenCount: Int
    let prsBroken: [PRBroken]
    let ritualCompletionRate: Double
    let breathworkSessions: Int
    let meditationMinutes: Int
    let journalEntries: Int

    enum CodingKeys: String, CodingKey {
        case warRoomVictories   = "war_room_victories"
        case warRoomBattles     = "war_room_battles"
        case warRoomBestStreak  = "war_room_best_streak"
        case warRoomResets      = "war_room_resets"
        case prsBrokenCount     = "prs_broken_count"
        case prsBroken          = "prs_broken"
        case ritualCompletionRate = "ritual_completion_rate"
        case breathworkSessions = "breathwork_sessions"
        case meditationMinutes  = "meditation_minutes"
        case journalEntries     = "journal_entries"
    }
}

struct SeasonReport: Codable, Identifiable {
    var id: String { season.id }
    let season: Season
    let startSnapshot: SeasonSnapshot?
    let endSnapshot: SeasonSnapshot?
    let stats: SeasonStats
    let narrative: String
    let headlineDelta: String
    let arc: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case season, stats, narrative, arc, title
        case startSnapshot  = "start_snapshot"
        case endSnapshot    = "end_snapshot"
        case headlineDelta  = "headline_delta"
    }
}
