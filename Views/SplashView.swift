import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 1.05
    var onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image("SplashImage")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(opacity)
                .scaleEffect(scale)

            // Dark gradient overlay at bottom for polish
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                opacity = 1
                scale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeIn(duration: 0.5)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onFinish()
                }
            }
        }
    }
}
