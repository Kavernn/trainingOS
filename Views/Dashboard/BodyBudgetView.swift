import SwiftUI

// MARK: - BodyBudgetCard

struct BodyBudgetCard: View {
    let budget: BodyBudgetResponse?

    @State private var isLoading = true

    var body: some View {
        Group {
            if let b = budget {
                BodyBudgetContent(budget: b)
            } else if isLoading {
                BodyBudgetSkeleton()
            }
        }
        .onAppear { isLoading = budget == nil }
        .onChange(of: budget == nil) { _ in isLoading = false }
    }
}

// MARK: - Content

private struct BodyBudgetContent: View {
    let budget: BodyBudgetResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                OrganismeOrb(
                    score: budget.score,
                    training: budget.pillars.training,
                    stress: budget.pillars.stress,
                    nutrition: budget.pillars.nutrition
                )
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(budget.score)")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(scoreColor(budget.score))
                            .contentTransition(.numericText())
                        Text("/ 100")
                            .font(.appLabel)
                            .foregroundColor(.gray)
                            .padding(.bottom, 3)
                        Spacer()
                        TrendChip(trend: budget.trend)
                    }
                    HStack(spacing: 4) {
                        Text("Body Budget")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.gray)
                            .tracking(0.5)
                            .textCase(.uppercase)
                        CardInfoButton(title: "Body Budget", entries: InfoEntry.bodyBudgetEntries)
                    }
                }
            }

            Text(budget.insight)
                .font(.appLabel.weight(.regular))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            PillarRow(pillars: budget.pillars)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(scoreColor(budget.score).opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 75...: return .green
        case 55..<75: return Color(red: 0.93, green: 0.76, blue: 0.0)
        default:     return .orange
        }
    }
}

// MARK: - Pillar Row

private struct PillarRow: View {
    let pillars: BodyBudgetPillars

    var body: some View {
        HStack(spacing: 0) {
            PillarCell(label: "Training",   value: pillars.training,  color: .teal)
            Divider().frame(height: 28).background(Color.white.opacity(0.08))
            PillarCell(label: "Stress",     value: pillars.stress,    color: Color(red: 0.55, green: 0.47, blue: 0.9))
            Divider().frame(height: 28).background(Color.white.opacity(0.08))
            PillarCell(label: "Nutrition",  value: pillars.nutrition, color: Color(red: 0.95, green: 0.65, blue: 0.1))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
}

private struct PillarCell: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.appCaption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trend Chip

private struct TrendChip: View {
    let trend: String

    var icon: String {
        switch trend {
        case "up":   return "arrow.up.right"
        case "down": return "arrow.down.right"
        default:     return "minus"
        }
    }
    var color: Color {
        switch trend {
        case "up":   return .green
        case "down": return .orange
        default:     return .gray
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.appMicro.weight(.bold))
            Text(trend == "stable" ? "stable" : trend == "up" ? "hausse" : "baisse")
                .font(.appCaption.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }
}

// MARK: - Organisme Orb (animated concentric rings)

private struct OrganismeOrb: View {
    let score:     Int
    let training:  Int
    let stress:    Int
    let nutrition: Int

    @State private var phase: Double = 0

    private let tealColor   = Color.teal
    private let indigoColor = Color(red: 0.55, green: 0.47, blue: 0.9)
    private let amberColor  = Color(red: 0.95, green: 0.65, blue: 0.1)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { ctx2, size in
                let cx = size.width  / 2
                let cy = size.height / 2
                let maxR = min(cx, cy) - 2

                // Outer ring — Training (teal)
                drawBreathingRing(
                    ctx: ctx2, cx: cx, cy: cy,
                    radius: maxR,
                    thickness: 3.5,
                    value: Double(training) / 100.0,
                    color: tealColor,
                    t: t,
                    speed: 0.8,
                    phase: 0
                )

                // Middle ring — Stress (indigo)
                drawBreathingRing(
                    ctx: ctx2, cx: cx, cy: cy,
                    radius: maxR * 0.72,
                    thickness: 3.0,
                    value: Double(stress) / 100.0,
                    color: indigoColor,
                    t: t,
                    speed: 1.1,
                    phase: Double.pi / 3
                )

                // Inner ring — Nutrition (amber)
                drawBreathingRing(
                    ctx: ctx2, cx: cx, cy: cy,
                    radius: maxR * 0.46,
                    thickness: 2.5,
                    value: Double(nutrition) / 100.0,
                    color: amberColor,
                    t: t,
                    speed: 0.65,
                    phase: Double.pi * 2 / 3
                )

                // Core glow
                let coreRadius  = maxR * 0.22
                let glowPulse   = 0.8 + 0.2 * sin(t * 1.2)
                let coreOpacity = 0.5 + 0.3 * Double(score) / 100.0
                ctx2.fill(
                    Path(ellipseIn: CGRect(
                        x: cx - coreRadius * glowPulse,
                        y: cy - coreRadius * glowPulse,
                        width: coreRadius * 2 * glowPulse,
                        height: coreRadius * 2 * glowPulse
                    )),
                    with: .color(.white.opacity(coreOpacity * glowPulse))
                )
            }
        }
    }

    private func drawBreathingRing(
        ctx: GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        radius: CGFloat,
        thickness: CGFloat,
        value: Double,
        color: Color,
        t: Double,
        speed: Double,
        phase: Double
    ) {
        let breathe = 1.0 + 0.04 * sin(t * speed + phase)
        let r       = radius * breathe
        let opacity = 0.25 + 0.65 * value
        let arcEnd  = value * 2 * Double.pi

        // Background track
        ctx.stroke(
            Path { p in
                p.addArc(center: CGPoint(x: cx, y: cy),
                         radius: r,
                         startAngle: .radians(-Double.pi / 2),
                         endAngle:   .radians(-Double.pi / 2 + 2 * Double.pi),
                         clockwise: false)
            },
            with: .color(color.opacity(0.08)),
            lineWidth: thickness
        )

        // Value arc
        ctx.stroke(
            Path { p in
                p.addArc(center: CGPoint(x: cx, y: cy),
                         radius: r,
                         startAngle: .radians(-Double.pi / 2),
                         endAngle:   .radians(-Double.pi / 2 + arcEnd),
                         clockwise: false)
            },
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: thickness, lineCap: .round)
        )
    }
}

// MARK: - Skeleton

private struct BodyBudgetSkeleton: View {
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.07)).frame(width: 80, height: 30)
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(width: 120, height: 12)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appCard))
    }
}
