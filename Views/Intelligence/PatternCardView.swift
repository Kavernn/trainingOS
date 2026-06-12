import SwiftUI

// MARK: - Daily pattern card (full)

struct PatternDailyCard: View {
    let pattern: PatternEntry
    let onPin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(.purple)
                Text("Pattern détecté")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(.purple)
                    .tracking(0.4)
                if pattern.isNew {
                    Text("NEW")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                }
                Spacer()
                PatternFamilyBadge(family: pattern.family, subLabel: pattern.subLabel)
            }

            // Headline
            Text(pattern.headline)
                .font(.appBody.weight(.semibold))
                .foregroundColor(.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            // Comparative bars
            PatternBarChart(barA: pattern.barA, barB: pattern.barB, color: patternColor)

            // Footer
            HStack(spacing: 0) {
                ConfidenceChip(confidence: pattern.confidence, n: pattern.n)
                Spacer()
                Button(action: onPin) {
                    HStack(spacing: 5) {
                        Image(systemName: pattern.pinned ? "pin.fill" : "pin")
                            .font(.appCaption.weight(.semibold))
                        Text(pattern.pinned ? "Suivi" : "Suivre")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(pattern.pinned ? .purple : Color(white: 0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background((pattern.pinned ? Color.purple : Color.white).opacity(0.09))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(patternColor.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var patternColor: Color { colorFromName(pattern.color) }
}

// MARK: - Pinned pattern chip (compact)

struct PatternPinnedChip: View {
    let pattern: PatternEntry
    let onUnpin: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: pattern.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorFromName(pattern.color))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pattern.subLabel.uppercased())
                            .font(.appMicro.weight(.bold))
                            .foregroundColor(colorFromName(pattern.color).opacity(0.7))
                        Text(pattern.headline)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(expanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            if let trend = pattern.trend, trend.isSignificant {
                                PatternTrendChip(trend: trend)
                            }
                            EffectBadge(pct: pattern.effectPct)
                        }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.appMicro)
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    PatternBarChart(barA: pattern.barA, barB: pattern.barB, color: colorFromName(pattern.color))
                        .padding(.horizontal, 12)

                    HStack {
                        ConfidenceChip(confidence: pattern.confidence, n: pattern.n)
                        Spacer()
                        Button(action: onUnpin) {
                            HStack(spacing: 4) {
                                Image(systemName: "pin.slash")
                                    .font(.system(size: 10))
                                Text("Retirer")
                                    .font(.appCaption)
                            }
                            .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - Bar chart (two horizontal bars)

private struct PatternBarChart: View {
    let barA: PatternBar
    let barB: PatternBar
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PatternBarRow(bar: barA, color: color, isTop: true)
            PatternBarRow(bar: barB, color: color.opacity(0.45), isTop: false)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }
}

private struct PatternBarRow: View {
    let bar: PatternBar
    let color: Color
    let isTop: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(bar.label)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            GeometryReader { geo in
                let w = geo.size.width * CGFloat(min(1.0, max(0.05, bar.frac)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05))
                    Capsule().fill(color).frame(width: w)
                }
            }
            .frame(height: 7)

            Text(bar.value >= 1000
                 ? String(format: "%.0f", bar.value)
                 : String(format: "%.1f", bar.value))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(isTop ? color : color.opacity(0.7))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Sub-components

private struct PatternFamilyBadge: View {
    let family: String
    let subLabel: String

    var body: some View {
        Text(subLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(familyColor(family))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(familyColor(family).opacity(0.12))
            .clipShape(Capsule())
    }

    private func familyColor(_ f: String) -> Color {
        switch f {
        case "A": return .purple
        case "B": return .teal
        case "C": return .orange
        case "D": return .red
        case "E": return Color(red: 0.85, green: 0.2, blue: 0.2)   // war-room red
        case "F": return Color(red: 0.3, green: 0.75, blue: 0.65)  // spirit teal-green
        case "G": return Color(red: 0.75, green: 0.3, blue: 0.85)  // reset violet
        default:  return .gray
        }
    }
}

private struct ConfidenceChip: View {
    let confidence: String
    let n: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(confidence == "forte" ? Color.green : Color.yellow)
                .frame(width: 6, height: 6)
            Text("Confiance \(confidence) · \(n) pts")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.5))
        }
    }
}

private struct EffectBadge: View {
    let pct: Double

    var body: some View {
        Text("+\(Int(pct))%")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.07))
            .clipShape(Capsule())
    }
}

private struct PatternTrendChip: View {
    let trend: PatternTrend

    var body: some View {
        HStack(spacing: 2) {
            Text(trend.arrow)
                .font(.system(size: 10, weight: .bold))
            Text("\(Int(abs(trend.deltaPct)))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundColor(trendColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(trendColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var trendColor: Color {
        switch trend.direction {
        case "rising":  return .green
        case "falling": return .red
        default:        return .gray
        }
    }
}

// MARK: - Dashboard chip (compact, one-liner)

struct PatternDailyChip: View {
    let pattern: PatternEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: pattern.icon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(colorFromName(pattern.color))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(pattern.subLabel.uppercased())
                            .font(.appMicro.weight(.bold))
                            .foregroundColor(colorFromName(pattern.color).opacity(0.7))
                            .tracking(0.3)
                        if pattern.isNew {
                            Text("NEW")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.yellow)
                                .clipShape(Capsule())
                        }
                    }
                    Text(pattern.headline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("+\(Int(pattern.effectPct))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(colorFromName(pattern.color))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(colorFromName(pattern.color).opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro Threshold Detail (Family C uniquement)

struct MacroThresholdDetail: View {
    let pattern: PatternEntry

    private var threshold: MacroThreshold? { pattern.macroThreshold }

    private var macroLabel: String {
        switch threshold?.macro {
        case "proteines": return "protéines"
        case "glucides":  return "glucides"
        default:          return "calories"
        }
    }

    var body: some View {
        if let t = threshold {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "target")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.purple.opacity(0.7))
                    Text("SEUIL PERSONNEL CALCULÉ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.4))
                        .tracking(0.5)
                }
                Text("Ton seuil optimal : \(Int(t.value))\(t.unit) de \(macroLabel) la veille")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(pattern.confidence == "forte" ? Color.green : Color.yellow)
                        .frame(width: 5, height: 5)
                    Text("Basé sur \(pattern.n) paires — corrélation \(pattern.confidence)")
                        .font(.appCaption)
                        .foregroundColor(Color(white: 0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.purple.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.12), lineWidth: 1))
            .cornerRadius(10)
        }
    }
}

// MARK: - Skeleton

struct PatternCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBar(height: 12, radius: 4).frame(width: 130)
            SkeletonBar(height: 18, radius: 6)
            SkeletonBar(height: 18, radius: 6).frame(maxWidth: .infinity * 0.75)
            SkeletonBar(height: 56, radius: 10)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.appCard))
    }
}

// MARK: - Color mapping

private func colorFromName(_ name: String) -> Color {
    switch name {
    case "purple":  return .purple
    case "blue":    return .blue
    case "green":   return .green
    case "teal":    return .teal
    case "orange":  return .orange
    case "red":     return .red
    case "yellow":  return .yellow
    case "indigo":  return .indigo
    case "pink":    return Color.pink
    case "cyan":    return Color.cyan
    default:        return .purple
    }
}
