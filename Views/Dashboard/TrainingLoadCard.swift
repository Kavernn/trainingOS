import SwiftUI

// MARK: - TrainingLoadCard (Dashboard compact)

struct TrainingLoadCard: View {
    let data: TrainingLoadData
    @State private var showDetail = false

    private var zoneColor: Color { Color(hex: data.zone.colorHex) }

    var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            TrainingLoadDetailSheet(data: data)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            metricsRow
            if !data.message.isEmpty {
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("ZONE DE CHARGE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            ZoneBadge(zone: data.zone)
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RATIO ACWR")
                    .font(.appMicro).tracking(0.8)
                    .foregroundColor(.white.opacity(0.28))
                Text(data.formattedRatio)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(zoneColor)
            }
            Spacer()
            LoadSparkline(values: data.trend4w, zone: data.zone)
        }
    }
}

// MARK: - Zone Badge

private struct ZoneBadge: View {
    let zone: TrainingZone

    private var color: Color { Color(hex: zone.colorHex) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: zone.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(zone.label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color.opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - 4-Week Sparkline

private struct LoadSparkline: View {
    let values: [Double]
    let zone: TrainingZone

    private var maxVal: Double { values.max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                let v = values[i]
                let isLast = i == values.count - 1
                let h = maxVal > 0 ? max(6.0, 40.0 * v / maxVal) : 6.0
                let barColor: Color = isLast ? Color(hex: zone.colorHex) : .white.opacity(0.22)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: 12, height: h)
                    Text("S\(i + 1)")
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(isLast ? 0.45 : 0.22))
                }
            }
        }
        .frame(height: 52, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct TrainingLoadDetailSheet: View {
    let data: TrainingLoadData
    @Environment(\.dismiss) private var dismiss

    private var zoneColor: Color { Color(hex: data.zone.colorHex) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    RatioBanner(data: data)
                    LoadBreakdownCard(data: data)
                    ZoneGuideCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Zone de Charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct RatioBanner: View {
    let data: TrainingLoadData
    private var zoneColor: Color { Color(hex: data.zone.colorHex) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RATIO ACWR")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                ZoneBadge(zone: data.zone)
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(data.formattedRatio)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(zoneColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct LoadBreakdownCard: View {
    let data: TrainingLoadData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DÉTAIL DE LA CHARGE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(spacing: 0) {
                LoadStat(label: "CHARGE AIGUË", sublabel: "7 jours",
                         value: data.acute.map { String(format: "%.0f", $0) } ?? "—",
                         color: Color(hex: data.zone.colorHex))
                Divider().background(Color.white.opacity(0.10)).frame(height: 40)
                LoadStat(label: "CHARGE CHRONIQUE", sublabel: "28 jours moy.",
                         value: data.chronic.map { String(format: "%.0f", $0) } ?? "—",
                         color: .white.opacity(0.55))
            }
            if data.strengthAcwr != nil || data.cardioAcwr != nil {
                Divider().background(Color.white.opacity(0.08))
                HStack(spacing: 0) {
                    if let s = data.strengthAcwr {
                        LoadStat(label: "FORCE", sublabel: "ACWR",
                                 value: s.ratio.map { String(format: "%.2f×", $0) } ?? "—",
                                 color: .white.opacity(0.70))
                    }
                    if data.strengthAcwr != nil && data.cardioAcwr != nil {
                        Divider().background(Color.white.opacity(0.10)).frame(height: 40)
                    }
                    if let c = data.cardioAcwr {
                        LoadStat(label: "CARDIO", sublabel: "ACWR",
                                 value: c.ratio.map { String(format: "%.2f×", $0) } ?? "—",
                                 color: .white.opacity(0.70))
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct LoadStat: View {
    let label: String
    let sublabel: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.appMicro.weight(.black)).tracking(1.0)
                .foregroundColor(.white.opacity(0.30))
            Text(value)
                .font(.appHeadline.weight(.bold))
                .foregroundColor(color)
            Text(sublabel)
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ZoneGuideCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GUIDE DES ZONES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            ForEach(ZoneRow.all, id: \.label) { row in
                HStack(spacing: 10) {
                    Circle().fill(row.color).frame(width: 8, height: 8)
                    Text(row.label)
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(.white.opacity(0.72))
                    Spacer()
                    Text(row.range)
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.38))
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    private struct ZoneRow {
        let label: String
        let range: String
        let color: Color
        static let all: [ZoneRow] = [
            .init(label: "Sous-chargé",    range: "< 0.80×",       color: Color(hex: "FF9500")),
            .init(label: "Zone optimale",  range: "0.80 – 1.30×",  color: Color(hex: "34C759")),
            .init(label: "Surcharge",      range: "> 1.30×",       color: Color(hex: "FF3B30")),
        ]
    }
}
