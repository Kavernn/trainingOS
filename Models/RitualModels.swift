import Foundation

// MARK: - Engagement (nouveau flow)

struct RitualEngagement: Codable, Identifiable {
    let id: String
    let date: String
    let text: String
    let status: String?   // nil | "done" | "notdone"
    let sortOrder: Int
    let createdAt: String?

    var isAddressed: Bool { status != nil }
    var isDone: Bool      { status == "done" }

    enum CodingKeys: String, CodingKey {
        case id, date, text, status
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decode(String.self, forKey: .id))        ?? UUID().uuidString
        date      = (try? c.decode(String.self, forKey: .date))      ?? ""
        text      = (try? c.decode(String.self, forKey: .text))      ?? ""
        status    = try? c.decode(String.self, forKey: .status)
        sortOrder = (try? c.decode(Int.self,    forKey: .sortOrder))  ?? 0
        createdAt = try? c.decode(String.self, forKey: .createdAt)
    }

    init(id: String, date: String, text: String, status: String?, sortOrder: Int, createdAt: String?) {
        self.id = id; self.date = date; self.text = text
        self.status = status; self.sortOrder = sortOrder; self.createdAt = createdAt
    }
}

struct RitualEngagementsResponse: Codable {
    let ok: Bool
    let engagements: [RitualEngagement]
}

// MARK: - RitualToday

struct RitualToday: Codable {
    let date: String
    let engagements: [RitualEngagement]         // engagements du jour à adresser
    let tomorrowEngagements: [RitualEngagement] // engagements créés pour demain

    // Engagement cycle state
    var hasEngagementsToday: Bool    { !engagements.isEmpty }
    var allEngagementsAddressed: Bool {
        !engagements.isEmpty && engagements.allSatisfy { $0.isAddressed }
    }
    var tomorrowCreated: Bool { !tomorrowEngagements.isEmpty }

    var engagementsCreatedAt: String? {
        guard let iso = engagements.first?.createdAt else { return nil }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = df.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return "Hier soir" }
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        return "Hier soir · \(fmt.string(from: d))"
    }

    enum CodingKeys: String, CodingKey {
        case date
        case engagements           = "engagements"
        case tomorrowEngagements   = "tomorrow_engagements"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date                  = (try? c.decode(String.self, forKey: .date))                          ?? ""
        engagements           = (try? c.decode([RitualEngagement].self, forKey: .engagements))         ?? []
        tomorrowEngagements   = (try? c.decode([RitualEngagement].self, forKey: .tomorrowEngagements)) ?? []
    }
}
