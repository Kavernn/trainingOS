import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var action: (() -> Void)? = nil
    var actionLabel: String = "Ajouter"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
