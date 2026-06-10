import SwiftUI

// MARK: - Warmup Guidance Banner
struct WarmupGuidanceBanner: View {
    let guidance: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.appLabel)
                .foregroundColor(.yellow.opacity(0.8))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Échauffement recommandé")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.yellow.opacity(0.9))
                Text(guidance)
                    .font(.appCaption)
                    .foregroundColor(.gray.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.05))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.15), lineWidth: 1))
    }
}
