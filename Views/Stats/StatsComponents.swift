import SwiftUI

// MARK: - Stats Tab Bar
struct StatsTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, label: String)] = [
        ("chart.bar.fill",           "Synthèse"),
        ("bolt.fill",                "Perf"),
        ("figure.stand",             "Corps"),
        ("fork.knife",               "Nutrition"),
        ("dumbbell.fill",            "Force"),
        ("heart.text.square.fill",   "Bien-être"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedTab = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: 13, weight: selectedTab == i ? .bold : .regular))
                        Text(tabs[i].label)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedTab == i ? .orange : .gray)
                    .background(selectedTab == i ? Color.orange.opacity(0.12) : Color.clear)
                    .cornerRadius(10)
                }
            }
        }
        .padding(4)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Period Picker
struct PeriodPicker: View {
    @Binding var selected: StatsPeriod

    var body: some View {
        HStack(spacing: 6) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.spring(response: 0.25)) { selected = p }
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(selected == p ? Color.orange : Color(hex: "1a1a28"))
                        .foregroundColor(selected == p ? .black : .gray)
                        .cornerRadius(20)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Smart Insights Banner
struct SmartInsightsBanner: View {
    let insights: [(icon: String, text: String, color: Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").foregroundColor(.yellow).font(.system(size: 10))
                Text("INSIGHTS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(insights.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Image(systemName: insights[i].icon)
                            .foregroundColor(insights[i].color)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(insights[i].text)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Adherence Rings Card
struct AdherenceRingsCard: View {
    let data: AdherenceData

    private struct Pillar {
        let label:   String
        let pct:     Int
        let color:   Color
        let rawDays: Int?
    }

    private var pillars: [Pillar] {
        [
            Pillar(label: "Body",        pct: data.bodyPct,   color: Color(hex: "F5A623"), rawDays: nil),
            Pillar(label: "Mind",        pct: data.mindPct,   color: .blue,                rawDays: nil),
            Pillar(label: "Consistance", pct: data.fuelPct,   color: .green,               rawDays: data.fuelDays),
            Pillar(label: "Spirit",      pct: data.spiritPct, color: Color(hex: "9B59B6"), rawDays: nil),
        ]
    }

    @State private var showFuelInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CONSTANCE CE MOIS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("\(data.daysElapsed) jours écoulés")
                    .font(.system(size: 11)).foregroundColor(.gray)
            }

            HStack(spacing: 24) {
                ZStack {
                    ForEach(pillars.indices.reversed(), id: \.self) { i in
                        AdherenceArc(
                            pct: Double(pillars[i].pct) / 100.0,
                            color: pillars[i].color,
                            radius: CGFloat(40 - i * 8),
                            lineWidth: 6
                        )
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(pillars.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(pillars[i].color)
                                .frame(width: 8, height: 8)
                            Text(pillars[i].label)
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                            Spacer()
                            if pillars[i].rawDays == .some(0) {
                                Text("—")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.gray)
                            } else {
                                Text("\(pillars[i].pct)%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(adherenceColor(pillars[i].pct))
                            }
                            if pillars[i].rawDays != nil {
                                Button { showFuelInfo = true } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
        .alert("Consistance", isPresented: $showFuelInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Jours avec au moins un repas loggué ce mois-ci")
        }
    }

    private func adherenceColor(_ pct: Int) -> Color {
        if pct >= 70 { return .green }
        if pct >= 40 { return .orange }
        return .red
    }
}

private struct AdherenceArc: View {
    let pct: Double
    let color: Color
    let radius: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: CGFloat(min(pct, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: radius * 2, height: radius * 2)
                .animation(.easeOut(duration: 0.6), value: pct)
        }
    }
}

// MARK: - Phoenix Ritual Stats Card (F3 + G2)
struct PhoenixRitualStatsCard: View {
    let stats: RitualStats
    private let red = Color(hex: "FF2D20")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13))
                    .foregroundColor(red)
                Text("RITUEL PHOENIX")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Color(white: 0.45))
                Spacer()
            }

            HStack(spacing: 0) {
                phoenixKPI(value: "\(stats.phoenixStreak)", label: "Streak actuel", accent: stats.phoenixStreak >= 3)
                Divider().background(Color(white: 0.12)).frame(height: 40)
                phoenixKPI(value: "\(stats.phoenixBest)", label: "Meilleur streak", accent: false)
                Divider().background(Color(white: 0.12)).frame(height: 40)
                phoenixKPI(value: "\(stats.phoenixTotalBurned)", label: "Total tués", accent: false)
            }

            Divider().background(Color(white: 0.1))

            HStack(spacing: 16) {
                rateBar(label: "7 jours", rate: stats.completionRate7d, burnRate: stats.burnRate7d)
                rateBar(label: "30 jours", rate: stats.completionRate30d, burnRate: stats.burnRate30d)
            }

            if !stats.weeklyCompletions.isEmpty {
                weeklyBars
            }
        }
        .padding(16)
        .background(Color(white: 0.06))
        .cornerRadius(12)
    }

    private func phoenixKPI(value: String, label: String, accent: Bool) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .black))
                .foregroundColor(accent ? red : .white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private func rateBar(label: String, rate: Double, burnRate: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.35))
            HStack(spacing: 4) {
                Text("\(Int(rate * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("complété")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.35))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.1)).frame(height: 4)
                    HStack(spacing: 0) {
                        Capsule().fill(red).frame(width: geo.size.width * CGFloat(burnRate), height: 4)
                        Capsule().fill(Color(white: 0.25)).frame(width: geo.size.width * CGFloat(max(0, rate - burnRate)), height: 4)
                    }
                }
            }
            .frame(height: 4)
            Text("\(Int(burnRate * 100))% BURNED")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(red.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklyBars: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEMAINES RÉCENTES")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundColor(Color(white: 0.28))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(stats.weeklyCompletions.suffix(8)) { entry in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.1)).frame(width: 20, height: 32)
                            if entry.completed > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(entry.burned == entry.completed ? red : Color(white: 0.3))
                                    .frame(width: 20, height: min(32, CGFloat(entry.completed) * 4.5))
                            }
                        }
                        Text(String(entry.week.suffix(2)))
                            .font(.system(size: 8))
                            .foregroundColor(Color(white: 0.25))
                    }
                }
                Spacer()
            }
        }
    }
}
