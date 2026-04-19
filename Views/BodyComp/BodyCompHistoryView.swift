import SwiftUI
import SwiftData
import Charts

struct BodyCompHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyCompEntry.date, order: .reverse) private var entries: [BodyCompEntry]

    var body: some View {
        ZStack {
            AmbientBackground(color: .green)

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if entries.count >= 2 {
                            chartCard
                                .appearAnimation(delay: 0.05)
                        }
                        historyList
                            .appearAnimation(delay: 0.1)
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("% MASSE GRASSE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            let sorted = entries.sorted { $0.date < $1.date }

            Chart(sorted) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("% MG", entry.bodyFatPct)
                )
                .foregroundStyle(Color.green.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", entry.date),
                    y: .value("% MG", entry.bodyFatPct)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.green.opacity(0.25), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("% MG", entry.bodyFatPct)
                )
                .foregroundStyle(Color.green)
                .symbolSize(28)
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f%%", v))
                                .font(.system(size: 10)).foregroundColor(.gray)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 10)).foregroundColor(.gray)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .glassCardAccent(.green)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - History list

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ENTRÉES")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                .padding(.horizontal, 16)

            ForEach(entries) { entry in
                historyRow(entry)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func historyRow(_ entry: BodyCompEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, style: .date)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(entry.date, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Text(String(format: "%.1f%%", entry.bodyFatPct))
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.blue)
                }
                HStack(spacing: 10) {
                    Label(String(format: "%.1f", entry.fatMassLbs), systemImage: "")
                        .font(.system(size: 11)).foregroundColor(.orange)
                    Label(String(format: "%.1f lbs", entry.leanMassLbs), systemImage: "")
                        .font(.system(size: 11)).foregroundColor(.green)
                }
            }
        }
        .padding(14)
        .glassCard(color: .green, intensity: 0.04)
        .cornerRadius(14)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelContext.delete(entry)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.arms.open")
                .font(.system(size: 48))
                .foregroundColor(.green.opacity(0.5))
            Text("Aucune mesure enregistrée")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray)
            Text("Utilise le calculateur pour enregistrer ta première composition corporelle.")
                .font(.system(size: 13))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
