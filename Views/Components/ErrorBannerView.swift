import SwiftUI

struct ErrorBannerView: View {
    let error: String
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundColor(.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(error)
            HStack(spacing: 8) {
                if let onRetry {
                    Button(action: onRetry) {
                        Text("Réessayer")
                            .font(.subheadline.bold())
                            .fixedSize()
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .foregroundColor(.appDanger)
                }
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.appTextSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Masquer le message d’erreur")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.appDanger.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}
