import Foundation

struct OathModel: Codable, Identifiable {
    let id: String
    let text: String
    let version: Int
    let wordCount: Int?
    let writtenAt: String
    let supersededAt: String?

    var isActive: Bool { supersededAt == nil }

    var formattedDate: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: writtenAt) else { return writtenAt }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        out.locale    = Locale(identifier: "fr_CA")
        return out.string(from: d)
    }

    enum CodingKeys: String, CodingKey {
        case id, text, version
        case wordCount    = "word_count"
        case writtenAt    = "written_at"
        case supersededAt = "superseded_at"
    }
}

struct OathRecall: Codable, Identifiable {
    let id: String
    let oathId: String
    let trigger: String
    let shownAt: String

    enum CodingKeys: String, CodingKey {
        case id, trigger
        case oathId  = "oath_id"
        case shownAt = "shown_at"
    }
}
