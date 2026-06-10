import SwiftUI

// MARK: - Overtraining Risk Card

struct OvertrainingRiskCard: View {
    let risk: OvertrainingRisk

    private var riskColor: Color {
        switch risk.level {
        case "high":     return .red
        case "moderate": return .orange
        default:         return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(riskColor)
                Text("RISQUE SURMENAGE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(risk.level.uppercased())
                    .font(.appCaption.weight(.black))
                    .foregroundColor(riskColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(riskColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(riskColor)
                        .frame(width: geo.size.width * CGFloat(min(risk.riskScore, 6)) / 6, height: 6)
                }
            }
            .frame(height: 6)

            if !risk.flags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(risk.flags, id: \.self) { flag in
                        HStack(spacing: 6) {
                            Circle().fill(riskColor).frame(width: 5, height: 5)
                            Text(flag).font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }

            Text(risk.recommendation)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(riskColor.opacity(0.9))
                .padding(8)
                .background(riskColor.opacity(0.08))
                .cornerRadius(8)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Mesocycle Status Card

struct MesocycleStatusCard: View {
    let status: MesocycleStatus

    private var phaseColor: Color {
        switch status.phase {
        case "accumulation":   return .blue
        case "intensification": return .orange
        case "realization":    return .red
        default:               return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status.icon)
                Text("MÉSOCYCLE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(status.phaseLabel.uppercased())
                    .font(.appCaption.weight(.black))
                    .foregroundColor(phaseColor)
            }

            Text(status.description)
                .font(.appLabel).foregroundColor(.white.opacity(0.85))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RPE CIBLE").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    Text(status.rpeTarget).font(.system(size: 14, weight: .black)).foregroundColor(phaseColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("SEMAINE CYCLE").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    Text("S\(status.weekInCycle + 1) / 8").font(.system(size: 14, weight: .black)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("DÉCHARGE DANS").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    Text("\(status.nextDeloadInWeeks) sem").font(.system(size: 14, weight: .black)).foregroundColor(.cyan)
                }
                Spacer()
            }

            Text(status.volGuidance)
                .font(.appCaption).foregroundColor(.gray)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Pain Journal Card

struct PainJournalCard: View {
    let data: PainJournalResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bandage.fill").foregroundColor(.red)
                Text("JOURNAL BLESSURES")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("\(data.byExercise.count) exercices")
                    .font(.appCaption).foregroundColor(.gray)
            }

            ForEach(data.byExercise.prefix(5)) { ex in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.exercise)
                            .font(.appLabel.weight(.semibold)).foregroundColor(.white)
                        Text(ex.zones.joined(separator: " · "))
                            .font(.appCaption).foregroundColor(.red.opacity(0.8))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(ex.count)×")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.orange)
                        if let d = ex.lastDate {
                            Text(String(d.prefix(10)))
                                .font(.system(size: 10)).foregroundColor(.gray)
                        }
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - 1RM Programming Card

struct OneRMProgrammingCard: View {
    let data: OneRMResponse
    @State private var selected: String? = nil
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "percent").foregroundColor(.purple)
                Text("PROGRAMMATION % 1RM")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(data.exercises) { ex in
                        Button {
                            withAnimation { selected = selected == ex.exercise ? nil : ex.exercise }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ex.exercise)
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text("1RM \(units.format(ex.estimated1rm, decimals: 0))")
                                        .font(.system(size: 10)).foregroundColor(.purple)
                                    if let pct = ex.pctOf1rm {
                                        Text(String(format: "· %.0f%%", pct))
                                            .font(.system(size: 10)).foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(10)
                            .background(selected == ex.exercise ? Color.purple.opacity(0.15) : Color.white.opacity(0.05))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == ex.exercise ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            if let selEx = data.exercises.first(where: { $0.exercise == selected }) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(selEx.table) { entry in
                        VStack(spacing: 2) {
                            Text("\(entry.pct)%")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.purple)
                            Text(units.format(entry.weight, decimals: 0))
                                .font(.appLabel.weight(.black)).foregroundColor(.white)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.purple.opacity(0.07))
                        .cornerRadius(8)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }
}
