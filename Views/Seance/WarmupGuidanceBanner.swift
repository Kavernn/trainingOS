import SwiftUI

// MARK: - Warmup Guidance Banner
struct WarmupGuidanceBanner: View {
    let guidance: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.appLabel)
                .foregroundColor(Color.forge.opacity(0.65))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Échauffement recommandé")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.appTextSecondary)
                Text(guidance)
                    .font(.appCaption)
                    .foregroundColor(Color.appTextMuted)
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
        .background(Color.appSurfaceInset.opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appSeparator, lineWidth: .appHairline)
        )
    }
}
