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
    let truth: String
    let truthType: String
    let intention: String?
    let morningAt: String?
    let outcome: String?          // "burned" | "survived" | nil
    let eveningAt: String?
    let carryCount: Int
    let carriedFrom: String?
    let carriedIntention: String? // haunting demon from a prior survived day
    let suggestions: [String]
    // Evening routine checklist (migration 065)
    let routineNoFood: Bool
    let routineDimLights: Bool
    let routineShower: Bool
    let routineConnection: Bool
    let routineDeconnect: Bool
    let routineBedtimeOk: Bool
    let routineCompletedAt: String?
    // Engagement flow (nouveau système)
    let engagements: [RitualEngagement]         // engagements du jour à adresser
    let tomorrowEngagements: [RitualEngagement] // engagements créés pour demain

    var morningDone: Bool  { morningAt != nil }
    var eveningDone: Bool  { eveningAt != nil }
    var burnedToday: Bool  { outcome == "burned" }
    var survivedToday: Bool { outcome == "survived" }

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
        case date, truth, intention, outcome, suggestions
        case truthType          = "truth_type"
        case morningAt          = "morning_at"
        case eveningAt          = "evening_at"
        case carryCount         = "carry_count"
        case carriedFrom        = "carried_from"
        case carriedIntention   = "carried_intention"
        case routineNoFood         = "routine_no_food"
        case routineDimLights      = "routine_dim_lights"
        case routineShower         = "routine_shower"
        case routineConnection     = "routine_connection"
        case routineDeconnect      = "routine_deconnect"
        case routineBedtimeOk      = "routine_bedtime_ok"
        case routineCompletedAt    = "routine_completed_at"
        case engagements           = "engagements"
        case tomorrowEngagements   = "tomorrow_engagements"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date              = (try? c.decode(String.self, forKey: .date))          ?? ""
        truth             = (try? c.decode(String.self, forKey: .truth))         ?? ""
        truthType         = (try? c.decode(String.self, forKey: .truthType))     ?? "default"
        intention         = try? c.decode(String.self, forKey: .intention)
        morningAt         = try? c.decode(String.self, forKey: .morningAt)
        outcome           = try? c.decode(String.self, forKey: .outcome)
        eveningAt         = try? c.decode(String.self, forKey: .eveningAt)
        carryCount        = (try? c.decode(Int.self,    forKey: .carryCount))    ?? 0
        carriedFrom       = try? c.decode(String.self, forKey: .carriedFrom)
        carriedIntention  = try? c.decode(String.self, forKey: .carriedIntention)
        suggestions       = (try? c.decode([String].self, forKey: .suggestions)) ?? []
        routineNoFood         = (try? c.decode(Bool.self, forKey: .routineNoFood))         ?? false
        routineDimLights      = (try? c.decode(Bool.self, forKey: .routineDimLights))      ?? false
        routineShower         = (try? c.decode(Bool.self, forKey: .routineShower))         ?? false
        routineConnection     = (try? c.decode(Bool.self, forKey: .routineConnection))     ?? false
        routineDeconnect      = (try? c.decode(Bool.self, forKey: .routineDeconnect))      ?? false
        routineBedtimeOk      = (try? c.decode(Bool.self, forKey: .routineBedtimeOk))      ?? false
        routineCompletedAt    = try? c.decode(String.self, forKey: .routineCompletedAt)
        engagements           = (try? c.decode([RitualEngagement].self, forKey: .engagements))         ?? []
        tomorrowEngagements   = (try? c.decode([RitualEngagement].self, forKey: .tomorrowEngagements)) ?? []
    }
}
