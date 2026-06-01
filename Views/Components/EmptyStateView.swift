import SwiftUI

// MARK: - EmptyStateView
/// État vide réutilisable : .default (pleine page) ou .compact (inline liste/card)
struct EmptyStateView: View {

    let icon: String
    let title: String
    var subtitle: String = ""
    var action: (() -> Void)? = nil
    var actionLabel: String = "Ajouter"
    var compact: Bool = false

    private var resolvedIcon: String {
        icon.isEmpty ? "questionmark.circle" : icon
    }

    // MARK: - Body

    var body: some View {
        if compact {
            compactBody
        } else {
            defaultBody
        }
    }

    // MARK: - Default (full-page empty state)

    private var defaultBody: some View {
        VStack(spacing: 12) {
            Image(systemName: resolvedIcon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action {
                PrimaryButton(title: actionLabel, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Compact (inline inside cards / lists)

    private var compactBody: some View {
        VStack(spacing: 10) {
            Image(systemName: resolvedIcon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))

            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var parts = [title]
        if !subtitle.isEmpty { parts.append(subtitle) }
        if action != nil { parts.append("Bouton : \(actionLabel)") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview

#Preview("EmptyStateView — tous les états") {
    ScrollView {
        VStack(spacing: 24) {

            Text("DEFAULT — pleine page").font(.caption).foregroundColor(.secondary)

            EmptyStateView(
                icon: "moon.zzz.fill",
                title: "Comment tu te sens ce matin ?",
                subtitle: "30 secondes suffisent.",
                action: {},
                actionLabel: "Logger ma récupération"
            )
            .glassCard()
            .padding(.horizontal)

            EmptyStateView(
                icon: "fork.knife",
                title: "Aucun aliment enregistré",
                subtitle: "Ajoute ton premier repas."
            )
            .glassCard()
            .padding(.horizontal)

            EmptyStateView(
                icon: "",
                title: "Icône manquante — fallback"
            )
            .glassCard()
            .padding(.horizontal)

            Divider().background(Color.white.opacity(0.1))

            Text("COMPACT — inline liste").font(.caption).foregroundColor(.secondary)

            VStack(spacing: 12) {
                EmptyStateView(icon: "figure.run", title: "Aucune session HIIT",
                               compact: true)
                    .glassCard()

                EmptyStateView(icon: "note.text", title: "Aucune séance",
                               compact: true)
                    .glassCard()

                EmptyStateView(icon: "magnifyingglass",
                               title: "Aucun exercice trouvé",
                               compact: true)
                    .glassCard()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 24)
    }
    .background(Color.appBg)
    .preferredColorScheme(.dark)
}
