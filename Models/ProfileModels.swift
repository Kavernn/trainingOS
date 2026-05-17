import Foundation

// MARK: - Profile Stats
struct ProfileStats: Decodable {
    let totalSessions:    Int
    let allTimeVolumeLbs: Double
    let currentStreak:    Int
    let longestStreak:    Int
    let memberSince:      String?
    let weeklyTonnage:    [WeeklyTonnageEntry]

    enum CodingKeys: String, CodingKey {
        case totalSessions    = "total_sessions"
        case allTimeVolumeLbs = "all_time_volume_lbs"
        case currentStreak    = "current_streak"
        case longestStreak    = "longest_streak"
        case memberSince      = "member_since"
        case weeklyTonnage    = "weekly_tonnage"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalSessions    = (try? c.decode(Int.self, forKey: .totalSessions))    ?? 0
        allTimeVolumeLbs = (try? c.decode(Double.self, forKey: .allTimeVolumeLbs)) ?? 0
        currentStreak    = (try? c.decode(Int.self, forKey: .currentStreak))    ?? 0
        longestStreak    = (try? c.decode(Int.self, forKey: .longestStreak))    ?? 0
        memberSince      = try? c.decode(String.self, forKey: .memberSince)
        weeklyTonnage    = (try? c.decode([WeeklyTonnageEntry].self, forKey: .weeklyTonnage)) ?? []
    }
}

// MARK: - User Profile
struct UserProfile: Codable {
    let name: String?
    let weight: Double?
    let height: Double?
    let age: Int?
    let goal: String?
    let level: String?
    let sex: String?
    let photoB64: String?   // legacy base64 storage
    let photoUrl: String?   // Supabase Storage public URL (preferred)

    enum CodingKeys: String, CodingKey {
        case name, weight, height, age, goal, level, sex
        case photoB64 = "photo_b64"
        case photoUrl = "photo_url"
    }
}
