import SwiftUI

// MARK: - Phoenix Card

struct PhoenixCard: View {
    let score: PhoenixScore
    var dayDelta: Double? = nil
    var budget: BodyBudgetResponse? = nil

    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            PhoenixCardContent(score: score, dayDelta: dayDelta, budget: budget, showCanvas: false)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            PhoenixDetailSheet(score: score, dayDelta: dayDelta, budget: budget)
        }
    }
}

// MARK: - Detail Sheet

private struct PhoenixDetailSheet: View {
    let score: PhoenixScore
    var dayDelta: Double? = nil
    var budget: BodyBudgetResponse? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    PhoenixCardContent(score: score, dayDelta: dayDelta, budget: budget, showCanvas: true)
                    if let b = budget {
                        Text(b.insight)
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(.appOnSurface.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Phoenix Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

// MARK: - Card Content (compact dashboard + full sheet)

private struct PhoenixCardContent: View {
    let score: PhoenixScore
    var dayDelta: Double? = nil
    var budget: BodyBudgetResponse? = nil
    var showCanvas: Bool = false

    @State private var seeds = PhoenixSeed.generate(count: 40)
    @State private var isVisible = false

    var body: some View {
        let state = score.phoenixState
        VStack(spacing: 0) {
            if showCanvas {
                phoenixCanvas(state: state)
            }
            scoreSection(state: state)
            if !score.isFoundation {
                axesSection(state: state)
            }
            if let b = budget {
                budgetSection(b)
            }
        }
        .background(state.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(state.glowColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: state.glowColor.opacity(state.glowOpacity), radius: state.glowRadius)
    }

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
                Text(score.isFoundation ? "PHOENIX SCORE" : state.label.uppercased())
                    .font(.appMicro.weight(.black)).tracking(3)
                    .foregroundColor(state.scoreColor.opacity(0.65))
                    .frame(maxWidth: .infinity)
                CardInfoButton(title: "Phoenix Score", entries: InfoEntry.phoenixEntries)
                    .padding(.trailing, 14)
            }

            if score.isFoundation {
                VStack(spacing: 6) {
                    Text("Commence une séance pour activer ton score")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appOnSurface.opacity(0.55))
                        .multilineTextAlignment(.center)
                    Text("Il apparaît après ta première semaine d'activité")
                        .font(.appCaption)
                        .foregroundColor(.appOnSurface.opacity(0.28))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
                .padding(.horizontal, 12)
            } else {
                let sign = score.score >= 0 ? "+" : ""
                let scoreStr = String(format: "%.1f", score.score)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(sign)
                        .font(.appHeadline.weight(.black))
                        .foregroundColor(state.scoreColor.opacity(0.8))
                    Text(scoreStr)
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .foregroundColor(state.scoreColor)
                }
                .padding(.top, 2)

                if let delta = dayDelta, abs(delta) >= 0.1 {
                    let dSign = delta >= 0 ? "+" : ""
                    let dColor: Color = delta >= 0 ? .statusGreen : Color.appDanger
                    HStack(spacing: 3) {
                        Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            .font(.appMicro.weight(.bold))
                        Text("\(dSign)\(String(format: "%.1f", delta)) vs hier")
                            .font(.appCaption.weight(.medium))
                    }
                    .foregroundColor(dColor.opacity(0.85))
                }
                if let hint = priorityGuidance {
                    Text(hint)
                        .font(.appCaption)
                        .foregroundColor(.appOnSurface.opacity(0.45))
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
        let div = Rectangle().fill(Color.appSurfaceInset).frame(width: 1)
        Rectangle()
            .fill(Color.appSurfaceInset)
            .frame(height: 1)
        HStack(alignment: .top, spacing: 0) {
            PhoenixAxisPill(label: "CORPS",  delta: score.axes.workout.delta,   color: state.scoreColor,
                            guidance: g?.workout) {
                NotificationCenter.default.post(name: .navigateToSeance, object: nil)
            }
            div.frame(height: pillDividerHeight(g?.workout,   g?.stress))
            PhoenixAxisPill(label: "MENTAL", delta: score.axes.stress.delta,    color: state.scoreColor,
                            guidance: g?.stress) {
                NotificationCenter.default.post(name: .navigateToRecovery, object: nil)
            }
            div.frame(height: pillDividerHeight(g?.stress,    g?.nutrition))
            PhoenixAxisPill(
                label: "PROGRESSION",
                delta: score.axes.nutrition.delta,
                color: state.scoreColor,
                guidance: g?.nutrition,
                hasBaseline: score.axes.nutrition.hasBaseline,
                infoText: "Évolution de ta nutrition sur les 7 derniers jours vs les 7 précédents"
            ) {
                NotificationCenter.default.post(name: .navigateToNutrition, object: nil)
            }
            div.frame(height: pillDividerHeight(g?.nutrition, g?.spirit))
            if let spirit = score.axes.spirit {
                PhoenixAxisPill(label: "ESPRIT", delta: spirit.delta, color: state.scoreColor,
                                guidance: g?.spirit) {
                    NotificationCenter.default.post(name: .navigateToIntelligence, object: nil)
                }
            } else {
                PhoenixAxisPillInactive(label: "ESPRIT")
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func budgetSection(_ b: BodyBudgetResponse) -> some View {
        Rectangle()
            .fill(Color.appSurfaceInset)
            .frame(height: 1)
        PillarRow(pillars: b.pillars)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
    var hasBaseline: Bool = true
    var infoText: String? = nil
    var onTap: (() -> Void)? = nil
    @State private var showInfo = false

    var body: some View {
        let deltaColor: Color = delta >= 0 ? color : Color.appDanger
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 6, weight: .black)).tracking(0.6)
                .foregroundColor(.appOnSurface.opacity(0.35))
            if hasBaseline {
                HStack(spacing: 2) {
                    Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                    Text(String(format: "%.0f%%", abs(delta)))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(deltaColor)
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.appOnSurface.opacity(0.30))
            }
            if let g = guidance {
                Text(g)
                    .font(.appMicro)
                    .foregroundColor(.appOnSurface.opacity(0.40))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if guidance != nil { onTap?() } }
        .onLongPressGesture { if infoText != nil { showInfo = true } }
        .alert(label, isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            if let info = infoText { Text(info) }
        }
    }
}

struct PhoenixAxisPillInactive: View {
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 6, weight: .black)).tracking(0.6)
                .foregroundColor(.appOnSurface.opacity(0.20))
            Text("—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.appOnSurface.opacity(0.20))
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
    let corePulse = 0.5 + 0.5 * sin(t * 3.0)
    let coreRect = CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16)
    ctx.fill(Path(ellipseIn: coreRect), with: .color(Color.appOnSurface.opacity(0.6 * corePulse)))
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
