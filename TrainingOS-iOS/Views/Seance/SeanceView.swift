import SwiftUI

struct SeanceView: View {
    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                Text("Séance")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text("En cours de développement")
                    .foregroundColor(.gray)
            }
        }
        .navigationBarHidden(true)
    }
}
