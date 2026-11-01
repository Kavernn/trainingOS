import SwiftUI

// MARK: - LoadError

/// Erreur présentable à l'utilisateur, mappée depuis les erreurs techniques réelles
/// qu'APIService peut jeter sur une LECTURE. Les mutations (queuedOffline, écritures)
/// ne passent pas par Loadable — guard défensif ci-dessous au cas où.
struct LoadError: Error, Equatable {
    enum Kind: Equatable {
        case server(Int)
        case network
        case offline
        case decoding
        case unknown
    }
    let kind: Kind
    let message: String

    /// Retourne nil pour les erreurs à ignorer (annulations, mutations différées).
    static func from(_ error: Error) -> LoadError? {
        if error is CancellationError { return nil }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return nil
            case .notConnectedToInternet:
                return .init(kind: .offline, message: "Hors ligne")
            case .timedOut:
                return .init(kind: .network, message: "Délai dépassé — réessayez")
            default:
                return .init(kind: .network, message: "Erreur réseau")
            }
        }

        if let api = error as? APIError {
            switch api {
            case .queuedOffline:
                // ponytail: Loadable = lectures seulement. Un read ne jettera jamais
                // queuedOffline, mais switch exhaustif = garde-fou compilateur si un
                // futur refactor change ça. Message serait mensonger → nil.
                return nil
            case .serverError(let code, let msg):
                let message = msg.isEmpty ? "Erreur serveur (\(code))" : msg
                return .init(kind: .server(code), message: message)
            case .invalidURL(let path):
                return .init(kind: .unknown, message: "URL invalide — \(path)")
            case .decodingFailed(let endpoint, let underlying):
                #if DEBUG
                return .init(kind: .decoding, message: "Décodage \(endpoint) : \(underlying)")
                #else
                return .init(kind: .decoding, message: "Données incompatibles sur \(endpoint)")
                #endif
            }
        }

        return .init(kind: .unknown, message: "Erreur inattendue")
    }
}

// MARK: - Loadable

/// État de chargement cache-aware pour une lecture. L'appelant lit le cache et
/// passe la valeur dans `seed` ; `operation` DOIT lever en cas d'échec (contrairement
/// à `fetchWithCache` qui avale les erreurs du refresh en arrière-plan). Un échec
/// avec seed présente une bannière « données périmées » ; sans seed, une carte
/// d'erreur avec « Réessayer ».
struct Loadable<Value> {
    var value: Value?
    var isLoading = false
    var error: LoadError?
    var lastUpdated: Date?

    /// Chargement initial = isLoading && aucune valeur à afficher (ni seed, ni fresh).
    var isInitialLoad: Bool { isLoading && value == nil }

    @MainActor
    mutating func load(
        seed: Value? = nil,
        _ operation: () async throws -> Value
    ) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if value == nil, let seed { value = seed }

        do {
            value = try await operation()
            error = nil
            lastUpdated = .now
        } catch {
            if let presentable = LoadError.from(error) {
                self.error = presentable
            }
        }
    }
}

// MARK: - LoadableSection

/// Vue de section standardisée : squelette au premier chargement, bannière périmée
/// si refresh échoue avec cache, carte d'erreur si tout échoue sans cache, état vide
/// distinct de l'erreur.
struct LoadableSection<Value, Content: View>: View {
    let title: String
    let state: Loadable<Value>
    let isEmpty: (Value) -> Bool
    let emptyMessage: String
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if state.isInitialLoad {
                placeholder
            } else if let value = state.value {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = state.error { staleBanner(error) }
                    if isEmpty(value) { emptyView } else { content(value) }
                }
            } else if let error = state.error {
                errorCard(error)
            } else {
                emptyView
            }
        }
    }

    private var placeholder: some View {
        LoadingSkeleton(style: .card)
            .opacity(reduceMotion ? 0.6 : 1.0)
            .accessibilityElement()
            .accessibilityLabel("Chargement de \(title)")
    }

    private func errorCard(_ error: LoadError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Erreur de chargement", systemImage: "exclamationmark.triangle")
                .font(.appLabel.weight(.semibold))
                .foregroundColor(.forge)
            Text(error.message)
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            retryButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) : erreur de chargement. \(error.message)")
    }

    private func staleBanner(_ error: LoadError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle")
                .accessibilityHidden(true)
            Text(staleText(error))
                .font(.appCaption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            retryButton
        }
        .foregroundColor(.appTextSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Données périmées. \(error.message)")
    }

    private func staleText(_ error: LoadError) -> String {
        guard let date = state.lastUpdated else {
            return "Actualisation impossible : \(error.message)"
        }
        return "Données \(date.formatted(.relative(presentation: .named))) · \(error.message)"
    }

    private var emptyView: some View {
        Text(emptyMessage)
            .font(.appCaption)
            .foregroundColor(.appTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard()
    }

    private var retryButton: some View {
        Button {
            Task { await retry() }
        } label: {
            Text("Réessayer")
                .font(.appCaption.weight(.semibold))
                .frame(minHeight: 44)
        }
        .disabled(state.isLoading)
        .accessibilityHint("Relance le chargement de \(title)")
    }
}
