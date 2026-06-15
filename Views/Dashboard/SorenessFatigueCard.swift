import SwiftUI

// MARK: - SorenessFatigueCard

struct SorenessFatigueCard: View {
    let data: SorenessFatigueData
    @State private var showDetail = false

    private var alertColor: Color {
        data.overreachingWeeks >= 2 ? Color.trendNegative : Color.trendNeutral
    }

    private var statusLabel: String {
        if data.overreachingWeeks >= 2 { return "Surmenage" }
        if data.sorenessTrend == "worsening" || data.fatigueTrend == "worsening" { return "En hausse" }
        if data.sorenessTrend == "improving" && data.fatigueTrend == "improving" { return "En baisse" }
        return "Stable"
    }

    private var statusColor: Color {
        if data.overreachingWeeks >= 2 { return Color.trendNegative }
        if data.sorenessTrend == "worsening" || data.fatigueTrend == "worsening" { return Color.trendNeutral }
        if data.sorenessTrend == "improving" && data.fatigueTrend == "improving" { return Color.trendPositive }
        return .gray
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("COURBATURES & FATIGUE")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(Color.appOnSurface.opacity(0.35))
                    Spacer()
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusColor.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(Color.appOnSurface.opacity(0.22))
                }

                HStack(spacing: 16) {
                    RecoveryGauge(label: "COURBATURES", value: data.currentSoreness, color: Color.trendNeutral)
                    RecoveryGauge(label: "FATIGUE",     value: data.currentFatigue,  color: Color.trendNegative)
                    Spacer()
                    SorenessDualSparkline(soreness: data.weeklySoreness, fatigue: data.weeklyFatigue)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SorenessFatigueDetailSheet(data: data)
        }
    }
}

private struct RecoveryGauge: View {
    let label: String
    let value: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.appMicro).tracking(0.6)
                .foregroundColor(Color.appOnSurface.opacity(0.28))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text("/10")
                    .font(.appCaption).foregroundColor(Color.appOnSurface.opacity(0.28))
            }
        }
    }
}

private struct SorenessDualSparkline: View {
    let soreness: [WeeklyRecoveryAvg]
    let fatigue:  [WeeklyRecoveryAvg]

    private var maxVal: Double {
        let sv = soreness.compactMap(\.avg).max() ?? 10
        let fv = fatigue.compactMap(\.avg).max() ?? 10
        return max(sv, fv, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(soreness.indices, id: \.self) { i in
                let sv = soreness[i].avg ?? 0
                let fv = i < fatigue.count ? (fatigue[i].avg ?? 0) : 0
                let sh = max(3.0, 32.0 * sv / maxVal)
                let fh = max(3.0, 32.0 * fv / maxVal)
                VStack(alignment: .center, spacing: 1) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.trendNeutral.opacity(0.7))
                        .frame(width: 3, height: sh)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.trendNegative.opacity(0.7))
                        .frame(width: 3, height: fh)
                }
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct SorenessFatigueDetailSheet: View {
    let data: SorenessFatigueData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SorenessBanner(data: data)
                    SorenessWeeklyChart(title: "COURBATURES / SEMAINE", weeks: data.weeklySoreness, color: Color.trendNeutral)
                    SorenessWeeklyChart(title: "FATIGUE / SEMAINE",     weeks: data.weeklyFatigue,  color: Color.trendNegative)
                    SorenessExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Courbatures & Fatigue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct SorenessBanner: View {
    let data: SorenessFatigueData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SURMENAGE & RÉCUPÉRATION")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.35))
            if data.overreachingWeeks > 0 {
                Text("\(data.overreachingWeeks) sem. de surmenage détectées (courbatures + fatigue > 6)")
                    .font(.appCaption).foregroundColor(Color.trendNegative.opacity(0.85))
            }
            Text(data.message)
                .font(.appCaption).foregroundColor(Color.appOnSurface.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}

private struct SorenessWeeklyChart: View {
    let title: String
    let weeks: [WeeklyRecoveryAvg]
    let color: Color

    private var maxVal: Double { weeks.compactMap(\.avg).max() ?? 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.35))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeks.indices, id: \.self) { i in
                    let isLast = i == weeks.count - 1
                    let v = weeks[i].avg ?? 0
                    let h = maxVal > 0 ? max(6.0, 56.0 * v / maxVal) : 6.0
                    VStack(spacing: 4) {
                        Text(weeks[i].avg.map { String(format: "%.0f", $0) } ?? "—")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(isLast ? Color.appOnSurface.opacity(0.65) : Color.appOnSurface.opacity(0.25))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? color : color.opacity(0.35))
                            .frame(height: h)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 72, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct SorenessExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.35))
            Text("Moyenne hebdomadaire des scores de courbatures et de fatigue perçue (1–10) issus des recovery logs. Une semaine de surmenage = courbatures ET fatigue > 6 en moyenne sur la semaine.")
                .font(.appCaption).foregroundColor(Color.appOnSurface.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
