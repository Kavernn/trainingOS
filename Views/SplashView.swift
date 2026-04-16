import SwiftUI

struct SplashView: View {
    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double = 0.85
    @State private var nameOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var allOpacity: Double = 1

    var onFinish: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image("SplashImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                Spacer().frame(height: 32)

                // Name
                Text("VINCESEVEN")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .tracking(1.5)
                    .opacity(nameOpacity)

                Spacer().frame(height: 8)

                // Tagline
                Text("Do More")
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(.orange)
                    .tracking(3)
                    .opacity(taglineOpacity)

                Spacer()
            }
        }
        .opacity(allOpacity)
        .onAppear { animate() }
    }

    private func animate() {
        // Logo fade in + scale up
        withAnimation(.easeOut(duration: 0.4)) {
            logoOpacity = 1
            logoScale   = 1.05
        }
        // Logo pulse back
        withAnimation(.easeInOut(duration: 0.25).delay(0.35)) {
            logoScale = 1.0
        }
        // Name fade in
        withAnimation(.easeOut(duration: 0.35).delay(0.35)) {
            nameOpacity = 1
        }
        // Tagline fade in
        withAnimation(.easeOut(duration: 0.35).delay(0.55)) {
            taglineOpacity = 1
        }
        // Fade out everything → finish
        withAnimation(.easeIn(duration: 0.3).delay(1.2)) {
            allOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onFinish()
        }
    }
}
