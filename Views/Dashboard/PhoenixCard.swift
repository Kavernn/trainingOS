import SwiftUI

// MARK: - Phoenix Card

struct PhoenixCard: View {
    let score: PhoenixScore
    var dayDelta: Double? = nil

    @State private var seeds = PhoenixSeed.generate(count: 40)
    @State private var isVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = score.phoenixState
        VStack(spacing: 0) {
            phoenixCanvas(state: state)
            scoreSection(state: state)
            if !score.isFoundation {
                axesSection(state: state)
            }
        }
        .background(state.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(state.glowColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: state.glowColor.opacity(state.glowOpacity), radius: state.glowRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phoenixAccessibilityLabel)
    }

    private var phoenixAccessibilityLabel: String {
        let state = score.phoenixState
        if score.isFoundation {
            return "Phoenix Score en construction. Accumule 7 jours de données."
        }
        let sign = score.score >= 0 ? "positif" : "négatif"
        let scoreStr = String(format: "%.1f", abs(score.score))
        var parts = ["Phoenix Score \(sign) : \(scoreStr). État : \(state.label)."]
        if let delta = dayDelta, abs(delta) >= 0.1 {
            let dir = delta >= 0 ? "en hausse" : "en baisse"
            parts.append("\(dir) de \(String(format: "%.1f", abs(delta))) par rapport à hier.")
        }
        let corps  = "Corps : \(score.axes.workout.delta >= 0 ? "+" : "")\(Int(score.axes.workout.delta))%"
        let mental = "Mental : \(score.axes.stress.delta >= 0 ? "+" : "")\(Int(score.axes.stress.delta))%"
        let fuel   = "Fuel : \(score.axes.nutrition.delta >= 0 ? "+" : "")\(Int(score.axes.nutrition.delta))%"
        parts.append("\(corps). \(mental). \(fuel).")
        if let spirit = score.axes.spirit {
            parts.append("Esprit : \(spirit.delta >= 0 ? "+" : "")\(Int(spirit.delta))%.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func phoenixCanvas(state: PhoenixState) -> some View {
        let capturedSeeds = seeds
        // Throttle to 1/min when off-screen (TabView keeps views alive between tabs)
        TimelineView((!reduceMotion && isVisible) ? .animation(minimumInterval: 1.0 / 30.0) : .everyMinute) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                drawPhoenixFrame(&ctx, size: size, seeds: capturedSeeds, state: state, t: t)
            }
        }
        .frame(height: 130)
        .clipped()
        .onAppear  { isVisible = true }
        .onDisappear { isVisible = false }
    }

    @ViewBuilder
    private func scoreSection(state: PhoenixState) -> some View {
        VStack(spacing: 5) {
            Text(score.isFoundation ? "PHOENIX SCORE" : state.label.uppercased())
                .font(.system(size: 9, weight: .black)).tracking(3)
                .foregroundColor(state.scoreColor.opacity(0.85))

            if score.isFoundation {
                Text("Accumule 7 jours de données")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 4)
            } else {
                let sign = score.score >= 0 ? "+" : ""
                let scoreStr = String(format: "%.1f", score.score)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(sign)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(state.scoreColor.opacity(0.8))
                    Text(scoreStr)
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .foregroundColor(state.scoreColor)
                }
                .padding(.top, 2)

                if let delta = dayDelta, abs(delta) >= 0.1 {
                    let dSign = delta >= 0 ? "+" : ""
                    let dColor: Color = delta >= 0 ? .green : Color(hex: "FF5555")
                    HStack(spacing: 3) {
                        Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(dSign)\(String(format: "%.1f", delta)) vs hier")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(dColor.opacity(0.85))
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func axesSection(state: PhoenixState) -> some View {
        let div = Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 34)
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
        HStack(spacing: 0) {
            PhoenixAxisPill(label: "CORPS",  delta: score.axes.workout.delta,   color: state.scoreColor)
            div
            PhoenixAxisPill(label: "MENTAL", delta: score.axes.stress.delta,    color: state.scoreColor)
            div
            PhoenixAxisPill(label: "FUEL",   delta: score.axes.nutrition.delta, color: state.scoreColor)
            div
            if let spirit = score.axes.spirit {
                PhoenixAxisPill(label: "ESPRIT", delta: spirit.delta, color: state.scoreColor)
            } else {
                PhoenixAxisPillInactive(label: "ESPRIT")
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Axis Pills

struct PhoenixAxisPill: View {
    let label: String
    let delta: Double
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 6, weight: .black)).tracking(0.6)
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 2) {
                Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 7, weight: .bold))
                Text(String(format: "%.0f%%", abs(delta)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(delta >= 0 ? color : Color(hex: "FF5555"))
        }
        .frame(maxWidth: .infinity)
    }
}

struct PhoenixAxisPillInactive: View {
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 6, weight: .black)).tracking(0.6)
                .foregroundColor(.white.opacity(0.45))
            Text("—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Particle seed

struct PhoenixSeed: Sendable {
    let x: Double
    let phase: Double
    let speed: Double
    let size: CGFloat
    let alpha: Double

    static func generate(count: Int) -> [PhoenixSeed] {
        var lcg: UInt64 = 9131
        func next() -> Double {
            lcg = lcg &* 6364136223846793005 &+ 1442695040888963407
            return Double(lcg >> 33) / Double(UInt64(1) << 31)
        }
        func frac(_ v: Double) -> Double { v - floor(v) }
        return (0..<count).map { _ in
            PhoenixSeed(
                x:     frac(next()),
                phase: frac(next()) * .pi * 2,
                speed: 0.4 + frac(next()) * 1.4,
                size:  CGFloat(2.0 + frac(next()) * 5.0),
                alpha: 0.35 + frac(next()) * 0.65
            )
        }
    }
}

// MARK: - Canvas drawing (free functions — avoids @Sendable capture issues)

fileprivate func drawPhoenixFrame(_ ctx: inout GraphicsContext, size: CGSize, seeds: [PhoenixSeed], state: PhoenixState, t: Double) {
    switch state {
    case .foundation:   drawFoundation(&ctx, size: size, seeds: seeds, t: t)
    case .cendres:      drawAsh(&ctx, size: size, seeds: seeds, t: t)
    case .braises:      drawEmbers(&ctx, size: size, seeds: seeds, t: t, hot: false)
    case .braisesChaud: drawEmbers(&ctx, size: size, seeds: seeds, t: t, hot: true)
    case .flamme:       drawFlame(&ctx, size: size, seeds: seeds, t: t, intensity: 1.0)
    case .envol:        drawFlame(&ctx, size: size, seeds: seeds, t: t, intensity: 1.8)
    case .supernova:    drawSupernova(&ctx, size: size, seeds: seeds, t: t)
    }
}

fileprivate func drawFoundation(_ ctx: inout GraphicsContext, size: CGSize, seeds: [PhoenixSeed], t: Double) {
    let cx = size.width / 2
    let cy = size.height / 2
    let count = min(seeds.count, 15)
    for i in 0..<count {
        let s = seeds[i]
        let r = 30.0 + Double(i) * 3.5
        let angle = s.phase + t * s.speed * 0.25
        let x = cx + cos(angle) * r
        let y = cy + sin(angle) * r * 0.55
        let pulse = 0.5 + 0.5 * sin(t * s.speed * 1.2 + s.phase)
        let opacity = s.alpha * 0.5 * pulse
        fillParticle(&ctx, x: x, y: y, size: s.size * 0.8, color: Color(hex: "6B8CFF"), opacity: opacity, glowMult: 2.0)
    }
}

fileprivate func drawAsh(_ ctx: inout GraphicsContext, size: CGSize, seeds: [PhoenixSeed], t: Double) {
    let count = min(seeds.count, 12)
    for i in 0..<count {
        let s = seeds[i]
        let speed = s.speed * 0.25
        let progress = fmod(t * speed + s.phase / (.pi * 2), 1.0)
        let x = s.x * size.width + sin(t * 0.3 + s.phase) * 12
        let y = progress * (size.height + 10) - 5
        let fade = min(1.0, min(progress * 4, (1.0 - progress) * 4))
        let opacity = s.alpha * 0.35 * fade
        fillParticle(&ctx, x: x, y: y, size: s.size * 0.7, color: Color(white: 0.45), opacity: opacity, glowMult: 0)
    }
}

fileprivate func drawEmbers(_ ctx: inout GraphicsContext, size: CGSize, seeds: [PhoenixSeed], t: Double, hot: Bool) {
    let count = min(seeds.count, hot ? 22 : 18)
    let baseColor = hot ? Color(hex: "E07030") : Color(hex: "802810")
    for i in 0..<count {
        let s = seeds[i]
        let x = s.x * size.width
        let drift = sin(t * s.speed * 0.15 + s.phase) * 8
        let baseY = s.phase / (.pi * 2) * size.height
        let y = baseY + drift
        let pulse = 0.4 + 0.6 * sin(t * s.speed * (hot ? 1.8 : 0.9) + s.phase)
        let opacity = s.alpha * (hot ? 0.7 : 0.4) * pulse
        let glow = hot ? 2.5 : 1.2
        fillParticle(&ctx, x: x, y: y, size: s.size * 0.85, color: baseColor, opacity: opacity, glowMult: glow)
    }
}

fileprivate func drawFlame(_ ctx: inout GraphicsContext, size: CGSize, seeds: [PhoenixSeed], t: Double, intensity: Double) {
    let count = min(seeds.count, intensity > 1.5 ? 34 : 28)
    for i in 0..<count {
        let s = seeds[i]
        let speed = s.speed * intensity * 0.35
        let progress = fmod(t * speed + s.phase / (.pi * 2), 1.0)
        let yBase = (1.0 - progress) * (size.height + 20) - 10
        let sway = sin(t * s.speed * 0.8 + s.phase) * (10 + intensity * 12)
        let x = s.x * size.width + sway
        let y = yBase
        let fade = min(1.0, min(progress * 5, (1.0 - progress) * 3))
        let opacity = s.alpha * 0.75 * fade
        // Color gradient: base = orange, tip = yellow
        let hue = progress > 0.5 ? Color(hex: "FFD700") : Color(hex: "F5A623")
        let glow = intensity > 1.5 ? 3.5 : 2.0
        fillParticle(&ctx, x: x, y: y, size: s.size * (0.5 + progress * 0.6), color: hue, opacity: opacity, glowMult: glow)
    }
    if intensity > 1.5 {
        drawWingArcs(&ctx, size: size, t: t)
    }
}

fileprivate func drawWingArcs(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
    let cx = size.width / 2
    let cy = size.height * 0.65
    for side in [-1.0, 1.0] {
        let sweep = t * 0.6
        var path = Path()
        let startAngle = Angle.degrees(side > 0 ? 200 : -20)
        let endAngle   = Angle.degrees(side > 0 ? 260 : -80)
        path.addArc(center: CGPoint(x: cx + side * 40, y: cy),
                    radius: 50, startAngle: startAngle, endAngle: endAngle, clockwise: side < 0)
        let pulse = 0.3 + 0.25 * sin(sweep)
        ctx.stroke(path, with: .color(Color(hex: "FFD700").opacity(pulse)), lineWidth: 1.5)
    }
}

fileprivate func drawSupernova(_ ctx: inout GraphicsContext, size: CGSize, seeds: [PhoenixSeed], t: Double) {
    let cx = size.width / 2
    let cy = size.height * 0.55
    let count = min(seeds.count, 40)
    let colors: [Color] = [.white, Color(hex: "FFD700"), Color(hex: "F5A623"), Color(hex: "FFF5CC")]
    for i in 0..<count {
        let s = seeds[i]
        let r = (fmod(t * s.speed * 0.4 + s.phase / (.pi * 2), 1.0)) * min(size.width, size.height) * 0.6
        let angle = s.phase + t * 0.08 * s.speed
        let x = cx + cos(angle) * r
        let y = cy + sin(angle) * r * 0.7
        let fade = 1.0 - r / (min(size.width, size.height) * 0.6)
        let opacity = s.alpha * max(0, fade) * 0.85
        let c = colors[i % colors.count]
        fillParticle(&ctx, x: x, y: y, size: s.size, color: c, opacity: opacity, glowMult: 3.0)
    }
    // Central burst
    let corePulse = 0.5 + 0.5 * sin(t * 3.0)
    let coreRect = CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16)
    ctx.fill(Path(ellipseIn: coreRect), with: .color(Color.white.opacity(0.6 * corePulse)))
    let haloRect = CGRect(x: cx - 20, y: cy - 20, width: 40, height: 40)
    ctx.fill(Path(ellipseIn: haloRect), with: .color(Color(hex: "FFD700").opacity(0.15 * corePulse)))
}

// MARK: - Shared particle draw

fileprivate func fillParticle(_ ctx: inout GraphicsContext, x: Double, y: Double, size: CGFloat, color: Color, opacity: Double, glowMult: Double) {
    guard opacity > 0.01 else { return }
    if glowMult > 0 {
        let gr = size * CGFloat(glowMult)
        let glowRect = CGRect(x: x - gr, y: y - gr, width: gr * 2, height: gr * 2)
        ctx.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(opacity * 0.18)))
    }
    let rect = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
}

fileprivate func fmod(_ a: Double, _ b: Double) -> Double {
    a - floor(a / b) * b
}
