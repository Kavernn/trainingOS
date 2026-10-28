import SwiftUI

/// Bannière persistante affichant les mutations rejetées par le serveur au
/// cours du rejeu de la file hors-ligne (4xx) ou abandonnées après
/// maxRetries (zombies 5xx). Reste visible jusqu'à ce que l'utilisateur
/// ferme chaque entrée ou "Tout effacer".
///
/// Alimentée par SyncManager.recentDiscards (plafonnée à 20 entrées).
struct SyncDiscardsBanner: View {
    @ObservedObject var sync: SyncManager

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return f
    }()

    var body: some View {
        if sync.recentDiscards.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color.appWarning)
                    Text("\(sync.recentDiscards.count) modification\(sync.recentDiscards.count > 1 ? "s" : "") non envoyée\(sync.recentDiscards.count > 1 ? "s" : "")")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.appTextPrimary)
                    Spacer()
                    Button {
                        sync.clearAllDiscards()
                    } label: {
                        Text("Tout effacer").font(.appMicro).foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.appWarning.opacity(0.12))

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(sync.recentDiscards) { d in
                            discardRow(d)
                            Divider().background(Color.appSeparator)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color.appCard)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appWarning.opacity(0.4), lineWidth: 1))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private func discardRow(_ d: DiscardedMutation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.label)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.appTextPrimary)
                Text(detailLine(d))
                    .font(.appMicro)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                sync.dismissDiscard(id: d.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func detailLine(_ d: DiscardedMutation) -> String {
        let time = Self.timeFormatter.string(from: d.timestamp)
        switch d.reason {
        case .rejected:
            if let msg = d.serverMessage {
                return "Serveur (\(d.statusCode)) : \(msg) · \(time)"
            }
            return "Rejet serveur \(d.statusCode) · \(time)"
        case .zombie:
            return "Abandonnée après \(d.retryCount) tentative\(d.retryCount > 1 ? "s" : "") · \(time)"
        }
    }
}
