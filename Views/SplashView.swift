import SwiftUI

// MARK: - Shattered character

private struct ShardChar: View {
    let char: String
    let index: Int
    let triggered: Bool

    // Deterministic "random" per character index
    private var offsetX: CGFloat { CGFloat((index * 73 + 11) % 160) - 80 }
    private var offsetY: CGFloat { CGFloat((index * 47 + 29) % 120) - 60 }
    private var rotation: Double { Double((index * 61 + 17) % 120) - 60 }

    var body: some View {
        Text(char)
            .font(.system(size: 42, weight: .black, design: .rounded))
            .foregroundColor(.orange)
            .tracking(4)
            .offset(x: triggered ? 0 : offsetX,
                    y: triggered ? 0 : offsetY)
            .rotationEffect(.degrees(triggered ? 0 : rotation))
            .opacity(triggered ? 1 : 0)
            .blur(radius: triggered ? 0 : 6)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.62, blendDuration: 0)
                .delay(Double(index) * 0.04),
                value: triggered
            )
    }
}

// MARK: - SplashView

struct SplashView: View {
    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double  = 0.92
    @State private var shatterTriggered   = false
    @State private var allOpacity: Double = 1

    var onFinish: () -> Void

    private let tagline = Array("DO MORE").map(String.init)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

                // Logo — scaledToFit pour rester dans l'écran
                Image("SplashImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                // Gradient bas pour lisibilité
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color(hex: "080810").opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.38)
                    .ignoresSafeArea()
                }

                // DO MORE — shatter
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(tagline.indices, id: \.self) { i in
                            ShardChar(char: tagline[i], index: i, triggered: shatterTriggered)
                        }
                    }
                    Spacer().frame(height: 60)
                }
            }
        }
        .opacity(allOpacity)
        .ignoresSafeArea()
        .onAppear { animate() }
    }

    private func animate() {
        // Logo pulse
        withAnimation(.easeOut(duration: 0.5)) {
            logoOpacity = 1
            logoScale   = 1.04
        }
        withAnimation(.easeInOut(duration: 0.25).delay(0.45)) {
            logoScale = 1.0
        }

        // Shatter DO MORE
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            shatterTriggered = true
        }

        // Fade out → finish après 3.5s total
        withAnimation(.easeIn(duration: 0.35).delay(3.15)) {
            allOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            onFinish()
        }
    }
}
