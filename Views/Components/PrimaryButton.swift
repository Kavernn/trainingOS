import SwiftUI

// MARK: - PrimaryButton
/// Bouton CTA réutilisable — remplace tous les patterns inline filled/destructive/outlined/ghost
struct PrimaryButton: View {

    let title: String
    var icon: String? = nil
    var style: Style = .filled
    var size: Size = .large
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    enum Style {
        case filled      // Color.forge background, texte blanc
        case outlined    // border Color.forge, texte Color.forge
        case destructive // fond rouge, texte blanc
        case ghost       // texte seul, Color.forge
    }

    enum Size {
        case large   // hauteur ~56pt, padding vertical 16pt
        case medium  // hauteur ~44pt, padding vertical 12pt
        case small   // hauteur ~36pt, padding vertical 8pt
    }

    // MARK: - Body

    var body: some View {
        Button(action: handleTap) {
            buttonLabel
                .frame(maxWidth: size == .small ? nil : .infinity)
                .frame(minHeight: visualHeight)
                .background(backgroundFill)
                .foregroundColor(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(borderOverlay)
        }
        .buttonStyle(SpringButtonStyle(scale: isDisabled || isLoading ? 1.0 : 0.97))
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled || isLoading)
        .frame(minWidth: size == .small ? 44 : nil, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(isDisabled ? .isStaticText : [])
    }

    // MARK: - Label

    @ViewBuilder
    private var buttonLabel: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(style == .ghost || style == .outlined ? Color.forge : AppTheme.shared.onAccent)
                    .scaleEffect(0.9)
            } else {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(buttonFont)
                    }
                    if !title.isEmpty {
                        Text(title)
                            .font(buttonFont)
                    }
                }
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, size == .small ? 16 : 0)
    }

    // MARK: - Styling

    @ViewBuilder
    private var backgroundFill: some View {
        switch style {
        case .filled:
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color.forge)
        case .destructive:
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color.appDanger)
        case .outlined, .ghost:
            Color.clear
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if style == .outlined {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.forge, lineWidth: 1.5)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .filled:      return AppTheme.shared.onAccent
        case .destructive: return .white
        case .outlined, .ghost: return Color.forge
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .large:  return 14
        case .medium: return 12
        case .small:  return 10
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .large:  return 16
        case .medium: return 12
        case .small:  return 8
        }
    }

    private var visualHeight: CGFloat {
        switch size {
        case .large:  return 56
        case .medium: return 44
        case .small:  return 36
        }
    }

    private var buttonFont: Font {
        switch size {
        case .large:  return .appBody.weight(.semibold)
        case .medium: return .appBody.weight(.semibold)
        case .small:  return .appLabel.weight(.semibold)
        }
    }

    // MARK: - Helpers

    private var accessibilityTitle: String {
        isLoading ? "Chargement" : (title.isEmpty ? (icon ?? "") : title)
    }

    private func handleTap() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        action()
    }
}

// MARK: - Preview

#Preview("PrimaryButton — tous les états") {
    ScrollView {
        VStack(spacing: 20) {

            Group {
                Text("FILLED").font(.caption).foregroundColor(.secondary)

                PrimaryButton(title: "Logger la récupération", icon: "moon.fill", action: {})
                PrimaryButton(title: "Chargement…", isLoading: true, action: {})
                PrimaryButton(title: "Désactivé", isDisabled: true, action: {})
            }

            Divider().background(Color.white.opacity(0.1))

            Group {
                Text("DESTRUCTIVE").font(.caption).foregroundColor(.secondary)

                PrimaryButton(title: "Supprimer la séance", icon: "trash.fill",
                              style: .destructive, action: {})
                PrimaryButton(title: "Enregistrer HIIT", icon: "bolt.fill",
                              style: .destructive, isLoading: true, action: {})
                PrimaryButton(title: "Supprimer", style: .destructive,
                              isDisabled: true, action: {})
            }

            Divider().background(Color.white.opacity(0.1))

            Group {
                Text("OUTLINED").font(.caption).foregroundColor(.secondary)

                PrimaryButton(title: "Remplir depuis Apple Santé",
                              icon: "heart.text.square.fill",
                              style: .outlined, action: {})
                PrimaryButton(title: "Voir tout", style: .outlined,
                              size: .medium, action: {})
            }

            Divider().background(Color.white.opacity(0.1))

            Group {
                Text("GHOST").font(.caption).foregroundColor(.secondary)

                PrimaryButton(title: "Annuler", style: .ghost, size: .medium, action: {})
                PrimaryButton(title: "Plus de détails", icon: "plus.circle",
                              style: .ghost, size: .small, action: {})
            }

            Divider().background(Color.white.opacity(0.1))

            Group {
                Text("SIZES").font(.caption).foregroundColor(.secondary)

                PrimaryButton(title: "Large (56pt)", size: .large, action: {})
                PrimaryButton(title: "Medium (44pt)", size: .medium, action: {})

                HStack {
                    PrimaryButton(title: "Small", size: .small, action: {})
                    PrimaryButton(title: "Small icon", icon: "plus",
                                  size: .small, action: {})
                    PrimaryButton(title: "Disabled small", size: .small,
                                  isDisabled: true, action: {})
                }
            }
        }
        .padding(20)
    }
    .background(Color.appBg)
    .preferredColorScheme(.dark)
}
