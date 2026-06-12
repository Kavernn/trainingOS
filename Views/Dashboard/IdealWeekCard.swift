import SwiftUI

// MARK: - IdealWeekCard (Dashboard compact)

struct IdealWeekCard: View {
    let data: IdealWeekData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            IdealWeekDetailSheet(data: data)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            statsRow
            if !data.gaps.isEmpty {
                gapChips
            }
        }
        .padding(14)
        .glassCard()
    }

    private var matchColor: Color {
        guard let m = data.matchPct else { return .white.opacity(0.40) }
        if m >= 80 { return .forge }
        if m >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("SEMAINE IDÉALE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            if let m = data.matchPct {
                Text("\(m)%")
                    .font(.appLabel.weight(.black))
                    .foregroundColor(matchColor)
            }
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            if let cur = data.currentWeek, let best = data.bestWeek {
                WeekStatMini(icon: "figure.strengthtraining.traditional",
                             current: cur.trainingDays, ideal: best.trainingDays, unit: "séances")
                WeekStatMini(icon: "moon.zzz.fill",
                             current: cur.goodSleep, ideal: best.goodSleep, unit: "nuits ≥7h30")
                WeekStatMini(icon: "fork.knife.circle.fill",
                             current: cur.nutritionDays, ideal: best.nutritionDays, unit: "jours nutrition")
            }
        }
    }

    private var gapChips: some View {
        HStack(spacing: 6) {
            ForEach(data.gaps.prefix(3), id: \.key) { gap in
                HStack(spacing: 3) {
                    Image(systemName: gap.icon)
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(Int(gap.current))/\(Int(gap.ideal))")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color.trendNeutral.opacity(0.85))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.trendNeutral.opacity(0.10))
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Compact stat column

private struct WeekStatMini: View {
    let icon: String
    let current: Int
    let ideal: Int
    let unit: String

    private var ratio: Double { ideal > 0 ? Double(current) / Double(ideal) : 0 }
    private var color: Color {
        if ratio >= 0.8 { return .forge }
        if ratio >= 0.5 { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(current)")
                    .font(.appLabel.weight(.bold))
                    .foregroundColor(color)
                Text("/\(ideal)")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.30))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Detail Sheet

private struct IdealWeekDetailSheet: View {
    let data: IdealWeekData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let match = data.matchPct {
                        MatchBanner(matchPct: match, totalWeeks: data.totalWeeks)
                    }
                    if let best = data.bestWeek, let cur = data.currentWeek {
                        ComparisonCard(best: best, current: cur)
                    }
                    if !data.gaps.isEmpty {
                        GapsCard(gaps: data.gaps)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Semaine Idéale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct MatchBanner: View {
    let matchPct: Int
    let totalWeeks: Int

    private var matchColor: Color {
        if matchPct >= 80 { return .forge }
        if matchPct >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ALIGNEMENT CETTE SEMAINE")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text("vs ta meilleure semaine sur \(totalWeeks)")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.50))
            }
            Spacer()
            Text("\(matchPct)%")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(matchColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct ComparisonCard: View {
    let best: WeekProfile
    let current: WeekProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COMPARAISON")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Text("Actuel")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.forge.opacity(0.80))
                    .frame(width: 50, alignment: .trailing)
                Text("Record")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 50, alignment: .trailing)
            }

            CompRow(icon: "figure.strengthtraining.traditional", label: "Séances",
                    current: Double(current.trainingDays), ideal: Double(best.trainingDays),
                    format: "%.0f")
            CompRow(icon: "moon.zzz.fill", label: "Nuits ≥7h30",
                    current: Double(current.goodSleep), ideal: Double(best.goodSleep),
                    format: "%.0f")
            CompRow(icon: "fork.knife.circle.fill", label: "Jours nutrition",
                    current: Double(current.nutritionDays), ideal: Double(best.nutritionDays),
                    format: "%.0f")
            if let ca = current.avgSleep, let ba = best.avgSleep {
                CompRow(icon: "clock.fill", label: "Sommeil moy.",
                        current: ca, ideal: ba, format: "%.1fh")
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct CompRow: View {
    let icon: String
    let label: String
    let current: Double
    let ideal: Double
    let format: String

    private var ratio: Double { ideal > 0 ? current / ideal : 1 }
    private var curColor: Color {
        if ratio >= 0.8 { return .forge }
        if ratio >= 0.5 { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 16)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.65))
            Spacer()
            Text(String(format: format, current))
                .font(.appCaption.weight(.bold))
                .foregroundColor(curColor)
                .frame(width: 50, alignment: .trailing)
            Text(String(format: format, ideal))
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 50, alignment: .trailing)
        }
    }
}

private struct GapsCard: View {
    let gaps: [WeekGap]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AXES D'AMÉLIORATION")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            ForEach(gaps, id: \.key) { gap in
                HStack(spacing: 10) {
                    Image(systemName: gap.icon)
                        .font(.appLabel)
                        .foregroundColor(Color.trendNeutral.opacity(0.80))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gap.label)
                            .font(.appLabel.weight(.medium))
                            .foregroundColor(.white.opacity(0.75))
                        Text("\(Int(gap.current)) cette semaine vs \(Int(gap.ideal)) lors de ta meilleure")
                            .font(.appMicro)
                            .foregroundColor(.white.opacity(0.32))
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}
