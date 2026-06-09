import SwiftUI

// MARK: - TrainingHeatmapCard

private let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]

struct TrainingHeatmapCard: View {
    let data: TrainingHeatmapData
    @State private var showDetail = false

    private var bestDayLabel: String {
        guard let idx = data.bestDayIndex, idx < dayLabels.count else { return "—" }
        let full = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        return full[idx]
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("HEATMAP")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    if data.hasData {
                        Text("Fav: \(bestDayLabel)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "34C759").opacity(0.85))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color(hex: "34C759").opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                HeatmapCompactGrid(weeks: data.weeks, bestDayIndex: data.bestDayIndex)
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            TrainingHeatmapDetailSheet(data: data)
        }
    }
}

// MARK: - Compact grid (mini preview, last 8 weeks)

private struct HeatmapCompactGrid: View {
    let weeks: [HeatmapWeek]
    let bestDayIndex: Int?

    private var displayWeeks: [HeatmapWeek] {
        Array(weeks.suffix(8))
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(dayLabels.indices, id: \.self) { i in
                    Text(dayLabels[i])
                        .font(.system(size: 7))
                        .foregroundColor(i == bestDayIndex ? Color(hex: "34C759").opacity(0.7) : .white.opacity(0.20))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(displayWeeks.indices, id: \.self) { wi in
                HStack(spacing: 3) {
                    ForEach(displayWeeks[wi].days.indices, id: \.self) { di in
                        let active = displayWeeks[wi].days[di] > 0
                        let isBest = di == bestDayIndex
                        RoundedRectangle(cornerRadius: 2)
                            .fill(active
                                  ? (isBest ? Color(hex: "34C759") : Color.white.opacity(0.45))
                                  : Color.white.opacity(0.07))
                            .frame(height: 8)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Detail Sheet

private struct TrainingHeatmapDetailSheet: View {
    let data: TrainingHeatmapData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HeatmapSummaryBanner(data: data)
                    HeatmapFullGrid(data: data)
                    HeatmapDayTotals(data: data)
                    HeatmapExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Heatmap d'Entraînement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct HeatmapSummaryBanner: View {
    let data: TrainingHeatmapData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RÉPARTITION DES SÉANCES — 12 SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text(data.message)
                .font(.appCaption).foregroundColor(.white.opacity(0.55))
            Text("\(data.sessionsTracked) séances sur la période")
                .font(.appCaption).foregroundColor(.white.opacity(0.30))
        }
        .padding(14)
        .glassCard()
    }
}

private struct HeatmapFullGrid: View {
    let data: TrainingHeatmapData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GRILLE 12 SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    let fullDays = ["L", "M", "M", "J", "V", "S", "D"]
                    ForEach(fullDays.indices, id: \.self) { i in
                        Text(fullDays[i])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(i == data.bestDayIndex ? Color(hex: "34C759").opacity(0.8) : .white.opacity(0.25))
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(data.weeks.indices, id: \.self) { wi in
                    HStack(spacing: 4) {
                        ForEach(data.weeks[wi].days.indices, id: \.self) { di in
                            let active  = data.weeks[wi].days[di] > 0
                            let isBest  = di == data.bestDayIndex
                            RoundedRectangle(cornerRadius: 3)
                                .fill(active
                                      ? (isBest ? Color(hex: "34C759") : Color.white.opacity(0.50))
                                      : Color.white.opacity(0.06))
                                .frame(height: 14)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct HeatmapDayTotals: View {
    let data: TrainingHeatmapData

    private var maxTotal: Int { data.totalByDay.max() ?? 1 }
    private let fullLabels = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOTAL PAR JOUR")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data.totalByDay.indices, id: \.self) { i in
                    let total  = data.totalByDay[i]
                    let isBest = i == data.bestDayIndex
                    let h      = maxTotal > 0 ? max(8.0, 56.0 * Double(total) / Double(maxTotal)) : 8.0
                    VStack(spacing: 4) {
                        Text("\(total)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(isBest ? .white.opacity(0.70) : .white.opacity(0.28))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isBest ? Color(hex: "34C759") : Color.white.opacity(0.20))
                            .frame(height: h)
                        Text(fullLabels[i])
                            .font(.system(size: 7))
                            .foregroundColor(isBest ? .white.opacity(0.55) : .white.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct HeatmapExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Chaque case représente un jour avec au moins une séance complétée. La grille couvre les 12 dernières semaines (lundi à dimanche). Le jour favori est celui avec le plus grand nombre de séances sur la période.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
