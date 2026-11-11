import SwiftUI

/// Bandeau d'erreur unique. Remplace l'ancien TopFailureBanner — même composant,
/// deux portes d'entrée : message brut (sections loadError @State) ou agrégateur
/// Loadable (orchestration offline/network globale avec âge des données).
struct ErrorBannerView: View {
    let error: String
    var detail: String? = nil
    var icon: String = "exclamationmark.triangle.fill"
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(detail.map { "\(error). \($0)" } ?? error)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
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

extension ErrorBannerView {
    /// Reprend le comportement de l'ancien TopFailureBanner : rend EmptyView
    /// si aucune panne globale, sinon un ErrorBannerView dérivé (icône wifi.slash
    /// vs triangle, titre Hors ligne/Erreur réseau, âge des dernières données,
    /// retry = aggregator.retryAll). Un seul endroit à maintenir côté UI.
    @ViewBuilder
    static func fromAggregator(_ aggregator: LoadableAggregator) -> some View {
        if aggregator.hasGlobalFailure {
            let isOffline = aggregator.globalKind == .offline
            let ageDetail: String? = aggregator.oldestSuccess.map {
                "Données \($0.formatted(.relative(presentation: .named)))"
            }
            ErrorBannerView(
                error:   isOffline ? "Hors ligne" : "Erreur réseau",
                detail:  ageDetail,
                icon:    isOffline ? "wifi.slash" : "exclamationmark.triangle.fill",
                onRetry: { Task { await aggregator.retryAll() } }
            )
        }
    }
}
