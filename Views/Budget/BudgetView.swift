import SwiftUI

struct BudgetView: View {
    @State private var status: BudgetStatus?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogSheet = false
    @State private var pendingCelebration: BudgetCelebrationData? = nil
    @State private var celebrationData: BudgetCelebrationData? = nil

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            if let s = status {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(s)
                        envelopesSection(s.envelopes)
                        debtsSection(s.debts)
                        trajectorySection(s)
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

            // FAB bouton ajout — masqué tant que le premier load n'a pas abouti
            // (sheet inutilisable sans envelopes/debts).
            if status != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Task {
                                // Refresh silencieux avant ouverture — envelopes fraîches.
                                // Si le refresh échoue, on garde status existant et on ouvre quand même.
                                if let fresh = try? await APIService.shared.fetchBudgetStatus() {
                                    status = fresh
                                }
                                showLogSheet = true
                            }
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
        }
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.inline)
        .task { if status == nil { await load() } }
        .sheet(isPresented: $showLogSheet, onDismiss: {
            // Anti-conflit sheet→fullScreenCover : différé après dismiss complet.
            if let data = pendingCelebration {
                pendingCelebration = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    celebrationData = data
                }
            }
        }) {
            BudgetLogSheet(
                envelopes:  status?.envelopes ?? [],
                debts:      status?.debts     ?? [],
                activeDebt: status?.activeDebt,
                onSaved:    { entry, total in
                    let old = status
                    await load()
                    if let data = BudgetCelebrationData.build(entry: entry, old: old, new: status, totalCents: total) {
                        pendingCelebration = data
                    }
                }
            )
        }
        .fullScreenCover(item: $celebrationData) { data in
            BudgetCelebrationView(data: data) { celebrationData = nil }
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
        let active = BudgetFormat.activeDebts(from: status?.debts ?? [])
        return VStack(alignment: .leading, spacing: 12) {
            Text("Enveloppes")
                .font(.appTitle)
                .foregroundStyle(Color.appTextPrimary)
            ForEach(envelopes) { envelopeRow($0, activeDebts: active) }
        }
    }

    private func envelopeRow(_ e: BudgetEnvelope, activeDebts: [BudgetDebt]) -> some View {
        let limit = max(e.limitCents, 1)
        let pct   = Double(e.spentCents) / Double(limit)
        let over  = e.remainingCents < 0
        let subtitle = BudgetFormat.envelopeSubtitle(e, activeDebts: activeDebts)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(e.label).font(.appHeadline).foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text("\(BudgetFormat.dollars(e.remainingCents)) / \(BudgetFormat.dollars(e.limitCents))")
                    .font(.appLabel)
                    .foregroundStyle(over ? Color.appDanger : .secondary)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            ProgressView(value: min(max(pct, 0), 1.0))
                .tint(envelopeColor(pct))
            if over {
                Text("Dépassé de \(BudgetFormat.dollars(-e.remainingCents))")
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
            Text("Dettes à rembourser")
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
                Text(BudgetFormat.dollars(balance)).font(.appLabel).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(pct, 0), 1.0)).tint(Color.forge)
            if let rate = d.interestRate {
                Text("Intérêts \(Int((rate * 100).rounded())) %")
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
        let subtitle: String? = {
            guard let deadline = BudgetFormat.dayMonth(d.deadlineDate) else { return nil }
            return "\(BudgetFormat.dollarsRounded(target)) pour le \(deadline)"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "airplane").foregroundStyle(Color.appInfo)
                Text(d.label).font(.appHeadline).foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text("\(BudgetFormat.dollars(current)) / \(BudgetFormat.dollars(target))")
                    .font(.appLabel).foregroundStyle(.secondary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.appCaption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
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

    // MARK: - Trajectoire

    private func trajectorySection(_ s: BudgetStatus) -> some View {
        let events = BudgetTrajectory.events(from: s)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Ce qui s'en vient")
                .font(.appTitle)
                .foregroundStyle(Color.appTextPrimary)
            if events.isEmpty {
                Text("Rien à projeter pour l'instant")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.offset) { idx, ev in
                        BudgetTrajectoryRow(event: ev, isLast: idx == events.count - 1)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
            }
        }
    }

    // MARK: - Helpers

    private func envelopeColor(_ pct: Double) -> Color {
        if pct >= 1.0 { return .appDanger }
        if pct >= 0.8 { return .appWarning }
        return .appSuccess
    }

    private func periodString(start: String, end: String) -> String {
        guard let s = BudgetFormat.parseYMD(start), let e = BudgetFormat.parseYMD(end) else {
            return "\(start) → \(end)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return "\(f.string(from: s)) → \(f.string(from: e))"
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

    // Célébration : logique extraite dans BudgetCelebrationData.build (partagée
    // avec DashboardView pour le mode Jour de Paie).
    // activeDebt : extrait dans BudgetStatus.activeDebt (3e usage).
}

// MARK: - BudgetCard (dashboard)

struct BudgetCard: View {
    let status: BudgetStatus
    var onTransferTap: ((PlannedTransfer) -> Void)? = nil

    private var totalVariable: Int {
        status.envelopes.reduce(0) { $0 + $1.remainingCents }
    }

    private var isFallback: Bool { status.projection?.isFallbackRate == true }
    private var isPayday: Bool { status.isPaydayToday == true }

    // Transferts planifiés du jour — piecewise via BudgetPlan (mêmes seuils que les chips).
    // Ordre = ordre d'exécution naturel : hypothèque → voyage → attaque.
    private var plannedTransfers: [PlannedTransfer] {
        let today = BudgetFormat.todayYMDMTL
        var out: [PlannedTransfer] = [
            PlannedTransfer(
                serverType:  "expense",
                label:       "Payer l'hypothèque",
                debtKey:     nil,
                envelopeKey: "fixes",
                categoryKey: "hypotheque",   // Diff B : G/L, envelope inférée à la sheet.
                amountCents: BudgetPlan.hypothequePerPeriodCents
            )
        ]
        if today <= BudgetPlan.fundDeadline {
            out.append(PlannedTransfer(
                serverType:  "fund_transfer",
                label:       "Virer au fonds voyage",
                debtKey:     "fonds_voyage",
                envelopeKey: nil,
                categoryKey: nil,
                amountCents: BudgetPlan.fundPerPeriod
            ))
        }
        if let active = status.activeDebt {
            let amount = today < BudgetPlan.planSwitchDate
                ? BudgetPlan.attackPerPeriodBefore
                : BudgetPlan.attackPerPeriodAfter
            out.append(PlannedTransfer(
                serverType:  "debt_payment",
                label:       "Rembourser · \(active.label)",
                debtKey:     active.key,
                envelopeKey: nil,
                categoryKey: nil,
                amountCents: amount
            ))
        }
        return out
    }

    // Fait = un log du même type + même clé (debt pour fund/debt, envelope pour expense)
    // existe aujourd'hui. Montants non comparés (ceinture existante conservée).
    private func isDone(_ pt: PlannedTransfer) -> Bool {
        (status.todayTransfers ?? []).contains {
            guard $0.type == pt.serverType else { return false }
            if pt.serverType == "expense" { return $0.envelopeKey == pt.envelopeKey }
            return $0.debtKey == pt.debtKey
        }
    }

    // Solde live : paie − somme SIGNÉE des money_logs du jour (today_net_spent_cents,
    // fourni par le backend — nette les contre-écritures, exclut income + windfall).
    private var remainingToDistributeCents: Int {
        BudgetPlan.payPerPeriodCents - (status.todayNetSpentCents ?? 0)
    }
    private var allPaydayDone: Bool {
        !plannedTransfers.isEmpty && plannedTransfers.allSatisfy(isDone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isPayday {
                paydayHeader
                if plannedTransfers.isEmpty {
                    Text("Aucune action prévue aujourd'hui")
                        .font(.appCaption).foregroundStyle(.secondary)
                } else {
                    ForEach(plannedTransfers) { pt in
                        PaydayTransferRow(
                            transfer: pt,
                            done: isDone(pt),
                            onTap: { onTransferTap?(pt) }
                        )
                    }
                    paydayFooter
                }
            } else {
                headerRow
                if let debt = status.activeDebt { debtRow(debt) }
                if let milestone = status.nextMilestone { milestoneRow(milestone) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appCard))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appSeparator, lineWidth: 0.5))
    }

    // "Reste à distribuer : X / 1 743,91 $" — décrémente à chaque log positif du jour.
    private var paydayHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "banknote.fill")
                .foregroundColor(Color.forge)
                .font(.appLabel.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Jour de paie")
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                Text("Reste à distribuer : \(BudgetFormat.dollars(remainingToDistributeCents)) / \(BudgetFormat.dollars(BudgetPlan.payPerPeriodCents))")
                    .font(.appHeadline.weight(.bold))
                    .foregroundColor(remainingToDistributeCents < 0 ? Color.appWarning : Color.appTextPrimary)
            }
            Spacer()
        }
    }

    // Ligne informative finale : reste dans le compte pour le mois.
    private var paydayFooter: some View {
        let fixesDivers = BudgetPlan.fixesDiversPerPeriodCents
        let groceries: Int = {
            (status.envelopes.first(where: { $0.key == "epicerie" })?.limitCents ?? 0) / 2
        }()
        let variable: Int = {
            (status.envelopes.first(where: { $0.key == "variable" })?.limitCents ?? 0) / 2
        }()
        let leftover = groceries + variable + fixesDivers
        return VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.vertical, 2)
            Text("Reste dans ton compte : \(BudgetFormat.dollars(leftover))")
                .font(.appCaption.weight(.semibold))
                .foregroundColor(Color.appTextPrimary.opacity(0.85))
            Text("Épicerie \(BudgetFormat.dollars(groceries)), dépenses libres \(BudgetFormat.dollars(variable)), fixes divers \(BudgetFormat.dollars(fixesDivers))." + (allPaydayDone ? " Rien d'autre à faire aujourd'hui." : ""))
                .font(.appCaption)
                .foregroundColor(.secondary)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "wallet.pass.fill")
                .foregroundColor(Color.forge)
                .font(.appLabel.weight(.semibold))
            Text(BudgetFormat.dollars(totalVariable))
                .font(.appHeadline.weight(.bold))
                .foregroundColor(Color.appTextPrimary)
            Text("· paie dans \(status.daysToNextPayday) j")
                .font(.appLabel)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func debtRow(_ debt: BudgetDebt) -> some View {
        let initial = max(debt.initialCents ?? 1, 1)
        let balance = debt.balanceCents ?? initial
        let paid    = initial - balance
        let pct     = min(max(Double(paid) / Double(initial), 0), 1)
        let dateStr = BudgetFormat.shortDate(debt.projectedDeathDate)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(debt.label)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.appTextPrimary.opacity(0.85))
                Spacer()
                if let dateStr {
                    Text(dateStr + (isFallback ? " · plan" : ""))
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
            }
            ProgressView(value: pct).tint(Color.forge)
        }
    }

    private func milestoneRow(_ m: BudgetMilestone) -> some View {
        let label = BudgetFormat.milestoneLabel(m, debts: status.debts, isFallback: isFallback)
        return HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.appCaption)
                .foregroundColor(.secondary)
            Text(label)
                .font(.appCaption)
                .foregroundColor(Color.appTextPrimary.opacity(0.8))
                .lineLimit(1)
            Spacer()
        }
    }
}

// MARK: - BudgetCelebrationView (post-log)

struct BudgetCelebrationData: Identifiable {
    let id = UUID()
    let amountCents: Int      // montant loggé (80 % pour windfall)
    let targetLabel: String
    let daysEarlier: Int?     // nil ou 0 → fallback
    let verb: String          // "meurt" | "atteint"
    let totalCents: Int?      // windfall : total reçu ; nil sinon → format standard

    // Extrait de BudgetView.buildCelebration — partagé avec DashboardView
    // (mode Jour de Paie). Delta nil → message fallback (jamais "0 jour plus tôt").
    static func build(
        entry: BudgetLogEntry,
        old: BudgetStatus?,
        new: BudgetStatus?,
        totalCents: Int?
    ) -> BudgetCelebrationData? {
        guard entry.type != "expense" else { return nil }

        let amount = entry.amountCents
        switch entry.type {
        case "debt_payment", "windfall":
            guard let debtKey = entry.debtKey else { return nil }
            let oldDebt = old?.debts.first(where: { $0.key == debtKey })
            let newDebt = new?.debts.first(where: { $0.key == debtKey })
            let label = newDebt?.label ?? oldDebt?.label ?? "Dette"
            let days  = BudgetFormat.daysEarlier(
                old: oldDebt?.projectedDeathDate,
                new: newDebt?.projectedDeathDate
            )
            return BudgetCelebrationData(
                amountCents: amount,
                targetLabel: label,
                daysEarlier: days,
                verb: "meurt",
                totalCents: totalCents
            )
        case "fund_transfer":
            guard let fundKey = entry.debtKey else { return nil }
            let oldFund = old?.debts.first(where: { $0.key == fundKey })
            let newFund = new?.debts.first(where: { $0.key == fundKey })
            let label = newFund?.label ?? oldFund?.label ?? "Fonds voyage"
            let days  = BudgetFormat.daysEarlier(
                old: oldFund?.projectedCompletionDate,
                new: newFund?.projectedCompletionDate
            )
            return BudgetCelebrationData(
                amountCents: amount,
                targetLabel: label,
                daysEarlier: days,
                verb: "atteint",
                totalCents: nil
            )
        default:
            return nil
        }
    }
}

// MARK: - PaydayTransferRow (mode Jour de Paie)

struct PaydayTransferRow: View {
    let transfer: PlannedTransfer
    let done: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(done ? Color.appSuccess : Color.appTextPrimary.opacity(0.4))
                    .font(.appBody)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.label)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.appTextPrimary.opacity(done ? 0.5 : 1))
                    Text(BudgetFormat.dollars(transfer.amountCents))
                        .font(.appCaption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(done)  // anti-doublon accidentel ; log additionnel via le FAB de BudgetView.
    }
}

struct BudgetCelebrationView: View {
    let data: BudgetCelebrationData
    let onDismiss: () -> Void

    @State private var appear = false

    // Windfall : "100 $ reçu" en gros, "80 $ → …" en sous-texte.
    // Autres : "150 $" en gros, "… meurt X j plus tôt" en sous-texte.
    private var amountText: String {
        if let total = data.totalCents {
            return "\(BudgetFormat.dollars(total)) reçu"
        }
        return BudgetFormat.dollars(data.amountCents)
    }

    private var subtitle: String {
        let base: String
        if let days = data.daysEarlier, days > 0 {
            let jour = days == 1 ? "jour" : "jours"
            base = "\(data.targetLabel) \(data.verb) \(days) \(jour) plus tôt"
        } else {
            base = "sur \(data.targetLabel)"
        }
        if data.totalCents != nil {
            return "\(BudgetFormat.dollars(data.amountCents)) → \(base)"
        }
        return base
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            RadialGradient(
                colors: [Color.forge.opacity(appear ? 0.20 : 0), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(amountText)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(Color.forge)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)
                Text(subtitle)
                    .font(.appHeadline)
                    .foregroundColor(Color.appTextPrimary.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(appear ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appear = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                onDismiss()
            }
        }
    }
}

// MARK: - Format helpers

enum BudgetFormat {
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CAD"
        f.locale = Locale(identifier: "fr_CA")
        f.maximumFractionDigits = 2
        return f
    }()

    static func dollars(_ cents: Int) -> String {
        currencyFormatter.string(from: NSNumber(value: Double(cents) / 100.0))
            ?? "\(cents/100) $"
    }

    // "13 640 $" — dollars arrondis, séparateur milliers fr_CA (espace).
    private static let roundedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "fr_CA")
        f.maximumFractionDigits = 0
        return f
    }()
    static func dollarsRounded(_ cents: Int) -> String {
        let dollars = Int((Double(cents) / 100.0).rounded())
        let s = roundedFormatter.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
        return "\(s) $"
    }

    // "12 septembre" — jour + mois complet fr_CA, sans année.
    static func dayMonth(_ ymd: String?) -> String? {
        guard let ymd, let d = parseYMD(ymd) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMMM"
        return f.string(from: d)
    }

    // Dettes actives (non-savings, solde > 0) triées par attack_order.
    static func activeDebts(from debts: [BudgetDebt]) -> [BudgetDebt] {
        debts
            .filter { !$0.isSavings && ($0.balanceCents ?? 0) > 0 }
            .sorted { ($0.attackOrder ?? Int.max) < ($1.attackOrder ?? Int.max) }
    }

    // Sous-titre "composition" affiché sous chaque enveloppe (liste + picker sheet).
    // Fixes : lignes mensuelles depuis BudgetPlan. Attaque : dettes vivantes.
    // Épicerie / Dépenses libres : limite mensuelle + description d'usage.
    static func envelopeSubtitle(_ env: BudgetEnvelope, activeDebts: [BudgetDebt]) -> String {
        switch env.key {
        case "fixes":
            return BudgetPlan.fixesPerMonth
                .map { "\($0.label) \(dollarsRounded($0.monthlyCents))" }
                .joined(separator: " · ")
        case "attaque":
            if activeDebts.isEmpty { return "Aucune dette 🎉" }
            return activeDebts
                .map { "\($0.label) \(dollarsRounded($0.balanceCents ?? 0))" }
                .joined(separator: " → puis ")
        case "epicerie":
            return "\(dollarsRounded(env.limitCents))/mois pour manger"
        case "variable":
            return "\(dollarsRounded(env.limitCents))/mois — sorties, extras, imprévus"
        default:
            return ""
        }
    }

    static func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "fr_CA")
        f.timeZone = TimeZone(identifier: "America/Montreal")
        return f.date(from: s)
    }

    static func shortDate(_ ymd: String?) -> String? {
        guard let ymd, let d = parseYMD(ymd) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    /// Nombre de jours dont `new` précède `old` (positif = meilleure trajectoire).
    static func daysEarlier(old: String?, new: String?) -> Int? {
        guard let old, let new,
              let od = parseYMD(old), let nd = parseYMD(new) else { return nil }
        return Calendar.current.dateComponents([.day], from: nd, to: od).day
    }

    // Utilisé par BudgetLogSheet (chips) et BudgetCard (payday planned transfers).
    static var todayYMDMTL: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/Montreal")
        return f.string(from: Date())
    }

    static func milestoneLabel(_ m: BudgetMilestone, debts: [BudgetDebt], isFallback: Bool) -> String {
        let target = debts.first(where: { $0.key == m.key })?.label ?? m.key
        let dateStr = shortDate(m.projectedDate)
        let suffix = isFallback ? " · plan" : ""
        switch m.kind {
        case "debt_death":
            let base = dateStr.map { "\(target) remboursée ~\($0)" } ?? "\(target) bientôt remboursée"
            return base + suffix
        case "fund_threshold":
            if let seuil = m.thresholdCents, let dateStr {
                return "\(target) atteint \(dollars(seuil)) ~\(dateStr)\(suffix)"
            }
            return "\(target) prochaine étape" + suffix
        default:
            return dateStr.map { "\(target) ~\($0)\(suffix)" } ?? target
        }
    }
}

// MARK: - Trajectoire (timeline verticale)

struct BudgetTrajectoryEvent: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    let dateStr: String
    let daysRemaining: Int
    let kind: Kind
    let subtitle: String?
    let subtitleTint: Color?
    enum Kind { case today, debtDeath, fundCompletion, fundDeadline }
}

enum BudgetTrajectory {
    static func events(from s: BudgetStatus) -> [BudgetTrajectoryEvent] {
        let today = Date()
        var out: [BudgetTrajectoryEvent] = [.init(
            label: "Aujourd'hui",
            date: today,
            dateStr: shortDate(today),
            daysRemaining: 0,
            kind: .today,
            subtitle: nil,
            subtitleTint: nil
        )]

        for d in s.debts {
            if d.isSavings {
                // Précédence : deadline réelle > projection completion.
                if let ymd = d.deadlineDate, let date = BudgetFormat.parseYMD(ymd) {
                    let target = d.targetCents ?? 0
                    let projected = d.projectedAmountAtDeadlineCents ?? (d.currentCents ?? 0)
                    let subtitle = "~\(BudgetFormat.dollars(projected)) / \(BudgetFormat.dollars(target)) au départ"
                    let tint: Color = projected >= target ? .appSuccess : .appWarning
                    out.append(.init(
                        label: "\(d.label) · départ",
                        date: date,
                        dateStr: BudgetFormat.shortDate(ymd) ?? ymd,
                        daysRemaining: daysBetween(today, date),
                        kind: .fundDeadline,
                        subtitle: subtitle,
                        subtitleTint: tint
                    ))
                } else if let ymd = d.projectedCompletionDate, let date = BudgetFormat.parseYMD(ymd) {
                    out.append(.init(
                        label: d.label,
                        date: date,
                        dateStr: BudgetFormat.shortDate(ymd) ?? ymd,
                        daysRemaining: daysBetween(today, date),
                        kind: .fundCompletion,
                        subtitle: nil,
                        subtitleTint: nil
                    ))
                }
            } else {
                if let ymd = d.projectedDeathDate, let date = BudgetFormat.parseYMD(ymd) {
                    out.append(.init(
                        label: "\(d.label) · remboursée",
                        date: date,
                        dateStr: BudgetFormat.shortDate(ymd) ?? ymd,
                        daysRemaining: daysBetween(today, date),
                        kind: .debtDeath,
                        subtitle: nil,
                        subtitleTint: nil
                    ))
                }
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    private static func daysBetween(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

struct BudgetTrajectoryRow: View {
    let event: BudgetTrajectoryEvent
    let isLast: Bool

    private var accent: Color {
        switch event.kind {
        case .today:          return Color.appTextPrimary.opacity(0.7)
        case .debtDeath:      return Color.forge
        case .fundCompletion: return Color.appSuccess
        case .fundDeadline:   return Color.appInfo
        }
    }

    private var icon: String {
        switch event.kind {
        case .today:          return "circle.fill"
        case .debtDeath:      return "xmark.circle.fill"
        case .fundCompletion: return "airplane"
        case .fundDeadline:   return "airplane.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.appBody)
                    .foregroundColor(accent)
                if !isLast {
                    Rectangle()
                        .fill(Color.appSeparator)
                        .frame(width: 1)
                        .frame(minHeight: 24)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.label)
                    .font(.appHeadline)
                    .foregroundStyle(Color.appTextPrimary)
                Text(event.dateStr)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                if let sub = event.subtitle {
                    Text(sub)
                        .font(.appCaption)
                        .foregroundStyle(event.subtitleTint ?? Color.appTextPrimary.opacity(0.8))
                }
                if event.daysRemaining > 0 {
                    Text("dans \(event.daysRemaining) j")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
