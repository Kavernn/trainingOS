import SwiftUI

// MARK: - Protocol d'agrégation

/// Protocole minimal exposé par chaque Loadable, pour permettre l'agrégation
/// hétérogène (Loadable<X>, Loadable<Y>…) sans friction generics.
@MainActor
protocol LoadableStateView {
    var hasError: Bool { get }
    var hasValue: Bool { get }
    var errorKind: LoadError.Kind? { get }
    var errorMessage: String? { get }
    var lastUpdated: Date? { get }
    var isLoading: Bool { get }
}

extension LoadableStateView {
    /// true si ce Loadable a été déclenché (en cours, en erreur, ou succès passé).
    /// Les Loadables jamais touchés (ex. onglet jamais ouvert) sont ignorés par
    /// l'agrégateur ET par retryAll.
    var wasAttempted: Bool { isLoading || hasError || lastUpdated != nil }
}

extension Loadable: LoadableStateView {
    var hasError: Bool          { error != nil }
    var hasValue: Bool          { value != nil }
    var errorKind: LoadError.Kind? { error?.kind }
    var errorMessage: String?   { error?.message }
}

// MARK: - Agrégateur

/// Un groupe = N Loadable alimentés par un même retry (ex. loadData() couvre
/// 12 Loadables). retryAll ne relance qu'un groupe si au moins un de ses
/// states est tenté — évite de ping un endpoint qu'on n'a jamais consulté.
@MainActor
struct LoadableRetryGroup {
    let states: [any LoadableStateView]
    let retry: () async -> Void
}

@MainActor
struct LoadableAggregator {
    let groups: [LoadableRetryGroup]

    var allStates: [any LoadableStateView] { groups.flatMap { $0.states } }
    var tried:     [any LoadableStateView] { allStates.filter { $0.wasAttempted } }

    private var triedKinds: [LoadError.Kind] { tried.compactMap { $0.errorKind } }

    /// Toute erreur .offline / .network dans un Loadable tenté → bandeau top.
    /// Les .server / .decoding sont gérées par SectionErrorView, pas ici.
    var hasGlobalFailure: Bool {
        triedKinds.contains { $0 == .offline || $0 == .network }
    }

    /// Priorité offline > network pour l'icône.
    var globalKind: LoadError.Kind? {
        if triedKinds.contains(.offline) { return .offline }
        if triedKinds.contains(.network) { return .network }
        return nil
    }

    /// Date la plus ancienne parmi les succès/seed des Loadables tentés.
    /// Sert à afficher "données d'il y a X" dans le bandeau top.
    var oldestSuccess: Date? {
        tried.compactMap { $0.lastUpdated }.min()
    }

    /// Relance uniquement les groupes dont au moins un state est tenté.
    func retryAll() async {
        for group in groups where group.states.contains(where: { $0.wasAttempted }) {
            await group.retry()
        }
    }
}

// MARK: - Views

/// Bandeau top des pages orchestrées (ex. Stats). Visible UNIQUEMENT quand
/// l'agrégateur détecte une panne globale (offline/network). Un seul Réessayer
/// relance tous les groupes affectés.
struct StatsTopBanner: View {
    let aggregator: LoadableAggregator

    var body: some View {
        if aggregator.hasGlobalFailure {
            HStack(spacing: 8) {
                Image(systemName: aggregator.globalKind == .offline
                      ? "wifi.slash"
                      : "exclamationmark.triangle")
                    .foregroundColor(.forge)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(aggregator.globalKind == .offline ? "Hors ligne" : "Erreur réseau")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let age = aggregator.oldestSuccess {
                        Text("Données \(age.formatted(.relative(presentation: .named)))")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    Task { await aggregator.retryAll() }
                } label: {
                    Text("Réessayer")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.forge)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityHint("Relance les sections affectées")
            }
            .padding(12)
            .background(Color.appCard)
            .cornerRadius(8)
        }
    }
}

/// Carte / bannière d'erreur à placer AU-DESSUS d'une section de données.
/// - .server / .decoding → bannière avec message serveur + Réessayer local.
/// - .offline / .network ET pas de value → "Indisponible" compact, sans bouton
///   (le StatsTopBanner global gère la relance).
/// - Autrement : rien (section affiche ses données, stale ou fraîches).
struct SectionErrorView: View {
    let state: any LoadableStateView
    let retry: () async -> Void

    var body: some View {
        if state.hasError {
            if case .server   = state.errorKind { serverBanner }
            else if case .decoding = state.errorKind { serverBanner }
            else if !state.hasValue { unavailableLabel }
        }
    }

    private var unavailableLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.appTextSecondary)
                .accessibilityHidden(true)
            Text("Indisponible")
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var serverBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.forge)
                .accessibilityHidden(true)
            Text(state.errorMessage ?? "Erreur")
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                Task { await retry() }
            } label: {
                Text("Réessayer")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.forge)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityHint("Relance le chargement")
        }
    }
}
