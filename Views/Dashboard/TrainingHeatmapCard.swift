import SwiftUI

// MARK: - TrainingHeatmapCard

private let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]

struct TrainingHeatmapCard: View {
    let data: TrainingHeatmapData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("HEATMAP")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                HeatmapCompactGrid(weeks: data.weeks)
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

    private var displayWeeks: [HeatmapWeek] {
        Array(weeks.suffix(8))
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(dayLabels.indices, id: \.self) { i in
                    Text(dayLabels[i])
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(0.20))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(displayWeeks.indices, id: \.self) { wi in
                HStack(spacing: 3) {
                    ForEach(displayWeeks[wi].days.indices, id: \.self) { di in
                        let active = displayWeeks[wi].days[di] > 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(active ? Color.white.opacity(0.45) : Color.white.opacity(0.07))
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
                    HeatmapAdherenceChart(data: data)
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
            Text("HEATMAP — 12 SEMAINES")
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
                            .font(.appMicro.weight(.medium))
                            .foregroundColor(.white.opacity(0.25))
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(data.weeks.indices, id: \.self) { wi in
                    HStack(spacing: 4) {
                        ForEach(data.weeks[wi].days.indices, id: \.self) { di in
                            let active = data.weeks[wi].days[di] > 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(active ? Color.white.opacity(0.50) : Color.white.opacity(0.06))
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

// MARK: - Adherence Chart (replaces day totals bar chart)

private struct HeatmapAdherenceChart: View {
    let data: TrainingHeatmapData

    private let allLabels = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    private func adherenceColor(_ rate: Double) -> Color {
        if rate >= 0.85 { return Color.trendPositive }
        if rate >= 0.70 { return Color.forge }
        return Color.trendNegative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADHÉRENCE AU PLAN")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            let entries = data.trainingDayAdherence

            if entries.isEmpty {
                Text("Programme non configuré — configure ton programme pour voir l'adhérence par jour.")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(entries, id: \.dayIndex) { item in
                        let color = adherenceColor(item.entry.rate)
                        let h = max(8.0, 56.0 * item.entry.rate)
                        VStack(spacing: 4) {
                            Text("\(Int(item.entry.rate * 100))%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(color.opacity(0.80))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(height: h)
                            Text(allLabels[item.dayIndex])
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.45))
                            Text("\(item.entry.actual)/\(item.entry.planned)")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.28))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 90, alignment: .bottom)
            }
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
            Text("Chaque case représente un jour avec au moins une séance complétée. La grille couvre les 12 dernières semaines. L'adhérence mesure le ratio séances réalisées / jours d'entraînement planifiés — les jours de repos sont exclus.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
