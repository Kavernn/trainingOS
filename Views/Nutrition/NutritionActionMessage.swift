import SwiftUI

// MARK: - Nutrition Action Message

struct NutritionActionMessage: View {
    let totals: NutritionTotals?
    let settings: NutritionSettings?
    let hasEntries: Bool
    var onAddMeal: (() -> Void)? = nil

    private enum MsgState {
        case noEntries
        case proteinLow(Int)
        case proteinClose(Int)
        case proteinOnTarget(consumed: Int, target: Int)
        case allOnTarget
    }

    private var msgState: MsgState? {
        guard let pTarget = settings?.proteines, pTarget > 0 else { return nil }
        guard hasEntries else { return .noEntries }
        let consumed = totals?.proteines ?? 0
        let ratio = consumed / pTarget
        if ratio < 0.70 { return .proteinLow(Int(pTarget - consumed)) }
        if ratio < 0.90 { return .proteinClose(Int(pTarget - consumed)) }
        let calConsumed = Int(totals?.calories ?? 0)
        let calTarget   = Int(settings?.calories ?? 0)
        let calRatio    = calTarget > 0 ? Double(calConsumed) / Double(calTarget) : 1.0
        if calRatio >= 0.90 { return .allOnTarget }
        return .proteinOnTarget(consumed: calConsumed, target: calTarget)
    }

    var body: some View {
        if let state = msgState {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(msgColor(state))
                        .frame(width: 8, height: 8)
                    Text(msgText(state))
                        .font(.appBody.weight(.bold))
                        .foregroundColor(msgColor(state))
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .noEntries = state, let action = onAddMeal {
                    Button(action: action) {
                        Text("Logger un repas")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(Color.forge)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.forge.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.forge.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(msgColor(state).opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(msgColor(state).opacity(0.2), lineWidth: 1))
        }
    }

    private func msgText(_ state: MsgState) -> String {
        switch state {
        case .noEntries:                          return "Premier repas de la journée ?\nLogue-le en 10 secondes."
        case .proteinLow(let g):                  return "Il te manque \(g)g de protéines aujourd'hui."
        case .proteinClose(let g):                return "Encore \(g)g de protéines pour atteindre ton objectif."
        case .proteinOnTarget(let c, let t):      return "Protéines sur cible. Calories : \(c) / \(t) kcal."
        case .allOnTarget:                        return "Objectifs nutrition atteints aujourd'hui."
        }
    }

    private func msgColor(_ state: MsgState) -> Color {
        switch state {
        case .noEntries:       return .gray
        case .proteinLow:      return Color.appDanger
        case .proteinClose:    return Color.appWarning
        case .proteinOnTarget: return Color.statusBlue
        case .allOnTarget:     return Color.appSuccess
        }
    }
}
