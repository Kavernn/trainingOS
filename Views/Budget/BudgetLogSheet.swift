import SwiftUI

// Miroir de api/budget_projection.py — plan front-load 2026-07-12.
// Si le plan change : mettre à jour LES DEUX côtés (backend + iOS).
enum BudgetPlan {
    static let planSwitchDate        = "2026-09-13"   // yyyy-MM-dd MTL
    static let fundDeadline          = "2026-09-12"
    static let attackPerPeriodBefore = 45781          // cents — 457,81 $/paie (front-load voyage)
    static let attackPerPeriodAfter  = 83281          //         832,81 $/paie plein régime
    static let fundPerPeriod         = 37500          // 375 $

    // Paie brute (Vince, source liste 2026-07-15). Utilisé pour le solde live
    // du mode Jour de Paie ("Reste à distribuer : X / 1 743,91 $").
    static let payPerPeriodCents     = 174391         // 1 743,91 $/paie

    // Composition des fixes en cents MENSUELS. La vue divise par 2 pour l'affichage
    // par paie (arrondi half-away-from-zero pour Claude 3219/2 → 1610).
    // Ordre = ordre d'apparition dans la sheet dépliable.
    struct FixLine: Identifiable {
        let label: String
        let monthlyCents: Int
        var id: String { label }
        var perPeriodCents: Int {
            Int((Double(monthlyCents) / 2.0).rounded(.toNearestOrAwayFromZero))
        }
    }
    static let fixesPerMonth: [FixLine] = [
        FixLine(label: "Hypothèque", monthlyCents: 90000),
        FixLine(label: "Gaz",        monthlyCents: 13000),
        FixLine(label: "Vapo",       monthlyCents:  8000),
        FixLine(label: "Claude",     monthlyCents:  3219),
        FixLine(label: "Supabase",   monthlyCents:  3000),
    ]
    static var fixesTotalPerPeriodCents: Int {
        fixesPerMonth.reduce(0) { $0 + $1.perPeriodCents }
    }
    // Première ligne (hypothèque) = seule action payday parmi les fixes.
    static var hypothequePerPeriodCents: Int {
        fixesPerMonth.first?.perPeriodCents ?? 0
    }
    static var fixesDiversPerPeriodCents: Int {
        fixesTotalPerPeriodCents - hypothequePerPeriodCents
    }
}

struct BudgetLogSheet: View {
    let envelopes: [BudgetEnvelope]
    let debts: [BudgetDebt]
    let activeDebt: BudgetDebt?         // cible auto du windfall (nil = pas de dette active)
    var prefill: PlannedTransfer? = nil // Mode Jour de Paie : pré-remplit type/cible/montant.
    var onSaved: (BudgetLogEntry, Int?) async -> Void  // Int? = totalCents pour windfall

    @Environment(\.dismiss) private var dismiss

    // Décision de plan 2026-07-12 : windfall = 80 % attaque dette, 20 % libre non loggé.
    private static let WINDFALL_SPLIT: Double = 0.8

    enum LogType: String, CaseIterable, Identifiable {
        case expense       = "Dépense"
        case debtPayment   = "Remboursement de dette"
        case fundTransfer  = "Virer à un fonds"
        case windfall      = "Rentrée d'argent"
        var id: String { rawValue }
        var serverType: String {
            switch self {
            case .expense:      return "expense"
            case .debtPayment:  return "debt_payment"
            case .fundTransfer: return "fund_transfer"
            case .windfall:     return "windfall"
            }
        }
    }

    // Windfall masqué si aucune dette active — option qu'on ne peut pas mal utiliser.
    private var availableTypes: [LogType] {
        var out: [LogType] = [.expense, .debtPayment, .fundTransfer]
        if activeDebt != nil { out.append(.windfall) }
        return out
    }

    private var windfallSplitCents: Int {
        Int((Double(amountCents) * Self.WINDFALL_SPLIT).rounded())
    }
    private var windfallFreeCents: Int { amountCents - windfallSplitCents }

    @State private var type: LogType = .expense
    @State private var envelopeKey: String = ""
    @State private var debtKey: String = ""
    @State private var amountStr: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isCorrection: Bool = false

    // Gère "," et "." pour le clavier iOS FR.
    private var amountDollars: Double {
        Double(amountStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var amountCents: Int { Int((amountDollars * 100).rounded()) }

    private var attackableDebts: [BudgetDebt] { debts.filter { !$0.isSavings } }

    // Toggle masqué en windfall (spec) — état effectif dépend du type.
    private var isCorrectionActive: Bool { isCorrection && type != .windfall }

    // Comparaisons piecewise sur String "yyyy-MM-dd" MTL — pas de Date/timezone.
    private var todayYMD: String { BudgetFormat.todayYMDMTL }
    private var attackChipCents: Int {
        todayYMD < BudgetPlan.planSwitchDate
          ? BudgetPlan.attackPerPeriodBefore
          : BudgetPlan.attackPerPeriodAfter
    }
    private var fundChipEligible: Bool { todayYMD <= BudgetPlan.fundDeadline }
    private var selectedEnvelope: BudgetEnvelope? {
        envelopes.first(where: { $0.key == envelopeKey })
    }
    private var effectiveCents: Int { isCorrectionActive ? -amountCents : amountCents }

    private var canSave: Bool {
        guard amountCents > 0 else { return false }
        if isCorrectionActive, note.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        switch type {
        case .expense:      return !envelopeKey.isEmpty
        case .debtPayment:  return !debtKey.isEmpty
        case .fundTransfer: return true
        case .windfall:     return activeDebt != nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        typePicker
                        keyPicker
                        amountField
                        correctionToggle
                        dateField
                        noteField
                        if let msg = errorMessage {
                            Text(msg)
                                .font(.appCaption)
                                .foregroundStyle(Color.appDanger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        PrimaryButton(title: "Enregistrer", isLoading: isSaving) {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Nouveau mouvement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .onAppear {
            if envelopeKey.isEmpty, let first = envelopes.first { envelopeKey = first.key }
            if debtKey.isEmpty, let first = attackableDebts.first { debtKey = first.key }
            if let pt = prefill { applyPrefill(pt) }
        }
        .onChange(of: type) { _, newValue in
            if newValue == .windfall { isCorrection = false }
        }
    }

    private var typePicker: some View {
        Picker("Type", selection: $type) {
            ForEach(availableTypes) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var keyPicker: some View {
        switch type {
        case .expense:
            VStack(alignment: .leading, spacing: 6) {
                Text("Enveloppe").font(.appLabel).foregroundStyle(.secondary)
                Picker("Enveloppe", selection: $envelopeKey) {
                    ForEach(envelopes) { Text($0.label).tag($0.key) }
                }
                .pickerStyle(.menu).tint(Color.forge)
            }
        case .debtPayment:
            VStack(alignment: .leading, spacing: 6) {
                Text("Dette").font(.appLabel).foregroundStyle(.secondary)
                Picker("Dette", selection: $debtKey) {
                    ForEach(attackableDebts) { Text($0.label).tag($0.key) }
                }
                .pickerStyle(.menu).tint(Color.forge)
            }
        case .fundTransfer:
            VStack(alignment: .leading, spacing: 6) {
                Text("Destination").font(.appLabel).foregroundStyle(.secondary)
                Text("Fonds voyage").font(.appBody).foregroundStyle(Color.appTextPrimary)
            }
        case .windfall:
            VStack(alignment: .leading, spacing: 6) {
                Text("Répartition auto 80 / 20").font(.appLabel).foregroundStyle(.secondary)
                if let active = activeDebt, amountCents > 0 {
                    Text("\(BudgetFormat.dollars(windfallSplitCents)) → \(active.label) · \(BudgetFormat.dollars(windfallFreeCents)) libres pour toi")
                        .font(.appBody).foregroundStyle(Color.appTextPrimary)
                } else if activeDebt == nil {
                    Text("Aucune dette à rembourser").font(.appCaption).foregroundStyle(.secondary)
                } else {
                    Text("Saisis un montant pour voir la répartition")
                        .font(.appCaption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(type == .windfall ? "Montant total reçu ($)" : "Montant ($)")
                .font(.appLabel).foregroundStyle(.secondary)
            TextField("0.00", text: $amountStr)
                .keyboardType(.decimalPad)
                .font(.appHeadline)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            chipsRow
            envelopeBalanceRow
            if isCorrectionActive {
                Text("Ce montant sera annulé — écris pourquoi")
                    .font(.appCaption).foregroundStyle(Color.appWarning)
            }
        }
    }

    @ViewBuilder private var chipsRow: some View {
        switch type {
        case .fundTransfer where fundChipEligible:
            HStack {
                amountChip(BudgetPlan.fundPerPeriod)
                Spacer()
            }
        case .debtPayment:
            HStack {
                amountChip(attackChipCents)
                Spacer()
            }
        default:
            EmptyView()
        }
    }

    private func amountChip(_ cents: Int) -> some View {
        Button {
            amountStr = String(format: "%.2f", Double(cents) / 100.0)
        } label: {
            Text(BudgetFormat.dollars(cents))
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(Color.appTextPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // Solde live : "Après …" = remaining - effectiveCents.
    // Contre-écriture : effective négatif → after > remaining (crédit explicite).
    @ViewBuilder private var envelopeBalanceRow: some View {
        if type == .expense, let env = selectedEnvelope {
            let after = env.remainingCents - effectiveCents
            let afterTint: Color = {
                if after < 0                  { return .appDanger }
                if after < env.limitCents / 5 { return .appWarning }
                return .secondary
            }()
            VStack(alignment: .leading, spacing: 2) {
                Text("Reste \(BudgetFormat.dollars(env.remainingCents)) / \(BudgetFormat.dollars(env.limitCents))")
                    .font(.appCaption).foregroundStyle(.secondary)
                if amountCents > 0 {
                    let prefix = isCorrectionActive ? "Après cette correction" : "Après cette dépense"
                    Text("\(prefix) : \(BudgetFormat.dollars(after))")
                        .font(.appCaption).foregroundStyle(afterTint)
                }
            }
        }
    }

    @ViewBuilder private var correctionToggle: some View {
        if type != .windfall {
            Toggle(isOn: $isCorrection) {
                Text("Correction")
                    .font(.appLabel).foregroundStyle(Color.appTextPrimary)
            }
            .tint(Color.appWarning)
        }
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date").font(.appLabel).foregroundStyle(.secondary)
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }

    private var noteField: some View {
        let required = isCorrectionActive
        return VStack(alignment: .leading, spacing: 6) {
            Text("Note\(required ? " (obligatoire)" : " (optionnelle)")")
                .font(.appLabel)
                .foregroundStyle(required ? Color.appWarning : .secondary)
            TextField("Ex : Loblaws — courses semaine", text: $note)
                .font(.appBody)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(required ? Color.appWarning : .clear, lineWidth: 1)
                )
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let sendCents: Int
        let sendDebtKey: String?
        let totalCents: Int?
        switch type {
        case .expense:
            sendCents = isCorrectionActive ? -amountCents : amountCents
            sendDebtKey = nil; totalCents = nil
        case .debtPayment:
            sendCents = isCorrectionActive ? -amountCents : amountCents
            sendDebtKey = debtKey; totalCents = nil
        case .fundTransfer:
            sendCents = isCorrectionActive ? -amountCents : amountCents
            sendDebtKey = "fonds_voyage"; totalCents = nil
        case .windfall:
            // 80 % loggé sur la cible active, 20 % non loggé (reste dans la poche).
            sendCents = windfallSplitCents; sendDebtKey = activeDebt?.key; totalCents = amountCents
        }
        let entry = BudgetLogEntry(
            date:         ymdString(date),
            type:         type.serverType,
            amountCents:  sendCents,
            envelopeKey:  type == .expense ? envelopeKey : nil,
            debtKey:      sendDebtKey,
            note:         trimmedNote.isEmpty ? nil : trimmedNote
        )
        do {
            try await APIService.shared.logBudget(entry)
            triggerNotificationFeedback(.success)
            triggerImpact(style: .medium)
            await onSaved(entry, totalCents)
            dismiss()
        } catch {
            errorMessage = "Échec : \(error.localizedDescription)"
        }
    }

    private func ymdString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/Montreal")
        return f.string(from: d)
    }

    private func applyPrefill(_ pt: PlannedTransfer) {
        switch pt.serverType {
        case "fund_transfer": type = .fundTransfer
        case "debt_payment":  type = .debtPayment
        case "expense":       type = .expense
        default: break
        }
        if let dk = pt.debtKey     { debtKey     = dk }
        if let ek = pt.envelopeKey { envelopeKey = ek }
        amountStr = String(format: "%.2f", Double(pt.amountCents) / 100.0)
    }
}
