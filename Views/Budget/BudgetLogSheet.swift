import SwiftUI

struct BudgetLogSheet: View {
    let envelopes: [BudgetEnvelope]
    let debts: [BudgetDebt]
    var onSaved: (BudgetLogEntry) async -> Void

    @Environment(\.dismiss) private var dismiss

    enum LogType: String, CaseIterable, Identifiable {
        case expense       = "Dépense"
        case debtPayment   = "Paiement dette"
        case fundTransfer  = "Fonds voyage"
        var id: String { rawValue }
        var serverType: String {
            switch self {
            case .expense:      return "expense"
            case .debtPayment:  return "debt_payment"
            case .fundTransfer: return "fund_transfer"
            }
        }
    }

    @State private var type: LogType = .expense
    @State private var envelopeKey: String = ""
    @State private var debtKey: String = ""
    @State private var amountStr: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Gère "," et "." pour le clavier iOS FR.
    private var amountDollars: Double {
        Double(amountStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var amountCents: Int { Int((amountDollars * 100).rounded()) }

    private var attackableDebts: [BudgetDebt] { debts.filter { !$0.isSavings } }

    private var canSave: Bool {
        guard amountCents != 0 else { return false }
        if amountCents < 0, note.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        switch type {
        case .expense:      return !envelopeKey.isEmpty
        case .debtPayment:  return !debtKey.isEmpty
        case .fundTransfer: return true
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
                        dateField
                        noteField
                        if let msg = errorMessage {
                            Text(msg)
                                .font(.appCaption)
                                .foregroundStyle(Color.appDanger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        PrimaryButton(title: "Logger", isLoading: isSaving) {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Nouveau log")
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
        }
    }

    private var typePicker: some View {
        Picker("Type", selection: $type) {
            ForEach(LogType.allCases) { Text($0.rawValue).tag($0) }
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
                Text("Cible").font(.appLabel).foregroundStyle(.secondary)
                Text("Fonds voyage").font(.appBody).foregroundStyle(Color.appTextPrimary)
            }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Montant ($)").font(.appLabel).foregroundStyle(.secondary)
            TextField("0.00", text: $amountStr)
                .keyboardType(.numbersAndPunctuation)
                .font(.appHeadline)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            if amountCents < 0 {
                Text("Contre-écriture — note obligatoire")
                    .font(.appCaption).foregroundStyle(Color.appWarning)
            }
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
        let required = amountCents < 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Note\(required ? " (obligatoire)" : " (optionnelle)")")
                .font(.appLabel).foregroundStyle(.secondary)
            TextField("Ex : Loblaws — courses semaine", text: $note)
                .font(.appBody)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let entry = BudgetLogEntry(
            date:         ymdString(date),
            type:         type.serverType,
            amountCents:  amountCents,
            envelopeKey:  type == .expense ? envelopeKey : nil,
            debtKey:      type == .debtPayment ? debtKey
                         : type == .fundTransfer ? "fonds_voyage" : nil,
            note:         trimmedNote.isEmpty ? nil : trimmedNote
        )
        do {
            try await APIService.shared.logBudget(entry)
            triggerNotificationFeedback(.success)
            triggerImpact(style: .medium)
            await onSaved(entry)
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
}
