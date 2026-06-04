import SwiftUI
import Charts

// MARK: - Tab Content Extensions
extension StatsView {

    // MARK: - Vue Globale Tab
    @ViewBuilder var vueGlobaleTab: some View {

        // 1. Smart Insights (moved inside tab)
        if !smartInsights.isEmpty {
            SmartInsightsBanner(insights: smartInsights)
                .padding(.horizontal, 16)
        }

        // 2. Activity Rings — Score de constance
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

        // 4. KPI Grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            KPICard(value: "\(filteredSessions.count)", label: "Séances (\(period.rawValue))", color: .orange)
            KPICard(value: "\(sessionsThisMonth)", label: "Mois actuel", color: .blue)
            KPICard(
                value: currentStreak > 0 ? "\(currentStreak)🔥" : "0",
                label: "Streak",
                color: .red,
                subtitle: "jours cons."
            )
            KPICard(
                value: avgRPEPeriod > 0 ? String(format: "%.1f", avgRPEPeriod) : "—",
                label: "RPE moy.",
                color: .purple
            )
            KPICard(value: weeklyVolume > 0 ? formatK(weeklyVolume) : "—", label: "Vol. sem.", color: .green)
            KPICard(
                value: thisWeekAvgDuration > 0 ? "\(Int(thisWeekAvgDuration))min" : "—",
                label: "Durée moy.",
                color: .cyan,
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
        TransformationMarkersCard(tombstoneCount: graveyardCount, warRoomStats: warRoomStats)
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.10)

        // 8. Badges
        if !earnedBadges.isEmpty {
            BadgesView(badges: earnedBadges)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    // MARK: - Performance Tab
    @ViewBuilder var performanceTab: some View {

        // 1. Charge — ACWR
        if let acwrData = acwr {
            ACWRCardView(data: acwrData)
                .padding(.horizontal, 16)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18)).foregroundColor(.gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACWR non disponible")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.gray)
                    Text("Logge au moins 4 semaines de séances avec RPE et durée")
                        .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
            }
            .padding(14).background(Color.appCard).cornerRadius(14)
            .padding(.horizontal, 16)
        }

        // 2. Tonnage hebdo + fréquence
        HStack(spacing: 12) {
            SimpleBarChart(
                title: "FRÉQUENCE / SEM",
                data: weeklyFrequency.map { (weekLabel($0.0), $0.1) },
                color: .orange,
                unit: "séances"
            )
            SimpleBarChart(
                title: "VOLUME / SEM",
                data: weeklyVolumeChart.map { (weekLabel($0.0), UnitSettings.shared.display($0.1)) },
                color: .blue,
                unit: UnitSettings.shared.label
            )
        }
        .padding(.horizontal, 16)

        // 3. Volume / muscle / semaine (hard sets vs landmarks)
        if !muscleLandmarks.isEmpty {
            VolumeLandmarksCard(landmarks: muscleLandmarks)
                .padding(.horizontal, 16)
        }

        // 4. Intensité relative (%1RM)
        if let intensity = intensityData, intensity.avgPct1rm != nil {
            IntensityCard(data: intensity)
                .padding(.horizontal, 16)
        }

        // 5. Équilibre Push/Pull/Legs
        if let pv = patternVolume {
            PatternVolumeView(data: pv)
                .padding(.horizontal, 16)
        }

        // 6. Programme compliance
        if complianceWeeks.count >= 2 {
            ComplianceProgrammeView(weeks: complianceWeeks)
                .padding(.horizontal, 16)
        }

        // 7. Jours depuis deload
        if let dl = deloadStatus {
            DeloadStatusCard(data: dl)
                .padding(.horizontal, 16)
        }

        // 8. RPE + intensité
        if filteredSessions.count >= 5 {
            RPEDistributionView(sessions: filteredSessions)
                .padding(.horizontal, 16)
        }

        if let rp = rpeProgression {
            RPEProgressionView(data: rp)
                .padding(.horizontal, 16)
        }

        if !rirByExercise.isEmpty {
            RIRByExerciseView(entries: rirByExercise)
                .padding(.horizontal, 16)
        }

        let sessionsWithEnergy = filteredSessions.compactMap { d, e -> (String, Int)? in
            e.energyPre.map { (d, $0) }
        }.sorted { $0.0 < $1.0 }.suffix(20).map { $0 }
        if sessionsWithEnergy.count >= 3 {
            EnergyTrendView(data: sessionsWithEnergy)
                .padding(.horizontal, 16)
        }

        if !oneRmTrend.isEmpty {
            OneRMTrendView(trend: oneRmTrend)
                .padding(.horizontal, 16)
        }

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
                    .font(.system(size: 40)).foregroundColor(.gray)
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

        // 1. Progression force 6 mois (flagship)
        if !oneRmTrend.isEmpty {
            StrengthProgressionCard(trend: oneRmTrend, weights: weights)
                .padding(.horizontal, 16)
        }

        // 2. PRs actuels
        if !personalRecords.isEmpty {
            PersonalRecordsView(records: personalRecords)
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
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                .padding(.horizontal, 16)
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Rechercher un exercice...", text: $searchText)
                    .foregroundColor(.white).tint(.orange)
            }
            .padding(12)
            .background(Color.appCard).cornerRadius(12)
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
                color: .blue
            )
            .padding(.horizontal, 16)
        }

        // 3. Wellness trend (3 sparklines)
        if filteredRecovery.count >= 7 {
            WellnessTrendView(recovery: Array(filteredRecovery.prefix(30).reversed()), pssHistory: pssHistory)
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
                color: .orange
            )
            .padding(.horizontal, 16)
        }

        if !selfCareStreaks.isEmpty {
            SelfCareStreaksView(streaks: selfCareStreaks, compliance: selfCareCompliance)
                .padding(.horizontal, 16)
        }

        // F3 + G2: Phoenix Ritual section
        if let rs = ritualStats {
            PhoenixRitualStatsCard(stats: rs)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }
}
