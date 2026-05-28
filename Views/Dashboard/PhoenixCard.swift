import SwiftUI

// MARK: - Phoenix Card

// Wrapper Identifiable pour les alerts de guidance
private struct GuidanceAlert: Identifiable {
    let id = UUID()
    let label: String
    let text: String
}

struct PhoenixCard: View {
    let score: PhoenixScore
    var dayDelta: Double? = nil

    @State private var seeds = PhoenixSeed.generate(count: 40)
    @State private var isVisible = false
    @State private var guidanceAlert: GuidanceAlert? = nil

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
        .alert(item: $guidanceAlert) { a in
            Alert(title: Text(a.label), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
    }

    // Priority guidance: worst-delta axis message shown below the score
    private var priorityGuidance: String? {
        guard let g = score.guidance, !score.isFoundation else { return nil }
        let candidates: [(Double, String?)] = [
            (score.axes.workout.delta,          g.workout),
            (score.axes.stress.delta,           g.stress),
            (score.axes.nutrition.delta,        g.nutrition),
            (score.axes.spirit?.delta ?? 0,     g.spirit),
        ]
        return candidates
            .compactMap { delta, msg -> (Double, String)? in
                guard let msg else { return nil }
                return (delta, msg)
            }
            .min(by: { $0.0 < $1.0 })
            .map { $0.1 }
    }

    @ViewBuilder
    private func phoenixCanvas(state: PhoenixState) -> some View {
        let capturedSeeds = seeds
        // Throttle to 1/min when off-screen (TabView keeps views alive between tabs)
        TimelineView(.animation(minimumInterval: isVisible ? 1.0 / 30.0 : 60.0)) { tl in
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
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Text(score.isFoundation ? "PHOENIX SCORE" : state.label.uppercased())
                        .font(.system(size: 9, weight: .black)).tracking(3)
                        .foregroundColor(state.scoreColor.opacity(0.65))
                    Text("Ta transformation · semaine en cours")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.white.opacity(0.28))
                }
                .frame(maxWidth: .infinity)
                CardInfoButton(title: "Phoenix Score", entries: InfoEntry.phoenixEntries)
                    .padding(.trailing, 14)
            }

            if score.isFoundation {
                VStack(spacing: 6) {
                    Text("Commence une séance pour activer ton score")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                    Text("Il apparaît après ta première semaine d'activité")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.28))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
                .padding(.horizontal, 12)
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
                }
                if let hint = priorityGuidance {
                    Text(hint)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func axesSection(state: PhoenixState) -> some View {
        let g   = score.guidance
        let div = Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
        HStack(alignment: .top, spacing: 0) {
            PhoenixAxisPill(label: "CORPS",  delta: score.axes.workout.delta,   color: state.scoreColor,
                            guidance: g?.workout) {
                if let msg = g?.workout   { guidanceAlert = GuidanceAlert(label: "Corps",  text: msg) }
            }
            div.frame(height: pillDividerHeight(g?.workout,   g?.stress))
            PhoenixAxisPill(label: "MENTAL", delta: score.axes.stress.delta,    color: state.scoreColor,
                            guidance: g?.stress) {
                if let msg = g?.stress    { guidanceAlert = GuidanceAlert(label: "Mental", text: msg) }
            }
            div.frame(height: pillDividerHeight(g?.stress,    g?.nutrition))
            PhoenixAxisPill(label: "FUEL",   delta: score.axes.nutrition.delta, color: state.scoreColor,
                            guidance: g?.nutrition) {
                if let msg = g?.nutrition { guidanceAlert = GuidanceAlert(label: "Fuel",   text: msg) }
            }
            div.frame(height: pillDividerHeight(g?.nutrition, g?.spirit))
            if let spirit = score.axes.spirit {
                PhoenixAxisPill(label: "ESPRIT", delta: spirit.delta, color: state.scoreColor,
                                guidance: g?.spirit) {
                    if let msg = g?.spirit { guidanceAlert = GuidanceAlert(label: "Esprit", text: msg) }
                }
            } else {
                PhoenixAxisPillInactive(label: "ESPRIT")
            }
        }
        .padding(.vertical, 10)
    }

    private func pillDividerHeight(_ a: String?, _ b: String?) -> CGFloat {
        (a != nil || b != nil) ? 54 : 34
    }
}

// MARK: - Axis Pills

struct PhoenixAxisPill: View {
    let label: String
    let delta: Double
    let color: Color
    var guidance: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        let deltaColor: Color = delta >= 0 ? color : Color(hex: "FF5555")
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 6, weight: .black)).tracking(0.6)
                .foregroundColor(.white.opacity(0.35))
            HStack(spacing: 2) {
                Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 7, weight: .bold))
                Text(String(format: "%.0f%%", abs(delta)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(deltaColor)
            if let g = guidance {
                Text(g)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.white.opacity(0.40))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if guidance != nil { onTap?() } }
    }
}

struct PhoenixAxisPillInactive: View {
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 6, weight: .black)).tracking(0.6)
                .foregroundColor(.white.opacity(0.20))
            Text("—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.20))
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
