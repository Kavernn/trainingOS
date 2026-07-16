import SwiftUI

// Diff C — Registre chronologique des money_logs. Lecture seule.
// Le parent (BudgetView) passe envelopes/debts pour résoudre les labels ;
// la vue fetche ses propres logs par mois (GET /api/budget/logs?month=YYYY-MM).
struct BudgetJournalView: View {
    let envelopes: [BudgetEnvelope]
    let debts: [BudgetDebt]

    @State private var logs: [BudgetLog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var yearMonth: String = BudgetJournalView.currentYearMonth()

    // Borne arrière = mois de PLAN_START (2026-07-15).
    private static let PLAN_START_YM = "2026-07"

    private static let ymFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "America/Montreal")
        return f
    }()

    private static func currentYearMonth() -> String {
        ymFormatter.string(from: Date())
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.timeZone = TimeZone(identifier: "America/Montreal")
        f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: yearMonth) else { return yearMonth }
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized
    }

    private var canGoBack: Bool    { yearMonth > BudgetJournalView.PLAN_START_YM }
    private var canGoForward: Bool { yearMonth < BudgetJournalView.currentYearMonth() }

    private var groupedByDay: [(day: String, logs: [BudgetLog])] {
        let grouped = Dictionary(grouping: logs) { $0.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    monthNav
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if let msg = errorMessage {
                        Text(msg)
                            .font(.appBody).foregroundColor(Color.appDanger)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else if logs.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedByDay, id: \.day) { section in
                            daySection(day: section.day, logs: section.logs)
                        }
                    }
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: yearMonth) { _, _ in
            Task { await load() }
        }
    }

    private var monthNav: some View {
        HStack {
            Button {
                yearMonth = shiftMonth(yearMonth, by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appBody.weight(.semibold))
                    .foregroundStyle(canGoBack ? Color.forge : Color.appTextPrimary.opacity(0.25))
            }
            .disabled(!canGoBack)
            Spacer()
            Text(monthLabel)
                .font(.appHeadline.weight(.bold))
                .foregroundStyle(Color.appTextPrimary)
            Spacer()
            Button {
                yearMonth = shiftMonth(yearMonth, by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appBody.weight(.semibold))
                    .foregroundStyle(canGoForward ? Color.forge : Color.appTextPrimary.opacity(0.25))
            }
            .disabled(!canGoForward)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("Aucun mouvement en \(monthLabel.lowercased())")
                .font(.appBody).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    private func daySection(day: String, logs: [BudgetLog]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BudgetFormat.dayMonth(day) ?? day)
                .font(.appLabel.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(logs) { logRow($0) }
        }
    }

    private func logRow(_ log: BudgetLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(log))
                    .font(.appBody).foregroundStyle(Color.appTextPrimary)
                if let sub = rowSubtitle(log) {
                    Text(sub)
                        .font(.appCaption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Text(BudgetFormat.dollarsSigned(displayAmount(log)))
                .font(.appBody.weight(.semibold))
                .foregroundStyle(amountColor(log))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }

    // MARK: - Row logic (Q6 conventions)

    private func isCorrection(_ log: BudgetLog) -> Bool {
        ["expense", "debt_payment", "fund_transfer"].contains(log.type) && log.amountCents < 0
    }

    // Outflow (expense/debt/fund) → négation. Inflow (income/windfall) → tel quel.
    private func displayAmount(_ log: BudgetLog) -> Int {
        switch log.type {
        case "expense", "debt_payment", "fund_transfer": return -log.amountCents
        default: return log.amountCents
        }
    }

    private func amountColor(_ log: BudgetLog) -> Color {
        if isCorrection(log) { return Color.appWarning }
        return displayAmount(log) < 0 ? .secondary : Color.appSuccess
    }

    private func rowTitle(_ log: BudgetLog) -> String {
        let prefix = isCorrection(log) ? "Correction · " : ""
        // Priorité descendante : catégorie > enveloppe > dette > type localisé.
        if let ck = log.categoryKey, let cat = lookupCategoryLabel(ck) {
            return prefix + cat
        }
        if let ek = log.envelopeKey, let env = envelopes.first(where: { $0.key == ek }) {
            return prefix + env.label
        }
        if let dk = log.debtKey, let debt = debts.first(where: { $0.key == dk }) {
            return prefix + debt.label
        }
        switch log.type {
        case "income":   return prefix + "Paie"
        case "windfall": return prefix + "Rentrée d'argent"
        default:         return prefix + log.type.capitalized
        }
    }

    private func rowSubtitle(_ log: BudgetLog) -> String? {
        if let note = log.note, !note.isEmpty { return note }
        // Titre = catégorie → sous-titre = enveloppe (contexte).
        if log.categoryKey != nil,
           let ek = log.envelopeKey,
           let env = envelopes.first(where: { $0.key == ek }) {
            return env.label
        }
        // Titre = enveloppe → sous-titre = "Dépense".
        if log.categoryKey == nil, log.envelopeKey != nil {
            return "Dépense"
        }
        // Titre = dette → contexte du type.
        if log.debtKey != nil {
            switch log.type {
            case "debt_payment":  return "Remboursement dette"
            case "fund_transfer": return "Fonds voyage"
            case "windfall":      return "Rentrée d'argent"
            default: return nil
            }
        }
        if log.type == "income" { return "Revenu" }
        return nil
    }

    private func lookupCategoryLabel(_ key: String) -> String? {
        for group in BudgetPlan.categoriesByEnvelope {
            if let c = group.categories.first(where: { $0.key == key }) {
                return c.label
            }
        }
        return nil
    }

    // MARK: - Fetch + nav

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            logs = try await APIService.shared.fetchBudgetLogs(month: yearMonth)
        } catch {
            errorMessage = "Impossible de charger : \(error.localizedDescription)"
            logs = []
        }
    }

    private func shiftMonth(_ ym: String, by delta: Int) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return ym }
        var newY = y
        var newM = m + delta
        while newM > 12 { newM -= 12; newY += 1 }
        while newM < 1  { newM += 12; newY -= 1 }
        return String(format: "%04d-%02d", newY, newM)
    }
}
