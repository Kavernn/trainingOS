import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject private var units  = UnitSettings.shared
    @ObservedObject private var theme  = AppTheme.shared
    @AppStorage("steps_daily_goal")   private var stepsGoal: Int = 10000
    @AppStorage("hydration_goal_ml")  private var hydrationGoal: Int = 2500
    @State private var pendingTheme: AppThemeOption = AppTheme.shared.selectedTheme

    private func syncPending() { pendingTheme = theme.selectedTheme }

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

            List {
                Section("Apparence") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AppThemeOption.allCases, id: \.rawValue) { option in
                                themeCard(option)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 2)
                    }
                    .animation(.easeInOut(duration: 0.2), value: pendingTheme)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                applySection

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
                .listRowBackground(Color.appCard)
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
                                .font(.system(size: 14, weight: .semibold))
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
                .listRowBackground(Color.appCard)
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appTextPrimary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Affichage & Unités")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { syncPending() }
    }

    private var hasChange: Bool { pendingTheme != theme.selectedTheme }

    @ViewBuilder
    private var applySection: some View {
        Section {
            Button {
                guard hasChange else { return }
                theme.applyTheme(pendingTheme)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: hasChange ? "paintpalette.fill" : "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(hasChange ? pendingTheme.previewColor : .statusGreen)
                    Text(hasChange ? "Appliquer « \(pendingTheme.displayName) »" : "Thème appliqué")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(hasChange ? .white : Color.appOnSurface.opacity(0.35))
                    Spacer()
                    if hasChange {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.appOnSurface.opacity(0.3))
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(hasChange ? pendingTheme.previewColor.opacity(0.14) : Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    @ViewBuilder
    private func themeCard(_ option: AppThemeOption) -> some View {
        let isPending = pendingTheme == option
        let isApplied = theme.selectedTheme == option && !hasChange
        Button { pendingTheme = option } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(option.previewColor)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.appOnSurface.opacity(isPending ? 0.9 : 0.15),
                                              lineWidth: isPending ? 2.5 : 1)
                        )
                    if isApplied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.appLabel)
                            .foregroundColor(.appTextPrimary)
                            .background(Circle().fill(option.previewColor).padding(1))
                            .offset(x: 4, y: 4)
                    }
                }
                .padding(.bottom, isApplied ? 4 : 0)

                Text(option.displayName)
                    .font(.system(size: 11, weight: isPending ? .bold : .regular))
                    .foregroundColor(isPending ? .white : Color.appOnSurface.opacity(0.4))
            }
            .frame(width: 64)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPending ? Color.appSurfaceInset : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isPending ? Color.appOnSurface.opacity(0.4) : Color.clear,
                                          lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
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
