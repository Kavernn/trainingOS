import SwiftUI

struct SeasonReportView: View {
    let report: SeasonReport
    @ObservedObject private var units = UnitSettings.shared
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                divider
                headlineSection
                divider
                bodySection
                divider
                spiritSection
                divider
                warSection
                divider
                habitSection
                divider
                verdictSection
                if let note = report.season.personalNote, !note.isEmpty {
                    divider
                    noteSection(note)
                }
                Spacer(minLength: 60)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.title)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(arcColor)
                .tracking(1)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: appeared)

            if !report.season.startFormatted.isEmpty {
                Text("\(report.season.startFormatted) → \(report.season.endFormatted)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .tracking(1)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: appeared)
            }
        }
        .padding(.bottom, 24)
        .onAppear { appeared = true }
    }

    // MARK: Headline

    private var headlineSection: some View {
        Text(report.headlineDelta)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.primary)
            .padding(.vertical, 20)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)
    }

    // MARK: Body (physical)

    private var bodySection: some View {
        reportSection(label: "LE CORPS", delay: 0.3) {
            if let sw = report.startSnapshot?.weightLbs, let ew = report.endSnapshot?.weightLbs {
                deltaRow("Poids", from: units.format(sw, decimals: 0), to: units.format(ew, decimals: 0),
                         delta: ew - sw, unit: units.label, lowerIsBetter: false)
            }
            if let sbf = report.startSnapshot?.bodyFatPct, let ebf = report.endSnapshot?.bodyFatPct {
                deltaRow("Body fat", from: "\(String(format: "%.1f", sbf))%",
                         to: "\(String(format: "%.1f", ebf))%",
                         delta: ebf - sbf, unit: "%", lowerIsBetter: true)
            }
            let prs = report.stats.prsBroken
            if !prs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRs tombés : \(prs.count)")
                        .font(.appLabel.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    ForEach(prs.prefix(5), id: \.exercise) { pr in
                        HStack {
                            Text("• \(pr.exercise)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondary)
                            Spacer()
                            Text("\(units.format(pr.oldWeightLbs, decimals: 0)) → \(units.format(pr.newWeightLbs, decimals: 0))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.green)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: Spirit (Phoenix + PSS)

    private var spiritSection: some View {
        reportSection(label: "L'ESPRIT", delay: 0.4) {
            if let sp = report.startSnapshot?.pssScore, let ep = report.endSnapshot?.pssScore {
                deltaRow("PSS", from: "\(sp)", to: "\(ep)",
                         delta: Double(ep - sp), unit: "", lowerIsBetter: true)
            }
            if let sph = report.startSnapshot?.phoenixAvg, let eph = report.endSnapshot?.phoenixAvg {
                deltaRow("Phoenix Score", from: "\(String(format: "%.1f", sph))",
                         to: "\(String(format: "%.1f", eph))",
                         delta: eph - sph, unit: "pts", lowerIsBetter: false)
            }
        }
    }

    // MARK: War Room

    private var warSection: some View {
        reportSection(label: "LE COMBAT", delay: 0.5) {
            let s = report.stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(s.warRoomVictories) victoires")
                        .font(.system(size: 14, weight: .semibold))
                    Text("sur \(s.warRoomBattles) batailles")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.warRoomBestStreak)j max")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(arcColor)
                    Text(s.warRoomResets == 0 ? "Invaincu" : "\(s.warRoomResets) reset\(s.warRoomResets > 1 ? "s" : "")")
                        .font(.system(size: 12))
                        .foregroundStyle(s.warRoomResets == 0 ? Color.green : Color.secondary)
                }
            }
        }
    }

    // MARK: Habit

    private var habitSection: some View {
        reportSection(label: "L'HABITUDE", delay: 0.6) {
            let s = report.stats
            metricRow("Rituels", value: "\(Int(s.ritualCompletionRate * 100))% complétés")
            if s.breathworkSessions > 0 {
                metricRow("Breathwork", value: "\(s.breathworkSessions) sessions")
            }
            if s.meditationMinutes > 0 {
                metricRow("Méditation", value: "\(s.meditationMinutes) min")
            }
        }
    }

    // MARK: Verdict

    private var verdictSection: some View {
        reportSection(label: "LE VERDICT", delay: 0.7) {
            Text(report.narrative)
                .font(.appBody.weight(.light))
                .foregroundStyle(Color.primary)
                .lineSpacing(5)
        }
    }

    private func noteSection(_ note: String) -> some View {
        reportSection(label: "TON MOT", delay: 0.8) {
            Text("\u{201C}\(note)\u{201D}")
                .font(.system(size: 14, weight: .light, design: .serif))
                .foregroundStyle(Color.secondary)
                .lineSpacing(4)
        }
    }

    // MARK: Helpers

    private func reportSection<Content: View>(
        label: String,
        delay: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(arcColor.opacity(0.7))
                .tracking(4)
            content()
        }
        .padding(.vertical, 20)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(delay), value: appeared)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }

    private func deltaRow(_ label: String, from: String, to: String,
                          delta: Double, unit: String, lowerIsBetter: Bool) -> some View {
        HStack {
            Text(label)
                .font(.appLabel)
                .foregroundStyle(Color.secondary)
            Spacer()
            Text("\(from) → \(to)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.primary)
            let positive = lowerIsBetter ? delta < 0 : delta > 0
            Text(delta == 0 ? "" : (delta > 0 ? "+\(String(format: "%.1f", abs(delta)))" : "−\(String(format: "%.1f", abs(delta)))") + (unit.isEmpty ? "" : " \(unit)"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(delta == 0 ? .clear : (positive ? Color.green : Color.red))
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.appLabel)
                .foregroundStyle(Color.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.primary)
        }
    }

    private var arcColor: Color {
        switch report.arc {
        case "rebirth":      return .purple
        case "comeback":     return Color.forge
        case "war":          return .red
        case "breakthrough": return .yellow
        case "ascent":       return .green
        case "descent":      return Color.red.opacity(0.6)
        case "plateau":      return .secondary
        default:             return .blue
        }
    }
}
