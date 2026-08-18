import SwiftUI

// MARK: - Warmup Guidance Banner
struct WarmupGuidanceBanner: View {
    let guidance: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.appLabel)
                .foregroundColor(Color.forge.opacity(0.85))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Échauffement recommandé")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.forge)
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
        .glassCard(cornerRadius: 10)
    }
}
