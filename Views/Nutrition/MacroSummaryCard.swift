import SwiftUI

// MARK: - Macro Summary Card

struct MacroSummaryCard: View {
    let totals: NutritionTotals?
    let settings: NutritionSettings?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CALORIES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.gray)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(Int(totals?.calories ?? 0))")
                            .font(.system(size: 40, weight: .black))
                            .foregroundColor((totals?.calories ?? 0) > (settings?.calories ?? .infinity) ? .red : .orange)
                        if let target = settings?.calories {
                            Text("/ \(Int(target)) kcal")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                if let target = settings?.calories, target > 0 {
                    let pct = min((totals?.calories ?? 0) / target, 1.0)
                    let over = (totals?.calories ?? 0) > target
                    ZStack {
                        Circle().stroke(Color(hex: "191926"), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: pct)
                            .stroke(over ? Color.red : Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(over ? .red : .orange)
                    }
                    .frame(width: 60, height: 60)
                    .animation(.easeOut, value: pct)
                }
            }

            if let target = settings?.calories {
                let pct = min((totals?.calories ?? 0) / target, 1.0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "191926")).frame(height: 6)
                        Capsule()
                            .fill(pct > 1 ? Color.red : Color.orange)
                            .frame(width: geo.size.width * pct, height: 6)
                    }
                }
                .frame(height: 6)
                .animation(.easeOut, value: pct)
            }

            Divider().background(Color.white.opacity(0.07))

            HStack(spacing: 0) {
                MacroBar(label: "Prot", current: totals?.proteines ?? 0, target: settings?.proteines, color: .blue)
                Divider().background(Color.white.opacity(0.07)).frame(height: 40)
                MacroBar(label: "Carbs", current: totals?.glucides ?? 0, target: settings?.glucides, color: .yellow)
                Divider().background(Color.white.opacity(0.07)).frame(height: 40)
                MacroBar(label: "Lip", current: totals?.lipides ?? 0, target: settings?.lipides, color: .pink)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

struct MacroBar: View {
    let label: String
    let current: Double
    let target: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(Int(current))g")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            if let t = target {
                Text("/ \(Int(t))g")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "191926")).frame(height: 4)
                        Capsule()
                            .fill(color)
                            .frame(width: t > 0 ? geo.size.width * min(current / t, 1.0) : 0, height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 8)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
