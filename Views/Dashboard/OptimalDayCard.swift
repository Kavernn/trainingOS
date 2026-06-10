import SwiftUI

// MARK: - OptimalDayCard (Dashboard compact)

struct OptimalDayCard: View {
    let data: OptimalDayData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: { cardContent }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                OptimalDayDetailSheet(data: data)
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            heatmapRow
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("JOUR OPTIMAL")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            if let best = data.bestDay {
                BestDayBadge(label: data.byDay.first(where: { $0.dow == best })?.short ?? "—")
            }
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var heatmapRow: some View {
        HStack(spacing: 4) {
            ForEach(data.byDay, id: \.dow) { day in
                DayDot(day: day, isBest: day.dow == data.bestDay)
            }
        }
    }
}

// MARK: - Sub-views

private struct BestDayBadge: View {
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.appMicro.weight(.semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color.trendPositive.opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.trendPositive.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct DayDot: View {
    let day: DayStats
    let isBest: Bool

    private var intensity: Double {
        guard let rpe = day.avgRpe else { return 0 }
        return min(1.0, rpe / 10.0)
    }

    private var dotColor: Color {
        guard day.hasData else { return .white.opacity(0.07) }
        if isBest { return Color.trendPositive }
        return Color.trendNeutral.opacity(0.4 + intensity * 0.6)
    }

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(dotColor)
                .frame(height: isBest ? 28 : max(8, 24 * intensity))
            Text(day.short)
                .font(.system(size: 7))
                .foregroundColor(isBest ? .white.opacity(0.65) : .white.opacity(0.28))
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct OptimalDayDetailSheet: View {
    let data: OptimalDayData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    BestDayBanner(data: data)
                    DayBreakdownCard(data: data)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Jour Optimal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct BestDayBanner: View {
    let data: OptimalDayData
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TON MEILLEUR JOUR")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                if let rpe = data.bestDayRpe {
                    Text("RPE moyen \(String(format: "%.1f", rpe))")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.55))
                }
                Text("Basé sur \(data.sessionsAnalyzed) séances")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.38))
            }
            Spacer()
            Text(data.bestDayLabel)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(Color.trendPositive)
        }
        .padding(14)
        .glassCard()
    }
}

private struct DayBreakdownCard: View {
    let data: OptimalDayData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PAR JOUR DE SEMAINE")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Text("RPE moy.")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 55, alignment: .trailing)
                Text("Séances")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 50, alignment: .trailing)
            }
            ForEach(data.byDay, id: \.dow) { day in
                DayDetailRow(day: day, isBest: day.dow == data.bestDay, isWorst: day.dow == data.worstDay)
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct DayDetailRow: View {
    let day: DayStats
    let isBest: Bool
    let isWorst: Bool

    private var accent: Color {
        if isBest  { return Color.trendPositive }
        if isWorst { return Color.trendNegative }
        return .white.opacity(0.65)
    }

    var body: some View {
        HStack(spacing: 8) {
            if isBest {
                Image(systemName: "star.fill")
                    .font(.appMicro)
                    .foregroundColor(Color.trendPositive)
            } else if isWorst && day.hasData {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.appMicro)
                    .foregroundColor(Color.trendNegative)
            } else {
                Circle().fill(Color.clear).frame(width: 9)
            }
            Text(day.label)
                .font(.appCaption)
                .foregroundColor(accent)
            Spacer()
            Text(day.avgRpe.map { String(format: "%.1f", $0) } ?? "—")
                .font(.appCaption.weight(.bold))
                .foregroundColor(accent)
                .frame(width: 55, alignment: .trailing)
            Text(day.hasData ? "\(day.sessionCount)" : "—")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 50, alignment: .trailing)
        }
    }
}
