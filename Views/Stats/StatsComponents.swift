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
