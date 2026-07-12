import Foundation

// Dates en String "YYYY-MM-DD" — le decoder ISO8601 global ne s'applique pas
// (backend renvoie des dates plain, pas des datetimes).

struct BudgetStatus: Decodable {
    let periodStart: String
    let periodEnd: String
    let daysToNextPayday: Int
    let envelopes: [BudgetEnvelope]
    let debts: [BudgetDebt]
    let projection: BudgetProjection?
    let nextMilestone: BudgetMilestone?

    enum CodingKeys: String, CodingKey {
        case periodStart        = "period_start"
        case periodEnd          = "period_end"
        case daysToNextPayday   = "days_to_next_payday"
        case envelopes, debts, projection
        case nextMilestone      = "next_milestone"
    }
}

struct BudgetProjection: Decodable {
    let attackRateCentsPerDay: Int?
    let fundRateCentsPerDay: Int?
    let isFallbackRate: Bool?

    enum CodingKeys: String, CodingKey {
        case attackRateCentsPerDay = "attack_rate_cents_per_day"
        case fundRateCentsPerDay   = "fund_rate_cents_per_day"
        case isFallbackRate        = "is_fallback_rate"
    }
}

struct BudgetMilestone: Decodable {
    let kind: String                 // "debt_death" | "fund_threshold" | ...
    let key: String                  // debt/fund key
    let thresholdCents: Int?
    let projectedDate: String?       // YYYY-MM-DD
    let daysRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case kind, key
        case thresholdCents = "threshold_cents"
        case projectedDate  = "projected_date"
        case daysRemaining  = "days_remaining"
    }
}

struct BudgetEnvelope: Decodable, Identifiable {
    let key: String
    let label: String
    let limitCents: Int
    let spentCents: Int
    let remainingCents: Int
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label
        case limitCents     = "limit_cents"
        case spentCents     = "spent_cents"
        case remainingCents = "remaining_cents"
    }
}

struct BudgetDebt: Decodable, Identifiable {
    let key: String
    let label: String
    let isSavings: Bool
    let balanceCents: Int?
    let initialCents: Int?
    let interestRate: Double?
    let attackOrder: Int?
    let currentCents: Int?
    let targetCents: Int?
    let progressPct: Double?
    let projectedDeathDate: String?
    let projectedCompletionDate: String?
    let deadlineDate: String?
    let projectedAmountAtDeadlineCents: Int?
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label
        case isSavings                        = "is_savings"
        case balanceCents                     = "balance_cents"
        case initialCents                     = "initial_cents"
        case interestRate                     = "interest_rate"
        case attackOrder                      = "attack_order"
        case currentCents                     = "current_cents"
        case targetCents                      = "target_cents"
        case progressPct                      = "progress_pct"
        case projectedDeathDate               = "projected_death_date"
        case projectedCompletionDate          = "projected_completion_date"
        case deadlineDate                     = "deadline_date"
        case projectedAmountAtDeadlineCents   = "projected_amount_at_deadline_cents"
    }
}

struct BudgetLogEntry: Encodable {
    let date: String            // "YYYY-MM-DD" MTL
    let type: String            // "expense" | "debt_payment" | "fund_transfer"
    let amountCents: Int
    let envelopeKey: String?
    let debtKey: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case date, type, note
        case amountCents  = "amount_cents"
        case envelopeKey  = "envelope_key"
        case debtKey      = "debt_key"
    }
}
