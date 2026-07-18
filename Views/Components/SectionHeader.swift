import SwiftUI

/// En-tête de section overline — signature unique pour structurer la lecture.
/// Texte uppercase tracké + trailing ViewBuilder libre (Badge count, action
/// button, chevron…).
///
/// Livré pour Lot D2+ (les tabs Aujourd'hui / Semaine / Structure introduisent
/// des sections nommées). Non-consommé en D1.
struct AppSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.appCaption.weight(.bold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundColor(.appTextSecondary.opacity(0.70))
            Spacer()
            trailing()
        }
        .padding(.bottom, 8)
    }
}

extension AppSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}
