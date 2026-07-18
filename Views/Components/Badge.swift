import SwiftUI

/// Étiquette de statut courte, en majuscules, à la signature unique du système
/// visuel : label uppercase + tracking, fond teinté + outline, appPillRadius.
///
/// Réservé aux labels et compteurs (AUJOURD'HUI, SOIR, 5 EXOS, SEM. 3). Les
/// signaux avec icône fonctionnelle (spinner "Sauvegarde…", triangle "Erreur
/// réseau") restent des chips inline — pas des badges.
///
/// La couleur est dérivée d'un rôle sémantique qui mappe aux tokens thème —
/// aucune couleur hardcoded, compatibilité 3 thèmes automatique.
struct AppBadge: View {
    let text: String
    let role: BadgeRole

    init(_ text: String, role: BadgeRole) {
        self.text = text
        self.role = role
    }

    var body: some View {
        Text(text)
            .font(.appCaption.weight(.bold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundColor(role.color)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(role.color.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: .appPillRadius)
                    .stroke(role.color.opacity(0.30), lineWidth: 1)
            )
            .cornerRadius(.appPillRadius)
    }
}

enum BadgeRole {
    case info      // séance du jour, chip programme actif
    case success   // état OK
    case warning   // sous MEV, attention
    case alert     // erreur, danger
    case evening   // séance du soir, repos
    case neutral   // compteur, meta

    var color: Color {
        switch self {
        case .info:    return .forge
        case .success: return .appSuccess
        case .warning: return .statusOrange
        case .alert:   return .appDanger
        case .evening: return .statusPurple
        case .neutral: return .appTextSecondary
        }
    }
}
