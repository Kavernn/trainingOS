import Foundation

// Dates en String "YYYY-MM-DD" — le decoder ISO8601 global ne s'applique pas
// (backend renvoie des dates plain, pas des datetimes).

struct BudgetStatus: Decodable {
    let periodStart: String
    let periodEnd: String
    let daysToNextPayday: Int
    let isPaydayToday: Bool?
    let todayTransfers: [BudgetTodayTransfer]?
    let todayNetSpentCents: Int?
    let envelopes: [BudgetEnvelope]
    let debts: [BudgetDebt]
    let projection: BudgetProjection?
    let nextMilestone: BudgetMilestone?

    enum CodingKeys: String, CodingKey {
        case periodStart         = "period_start"
        case periodEnd           = "period_end"
        case daysToNextPayday    = "days_to_next_payday"
        case isPaydayToday       = "is_payday_today"
        case todayTransfers      = "today_transfers"
        case todayNetSpentCents  = "today_net_spent_cents"
        case envelopes, debts, projection
        case nextMilestone       = "next_milestone"
    }
}

// 3e usage → extraction (BudgetView, BudgetCard, DashboardView).
extension BudgetStatus {
    var activeDebt: BudgetDebt? {
        debts
            .filter { !$0.isSavings && ($0.balanceCents ?? 0) > 0 }
            .sorted { ($0.attackOrder ?? Int.max) < ($1.attackOrder ?? Int.max) }
            .first
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

// Retour backend : logs positifs du jour (expense + fund + debt) pour
// cocher les items payday et alimenter le solde live.
struct BudgetTodayTransfer: Decodable, Equatable, Identifiable {
    let type: String
    let debtKey: String?
    let envelopeKey: String?
    let categoryKey: String?     // Diff B : G/L, nil sauf expense.
    let amountCents: Int
    var id: String { "\(type)-\(debtKey ?? envelopeKey ?? "")" }

    enum CodingKeys: String, CodingKey {
        case type
        case debtKey     = "debt_key"
        case envelopeKey = "envelope_key"
        case categoryKey = "category_key"
        case amountCents = "amount_cents"
    }
}

// Transfert planifié affiché sur la BudgetCard en mode Jour de Paie.
// Construit iOS depuis BudgetPlan — pas un champ backend.
struct PlannedTransfer: Identifiable, Equatable {
    let id = UUID()
    let serverType: String       // "expense" | "fund_transfer" | "debt_payment"
    let label: String
    let debtKey: String?         // set pour fund/debt
    let envelopeKey: String?     // set pour expense
    let categoryKey: String?     // Diff B : G/L, set pour expense (nil pour fund/debt).
    let amountCents: Int
}

struct BudgetLogEntry: Encodable {
    let date: String            // "YYYY-MM-DD" MTL
    let type: String            // "expense" | "debt_payment" | "fund_transfer" | "windfall"
    let amountCents: Int
    let envelopeKey: String?    // set pour expense (inféré depuis categoryKey)
    let debtKey: String?        // set pour debt_payment | fund_transfer | windfall
    let categoryKey: String?    // Diff B : G/L, set pour expense (nil pour les 3 autres types)
    let note: String?

    enum CodingKeys: String, CodingKey {
        case date, type, note
        case amountCents  = "amount_cents"
        case envelopeKey  = "envelope_key"
        case debtKey      = "debt_key"
        case categoryKey  = "category_key"
    }
}
