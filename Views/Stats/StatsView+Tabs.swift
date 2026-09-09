import SwiftUI
import Charts

// MARK: - Deload Card

private struct DeloadCard: View {
    let status: DeloadStatus?
    let onUpdate: (DeloadStatus?) -> Void

    @State private var isLoading = false
    @State private var showConfirmDeactivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = status, s.active {
                activeView(s)
            } else {
                inactiveView
            }
        }
        .padding(16)
        .background(Color(white: 0.07))
        .cornerRadius(14)
    }

    private func activeView(_ s: DeloadStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(.forge)
                Text("DÉCHARGE VOLONTAIRE")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(.forge)
                Spacer()
                if let days = s.daysRemaining {
                    Text("\(days)j restant\(days > 1 ? "s" : "")")
                        .font(.appCaption)
                        .foregroundColor(Color(white: 0.4))
                }
            }
            if let reason = s.reason {
                Text(reason)
                    .font(.appLabel)
                    .foregroundColor(Color(white: 0.55))
            }
            if let ends = s.endsAt {
                Text("Reprise prévue le \(ends)")
                    .font(.appCaption)
                    .foregroundColor(Color(white: 0.4))
            }
            Button(action: { showConfirmDeactivate = true }) {
                Text("Terminer la décharge")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appDanger)
            }
            .disabled(isLoading)
        }
        .confirmationDialog("Terminer la décharge ?", isPresented: $showConfirmDeactivate, titleVisibility: .visible) {
            Button("Confirmer", role: .destructive) { deactivate() }
            Button("Annuler", role: .cancel) { }
        }
    }

    private var inactiveView: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.appTitle)
                .foregroundColor(Color(white: 0.35))
            // collage titre/sous-titre, micro-optique
            VStack(alignment: .leading, spacing: 2) {
                Text("Semaine de décharge")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text("Déclare un repos volontaire — les alertes seront suspendues")
                    .font(.appCaption)
                    .foregroundColor(Color(white: 0.4))
            }
            Spacer()
            Button(action: activate) {
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("Activer")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.forge)
                }
            }
            .disabled(isLoading)
        }
    }

    private func activate() {
        isLoading = true
        Task {
            try? await APIService.shared.activateDeload()
            let fresh = try? await APIService.shared.fetchDeloadStatus()
            await MainActor.run { onUpdate(fresh); isLoading = false }
        }
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

// MARK: - Tab Content Extensions
extension StatsView {

    // MARK: - Régularité Tab
    // Shell-only composition of the existing heatmap and server-provided streak.
    @ViewBuilder var consistencyTab: some View {
        if let cockpit = cockpitData {
            StatsRegularitySummary(trainingLoad: cockpit.trainingLoad)
            StatsWeeklyRegularityChart(weekly: cockpit.trainingLoad.weekly)
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

    private func tonnageCoverageLabel(_ coverage: StatsTonnageCoverage) -> String {
        switch coverage {
        case .complete: return "Complet"
        case .partial: return "Partiel"
        case .unavailable: return "Indisponible"
        case .unknown: return "Données partielles"
        }
    }

    // MARK: - Vue Globale Tab
    @ViewBuilder var vueGlobaleTab: some View {

        if let cockpit = cockpitData {
            let counts = cockpit.progression.statusCounts
            let comparable = counts.improving + counts.stable + counts.declining
            let tonnage = cockpit.trainingLoad.summary.tonnage

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

            StatsProgressionHero(progression: cockpit.progression)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatsOverviewMetric(
                    value: "\(comparable)",
                    label: "Comparables"
                )
                StatsOverviewMetric(
                    value: "\(cockpit.trainingLoad.summary.sessionCount)",
                    label: "Séances"
                )
                StatsOverviewMetric(
                    value: "\(cockpit.trainingLoad.summary.activeDayCount)",
                    label: "Jours actifs"
                )
                StatsOverviewMetric(
                    value: tonnage.value.map { units.format($0, decimals: 0) } ?? "—",
                    label: "Tonnage reps",
                    detail: tonnageCoverageLabel(tonnage.coverage)
                )
            }
            .padding(.appCardInsetV)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
            .padding(.horizontal, .appPagePadding)

            if !cockpit.progression.topMovers.isEmpty {
                StatsTopMoversCard(
                    movers: cockpit.progression.topMovers,
                    onSelectExercise: { selectedExercise = $0 }
                )
            }

            if !cockpit.progression.attention.isEmpty {
                StatsAttentionCard(attention: cockpit.progression.attention)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("RÉGULARITÉ")
                    .font(.appMicro.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.appTextMuted)
                Text("\(cockpit.trainingLoad.summary.sessionCount) séances · \(cockpit.trainingLoad.summary.activeDayCount) jours actifs")
                    .font(.appBody.weight(.medium))
                    .foregroundColor(.appTextPrimary)
                Button("Voir la régularité") {
                    selectedTab = .consistency
                }
                .font(.appCaption.weight(.semibold))
                .foregroundColor(Color.domainAccent(.training))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.appCardInsetV)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
            .padding(.horizontal, .appPagePadding)
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

        // 0. Workout DNA — accès à la synthèse (archétype · patterns · intensité)
        NavigationLink { WorkoutDNASection() } label: {
            HStack(spacing: 12) {
                Image(systemName: "staroflife.fill")
                    .font(.appHeadline)
                    .foregroundColor(.gray)
                    .frame(width: 30)
                // collage titre/sous-titre, micro-optique
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout DNA")
                        .font(.appHeadline)
                        .foregroundColor(.appTextPrimary)
                    Text("Archétype · patterns · intensité")
                        .font(.appCaption)
                        .foregroundColor(Color(white: 0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appCaption)
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)

        // 2. Décharge volontaire (si active ou à déclarer)
        DeloadCard(status: activeDeload) { newStatus in
            activeDeload = newStatus
        }
        .padding(.horizontal, 16)

        // Season Comparison
        if let comp = seasonComparison {
            SeasonComparisonCard(data: comp)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.08)
        }

        // 7. Marqueurs de transformation
        TransformationMarkersCard(warRoomStats: warRoomStats)
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.10)

        Spacer(minLength: 32)
    }

    // MARK: - Charge & Volume Tab
    @ViewBuilder var chargeVolumeTab: some View {

        if let cockpit = cockpitData {
            StatsChargeHeroCard(trainingLoad: cockpit.trainingLoad, muscles: cockpit.muscles)
            StatsMuscleWorkloadComparisonChart(muscles: cockpit.muscles)
            StatsExternalLoadSection(trainingLoad: cockpit.trainingLoad)
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

        Text("CHARGE INTERNE")
            .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            .padding(.horizontal, .appPagePadding)
        Text("Effort perçu × durée · ACWR aiguë 7 j / chronique 28 j")
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

        if let cockpit = cockpitData {
            StatsMuscleWorkloadSection(muscles: cockpit.muscles)
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
            StatsStrengthProgressionSection(
                comparisons: cockpit.progression.comparisons,
                onSelectExercise: { selectedExercise = $0 }
            )
        }

        // 1. PRs actuels
        if !recentPRs.isEmpty {
            PersonalRecordsView(records: recentPRs.map { ($0.name, $0.est1RM) })
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
