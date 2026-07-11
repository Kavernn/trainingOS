import SwiftUI

struct BudgetView: View {
    @State private var status: BudgetStatus?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogSheet = false

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            if let s = status {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(s)
                        envelopesSection(s.envelopes)
                        debtsSection(s.debts)
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
            } else if isLoading {
                ProgressView()
            } else if let msg = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.appTitle)
                    Text(msg).font(.appBody).multilineTextAlignment(.center)
                    Button("Réessayer") { Task { await load() } }
                }
                .padding()
            }

            // FAB bouton ajout
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showLogSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.forge)
                            .clipShape(Circle())
                            .shadow(radius: 8, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Budget & Finances")
        .navigationBarTitleDisplayMode(.inline)
        .task { if status == nil { await load() } }
        .sheet(isPresented: $showLogSheet) {
            BudgetLogSheet(
                envelopes: status?.envelopes ?? [],
                debts:     status?.debts     ?? [],
                onSaved:   { await load() }
            )
        }
    }

    // MARK: - Sections

    private func headerSection(_ s: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(periodString(start: s.periodStart, end: s.periodEnd))
                .font(.appTitle)
                .foregroundStyle(Color.appTextPrimary)
            Text("Prochaine paie dans \(s.daysToNextPayday) jour\(s.daysToNextPayday == 1 ? "" : "s")")
                .font(.appLabel)
                .foregroundStyle(.secondary)
        }
    }

    private func envelopesSection(_ envelopes: [BudgetEnvelope]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enveloppes")
                .font(.appTitle)
                .foregroundStyle(Color.appTextPrimary)
            ForEach(envelopes) { envelopeRow($0) }
        }
    }

    private func envelopeRow(_ e: BudgetEnvelope) -> some View {
        let limit = max(e.limitCents, 1)
        let pct   = Double(e.spentCents) / Double(limit)
        let over  = e.remainingCents < 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(e.label).font(.appHeadline).foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text("\(dollarsString(e.remainingCents)) / \(dollarsString(e.limitCents))")
                    .font(.appLabel)
                    .foregroundStyle(over ? Color.appDanger : .secondary)
            }
            ProgressView(value: min(max(pct, 0), 1.0))
                .tint(envelopeColor(pct))
            if over {
                Text("Dépassement : \(dollarsString(-e.remainingCents))")
                    .font(.appCaption)
                    .foregroundStyle(Color.appDanger)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }

    private func debtsSection(_ debts: [BudgetDebt]) -> some View {
        let sorted = debts.sorted { a, b in
            if a.isSavings != b.isSavings { return !a.isSavings }
            return (a.attackOrder ?? Int.max) < (b.attackOrder ?? Int.max)
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Plan d'attaque")
                .font(.appTitle)
                .foregroundStyle(Color.appTextPrimary)
            ForEach(sorted) { d in
                if d.isSavings { savingsRow(d) } else { debtRow(d) }
            }
        }
    }

    private func debtRow(_ d: BudgetDebt) -> some View {
        let initial = max(d.initialCents ?? 1, 1)
        let balance = d.balanceCents ?? initial
        let paid    = initial - balance
        let pct     = Double(paid) / Double(initial)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let order = d.attackOrder {
                    Text("\(order)")
                        .font(.appCaption)
                        .foregroundStyle(Color.appTextPrimary.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().stroke(Color.appTextPrimary.opacity(0.3)))
                }
                Text(d.label).font(.appHeadline).foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text(dollarsString(balance)).font(.appLabel).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(pct, 0), 1.0)).tint(Color.forge)
            if let rate = d.interestRate {
                Text("Taux \(Int((rate * 100).rounded())) %")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }

    private func savingsRow(_ d: BudgetDebt) -> some View {
        let current = d.currentCents ?? 0
        let target  = max(d.targetCents ?? 1, 1)
        let pct     = Double(current) / Double(target)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "airplane").foregroundStyle(Color.appInfo)
                Text(d.label).font(.appHeadline).foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text("\(dollarsString(current)) / \(dollarsString(target))")
                    .font(.appLabel).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(pct, 0), 1.0)).tint(Color.appSuccess)
            if let p = d.progressPct {
                Text("\(String(format: "%.1f", p)) %")
                    .font(.appCaption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }

    // MARK: - Helpers

    private func envelopeColor(_ pct: Double) -> Color {
        if pct >= 1.0 { return .appDanger }
        if pct >= 0.8 { return .appWarning }
        return .appSuccess
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CAD"
        f.locale = Locale(identifier: "fr_CA")
        f.maximumFractionDigits = 2
        return f
    }()

    private func dollarsString(_ cents: Int) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: Double(cents) / 100.0))
            ?? "\(cents/100) $"
    }

    private func periodString(start: String, end: String) -> String {
        guard let s = parseYMD(start), let e = parseYMD(end) else {
            return "\(start) → \(end)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return "\(f.string(from: s)) → \(f.string(from: e))"
    }

    private func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "fr_CA")
        f.timeZone = TimeZone(identifier: "America/Montreal")
        return f.date(from: s)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            status = try await APIService.shared.fetchBudgetStatus()
        } catch {
            errorMessage = "Impossible de charger : \(error.localizedDescription)"
        }
        isLoading = false
    }
}
