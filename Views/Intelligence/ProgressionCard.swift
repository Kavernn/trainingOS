import SwiftUI

struct ProgressionCard: View {
    let weightsData: [String: WeightData]
    let goal: String?
    @ObservedObject private var units = UnitSettings.shared

    private var isForce: Bool { goal?.lowercased().contains("force") == true }
    private var accent: Color { isForce ? .statusBlue : .teal }
    private var headerLabel: String { isForce ? "FORCE — TOP CHARGES" : "HYPERTROPHIE — PROGRESSION" }
    private var headerIcon: String { isForce ? "bolt.fill" : "arrow.up.right" }

    private struct LiftRow: Identifiable {
        var id: String { name }
        let name: String
        let currentWeight: Double
        let delta: Double?
    }

    private var topLifts: [LiftRow] {
        let iso30dAgo = DateFormatter.isoDate.string(
            from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 30 * 86400))
        let rows: [LiftRow] = weightsData.compactMap { name, data in
            guard let cw = data.currentWeight else { return nil }
            var delta: Double? = nil
            if let hist = data.history, hist.count >= 2 {
                let old = hist.filter { ($0.date ?? "9999") <= iso30dAgo }
                    .max(by: { ($0.date ?? "") < ($1.date ?? "") })
                if let oldW = old?.weight { delta = cw - oldW }
            }
            return LiftRow(name: name, currentWeight: cw, delta: delta)
        }
        return Array(rows.sorted { a, b in
            if isForce { return a.currentWeight > b.currentWeight }
            let da = a.delta ?? -999, db = b.delta ?? -999
            return abs(da - db) > 0.01 ? da > db : a.currentWeight > b.currentWeight
        }.prefix(3))
    }

    var body: some View {
        let lifts = topLifts
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: headerIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accent)
                Text(headerLabel)
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .foregroundColor(accent)
            }
            ForEach(lifts) { lift in
                liftRow(lift)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func liftRow(_ lift: LiftRow) -> some View {
        HStack {
            Text(lift.name)
                .font(.appLabel)
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
            Spacer()
            if let delta = lift.delta, abs(delta) > 0.5 {
                Text(delta > 0 ? "+\(units.format(delta, decimals: 0))" : units.format(delta, decimals: 0))
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(delta > 0 ? .statusGreen : .statusOrange)
                    .padding(.trailing, 6)
            }
            Text(units.format(lift.currentWeight, decimals: 0))
                .font(.appLabel.weight(.bold))
                .foregroundColor(.appTextPrimary)
        }
    }
}
