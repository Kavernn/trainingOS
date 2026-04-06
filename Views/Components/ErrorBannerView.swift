import SwiftUI

struct ErrorBannerView: View {
    let error: String
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button("Réessayer", action: onRetry)
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
            }
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}
