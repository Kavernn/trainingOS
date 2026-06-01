import SwiftUI

struct WatchSyncBannerView: View {
    @ObservedObject var sync: WatchSyncService
    let onSync: () -> Void

    private var statusText: String {
        if sync.isSyncing { return "Synchronisation en cours..." }
        if let last = sync.lastSyncDate { return "Sync Watch · \(last.formatted(.relative(presentation: .numeric)))" }
        if let err = sync.lastError { return err }
        return "Apple Watch · Appuyer pour synchroniser"
    }
    private var statusColor: Color {
        if sync.isSyncing { return .cyan }
        if sync.lastError != nil { return .red }
        return .gray
    }

    var body: some View {
        Button(action: { if !sync.isSyncing { onSync() } }) {
            HStack(spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.system(size: 12)).foregroundColor(.cyan)

                Text(statusText)
                    .font(.system(size: 12)).foregroundColor(statusColor)
                    .lineLimit(1)

                Spacer()

                if sync.isSyncing {
                    ProgressView().tint(.cyan).scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12)).foregroundColor(.cyan)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.cyan.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.12), lineWidth: 1))
            .cornerRadius(10)
        }
        .buttonStyle(SpringButtonStyle(scale: 0.97))
        .disabled(sync.isSyncing)
    }
}
