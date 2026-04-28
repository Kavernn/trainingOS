import SwiftUI
import Combine

// MARK: - Modèles
struct AdvancedShard: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGSize
    var rotation: Double
    var size: CGFloat
    var opacity: Double
    var color: Color
    var type: Int
}

struct CrackSegment {
    let points:    [CGPoint]
    let lineWidth: CGFloat
    let opacity:   Double
}

// MARK: - SplashView
struct SplashView: View {

    // ── Logo
    @State private var logoOpacity:     Double  = 0
    @State private var logoScale:       CGFloat = 0.78
    @State private var logoRingOpacity: Double  = 0
    @State private var logoBuildupScale: CGFloat = 1.0

    // ── Ambiance
    @State private var gridOpacity:   Double  = 0
    @State private var glowPulsing:   Bool    = false
    @State private var glowIntensity: Double  = 0.13  // monte au buildup
    @State private var vignetteIntensity: Double = 0  // pulse à l'impact

    // ── Brackets
    @State private var bracketsVisible:    Bool   = false
    @State private var bracketsFlash:      Double = 1.0

    // ── Wordmark
    @State private var vinceVisible:   Bool = false
    @State private var sevenVisible:   Bool = false
    @State private var dividerVisible: Bool = false
    @State private var taglineVisible: Bool = false

    // ── Chromatic aberration (post-impact)
    @State private var chromaticOffset: CGFloat = 0

    // ── Bottom
    @State private var bottomVisible: Bool    = false
    @State private var progressWidth: CGFloat = 0
    @State private var progressPct:   Int     = 0

    // ── Fracture d'Impact
    @State private var cracks:          [CrackSegment] = []
    @State private var crackProgress:   Double = 0
    @State private var crackOpacity:    Double = 0
    @State private var cracks2:         [CrackSegment] = [] // 2e vague
    @State private var crackProgress2:  Double = 0
    @State private var crackOpacity2:   Double = 0

    // ── Flash
    @State private var flashOrangeOpacity: Double = 0
    @State private var flashWhiteOpacity:  Double = 0
    @State private var screenDarken:       Double = 0

    // ── Rings
    @State private var impactTime1: Date? = nil
    @State private var impactTime2: Date? = nil

    // ── Scanline sweep
    @State private var scanlineY:       CGFloat = -100
    @State private var scanlineOpacity: Double  = 0

    // ── FX hérités
    @State private var particles:        [AdvancedShard] = []
    @State private var shatterTriggered: Bool    = false
    @State private var screenShake:      CGFloat = 0
    @State private var allOpacity:       Double  = 1
    @State private var tick:             Bool    = false

    // ── Palette
    private let orange     = Color(red: 240/255, green: 82/255,  blue: 14/255)
    private let orange2    = Color(red: 255/255, green: 107/255, blue: 48/255)
    private let bgColor    = Color(red: 9/255,   green: 9/255,   blue: 9/255)
    private let textColor  = Color(red: 245/255, green: 240/255, blue: 236/255)
    private let mutedColor = Color(red: 74/255,  green: 70/255,  blue: 64/255)
    private let gridLine   = Color(red: 240/255, green: 82/255,  blue: 14/255).opacity(0.18)

    let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    var onFinish: () -> Void

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            ZStack {

                // ─── 1. FOND
                bgColor.ignoresSafeArea()

                // ─── 2. GRILLE
                Canvas { ctx, size in
                    let step: CGFloat = 40
                    var x: CGFloat = 0
                    while x <= size.width {
                        let p = Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        ctx.stroke(p, with: .color(gridLine), lineWidth: 0.5)
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        let p = Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        ctx.stroke(p, with: .color(gridLine), lineWidth: 0.5)
                        y += step
                    }
                }
                .opacity(gridOpacity)

                // ─── 3. GLOW RADIAL (intensité variable)
                RadialGradient(
                    colors: [orange.opacity(glowIntensity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(geo.size.width, geo.size.height) * 0.72
                )
                .scaleEffect(glowPulsing ? 1.22 : 1.0)
                .animation(
                    .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                    value: glowPulsing
                )

                // ─── 4. CANVAS FX
                Canvas { ctx, size in
                    let _ = tick
                    let center = CGPoint(x: size.width / 2, y: size.height * 0.42)

                    // ── Shockwave rings — Impact 1
                    if let t = impactTime1 {
                        drawRings(ctx: ctx, size: size, center: center,
                                  elapsed: Date().timeIntervalSince(t),
                                  baseR: 76, scale: 1.0)
                    }

                    // ── Shockwave rings — Impact 2 (plus grands)
                    if let t = impactTime2 {
                        drawRings(ctx: ctx, size: size, center: center,
                                  elapsed: Date().timeIntervalSince(t),
                                  baseR: 76, scale: 1.5)
                    }

                    // ── Fissures vague 1
                    drawCracks(ctx: ctx, cracks: cracks,
                               progress: crackProgress, opacity: crackOpacity)

                    // ── Fissures vague 2
                    drawCracks(ctx: ctx, cracks: cracks2,
                               progress: crackProgress2, opacity: crackOpacity2)

                    // ── Scanline sweep
                    if scanlineOpacity > 0 {
                        let sw = size.width
                        let scanH: CGFloat = 3
                        let gradient = ctx.resolve(
                            GraphicsContext.Shading.linearGradient(
                                Gradient(colors: [.clear,
                                                  Color.white.opacity(0.55 * scanlineOpacity),
                                                  .clear]),
                                startPoint: CGPoint(x: 0, y: scanlineY),
                                endPoint:   CGPoint(x: sw, y: scanlineY)
                            )
                        )
                        ctx.fill(
                            Path(CGRect(x: 0, y: scanlineY - scanH/2,
                                        width: sw, height: scanH)),
                            with: gradient
                        )
                    }

                    // ── Particules
                    for shard in particles {
                        var inner = ctx
                        inner.opacity = shard.opacity
                        inner.translateBy(x: shard.position.x, y: shard.position.y)
                        inner.rotate(by: .degrees(shard.rotation))
                        inner.scaleBy(x: shard.size / 10, y: shard.size / 10)
                        let path = Path { p in
                            if shard.type == 0 {
                                p.move(to: .zero)
                                p.addLine(to: CGPoint(x: 10, y: 2))
                                p.addLine(to: CGPoint(x: 5,  y: 10))
                            } else {
                                p.move(to: CGPoint(x: 0,  y: 3))
                                p.addLine(to: CGPoint(x: 10, y: 0))
                                p.addLine(to: CGPoint(x: 8,  y: 10))
                                p.addLine(to: CGPoint(x: 2,  y: 8))
                            }
                            p.closeSubpath()
                        }
                        inner.fill(path, with: .color(shard.color))
                    }
                }
                .blendMode(.plusLighter)

                // ─── 5. VIGNETTE (pulse à l'impact)
                if vignetteIntensity > 0 {
                    RadialGradient(
                        colors: [.clear, Color.black.opacity(vignetteIntensity)],
                        center: .center,
                        startRadius: geo.size.width * 0.25,
                        endRadius:   geo.size.width * 0.85
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                // ─── 6. FLASH ORANGE
                Color(red: 240/255, green: 82/255, blue: 14/255)
                    .opacity(flashOrangeOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .blendMode(.screen)

                // ─── 7. FLASH BLANC
                Color.white
                    .opacity(flashWhiteOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // ─── 8. ASSOMBRISSEMENT post-flash
                Color.black
                    .opacity(screenDarken)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // ─── 9. LAYOUT PRINCIPAL
                VStack(spacing: 0) {

                    // Status dot
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(orange.opacity(0.3), lineWidth: 3)
                                .frame(width: 14, height: 14)
                                .scaleEffect(glowPulsing ? 2.0 : 1.0)
                                .opacity(glowPulsing ? 0 : 0.5)
                                .animation(
                                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                                    value: glowPulsing
                                )
                            Circle().fill(orange).frame(width: 6, height: 6)
                        }
                        Text("SYSTEM ACTIVE")
                            .font(.system(size: 10, weight: .light))
                            .kerning(2.5)
                            .foregroundColor(mutedColor)
                    }
                    .opacity(bottomVisible ? 1 : 0)
                    .padding(.top, geo.safeAreaInsets.top + 16)

                    Spacer()

                    VStack(spacing: 26) {

                        // Logo + ring
                        ZStack {
                            // Outer glow ring (buildup)
                            RoundedRectangle(cornerRadius: 34)
                                .stroke(orange.opacity(logoRingOpacity * 0.3), lineWidth: 6)
                                .frame(width: 162, height: 162)
                                .blur(radius: 8)

                            RoundedRectangle(cornerRadius: 30)
                                .stroke(
                                    LinearGradient(
                                        colors: [orange.opacity(0.65), orange.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                                .frame(width: 152, height: 152)
                                .opacity(logoRingOpacity)
                                .brightness(bracketsFlash - 1.0)

                            Image("SplashImage")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 26))
                        }
                        .opacity(logoOpacity)
                        .scaleEffect(shatterTriggered
                                     ? 1.06
                                     : logoScale * logoBuildupScale)
                        .offset(x: screenShake * 0.35)
                        .animation(.spring(response: 0.45, dampingFraction: 0.50), value: shatterTriggered)

                        // VINCE / SEVEN avec chromatic aberration
                        ZStack {
                            // Couche Rouge (décalée à gauche)
                            VStack(spacing: -2) {
                                Text("VINCE")
                                    .font(.system(size: 56, weight: .black))
                                    .kerning(3)
                                    .foregroundColor(.red.opacity(0.7))
                                Text("SEVEN")
                                    .font(.system(size: 56, weight: .ultraLight))
                                    .kerning(14)
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .offset(x: -chromaticOffset, y: 0)
                            .blendMode(.screen)

                            // Couche Cyan (décalée à droite)
                            VStack(spacing: -2) {
                                Text("VINCE")
                                    .font(.system(size: 56, weight: .black))
                                    .kerning(3)
                                    .foregroundColor(Color(red: 0, green: 0.9, blue: 1.0).opacity(0.7))
                                Text("SEVEN")
                                    .font(.system(size: 56, weight: .ultraLight))
                                    .kerning(14)
                                    .foregroundColor(Color(red: 0, green: 0.9, blue: 1.0).opacity(0.7))
                            }
                            .offset(x: chromaticOffset, y: 0)
                            .blendMode(.screen)

                            // Couche principale
                            VStack(spacing: -2) {
                                Text("VINCE")
                                    .font(.system(size: 56, weight: .black))
                                    .kerning(3)
                                    .foregroundColor(textColor)
                                    .opacity(vinceVisible ? 1 : 0)
                                    .offset(y: vinceVisible ? 0 : 22)

                                Text("SEVEN")
                                    .font(.system(size: 56, weight: .ultraLight))
                                    .kerning(14)
                                    .foregroundColor(orange)
                                    .opacity(sevenVisible ? 1 : 0)
                                    .offset(y: sevenVisible ? 0 : 22)
                            }
                        }
                        .offset(x: screenShake)

                        // Séparateur + DO MORE
                        VStack(spacing: 14) {
                            LinearGradient(
                                colors: [.clear, orange, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 120, height: 1)
                            .opacity(dividerVisible ? 1 : 0)

                            Text("DO MORE")
                                .font(.system(size: 11, weight: .light))
                                .kerning(5)
                                .foregroundColor(mutedColor)
                                .opacity(taglineVisible ? 1 : 0)
                        }
                    }

                    Spacer()

                    // Progress + version
                    VStack(spacing: 14) {
                        VStack(spacing: 8) {
                            HStack {
                                Text("LOADING")
                                    .font(.system(size: 10, weight: .light))
                                    .kerning(2)
                                    .foregroundColor(mutedColor)
                                Spacer()
                                Text("\(progressPct)%")
                                    .font(.system(size: 10, weight: .light))
                                    .kerning(1)
                                    .foregroundColor(mutedColor)
                            }
                            .frame(width: 260)

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.07))
                                    .frame(width: 260, height: 2)
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [orange, orange2],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                                    .frame(width: max(4, 260 * progressWidth), height: 2)
                                    .shadow(color: orange.opacity(0.7), radius: 5)
                            }
                        }
                        Text("BUILD 2025.1")
                            .font(.system(size: 10, weight: .ultraLight))
                            .kerning(1.5)
                            .foregroundColor(mutedColor)
                    }
                    .opacity(bottomVisible ? 1 : 0)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom + 36, 50))
                }

                // ─── 10. BRACKETS
                bracketOverlay(geo: geo)
                    .opacity(bracketsVisible ? bracketsFlash : 0)
                    .scaleEffect(bracketsVisible ? 1 : 0.6)
            }
        }
        .opacity(allOpacity)
        .ignoresSafeArea()
        .onReceive(timer) { _ in updateParticles() }
        .onAppear {
            glowPulsing = true
            generateCracks(target: &cracks,  mainCount: 13, branchChance: 0.85)
            generateCracks(target: &cracks2, mainCount: 8,  branchChance: 0.60)
            startSequence()
        }
    }

    // MARK: - Brackets
    @ViewBuilder
    private func bracketOverlay(geo: GeometryProxy) -> some View {
        let arm:   CGFloat = 24
        let thick: CGFloat = 1.5
        let m:     CGFloat = 24

        ZStack {
            Path { p in
                p.move(to: CGPoint(x: m, y: m + arm))
                p.addLine(to: CGPoint(x: m, y: m))
                p.addLine(to: CGPoint(x: m + arm, y: m))
            }.stroke(orange, style: StrokeStyle(lineWidth: thick, lineCap: .square))

            Path { p in
                let x = geo.size.width - m
                p.move(to: CGPoint(x: x - arm, y: m))
                p.addLine(to: CGPoint(x: x, y: m))
                p.addLine(to: CGPoint(x: x, y: m + arm))
            }.stroke(orange, style: StrokeStyle(lineWidth: thick, lineCap: .square))

            Path { p in
                let y = geo.size.height - m
                p.move(to: CGPoint(x: m, y: y - arm))
                p.addLine(to: CGPoint(x: m, y: y))
                p.addLine(to: CGPoint(x: m + arm, y: y))
            }.stroke(orange, style: StrokeStyle(lineWidth: thick, lineCap: .square))

            Path { p in
                let x = geo.size.width  - m
                let y = geo.size.height - m
                p.move(to: CGPoint(x: x - arm, y: y))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y - arm))
            }.stroke(orange, style: StrokeStyle(lineWidth: thick, lineCap: .square))
        }
    }

    // MARK: - Canvas helpers
    private func drawRings(ctx: GraphicsContext, size: CGSize,
                           center: CGPoint, elapsed: TimeInterval,
                           baseR: CGFloat, scale: CGFloat) {
        // Ring 1 — orange
        let r1p = min(elapsed / 0.70, 1.0)
        if r1p < 1.0 {
            let r = baseR * scale * (0.1 + CGFloat(r1p) * 3.0)
            let a = 0.85 * (1.0 - r1p * r1p)
            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
            ctx.stroke(ring, with: .color(orange.opacity(a)), lineWidth: 3.5)
        }
        // Ring 2 — orange2
        let r2p = min(max(0, elapsed - 0.12) / 0.90, 1.0)
        if r2p < 1.0 {
            let r = baseR * scale * (0.1 + CGFloat(r2p) * 4.5)
            let a = 0.50 * (1.0 - r2p)
            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
            ctx.stroke(ring, with: .color(orange2.opacity(a)), lineWidth: 2.0)
        }
        // Ring 3 — blanc large
        let r3p = min(max(0, elapsed - 0.26) / 1.20, 1.0)
        if r3p < 1.0 {
            let r = baseR * scale * (0.1 + CGFloat(r3p) * 7.0)
            let a = 0.20 * (1.0 - r3p)
            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
            ctx.stroke(ring, with: .color(Color.white.opacity(a)), lineWidth: 1.0)
        }
    }

    private func drawCracks(ctx: GraphicsContext, cracks: [CrackSegment],
                             progress: Double, opacity: Double) {
        guard opacity > 0 else { return }
        let total = cracks.count
        for (i, crack) in cracks.enumerated() {
            let threshold = Double(i) / Double(max(total, 1))
            guard progress >= threshold, let first = crack.points.first else { continue }
            let localProg  = min(1.0, (progress - threshold) * Double(total))
            let totalPts   = crack.points.count
            let visibleCnt = max(2, Int(Double(totalPts) * localProg))
            let visible    = Array(crack.points.prefix(visibleCnt))

            var path = Path()
            path.move(to: first)
            for pt in visible.dropFirst() { path.addLine(to: pt) }

            var inner = ctx
            inner.opacity = opacity * crack.opacity
            inner.stroke(path, with: .color(.white),
                         style: StrokeStyle(lineWidth: crack.lineWidth,
                                            lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Génération fissures
    private func generateCracks(target: inout [CrackSegment],
                                 mainCount: Int, branchChance: Double) {
        let screen = UIScreen.main.bounds
        let cx = screen.width / 2
        let cy = screen.height * 0.42
        var result: [CrackSegment] = []

        for i in 0..<mainCount {
            let baseAngle = (Double(i) / Double(mainCount)) * 2 * .pi
            var angle     = baseAngle + Double.random(in: -0.35...0.35)
            var current   = CGPoint(x: cx, y: cy)
            var points    = [current]
            let totalLen  = CGFloat.random(in: screen.width * 0.22...screen.width * 0.65)
            let numSegs   = Int.random(in: 3...7)

            for _ in 0..<numSegs {
                angle += Double.random(in: -0.32...0.32)
                let seg = totalLen / CGFloat(numSegs)
                let next = CGPoint(x: current.x + cos(angle) * seg,
                                   y: current.y + sin(angle) * seg)
                points.append(next)
                current = next
            }

            result.append(CrackSegment(
                points:    points,
                lineWidth: CGFloat.random(in: 0.8...2.2),
                opacity:   Double.random(in: 0.6...1.0)
            ))

            if Double.random(in: 0...1) < branchChance, points.count > 2 {
                let from   = points[Int.random(in: 1...min(2, points.count - 1))]
                var bAngle = angle + Double.random(in: 0.4...1.1) * (Bool.random() ? 1 : -1)
                let brLen  = CGFloat.random(in: 40...120)
                var bPts   = [from]
                var bCur   = from

                for _ in 0..<Int.random(in: 2...5) {
                    bAngle += Double.random(in: -0.28...0.28)
                    let seg = brLen / 3
                    let next = CGPoint(x: bCur.x + cos(bAngle) * seg,
                                       y: bCur.y + sin(bAngle) * seg)
                    bPts.append(next)
                    bCur = next
                }

                result.append(CrackSegment(
                    points:    bPts,
                    lineWidth: CGFloat.random(in: 0.4...1.2),
                    opacity:   Double.random(in: 0.25...0.55)
                ))
            }
        }

        target = result.shuffled()
    }

    // MARK: - Séquence cinématique (7s total)
    private func startSequence() {

        // ── Intro
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.easeOut(duration: 1.0)) { gridOpacity = 0.55 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeOut(duration: 1.2)) { logoOpacity = 1; logoScale = 1.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) {
            withAnimation(.easeOut(duration: 0.7)) { logoRingOpacity = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) { vinceVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) { sevenVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.00) {
            withAnimation(.easeOut(duration: 0.5)) { dividerVisible = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { bracketsVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.12) {
            withAnimation(.easeOut(duration: 0.5)) { taglineVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
            withAnimation(.easeOut(duration: 0.5)) { bottomVisible = true }
        }

        // ── PRÉ-IMPACT BUILDUP (t=1.6s) : glow monte, logo pulse, haptics légers
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.60) {
            buildupSequence()
        }

        // ── IMPACT 1 (t=2.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.20) {
            triggerImpact1()
        }

        // ── IMPACT 2 — deuxième onde (t=2.65s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) {
            triggerImpact2()
        }

        // ── Chromatic aberration (t=2.25s → settle à 2.9s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.25) {
            withAnimation(.easeOut(duration: 0.10)) { chromaticOffset = 9 }
            withAnimation(.easeInOut(duration: 0.60).delay(0.10)) { chromaticOffset = 0 }
        }

        // ── Scanline sweep post-impact (t=2.30s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.30) {
            scanlineY       = -40
            scanlineOpacity = 1.0
            withAnimation(.linear(duration: 0.55)) { scanlineY = UIScreen.main.bounds.height + 40 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.2)) { scanlineOpacity = 0 }
            }
        }

        // ── Progress bar
        animateProgress()

        // ── Sortie (t=6.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.50) {
            withAnimation(.easeOut(duration: 0.7)) { allOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onFinish() }
        }
    }

    // MARK: - Buildup
    private func buildupSequence() {
        // Glow monte
        withAnimation(.easeIn(duration: 0.55)) { glowIntensity = 0.35 }

        // Logo pulse subtil (×3 rapid)
        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()
        for i in 0..<3 {
            let d = Double(i) * 0.14
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.easeInOut(duration: 0.06)) { logoBuildupScale = 1.035 }
                withAnimation(.easeInOut(duration: 0.06).delay(0.06)) { logoBuildupScale = 1.0 }
                light.impactOccurred(intensity: 0.3 + Double(i) * 0.15)
            }
        }

        // Vignette commence à apparaître
        withAnimation(.easeIn(duration: 0.50)) { vignetteIntensity = 0.35 }
    }

    // MARK: - Impact 1 (principal)
    private func triggerImpact1() {
        // Flash orange → blanc (one-two punch)
        flashOrangeOpacity = 0.65
        withAnimation(.easeOut(duration: 0.08)) { flashOrangeOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            flashWhiteOpacity = 0.70
            withAnimation(.easeOut(duration: 0.20)) { flashWhiteOpacity = 0 }
        }

        // Assombrissement bref post-flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.10))  { screenDarken = 0.30 }
            withAnimation(.easeOut(duration: 0.35).delay(0.10)) { screenDarken = 0 }
        }

        // Rings vague 1
        impactTime1 = Date()

        // Fissures vague 1
        crackOpacity  = 1.0
        crackProgress = 0.0
        withAnimation(.easeOut(duration: 0.28)) { crackProgress = 1.0 }

        // Logo spring + shake violent
        shatterTriggered = true
        withAnimation(.default.repeatCount(6, autoreverses: true)) { screenShake = 9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.18)) { screenShake = 0 }
        }

        // Brackets flash
        withAnimation(.easeOut(duration: 0.05)) { bracketsFlash = 3.0 }
        withAnimation(.easeOut(duration: 0.35).delay(0.05)) { bracketsFlash = 1.0 }

        // Vignette pulse fort
        withAnimation(.easeOut(duration: 0.08)) { vignetteIntensity = 0.80 }
        withAnimation(.easeOut(duration: 0.60).delay(0.10)) { vignetteIntensity = 0.10 }

        // Glow redescend
        withAnimation(.easeOut(duration: 1.0)) { glowIntensity = 0.13 }

        // Particules vague 1
        createExplosion(count: 130, spreadMultiplier: 1.0)

        // Haptics séquence "craquage de verre"
        let heavy  = UIImpactFeedbackGenerator(style: .heavy)
        let rigid  = UIImpactFeedbackGenerator(style: .rigid)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let light  = UIImpactFeedbackGenerator(style: .light)
        [heavy, rigid, medium, light].forEach { $0.prepare() }

        heavy.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.050) { rigid.impactOccurred(intensity: 0.95) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.100) { rigid.impactOccurred(intensity: 0.78) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.165) { medium.impactOccurred(intensity: 0.88) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.245) { medium.impactOccurred(intensity: 0.60) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.350) { light.impactOccurred(intensity: 0.75) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.490) { light.impactOccurred(intensity: 0.45) }
    }

    // MARK: - Impact 2 (deuxième onde / réplique)
    private func triggerImpact2() {
        // Flash orange plus doux
        flashOrangeOpacity = 0.35
        withAnimation(.easeOut(duration: 0.25)) { flashOrangeOpacity = 0 }

        // Rings vague 2 (plus grandes)
        impactTime2 = Date()

        // Fissures vague 2
        crackOpacity2  = 0.80
        crackProgress2 = 0.0
        withAnimation(.easeOut(duration: 0.40)) { crackProgress2 = 1.0 }

        // Fondu des fissures (t+2.0s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.80) {
            withAnimation(.easeOut(duration: 1.80)) { crackOpacity  = 0 }
            withAnimation(.easeOut(duration: 1.50)) { crackOpacity2 = 0 }
        }

        // Mini shake
        withAnimation(.default.repeatCount(3, autoreverses: true)) { screenShake = 5 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeOut(duration: 0.15)) { screenShake = 0 }
        }

        // Particules vague 2 (moins, plus petites)
        createExplosion(count: 60, spreadMultiplier: 0.65)

        // Haptics réplique
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let light  = UIImpactFeedbackGenerator(style: .light)
        [medium, light].forEach { $0.prepare() }

        medium.impactOccurred(intensity: 0.80)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { medium.impactOccurred(intensity: 0.50) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { light.impactOccurred(intensity: 0.60) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) { light.impactOccurred(intensity: 0.30) }
    }

    // MARK: - Progress
    private func animateProgress() {
        let steps: [(w: CGFloat, pct: Int, delay: Double)] = [
            (0.38,  38, 1.30),
            (0.61,  61, 2.50),
            (0.84,  84, 3.60),
            (0.95,  95, 4.50),
            (1.00, 100, 5.60)
        ]
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) {
                withAnimation(.easeInOut(duration: 0.60)) { progressWidth = step.w }
                progressPct = step.pct
            }
        }
    }

    // MARK: - Explosion particules
    private func createExplosion(count: Int, spreadMultiplier: CGFloat) {
        let cx   = UIScreen.main.bounds.midX
        let cy   = UIScreen.main.bounds.height * 0.42
        let gold = Color(hex: "FFCC00")
        let white = Color.white

        for _ in 0..<count {
            let pick = Int.random(in: 0...2)
            let color: Color = pick == 0 ? orange : pick == 1 ? gold : white
            particles.append(AdvancedShard(
                position: CGPoint(x: cx, y: cy),
                velocity: CGSize(
                    width:  CGFloat.random(in: -24...24) * spreadMultiplier,
                    height: CGFloat.random(in: -32...16) * spreadMultiplier
                ),
                rotation: Double.random(in: 0...360),
                size:     CGFloat.random(in: 2...15) * spreadMultiplier,
                opacity:  1.0,
                color:    color,
                type:     Int.random(in: 0...1)
            ))
        }
    }

    // MARK: - Physique 60 fps
    private func updateParticles() {
        tick.toggle()
        for i in particles.indices {
            particles[i].position.x      += particles[i].velocity.width
            particles[i].position.y      += particles[i].velocity.height
            particles[i].velocity.height += 0.44
            particles[i].rotation        += particles[i].velocity.width * 2
            particles[i].opacity         -= 0.010
        }
        particles.removeAll { $0.opacity <= 0 }
    }
}
