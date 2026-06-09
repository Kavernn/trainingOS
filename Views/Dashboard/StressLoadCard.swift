import SwiftUI

// MARK: - StressLoadCard

struct StressLoadCard: View {
    let data: StressLoadData
    @State private var showDetail = false

    private var dominantLabel: String {
        switch data.dominant {
        case "training": return "Physique"
        case "pss":      return "Mental"
        case "balanced": return "Équilibré"
        default:         return "—"
        }
    }

    private var trendColor: Color {
        switch data.trend {
        case "rising":  return Color(hex: "FF6B6B")
        case "falling": return Color(hex: "34C759")
        default:        return Color(hex: "FF9500")
        }
    }

    private var trendIcon: String {
        switch data.trend {
        case "rising":  return "arrow.up.right"
        case "falling": return "arrow.down.right"
        default:        return "arrow.right"
        }
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("STRESS INDEX")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    if data.hasData {
                        HStack(spacing: 4) {
                            Image(systemName: trendIcon).font(.system(size: 9, weight: .semibold))
                            Text(dominantLabel).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(trendColor.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(trendColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CHARGE COMBINÉE")
                            .font(.appMicro).tracking(0.8)
                            .foregroundColor(.white.opacity(0.28))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            let combined = data.weeks.last?.combined
                            Text(combined.map { "\($0)" } ?? "—")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(trendColor)
                            Text("/100")
                                .font(.appCaption).foregroundColor(.white.opacity(0.30))
                        }
                    }
                    Spacer()
                    StressLoadMiniChart(weeks: data.weeks)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            StressLoadDetailSheet(data: data)
        }
    }
}

// MARK: - Mini chart

private struct StressLoadMiniChart: View {
    let weeks: [StressLoadWeek]

    private var maxVal: Int {
        weeks.map(\.combined).max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(weeks.indices, id: \.self) { i in
                let isLast = i == weeks.count - 1
                let h = maxVal > 0 ? max(4.0, 36.0 * Double(weeks[i].combined) / Double(maxVal)) : 4.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLast ? Color(hex: "FF9500") : Color.white.opacity(0.20))
                    .frame(width: 10, height: h)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct StressLoadDetailSheet: View {
    let data: StressLoadData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    StressLoadBanner(data: data)
                    StressLoadWeeksChart(weeks: data.weeks)
                    StressLoadExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Stress Load Index")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct StressLoadBanner: View {
    let data: StressLoadData

    private var trendColor: Color {
        switch data.trend {
        case "rising":  return Color(hex: "FF6B6B")
        case "falling": return Color(hex: "34C759")
        default:        return Color(hex: "FF9500")
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STRESS LOAD INDEX")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                if let t = data.currentTrainingStress, let p = data.currentPssStress {
                    Text("Physique : \(t)/100 · Mental : \(p)/100")
                        .font(.appCaption).foregroundColor(.white.opacity(0.50))
                }
                Text(data.message)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(data.weeks.last.map { "\($0.combined)" } ?? "—")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(trendColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct StressLoadWeeksChart: View {
    let weeks: [StressLoadWeek]

    private var maxVal: Int { weeks.map(\.combined).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("5 DERNIÈRES SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeks.indices, id: \.self) { i in
                    let w = weeks[i]
                    let isLast = i == weeks.count - 1
                    let h = maxVal > 0 ? max(8.0, 60.0 * Double(w.combined) / Double(maxVal)) : 8.0
                    VStack(spacing: 4) {
                        Text("\(w.combined)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(isLast ? .white.opacity(0.65) : .white.opacity(0.28))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? Color(hex: "FF9500") : Color.white.opacity(0.20))
                            .frame(height: h)
                        Text("S\(i + 1)")
                            .font(.system(size: 7))
                            .foregroundColor(isLast ? .white.opacity(0.50) : .white.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 84, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct StressLoadExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Deux signaux combinés : la charge d'entraînement (RPE hebdo normalisé 0–100) et le stress perçu PSS-4 (normalisé 0–100). Le dominant est le signal le plus élevé (>15 pts d'écart).")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
