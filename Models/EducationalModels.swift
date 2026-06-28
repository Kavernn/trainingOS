import Foundation

struct EducationalCapsule: Codable, Identifiable {
    let id: Int
    let category: String
    let title: String
    let body: String
    let movementPattern: String?
    let muscleSpecific: String?
    let tags: [String]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, title, body, tags
        case movementPattern = "movement_pattern"
        case muscleSpecific  = "muscle_specific"
        case createdAt       = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(Int.self, forKey: .id)
        category        = try c.decode(String.self, forKey: .category)
        title           = try c.decode(String.self, forKey: .title)
        body            = try c.decode(String.self, forKey: .body)
        movementPattern = try c.decodeIfPresent(String.self, forKey: .movementPattern)
        muscleSpecific  = try c.decodeIfPresent(String.self, forKey: .muscleSpecific)
        tags            = try c.decodeIfPresent([String].self, forKey: .tags)
        createdAt       = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}
