import SwiftUI

struct AppLoadingView: View {
    var color: Color = Color.forge
    var scale: CGFloat = 1.3

    var body: some View {
        ProgressView()
            .tint(color)
            .scaleEffect(scale)
    }
}
