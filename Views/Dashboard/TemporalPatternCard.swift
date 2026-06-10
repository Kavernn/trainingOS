import SwiftUI

// MARK: - TemporalPatternCard (Dashboard compact)

struct TemporalPatternCard: View {
    let data: TemporalPatterns
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            TemporalDetailSheet(data: data)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RYTHME HEBDOMADAIRE")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.22))
            }

            HStack(alignment: .top, spacing: 0) {
                // Weakest day
                VStack(alignment: .leading, spacing: 2) {
                    Text("POINT FAIBLE")
                        .font(.appMicro).tracking(0.8)
                        .foregroundColor(.white.opacity(0.28))
                    Text(data.weakestDay.capitalized)
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(Color.trendNegative)
                }
                Spacer()
                // Strongest day
                VStack(alignment: .trailing, spacing: 2) {
                    Text("POINT FORT")
                        .font(.appMicro).tracking(0.8)
                        .foregroundColor(.white.opacity(0.28))
                    Text(data.strongestDay.capitalized)
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(.forge)
                }
            }

            WeekdayBarsCompact(
                orderedScores: data.orderedDayScores,
                weakestDay: data.weakestDay
            )

            if !data.suggestion.isEmpty {
                Text(data.suggestion)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Weekday Bars (compact)

private struct WeekdayBarsCompact: View {
    let orderedScores: [(String, Double)]
    let weakestDay: String

    private let shorts = ["LU", "MA", "ME", "JE", "VE", "SA", "DI"]
    private let fulls  = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    private func shortLabel(_ day: String) -> String {
        guard let i = fulls.firstIndex(of: day), i < shorts.count else {
            return String(day.prefix(2)).uppercased()
        }
        return shorts[i]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(orderedScores, id: \.0) { (day, score) in
                let isWeakest = day == weakestDay
                let barColor: Color = isWeakest ? Color.trendNegative : Color.forge.opacity(0.55)
                let height = max(8.0, 36.0 * score)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: 14, height: height)
                    Text(shortLabel(day))
                        .font(.system(size: 7, weight: isWeakest ? .black : .regular))
                        .foregroundColor(isWeakest ? Color.trendNegative : .white.opacity(0.32))
                }
            }
        }
        .frame(height: 52, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct TemporalDetailSheet: View {
    let data: TemporalPatterns
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {

                    WeekdayBarsFull(
                        orderedScores: data.orderedDayScores,
                        weakestDay: data.weakestDay,
                        strongestDay: data.strongestDay,
                        details: data.dayDetails
                    )

                    if !data.suggestion.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("INTERVENTION RECOMMANDÉE")
                                .font(.appMicro.weight(.black)).tracking(1.5)
                                .foregroundColor(.white.opacity(0.35))
                            Text(data.suggestion)
                                .font(.appBody)
                                .foregroundColor(.white.opacity(0.80))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .glassCard()
                    }

                    if !data.weakestFactors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FACTEURS IDENTIFIÉS")
                                .font(.appMicro.weight(.black)).tracking(1.5)
                                .foregroundColor(.white.opacity(0.35))
                            ForEach(data.weakestFactors, id: \.self) { f in
                                FactorRow(factor: f)
                            }
                        }
                        .padding(14)
                        .glassCard()
                    }

                    DayDetailTable(
                        orderedScores: data.orderedDayScores,
                        details: data.dayDetails,
                        weakestDay: data.weakestDay
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Rythme Hebdomadaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Full Bar Chart (sheet)

private struct WeekdayBarsFull: View {
    let orderedScores: [(String, Double)]
    let weakestDay: String
    let strongestDay: String
    let details: [String: DayDetail]

    private let shorts = ["LU", "MA", "ME", "JE", "VE", "SA", "DI"]
    private let fulls  = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    private func shortLabel(_ day: String) -> String {
        guard let i = fulls.firstIndex(of: day), i < shorts.count else {
            return String(day.prefix(2)).uppercased()
        }
        return shorts[i]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCORE PAR JOUR (90 DERNIERS JOURS)")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(orderedScores, id: \.0) { (day, score) in
                    let isWeakest  = day == weakestDay
                    let isStrongest = day == strongestDay
                    let barColor: Color = isWeakest ? Color.trendNegative
                        : (isStrongest ? Color.forge : Color.forge.opacity(0.45))
                    let height = max(12.0, 80.0 * score)
                    VStack(spacing: 4) {
                        Text("\(Int(score * 100))%")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(barColor.opacity(0.8))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor)
                            .frame(height: height)
                        Text(shortLabel(day))
                            .font(.system(size: 9, weight: isWeakest || isStrongest ? .black : .regular))
                            .foregroundColor(isWeakest ? Color.trendNegative : (isStrongest ? .forge : .white.opacity(0.38)))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Factor Row

private struct FactorRow: View {
    let factor: String

    private var icon: String {
        switch factor {
        case "workout_absent":    return "figure.strengthtraining.traditional"
        case "stress_élevé":      return "brain.head.profile"
        case "nutrition_absente": return "fork.knife"
        default:                  return "exclamationmark.circle"
        }
    }

    private var label: String {
        switch factor {
        case "workout_absent":    return "Entraînement souvent absent"
        case "stress_élevé":      return "Niveau de stress plus élevé"
        case "nutrition_absente": return "Nutrition rarement loggée"
        default:                  return factor
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.appLabel)
                .foregroundColor(Color.trendNegative.opacity(0.80))
                .frame(width: 20)
            Text(label)
                .font(.appLabel)
                .foregroundColor(.white.opacity(0.75))
        }
    }
}

// MARK: - Day Detail Table

private struct DayDetailTable: View {
    let orderedScores: [(String, Double)]
    let details: [String: DayDetail]
    let weakestDay: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DÉTAIL PAR JOUR")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            ForEach(orderedScores, id: \.0) { (day, score) in
                if let detail = details[day] {
                    let isWeakest = day == weakestDay
                    HStack(spacing: 12) {
                        Text(day.capitalized)
                            .font(.appLabel.weight(isWeakest ? .bold : .regular))
                            .foregroundColor(isWeakest ? Color.trendNegative : .white.opacity(0.70))
                            .frame(width: 80, alignment: .leading)
                        DayMetricChip(
                            value: "\(Int(detail.workoutRate * 100))%",
                            icon: "flame.fill",
                            color: Color.forge
                        )
                        DayMetricChip(
                            value: "\(Int(detail.nutritionRate * 100))%",
                            icon: "fork.knife",
                            color: .green
                        )
                        if let pss = detail.pssAvg {
                            DayMetricChip(
                                value: "\(Int(pss))",
                                icon: "brain.head.profile",
                                color: pss > 20 ? Color.trendNegative : .forge
                            )
                        }
                        Spacer()
                        Text("\(Int(score * 100))%")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct DayMetricChip: View {
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(value)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color.opacity(0.85))
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}
