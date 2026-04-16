import SwiftUI

struct SplashView: View {
    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double = 0.85
    @State private var nameOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var allOpacity: Double = 1

    var onFinish: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

                // Logo plein écran en fond
                Image("SplashImage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                // Gradient sombre sur le bas pour lisibilité du texte
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color(hex: "080810").opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.45)
                    .ignoresSafeArea()
                }

                // Texte en bas
                VStack(spacing: 0) {
                    Spacer()
                    Text("VINCESEVEN")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(2)
                        .opacity(nameOpacity)

                    Spacer().frame(height: 8)

                    Text("Do More")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.orange)
                        .tracking(4)
                        .opacity(taglineOpacity)

                    Spacer().frame(height: 52)
                }
            }
        }
        .opacity(allOpacity)
        .ignoresSafeArea()
        .onAppear { animate() }
    }

    private func animate() {
        // Logo fade in + scale up
        withAnimation(.easeOut(duration: 0.5)) {
            logoOpacity = 1
            logoScale   = 1.05
        }
        // Logo pulse back
        withAnimation(.easeInOut(duration: 0.3).delay(0.45)) {
            logoScale = 1.0
        }
        // Name fade in
        withAnimation(.easeOut(duration: 0.4).delay(0.45)) {
            nameOpacity = 1
        }
        // Tagline fade in
        withAnimation(.easeOut(duration: 0.4).delay(0.65)) {
            taglineOpacity = 1
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
