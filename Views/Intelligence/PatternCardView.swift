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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.purple)
                Text("Pattern détecté")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.purple)
                    .tracking(0.4)
                Spacer()
                PatternFamilyBadge(family: pattern.family, subLabel: pattern.subLabel)
            }

            // Headline
            Text(pattern.headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
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
                            .font(.system(size: 11, weight: .semibold))
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
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(colorFromName(pattern.color).opacity(0.7))
                        Text(pattern.headline)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(expanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        EffectBadge(pct: pattern.effectPct)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
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
                                    .font(.system(size: 11))
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
                .font(.system(size: 11))
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
