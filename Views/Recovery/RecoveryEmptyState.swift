import SwiftUI

struct RecoveryEmptyState: View {
    var onAddTap: (() -> Void)? = nil

    var body: some View {
        EmptyStateView(
            icon: "moon.zzz.fill",
            title: "Comment tu te sens ce matin ?",
            subtitle: "30 secondes suffisent.",
            action: onAddTap,
            actionLabel: "Logger ma récupération"
        )
    }
}
