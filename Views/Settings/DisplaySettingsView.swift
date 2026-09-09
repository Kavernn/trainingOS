import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject private var units  = UnitSettings.shared
    @ObservedObject private var theme  = AppTheme.shared
    @AppStorage("steps_daily_goal")   private var stepsGoal: Int = 10000
    @AppStorage("hydration_goal_ml")  private var hydrationGoal: Int = 2500
    @AppStorage(HeroMoodPreference.storageKey) private var heroMoodRawValue = HeroMoodPreference.currentRawValue

    private let stepsOptions = [5000, 7500, 8000, 10000, 12000, 15000]

    private var hydrationLabel: String {
        if hydrationGoal >= 1000 {
            let l = Double(hydrationGoal) / 1000.0
            return l.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(l)) L"
                : String(format: "%.1f L", l)
        }
        return "\(hydrationGoal) mL"
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: .statusCyan)
                .id(theme.selectedTheme)

            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Touchez un thème pour le prévisualiser instantanément.")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(AppThemeOption.allCases, id: \.rawValue) { option in
                                    ThemePreviewCard(
                                        option: option,
                                        isSelected: theme.selectedTheme == option,
                                        action: { theme.applyTheme(option) }
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 2)
                        }
                    }
                }
                header: {
                    Text("Apparence")
                }
                .listRowBackground(Color.appCard.id(theme.selectedTheme))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Hero du tableau de bord") {
                    Picker("Atmosphère", selection: heroMoodSelection) {
                        Text(HeroMoodPreference.currentDisplayName)
                            .tag(HeroMoodPreference.currentRawValue)
                        ForEach(HeroMood.allCases) { mood in
                            Text(mood.displayName)
                                .tag(mood.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(Color.appCard.id(theme.selectedTheme))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Unités de mesure") {
                    HStack(spacing: 12) {
                        settingsIcon("scalemass.fill", color: .statusCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unité de poids").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                            Text("Appliqué à tous les exercices et métriques").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { units.isKg },
                            set: { units.isKg = $0 }
                        )) {
                            Text("kg").tag(true)
                            Text("lbs").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard.id(theme.selectedTheme))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Activité") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            settingsIcon("figure.walk", color: .statusGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Objectif de pas quotidien").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                                Text("Affiché dans le tableau de bord santé").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                            }
                            Spacer()
                            Text(stepsGoal.formatted())
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.statusGreen)
                        }

                        Picker("Objectif de pas", selection: $stepsGoal) {
                            ForEach(stepsOptions, id: \.self) { n in
                                Text(n.formatted()).tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.appCard.id(theme.selectedTheme))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Nutrition") {
                    HStack(spacing: 12) {
                        settingsIcon("drop.fill", color: .statusBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Objectif d'hydratation").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                            Text("Non encore connecté au suivi — disponible bientôt").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        Stepper(
                            value: $hydrationGoal,
                            in: 1000...5000,
                            step: 250
                        ) {
                            Text(hydrationLabel)
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard.id(theme.selectedTheme))
                .listRowSeparatorTint(Color.appSeparator)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Affichage & Unités")
        .navigationBarTitleDisplayMode(.large)
    }

    private var heroMoodSelection: Binding<String> {
        Binding(
            get: { HeroMoodPreference.normalizedRawValue(heroMoodRawValue) },
            set: { heroMoodRawValue = HeroMoodPreference.normalizedRawValue($0) }
        )
    }


    @ViewBuilder
    private func settingsIcon(_ icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
        }
    }
}

private struct ThemePreviewCard: View {
    let option: AppThemeOption
    let isSelected: Bool
    let action: () -> Void

    private var colors: AppThemeColors { option.colors }
    private var chartColors: [Color] { colors.chartPalette }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                Text(option.displayName)
                    .font(.appCaption.weight(isSelected ? .bold : .medium))
                    .foregroundColor(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 28)
                HStack(spacing: 5) {
                    swatch(colors.background)
                    swatch(option.resolvedPreviewAccent)
                    swatch(chartColors.count > 1 ? chartColors[1] : option.resolvedPreviewAccentLight)
                }
            }
            .frame(width: 118)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? option.resolvedPreviewAccent : colors.cardBorderColor,
                        lineWidth: isSelected ? 2 : max(0.5, colors.cardBorderWidth)
                    )
            )
            .shadow(
                color: isSelected ? option.resolvedPreviewAccent.opacity(0.22) : .clear,
                radius: isSelected ? 5 : 0
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(option.resolvedPreviewOnAccent)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(option.resolvedPreviewAccent))
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(colors.background)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(option.resolvedPreviewAccent)
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colors.textPrimary)
                        .frame(width: 42, height: 5)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(option.resolvedPreviewSuccess)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 7)

                RoundedRectangle(cornerRadius: min(8, colors.cardCornerRadius))
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: min(8, colors.cardCornerRadius))
                            .stroke(colors.cardBorderColor, lineWidth: min(1.5, max(0.5, colors.cardBorderWidth)))
                    )
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(chartColors.prefix(4).enumerated()), id: \.offset) { index, color in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color)
                                    .frame(width: 9, height: CGFloat(8 + index * 4))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(7)
                    }
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colors.textPrimary)
                                .frame(width: 28, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colors.textSecondary)
                                .frame(width: 18, height: 3)
                        }
                        .padding(7)
                    }
                    .frame(height: 48)
            }
            .padding(7)
        }
        .frame(height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(colors.textPrimary.opacity(0.18), lineWidth: 0.5))
    }
}
