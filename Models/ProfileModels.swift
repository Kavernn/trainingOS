import Foundation

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
