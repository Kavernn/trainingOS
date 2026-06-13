import SwiftUI

// MARK: - ComebackArcCard (Dashboard compact)

struct ComebackArcCard: View {
    let data: ComebackArcData
    @State private var showDetail = false

    private var arcColor: Color { Color(hex: data.arcColor) }

    var body: some View {
        Button { showDetail = true } label: { cardContent }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                ComebackArcDetailSheet(data: data)
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            progressRow
            Text(data.message)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("COMEBACK ARC")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            ArcStatusBadge(label: data.arcLabel, colorHex: data.arcColor)
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var progressRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("JOURS ACTIFS")
                    .font(.appMicro).tracking(0.8)
                    .foregroundColor(.white.opacity(0.28))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(data.activeSincePct ?? 0)%")
                        .font(.appCardMetric)
                        .foregroundColor(arcColor)
                    if let days = data.daysSinceRupture {
                        Text("sur \(days)j")
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.38))
                    }
                }
            }
            Spacer()
            ComebackProgressBar(pct: data.activeSincePct ?? 0, color: arcColor)
        }
    }
}

// MARK: - Sub-views

private struct ArcStatusBadge: View {
    let label: String
    let colorHex: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.forward.circle.fill")
                .font(.appMicro.weight(.semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color(hex: colorHex).opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(hex: colorHex).opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct ComebackProgressBar: View {
    let pct: Int
    let color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(pct)%")
                .font(.appMicro)
                .foregroundColor(color.opacity(0.70))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(pct) / 100, height: 6)
                }
            }
            .frame(width: 80, height: 6)
        }
    }
}

// MARK: - Detail Sheet

private struct ComebackArcDetailSheet: View {
    let data: ComebackArcData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ArcBanner(data: data)
                    RuptureContextCard(data: data)
                    ArcExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Comeback Arc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct ArcBanner: View {
    let data: ComebackArcData
    private var arcColor: Color { Color(hex: data.arcColor) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RETOUR EN FORCE")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                ArcStatusBadge(label: data.arcLabel, colorHex: data.arcColor)
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("\(data.activeSincePct ?? 0)%")
                .font(.appCardHero)
                .foregroundColor(arcColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct RuptureContextCard: View {
    let data: ComebackArcData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTEXTE DE LA RUPTURE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            ArcStatRow(label: "Durée de la rupture",
                       value: data.ruptureLength.map { "\($0) jour\($0 > 1 ? "s" : "")" } ?? "—",
                       icon: "exclamationmark.triangle.fill",
                       iconColor: Color.trendNegative)

            ArcStatRow(label: "Jours depuis la rupture",
                       value: data.daysSinceRupture.map { "\($0)j" } ?? "—",
                       icon: "calendar",
                       iconColor: .white.opacity(0.50))

            ArcStatRow(label: "Jours actifs depuis",
                       value: "\(data.activeDays ?? 0) / \(data.daysSinceRupture ?? 0)",
                       icon: "figure.strengthtraining.traditional",
                       iconColor: Color(hex: data.arcColor))
        }
        .padding(14)
        .glassCard()
    }
}

private struct ArcStatRow: View {
    let label: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(iconColor)
                .frame(width: 16)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.appCaption.weight(.bold))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

private struct ArcExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("C'EST QUOI UN COMEBACK ARC ?")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Une rupture = 2+ jours consécutifs sans entraînement ET sans nutrition loguée. Le comeback arc mesure la vitesse à laquelle tu reprends le rythme après une telle période.")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
