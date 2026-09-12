import SwiftUI
import Charts

// MARK: - Active Deload Signal

private struct ActiveDeloadOverviewCard: View {
    let status: DeloadStatus
    let onUpdate: (DeloadStatus?) -> Void

    @State private var isLoading = false
    @State private var showConfirmDeactivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "bed.double.fill")
                        .foregroundColor(.forge)
                        .accessibilityHidden(true)
                    Text("DÉCHARGE VOLONTAIRE")
                        .font(.appCaption.weight(.bold))
                        .foregroundColor(.forge)
                    Spacer()
                    if let days = status.daysRemaining {
                        Text("\(days)j restant\(days > 1 ? "s" : "")")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                    }
                }
                if let reason = status.reason {
                    Text(reason)
                        .font(.appCaption)
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                }
                if let ends = status.endsAt {
                    Text("Reprise prévue le \(ends)")
                        .font(.appCaption)
                        .foregroundColor(.appTextMuted)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)

            Button(action: { showConfirmDeactivate = true }) {
                Text("Terminer la décharge")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appDanger)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.appCardInsetV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .confirmationDialog("Terminer la décharge ?", isPresented: $showConfirmDeactivate, titleVisibility: .visible) {
            Button("Confirmer", role: .destructive) { deactivate() }
            Button("Annuler", role: .cancel) { }
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Décharge volontaire active"]
        if let days = status.daysRemaining {
            parts.append("\(days) jour\(days > 1 ? "s" : "") restant\(days > 1 ? "s" : "")")
        }
        if let ends = status.endsAt {
            parts.append("Reprise prévue le \(ends)")
        }
        return parts.joined(separator: ". ")
    }

    private func deactivate() {
        isLoading = true
        Task {
            try? await APIService.shared.deactivateDeload()
            let fresh = try? await APIService.shared.fetchDeloadStatus()
            await MainActor.run { onUpdate(fresh); isLoading = false }
        }
    }
}

// MARK: - Overview Explorer

private struct StatsOverviewExplorerSection: View {
    let showsDeloadActivation: Bool
    let onDeloadUpdate: (DeloadStatus?) -> Void

    @State private var isActivatingDeload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXPLORER")
                .font(.appMicro.weight(.bold))
                .tracking(2)
                .foregroundColor(.appTextMuted)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                NavigationLink { WorkoutDNASection() } label: {
                    explorerRow(
                        icon: "staroflife.fill",
                        title: "Workout DNA",
                        subtitle: "Archétype · patterns · intensité"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Workout DNA. Archétype, patterns et intensité")
                .accessibilityAddTraits(.isButton)

                Divider().overlay(Color.appSeparator)

                NavigationLink { SeasonView() } label: {
                    explorerRow(
                        icon: "calendar.badge.clock",
                        title: "Mes chapitres",
                        subtitle: "Compare tes périodes d’entraînement"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mes chapitres. Compare tes périodes d’entraînement")
                .accessibilityAddTraits(.isButton)

                if showsDeloadActivation {
                    Divider().overlay(Color.appSeparator)

                    Button(action: activateDeload) {
                        explorerRow(
                            icon: "moon.zzz.fill",
                            title: "Semaine de décharge",
                            subtitle: "Suspend temporairement les alertes",
                            trailingLabel: isActivatingDeload ? nil : "Activer",
                            showsProgress: isActivatingDeload
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActivatingDeload)
                    .accessibilityLabel("Activer la semaine de décharge. Suspend temporairement les alertes")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        }
        .padding(.horizontal, .appPagePadding)
    }

    private func explorerRow(
        icon: String,
        title: String,
        subtitle: String,
        trailingLabel: String? = nil,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.appLabel)
                .foregroundColor(.appTextSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsProgress {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityHidden(true)
            } else if let trailingLabel {
                Text(trailingLabel)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.forge)
            } else {
                Image(systemName: "chevron.right")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appTextMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private func activateDeload() {
        isActivatingDeload = true
        Task {
            try? await APIService.shared.activateDeload()
            let fresh = try? await APIService.shared.fetchDeloadStatus()
            await MainActor.run {
                onDeloadUpdate(fresh)
                isActivatingDeload = false
            }
        }
    }
}

// MARK: - Tab Content Extensions
extension StatsView {

    // MARK: - Régularité Tab
    // Shell-only composition of the existing heatmap and server-provided streak.
    @ViewBuilder var consistencyTab: some View {
        if let cockpit = cockpitData {
            StatsRegularityHero(trainingLoad: cockpit.trainingLoad)
        }
        SessionHeatmapView(
            sessions: sessions,
            hiitDates: Set(hiitLog.compactMap(\.date).map { String($0.prefix(10)) }),
            bestStreak: bestStreak
        )
        .padding(.horizontal, 16)

        StatsActivityStreakSummary(currentStreak: currentStreak, bestStreak: bestStreak)

        Spacer(minLength: 32)
    }

    private func consistencyMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appMicro.weight(.bold))
                .foregroundColor(.appTextMuted)
            Text(value)
                .font(.appHeadline.weight(.semibold))
                .foregroundColor(.appTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
    }

    // MARK: - Vue Globale Tab
    @ViewBuilder var vueGlobaleTab: some View {

        if let cockpit = cockpitData {
            if cockpitError != nil {
                Text("Actualisation impossible · dernières données affichées")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appTextMuted)
                    .padding(.horizontal, .appPagePadding)
            }
            let adapter = cockpit.dataQuality.adapter
            if adapter.invalidRowCount > 0 || adapter.missingTrackingTypeCount > 0 {
                Text("Données partielles")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appTextMuted)
                    .padding(.horizontal, .appPagePadding)
            }

            StatsProgressionHero(
                progression: cockpit.progression,
                onOpen: { selectedTab = .strength },
                onSelectExercise: { selectedExercise = $0 }
            )

            StatsOverviewActivityCard(trainingLoad: cockpit.trainingLoad) {
                selectedTab = .consistency
            }

            StatsOverviewExternalLoadCard(trainingLoad: cockpit.trainingLoad) {
                selectedTab = .load
            }

            StatsOverviewNotableCard(
                recentPRs: recentPRs,
                movers: cockpit.progression.topMovers,
                attention: cockpit.progression.attention,
                onSelectExercise: { selectedExercise = $0 }
            )
        } else if cockpitError != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROGRESSION")
                    .font(.appMicro.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.appTextMuted)
                Text("Progression indisponible")
                    .font(.appHeadline.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text("Les données de progression n’ont pas pu être chargées.")
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.appCardInsetV)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
            .padding(.horizontal, .appPagePadding)
        }

        if let deload = activeDeload, deload.active {
            ActiveDeloadOverviewCard(status: deload) { newStatus in
                activeDeload = newStatus
            }
            .padding(.horizontal, .appPagePadding)
        }

        StatsOverviewExplorerSection(
            showsDeloadActivation: activeDeload?.active != true
        ) { newStatus in
            activeDeload = newStatus
        }

        Spacer(minLength: 32)
    }

    // MARK: - Charge & Volume Tab
    @ViewBuilder var chargeVolumeTab: some View {

        if let cockpit = cockpitData {
            StatsChargeHeroCard(trainingLoad: cockpit.trainingLoad)
            StatsExternalLoadSection(trainingLoad: cockpit.trainingLoad)
            StatsMuscleWorkloadComparisonChart(muscles: cockpit.muscles)
            StatsMuscleWorkloadSection(muscles: cockpit.muscles)
        }

        // Volume hebdomadaire legacy — fallback uniquement si le cockpit est indisponible
        if cockpitData == nil && !isLoadingCockpit && cockpitError != nil {
            SimpleBarChart(
                title: "VOLUME / SEM",
                data: weeklyVolumeChart.map { (weekLabel($0.0), UnitSettings.shared.display($0.1)) },
                color: .forge,
                unit: UnitSettings.shared.label
            )
            .padding(.horizontal, 16)
        }

        HStack(alignment: .firstTextBaseline) {
            Text("CHARGE INTERNE")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            Spacer()
            Text("7 J / 28 J")
                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
        }
        .padding(.horizontal, .appPagePadding)
        Text("Charge récente comparée à ta référence")
            .font(.appCaption).foregroundColor(.appTextSecondary)
            .padding(.horizontal, .appPagePadding)

        if let acwrData = acwr {
            ACWRCardView(data: acwrData)
                .padding(.horizontal, 16)
        } else {
            Text("Charge interne indisponible")
                .font(.appBody).foregroundColor(.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .appPagePadding)
        }

        Spacer(minLength: 32)
    }

    // MARK: - Intensité Tab
    @ViewBuilder var intensiteTab: some View {

        // 1. Intensité relative (%1RM)
        if let intensity = intensityData, intensity.avgPct1rm != nil {
            IntensityCard(data: intensity)
                .padding(.horizontal, 16)
        }

        // 2. Distribution RPE
        if filteredSessions.count >= 5 {
            RPEDistributionView(sessions: filteredSessions)
                .padding(.horizontal, 16)
        }

        // 3. Progression RPE
        if let rp = rpeProgression {
            RPEProgressionView(data: rp)
                .padding(.horizontal, 16)
        }

        // 4. RIR par exercice
        if !rirByExercise.isEmpty {
            RIRByExerciseView(entries: rirByExercise)
                .padding(.horizontal, 16)
        }

        // 5. Énergie pré-séance (modulateur RPE)
        let sessionsWithEnergy = filteredSessions.compactMap { d, e -> (String, Int)? in
            e.energyPre.map { (d, $0) }
        }.sorted { $0.0 < $1.0 }.suffix(20).map { $0 }
        if sessionsWithEnergy.count >= 3 {
            EnergyTrendView(data: sessionsWithEnergy)
                .padding(.horizontal, 16)
        }

        // 6. Courbe RPE temporelle
        if rpeHistory.count >= 3 {
            RPEChartView(data: rpeHistory)
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge au moins 3 séances avec RPE pour voir la tendance")
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    // MARK: - Corps Tab
    @ViewBuilder var corpsTab: some View {
        let filteredBW = filteredBodyWeight

        // Current measurements intentionally use the unfiltered history: each
        // metric keeps its own latest valid observation/date.
        StatsCurrentBodyMeasurements(entries: bodyWeight)

        StatsWeightTrajectoryView(entries: filteredBW)
        StatsBodyFatTrajectoryView(entries: filteredBW)

        StatsBodyMeasurementsHistoryView(entries: filteredBW)

        Spacer(minLength: 32)
    }

    // MARK: - Nutrition Tab
    @ViewBuilder var nutritionTab: some View {
        let fn = filteredNutrition
        if fn.count >= 3, let target = nutritionTarget {
            NutritionComplianceChart(days: fn, targetCalories: targetCalories)
                .padding(.horizontal, 16)
            ProteinComplianceView(days: fn, target: target)
                .padding(.horizontal, 16)
            if target.glucides != nil || target.lipides != nil {
                MacrosBreakdownView(days: fn, target: target, targetCalories: targetCalories)
                    .padding(.horizontal, 16)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle")
                    .font(.appHero).foregroundColor(.gray)
                Text("Données nutritionnelles insuffisantes.")
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }

        if proteinWeightRatio.count >= 5 {
            ProteinWeightRatioView(data: proteinWeightRatio)
                .padding(.horizontal, 16)
        }

        if let mdt = macrosByDayType, mdt.nTraining >= 3, mdt.nRest >= 3 {
            MacrosDayTypeView(data: mdt)
                .padding(.horizontal, 16)
        }

        // Nutrition vs Performance correlation
        let fn2 = filteredNutrition
        if fn2.count >= 21, !weeklyTonnage.isEmpty {
            NutritionVsPerfView(nutritionDays: fn2, weeklyTonnage: weeklyTonnage, target: nutritionTarget)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    // MARK: - Exercices Tab
    @ViewBuilder var exercicesTab: some View {

        if let cockpit = cockpitData {
            StatsForceProgressionHero(progression: cockpit.progression)
            StatsStrengthProgressionSection(
                comparisons: cockpit.progression.comparisons,
                comparisonWindowDays: cockpit.progression.comparisonWindowDays,
                onSelectExercise: { selectedExercise = $0 }
            )
        }

        // 1. PRs récents
        if !recentPRs.isEmpty {
            PersonalRecordsView(records: recentPRs)
                .padding(.horizontal, 16)
        }

        // 4. 1RM trend par exercice
        if cockpitData == nil && !isLoadingCockpit && cockpitError != nil && !oneRmTrend.isEmpty {
            OneRMTrendView(trend: oneRmTrend)
                .padding(.horizontal, 16)
        }

        // 5. Exercices — recherche et poids actuels
        VStack(alignment: .leading, spacing: 8) {
            Text("TOUS LES EXERCICES")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                .padding(.horizontal, 16)
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Rechercher un exercice...", text: $searchText)
                    .foregroundColor(.appTextPrimary).tint(Color.forge)
            }
            .padding(12)
            .background(Color.appCard).cornerRadius(8)
            .padding(.horizontal, 16)

            ForEach(exercisesWithHistory, id: \.0) { name, data in
                ExerciseStatRow(name: name, data: data)
                    .padding(.horizontal, 16)
                    .onTapGesture { selectedExercise = name }
            }
        }

        Spacer(minLength: 32)
    }

    // MARK: - Bien-être Tab
    @ViewBuilder var bienetreTab: some View {

        if (!hasLoadedStatsWellness || !hasLoadedStatsHRV) &&
            (isLoadingStatsWellness || isLoadingStatsHRV) {
            ProgressView()
                .tint(.appTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }

        // 1. HRV en tête (actionnable immédiatement)
        if let hrv = hrvAnalysis, hrv.hrv30dAvg != nil {
            HRVBaselineCard(data: hrv)
                .padding(.horizontal, 16)
        }

        // 2. Corrélation sommeil → performance (enrichie)
        if sleepScatter.count >= 12 {
            SleepPerformanceInsightView(scatter: sleepScatter)
                .padding(.horizontal, 16)
        } else if sleepScatter.count >= 5 {
            ScatterPlotView(
                data: sleepScatter,
                xLabel: "Qualité sommeil (J-1)",
                yLabel: "Volume séance (J)",
                title: "SOMMEIL → PERFORMANCE",
                color: .forge
            )
            .padding(.horizontal, 16)
        }

        // 3. Wellness trend (sparklines — qualité sommeil, douleurs, fatigue, pas, énergie, FC repos)
        if filteredRecovery.count >= 7 {
            WellnessTrendView(recovery: Array(filteredRecovery.prefix(30).reversed()), pssHistory: pssHistory)
                .padding(.horizontal, 16)
        }

        // 3b. Sleep Debt 7j
        let recovFor7 = Array(recoveryLog.sorted { ($0.date ?? "") > ($1.date ?? "") }.prefix(14))
        if recovFor7.filter({ $0.sleepHours != nil }).count >= 3 {
            SleepDebtCard(recovery: recovFor7)
                .padding(.horizontal, 16)
        }

        // 3c. Profil de récupération (RPE 8+ → jours avant soreness < 3)
        if let rp = recoveryProfile {
            RecoveryProfileCard(avgDays: rp.avgDays, sampleSize: rp.sampleSize)
                .padding(.horizontal, 16)
        }

        // 4. Mood & PSS
        if !moodTrend.isEmpty {
            MoodStressTrendView(data: moodTrend, pssHistory: pssHistory)
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge ton humeur quotidiennement pour voir la tendance")
                .padding(.horizontal, 16)
        }

        if !pssHistory.isEmpty {
            PSSHistoryView(records: pssHistory)
                .padding(.horizontal, 16)
        }

        // 5. Meilleur jour de la semaine
        if !sessions.isEmpty {
            BestDayOfWeekView(sessions: sessions, weights: weights)
                .padding(.horizontal, 16)
        }

        // 6. Corrélation stress → cravings (War Room, conditionnel)
        if warRoomStats?.warStartDate != nil {
            StressCravingsInsightView(pssHistory: pssHistory, warRoomStats: warRoomStats)
                .padding(.horizontal, 16)
        }

        // 7. Volume → douleurs musculaires
        if sorenessScatter.count >= 5 {
            ScatterPlotView(
                data: sorenessScatter,
                xLabel: "Volume J-1 (\(units.label))",
                yLabel: "Soreness J (1–10)",
                title: "VOLUME → DOULEURS MUSCULAIRES",
                color: Color.forge
            )
            .padding(.horizontal, 16)
        }

        if !selfCareStreaks.isEmpty {
            SelfCareStreaksView(streaks: selfCareStreaks, compliance: selfCareCompliance)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }
}
