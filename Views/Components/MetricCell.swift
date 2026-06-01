import SwiftUI

// MARK: - MetricCell
/// Cellule KPI réutilisable : valeur + label + icône optionnelle
/// Remplace tous les patterns inline (kpiPill, secChip, CardioMetricChip, StatPill…)
struct MetricCell: View {

    let title: String
    var value: String?
    var unit: String?
    var icon: String?
    var trend: Trend?
    var status: Status?
    var tint: Color? = nil
    var isLoading: Bool = false
    var onTap: (() -> Void)?

    enum Trend { case up, down, flat }
    enum Status { case good, warning, critical, neutral }

    // MARK: - Size variants
    enum Size {
        case small    // kpiPill / inline compact
        case medium   // CardioMetricChip / secChip
        case large    // StatPill / standalone KPI
    }
    var size: Size = .medium

    // MARK: - Body
    var body: some View {
        Group {
            if isLoading {
                skeletonView
            } else if let onTap {
                Button(action: {
#if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                    onTap()
                }) {
                    content
                }
                .buttonStyle(SpringButtonStyle(scale: 0.96))
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(onTap != nil ? "Appuyez pour voir les détails" : "")
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .center, spacing: size == .small ? 2 : 4) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(isEmpty ? .gray.opacity(0.3) : iconColor)
                }
                Text(displayValue)
                    .font(.system(size: valueSize, weight: valueFontWeight, design: .rounded))
                    .foregroundColor(isEmpty ? .gray.opacity(0.35) : valueColor)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let trend, !isEmpty {
                    trendArrow(trend)
                }
            }

            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let unit, !isEmpty {
                    Text(unit)
                        .font(.system(size: labelSize - 1, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .center, spacing: 4) {
            SkeletonBar(width: 44, height: valueSizeAsHeight, radius: 4)
            SkeletonBar(width: 36, height: labelSize + 2, radius: 3)
        }
    }

    // MARK: - Helpers

    private var displayValue: String { value ?? "—" }
    private var isEmpty: Bool { value == nil }

    private var accessibilityLabelText: String {
        var base = "\(title): \(value ?? "non disponible")"
        if let unit, value != nil { base += " \(unit)" }
        if let trend, value != nil {
            switch trend {
            case .up:   base += ", en hausse"
            case .down: base += ", en baisse"
            case .flat: base += ", stable"
            }
        }
        return base
    }

    private var valueColor: Color {
        if let tint { return tint }
        if let status {
            switch status {
            case .good:     return .green
            case .warning:  return .orange
            case .critical: return .red
            case .neutral:  return .primary
            }
        }
        return .primary
    }

    private var iconColor: Color {
        if let tint { return tint }
        if let status {
            switch status {
            case .good:     return .green
            case .warning:  return Color.forge
            case .critical: return .red
            case .neutral:  return .secondary
            }
        }
        return Color.forge
    }

    @ViewBuilder
    private func trendArrow(_ t: Trend) -> some View {
        switch t {
        case .up:
            Image(systemName: "arrow.up")
                .font(.system(size: iconSize - 1, weight: .bold))
                .foregroundColor(.green)
        case .down:
            Image(systemName: "arrow.down")
                .font(.system(size: iconSize - 1, weight: .bold))
                .foregroundColor(.red)
        case .flat:
            Image(systemName: "arrow.right")
                .font(.system(size: iconSize - 1, weight: .bold))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sizing

    private var valueSize: CGFloat {
        switch size {
        case .small:  return 12
        case .medium: return 15
        case .large:  return 20
        }
    }

    private var valueSizeAsHeight: CGFloat { valueSize + 4 }

    private var valueFontWeight: Font.Weight {
        switch size {
        case .small:  return .semibold
        case .medium: return .bold
        case .large:  return .black
        }
    }

    private var labelSize: CGFloat {
        switch size {
        case .small:  return 9
        case .medium: return 10
        case .large:  return 11
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .small:  return 9
        case .medium: return 11
        case .large:  return 13
        }
    }
}


// MARK: - Preview

#Preview("MetricCell — tous les états") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {

            Text("LARGE — StatPill replacement")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal)

            HStack(spacing: 12) {
                MetricCell(title: "Volume", value: "12 450", unit: "kg",
                           icon: "dumbbell.fill", size: .large)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .glassCard()

                MetricCell(title: "FC repos", value: nil,
                           icon: "heart.fill", size: .large)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .glassCard()
            }
            .padding(.horizontal)

            Text("MEDIUM — CardioMetricChip replacement")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal)

            HStack(spacing: 0) {
                MetricCell(title: "Durée", value: "45 min",
                           icon: "clock.fill",
                           status: .good, size: .medium)
                    .frame(maxWidth: .infinity)

                MetricCell(title: "Distance", value: "8.4",
                           unit: "km", size: .medium)
                    .frame(maxWidth: .infinity)

                MetricCell(title: "FC moy", value: "162",
                           unit: "bpm",
                           icon: "heart.fill",
                           status: .warning, size: .medium)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .glassCard()
            .padding(.horizontal)

            Text("SMALL — kpiPill replacement")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal)

            HStack(spacing: 10) {
                MetricCell(title: "Sommeil", value: "7.5h",
                           icon: "moon.fill",
                           status: .good, size: .small)

                MetricCell(title: "Énergie", value: "3/10",
                           icon: "bolt.fill",
                           status: .critical, size: .small)

                MetricCell(title: "Courbatures", value: nil,
                           icon: "flame.fill", size: .small)
            }
            .padding()
            .glassCard()
            .padding(.horizontal)

            Text("TREND")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal)

            HStack(spacing: 12) {
                MetricCell(title: "HRV", value: "68",
                           unit: "ms", trend: .up, size: .large)
                    .frame(maxWidth: .infinity).padding(12).glassCard()

                MetricCell(title: "Poids", value: "82.4",
                           unit: "kg", trend: .down, size: .large)
                    .frame(maxWidth: .infinity).padding(12).glassCard()

                MetricCell(title: "Volume", value: "9 200",
                           unit: "kg", trend: .flat, size: .large)
                    .frame(maxWidth: .infinity).padding(12).glassCard()
            }
            .padding(.horizontal)

            Text("LOADING")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal)

            HStack(spacing: 12) {
                MetricCell(title: "Volume", isLoading: true, size: .large)
                    .frame(maxWidth: .infinity).padding(12).glassCard()
                MetricCell(title: "Séances", isLoading: true, size: .large)
                    .frame(maxWidth: .infinity).padding(12).glassCard()
                MetricCell(title: "FC repos", isLoading: true, size: .large)
                    .frame(maxWidth: .infinity).padding(12).glassCard()
            }
            .padding(.horizontal)

            Text("TAPPABLE")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal)

            MetricCell(
                title: "Séances ce mois",
                value: "14",
                icon: "calendar",
                trend: .up,
                onTap: {},
                size: .large
            )
            .frame(maxWidth: .infinity)
            .padding(14)
            .glassCard()
            .padding(.horizontal)
        }
        .padding(.vertical, 24)
    }
    .background(Color.appBg)
    .preferredColorScheme(.dark)
}
