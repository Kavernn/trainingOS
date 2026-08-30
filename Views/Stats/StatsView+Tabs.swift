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

    // MARK: - Vue Globale Tab
    @ViewBuilder var vueGlobaleTab: some View {

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

        // 0. Hero Stats — tonnage/séance FORCE + delta 6 mois + courbe force/accessoire
        //    + accents (PR récent, volume velocity). Structure figée par Vince.
        //    PR source = /api/pr-tracker (backend filtre baseline_count ≥ 2, récence
        //    30j). recentPRs sont triés date DESC serveur → .first = plus récent PR
        //    validé. Source unique PR dans tout Stats (hero + exercicesTab).
        if !forceAccessoryTimeline.isEmpty || thisWeekVolume > 0 {
            StatsHeroCard(
                timeline:        forceAccessoryTimeline,
                thisWeekVolume:  thisWeekVolume,
                lastWeekVolume:  lastWeekVolume,
                latestPRName:    recentPRs.first?.name,
                latestPROneRM:   recentPRs.first?.est1RM,
                latestPRDelta:   recentPRs.first?.delta
            )
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.0)
        }

        // 1. Smart Insights (moved inside tab)
        if !smartInsights.isEmpty {
            SmartInsightsBanner(insights: smartInsights)
                .padding(.horizontal, 16)
        }

        // 1b. Héros force — la progression qui monte
        if !oneRmTrend.isEmpty {
            ForceHeroCard(trend: oneRmTrend)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.01)
        }

        // 2. Décharge volontaire (si active ou à déclarer)
        DeloadCard(status: activeDeload) { newStatus in
            activeDeload = newStatus
        }
        .padding(.horizontal, 16)

        // 3. Activity Rings — Score de constance
        if let adh = adherenceData {
            AdherenceRingsCard(data: adh)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.02)
        }

        // 3. Cette semaine vs semaine précédente
        WeekComparisonCard(
            thisWeekSessions: thisWeekSessions, lastWeekSessions: lastWeekSessions,
            thisWeekVolume: thisWeekVolume,     lastWeekVolume: lastWeekVolume,
            thisWeekAvgRPE: thisWeekAvgRPE,     lastWeekAvgRPE: lastWeekAvgRPE,
            daysElapsed: daysElapsedThisWeek
        )
        .padding(.horizontal, 16)

        // 4. KPI Grid — fenêtres fixes étiquetées (sélecteur absent de cet onglet)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            KPICard(value: "\(sessionsThisMonth)", label: "Séances — ce mois-ci", color: Color.forge)
            KPICard(
                value: currentStreak > 0 ? "\(currentStreak)🔥" : "0",
                label: "Streak",
                color: .statusRed,
                subtitle: "jours cons."
            )
            KPICard(
                value: avgRPE30 > 0 ? String(format: "%.1f", avgRPE30) : "—",
                label: "RPE moy. — 30 j",
                color: .statusPurple
            )
            KPICard(value: weeklyVolume > 0 ? formatK(weeklyVolume) : "—", label: "Vol. sem.", color: .statusGreen)
            KPICard(
                value: thisWeekAvgDuration > 0 ? "\(Int(thisWeekAvgDuration))min" : "—",
                label: "Durée moy.",
                color: .statusCyan,
                subtitle: {
                    guard thisWeekAvgDuration > 0, lastWeekAvgDuration > 0 else { return nil }
                    let d = Int(thisWeekAvgDuration - lastWeekAvgDuration)
                    if d == 0 { return nil }
                    return d > 0 ? "+\(d) vs sem. préc." : "\(d) vs sem. préc."
                }()
            )
        }
        .padding(.horizontal, 16)
        .appearAnimation(delay: 0.05)

        // 5. Heatmap 90 jours
        SessionHeatmapView(
            sessions: sessions,
            hiitDates: Set(hiitLog.compactMap(\.date).map { String($0.prefix(10)) }),
            bestStreak: bestStreak
        )
        .padding(.horizontal, 16)

        // 6. Season Comparison
        if let comp = seasonComparison {
            SeasonComparisonCard(data: comp)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.08)
        }

        // 7. Marqueurs de transformation
        TransformationMarkersCard(warRoomStats: warRoomStats)
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.10)

        // 8. Badges
        if !earnedBadges.isEmpty {
            BadgesView(badges: earnedBadges)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    // MARK: - Charge & Volume Tab
    @ViewBuilder var chargeVolumeTab: some View {

        // 1. Charge — ACWR
        if let acwrData = acwr {
            ACWRCardView(data: acwrData)
                .padding(.horizontal, 16)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.appHeadline).foregroundColor(.gray)
                // collage titre/sous-titre, micro-optique
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACWR non disponible")
                        .font(.appLabel.weight(.semibold)).foregroundColor(.gray)
                    Text("Logge au moins 4 semaines de séances avec RPE et durée")
                        .font(.appCaption).foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
            }
            .padding(16).background(Color.appCard).cornerRadius(14)
            .padding(.horizontal, 16)
        }

        // 2. Tonnage hebdo + fréquence
        HStack(spacing: 12) {
            SimpleBarChart(
                title: "FRÉQUENCE / SEM",
                data: weeklyFrequency.map { (weekLabel($0.0), $0.1) },
                color: Color.forge,
                unit: "séances"
            )
            SimpleBarChart(
                title: "VOLUME / SEM",
                data: weeklyVolumeChart.map { (weekLabel($0.0), UnitSettings.shared.display($0.1)) },
                color: .statusBlue,
                unit: UnitSettings.shared.label
            )
        }
        .padding(.horizontal, 16)

        // 3. Volume / muscle / semaine (hard sets vs landmarks)
        if !muscleLandmarks.isEmpty {
            VolumeLandmarksCard(landmarks: muscleLandmarks)
                .padding(.horizontal, 16)
        }

        // 4. Équilibre Push/Pull/Legs
        if let pv = patternVolume {
            PatternVolumeView(data: pv)
                .padding(.horizontal, 16)
        }

        // 5. Programme compliance
        if complianceWeeks.count >= 2 {
            ComplianceProgrammeView(weeks: complianceWeeks)
                .padding(.horizontal, 16)
        }

        // 6. Jours depuis deload
        if let dl = deloadStatus {
            DeloadStatusCard(data: dl)
                .padding(.horizontal, 16)
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
        let bwWithFat  = filteredBW.filter { $0.bodyFat != nil && ($0.bodyFat ?? 0) > 0 }

        // 1. Body Recomposition Tracker (flagship — remplace les 2 courbes séparées)
        if bwWithFat.count >= 3 {
            BodyRecompView(entries: Array(filteredBW.reversed()))
                .padding(.horizontal, 16)
        } else if filteredBW.count >= 2 {
            WeightChartView(entries: Array(filteredBW.prefix(20).reversed()))
                .padding(.horizontal, 16)
            EmptyChartPlaceholder(message: "Logge ton % de masse grasse pour activer le Body Recomp Tracker")
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge au moins 2 pesées pour voir la courbe de poids")
                .padding(.horizontal, 16)
        }

        // 2. Recovery composite
        if filteredRecovery.count >= 5 {
            RecoveryCompositeScoreView(log: Array(filteredRecovery.prefix(30).reversed()))
                .padding(.horizontal, 16)
        }

        // 3. Mensurations
        if filteredBW.filter({ $0.waistCm != nil || $0.armsCm != nil }).count >= 2 {
            MeasurementsTrendView(entries: Array(filteredBW.prefix(20).reversed()))
                .padding(.horizontal, 16)
        }

        // 4. Soreness threshold
        if let st = sorenessThreshold, st.thresholdVol != nil {
            SorenessThresholdCard(data: st)
                .padding(.horizontal, 16)
        }

        // 5. HIIT
        if !hiitLog.isEmpty {
            HIITStatsSection(log: hiitLog)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    // MARK: - Nutrition Tab
    @ViewBuilder var nutritionTab: some View {
        let fn = filteredNutrition
        if fn.count >= 3, let target = nutritionTarget {
            NutritionComplianceChart(days: fn, target: target)
                .padding(.horizontal, 16)
            ProteinComplianceView(days: fn, target: target)
                .padding(.horizontal, 16)
            if target.glucides != nil || target.lipides != nil {
                MacrosBreakdownView(days: fn, target: target)
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

        // 1. PRs actuels
        if !recentPRs.isEmpty {
            PersonalRecordsView(records: recentPRs.map { ($0.name, $0.est1RM) })
                .padding(.horizontal, 16)
        }

        // 3. Top 5 fréquence
        if !weights.isEmpty {
            Top5FrequencyView(weights: weights)
                .padding(.horizontal, 16)
        }

        // 4. 1RM trend par exercice
        if !oneRmTrend.isEmpty {
            OneRMTrendView(trend: oneRmTrend)
                .padding(.horizontal, 16)
        }

        // 5. Exercices — recherche et poids actuels
        VStack(alignment: .leading, spacing: 8) {
            Text("POIDS ACTUELS")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
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
                color: .statusBlue
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
