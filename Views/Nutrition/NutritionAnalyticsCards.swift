import SwiftUI

// MARK: - Daily Remaining Card

struct DailyRemainingCard: View {
    let totals: NutritionTotals?
    let settings: NutritionSettings?
    var todayType: String? = nil
    @State private var prevAllDone = false
    @State private var goalScale: CGFloat = 1.0

    private var effectiveCalTarget: Double {
        if let t = todayType, let dt = settings?.dayTypeTargets?.target(for: t) { return dt.calories }
        return settings?.calories ?? 2400
    }
    private var calorieSurplus: Double { max(0, (totals?.calories ?? 0) - effectiveCalTarget) }
    private var remainingCal: Double  { max(effectiveCalTarget - (totals?.calories  ?? 0), 0) }
    private var remainingProt: Double { max((settings?.proteines ?? 180) - (totals?.proteines ?? 0), 0) }
    // N-C1: only mark as done when settings are actually configured
    private var allDone: Bool         { settings != nil && remainingCal <= 0 && remainingProt <= 0 }

    private var suggestion: (icon: String, text: String, color: Color) {
        if allDone           { return ("checkmark.seal.fill", "Objectifs atteints !", .green) }
        if remainingProt >= 40 { return ("fork.knife", "Repas complet protéiné", .blue) }
        if remainingProt >= 20 { return ("cup.and.saucer.fill", "Collation protéinée", .blue) }
        if remainingProt >= 5  { return ("takeoutbag.and.cup.and.straw.fill", "Shake ou skyr", .blue) }
        if remainingCal > 200  { return ("leaf.fill", "Légumes ou fruit", .green) }
        return ("checkmark.seal.fill", "Objectifs atteints !", .green)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("RESTE AUJOURD'HUI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
            }

            if settings == nil {
                // N-C1: settings not configured — don't show fake "Objectifs atteints !"
                Label("Configure tes objectifs pour suivre ta progression", systemImage: "gearshape.fill")
                    .font(.appLabel)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            } else if allDone {
                VStack(spacing: 6) {
                    Label("Objectifs atteints !", systemImage: "checkmark.seal.fill")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.green)
                        .scaleEffect(goalScale)
                        .onChange(of: allDone) { done in
                            if done && !prevAllDone {
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                triggerNotificationFeedback(.success)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { goalScale = 1.35 }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.15)) { goalScale = 1.0 }
                            }
                            prevAllDone = done
                        }
                    if calorieSurplus > 200 {
                        Label("Surplus de \(Int(calorieSurplus)) kcal — reste léger ce soir", systemImage: "exclamationmark.triangle.fill")
                            .font(.appCaption)
                            .foregroundColor(.yellow)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 2) {
                        Text("\(Int(remainingCal))")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(Color.forge)
                        Text("kcal restantes")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)

                    let s = suggestion
                    HStack(spacing: 6) {
                        Image(systemName: s.icon).font(.appLabel).foregroundColor(s.color)
                        Text(s.text).font(.system(size: 12, weight: .medium)).foregroundColor(s.color)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(s.color.opacity(0.1))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Adherence Score Card

struct AdherenceScoreCard: View {
    let history: [NutritionDayHistory]
    let settings: NutritionSettings?
    var period: Int = 7

    private var protTarget: Double { settings?.proteines ?? 180 }
    private var calTarget:  Double { settings?.calories  ?? 2400 }

    private var successDays: Int {
        history.filter { $0.proteines >= protTarget * 0.9 && $0.calories <= calTarget * 1.1 }.count
    }
    private var score: Int {
        history.isEmpty ? 0 : Int(Double(successDays) / Double(history.count) * 100)
    }
    private var badge: (text: String, color: Color) {
        if score >= 85 { return ("Super semaine", .green) }
        if score >= 60 { return ("En progression", .yellow) }
        return ("À améliorer", .red)
    }
    private var pct: Double { Double(score) / 100.0 }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("ADHÉRENCE · \(history.count) JOURS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
            }

            if history.count < 3 {
                Text("Pas encore assez de données · Revenez dans \(3 - history.count) jour(s)")
                    .font(.appLabel)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 24) {
                    ZStack {
                        Circle().stroke(Color.appSurfaceInset, lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: pct)
                            .stroke(badge.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.6), value: pct)
                        Text("\(score)%")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                    }
                    .frame(width: 90, height: 90)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(badge.text)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(badge.color)
                        Text("\(successDays)/\(history.count) jours dans les objectifs")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text("\(history.count)/\(period) jours loggués · Prot ≥90% · Cal ≤110%")
                            .font(.system(size: 10))
                            .foregroundColor(Color.gray.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Nutrition Patterns Card

struct NutritionPatternsCard: View {
    let history: [NutritionDayHistory]
    let settings: NutritionSettings?

    private var calTarget:  Double { settings?.calories  ?? 2400 }
    private var protTarget: Double { settings?.proteines ?? 180  }

    private var avgCal:  Double {
        history.isEmpty ? 0 : history.reduce(0) { $0 + $1.calories  } / Double(history.count)
    }
    private var avgProt: Double {
        history.isEmpty ? 0 : history.reduce(0) { $0 + $1.proteines } / Double(history.count)
    }

    @State private var bestStreak: Int = 0
    @State private var weekdayAverages: [(label: String, avgCal: Double)] = []

    private static func computeBestStreak(_ history: [NutritionDayHistory], protTarget: Double, calTarget: Double) -> Int {
        var best = 0, current = 0
        for day in history.sorted(by: { $0.date < $1.date }) {
            let ok = day.proteines >= protTarget * 0.9 && day.calories <= calTarget * 1.1
            current = ok ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    private static func computeWeekdayAverages(_ history: [NutritionDayHistory]) -> [(label: String, avgCal: Double)] {
        guard history.count >= 21 else { return [] }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let names = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]
        var groups: [Int: [Double]] = [:]
        for day in history {
            guard let d = fmt.date(from: day.date) else { continue }
            let epochDays = (Int(d.timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 86400
            let wd = ((epochDays + 4) % 7 + 1) - 1
            groups[wd, default: []].append(day.calories)
        }
        let reordered = [1,2,3,4,5,6,0]
        return reordered.compactMap { idx in
            guard let vals = groups[idx], !vals.isEmpty else { return nil }
            return (label: names[idx], avgCal: vals.reduce(0, +) / Double(vals.count))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TENDANCES")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(spacing: 0) {
                VStack(alignment: .center, spacing: 4) {
                    Text("\(Int(avgCal))")
                        .font(.system(size: 24, weight: .black)).foregroundColor(Color.forge)
                    Text("/ \(Int(calTarget)) kcal")
                        .font(.system(size: 10)).foregroundColor(.gray)
                    Text("moy. calories/j")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44).background(Color.white.opacity(0.07))

                VStack(alignment: .center, spacing: 4) {
                    Text("\(Int(avgProt))g")
                        .font(.system(size: 24, weight: .black)).foregroundColor(.blue)
                    Text("/ \(Int(protTarget))g")
                        .font(.system(size: 10)).foregroundColor(.gray)
                    Text("moy. protéines/j")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44).background(Color.white.opacity(0.07))

                VStack(alignment: .center, spacing: 4) {
                    Text("\(bestStreak)")
                        .font(.system(size: 24, weight: .black)).foregroundColor(.green)
                    Text("jours consécutifs")
                        .font(.system(size: 10)).foregroundColor(.gray)
                    Text("meilleur streak")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }

            if !weekdayAverages.isEmpty {
                Divider().background(Color.white.opacity(0.07))
                Text("MOYENNE PAR JOUR DE LA SEMAINE")
                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(Color.gray.opacity(0.6))
                let maxAvg = weekdayAverages.map(\.avgCal).max() ?? 1
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(weekdayAverages, id: \.label) { item in
                        let pct = item.avgCal / maxAvg
                        let overTarget = item.avgCal > calTarget * 1.1
                        VStack(spacing: 4) {
                            Text("\(Int(item.avgCal / 100) * 100)")
                                .font(.system(size: 7)).foregroundColor(.gray)
                            GeometryReader { geo in
                                VStack(spacing: 0) {
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(overTarget ? Color.red.opacity(0.5) : Color.forge.opacity(0.45))
                                        .frame(height: max(geo.size.height * pct, 4))
                                }
                            }
                            .frame(height: 36)
                            Text(item.label)
                                .font(.appMicro).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
        .task(id: history.count) {
            let h = history
            let pt = protTarget
            let ct = calTarget
            bestStreak = await Task.detached(priority: .utility) {
                NutritionPatternsCard.computeBestStreak(h, protTarget: pt, calTarget: ct)
            }.value
            weekdayAverages = await Task.detached(priority: .utility) {
                NutritionPatternsCard.computeWeekdayAverages(h)
            }.value
        }
    }
}

// MARK: - Macro Gap Card

struct MacroGapCard: View {
    let gap: MacroGap

    private var primaryColor: Color {
        switch gap.primaryGap {
        case "protein": return .green
        case "carbs":   return .orange
        default:        return .yellow
        }
    }

    private var primaryLabel: String {
        switch gap.primaryGap {
        case "protein": return "Protéines"
        case "carbs":   return "Glucides"
        default:        return "Calories"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "fork.knife").foregroundColor(primaryColor)
                Text("SUGGESTIONS MACRO GAP")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("Manque en \(primaryLabel)")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(primaryColor)
            }

            // Gap summary
            HStack(spacing: 12) {
                if gap.gaps.protein > 5 {
                    MacroGapChip(label: "P", value: Int(gap.gaps.protein), unit: "g", color: .green)
                }
                if gap.gaps.carbs > 10 {
                    MacroGapChip(label: "G", value: Int(gap.gaps.carbs), unit: "g", color: Color.forge)
                }
                if gap.gaps.fat > 5 {
                    MacroGapChip(label: "L", value: Int(gap.gaps.fat), unit: "g", color: .yellow)
                }
                if gap.gaps.calories > 100 {
                    MacroGapChip(label: "Kcal", value: Int(gap.gaps.calories), unit: "", color: .red)
                }
                Spacer()
            }

            if !gap.foodSuggestions.isEmpty {
                Text("ALIMENTS SUGGÉRÉS")
                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)

                ForEach(Array(gap.foodSuggestions.prefix(4).enumerated()), id: \.offset) { _, item in
                    if let name = item["name"]?.value {
                        HStack(spacing: 8) {
                            Text(name)
                                .font(.appLabel).foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            if let prot = item["protein_per_100g"]?.value, let d = Double(prot) {
                                Text(String(format: "%.0fg prot/100g", d))
                                    .font(.appCaption).foregroundColor(.green)
                            } else if let carb = item["carbs_per_100g"]?.value, let d = Double(carb) {
                                Text(String(format: "%.0fg gluc/100g", d))
                                    .font(.appCaption).foregroundColor(Color.forge)
                            } else if let cal = item["calories_per_100g"]?.value, let d = Double(cal) {
                                Text(String(format: "%.0f kcal/100g", d))
                                    .font(.appCaption).foregroundColor(.yellow)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

struct MacroGapChip: View {
    let label: String
    let value: Int
    let unit: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
            Text("\(value)\(unit)").font(.system(size: 14, weight: .black)).foregroundColor(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Nutrition Correlations Card

struct NutritionCorrelationsCard: View {
    let settings: NutritionSettings?
    var refreshID: UUID = UUID()
    @State private var data: NutritionCorrelations? = nil
    @State private var timingData: NutritionTimingData? = nil
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OBSERVATIONS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if isLoading {
                HStack { Spacer(); ProgressView().tint(.gray); Spacer() }.frame(height: 40)
            } else if let d = data, d.sampleDays >= 14, hasInsights(d) {
                VStack(spacing: 12) {
                    if let pr = d.protRpe {
                        NutritionCorrInsightRow(
                            icon:  "fork.knife",
                            title: "Protéines \u{2265} objectif → RPE lendemain",
                            left:  ("Oui (\(pr.sampleHigh)j)", String(format: "%.1f", pr.highProtAvgRpe)),
                            right: ("Non (\(pr.sampleLow)j)",  String(format: "%.1f", pr.lowProtAvgRpe)),
                            positive: pr.diff <= 0,
                            note:  pr.diff <= 0
                                ? "Séances perçues \(String(format: "%.1f", abs(pr.diff))) pts plus légères"
                                : "Pas de différence significative"
                        )
                    }
                    if let cr = d.calRec {
                        NutritionCorrInsightRow(
                            icon:  "moon.stars.fill",
                            title: "Calories dans objectif → récupération",
                            left:  ("Objectif (\(cr.sampleOn)j)",  String(format: "%.1f", cr.onTargetAvg)),
                            right: ("Hors cible (\(cr.sampleOff)j)", String(format: "%.1f", cr.offTargetAvg)),
                            positive: cr.diff >= 0,
                            note:  cr.diff >= 0.3
                                ? "Récupération \(String(format: "%.1f", cr.diff)) pts meilleure"
                                : "Différence non significative"
                        )
                    }
                    if let vc = d.volCal {
                        NutritionCorrInsightRow(
                            icon:  "dumbbell.fill",
                            title: "Volume élevé → calories lendemain",
                            left:  ("Volume haut", "\(vc.highVolAvgCal)"),
                            right: ("Volume bas",  "\(vc.lowVolAvgCal)"),
                            positive: vc.diff >= 0,
                            note:  "Compensation naturelle : \(abs(vc.diff)) kcal de plus"
                        )
                    }
                }
            } else {
                Text("Pas encore assez de données partagées entre nutrition, séances et récupération.\nContinue à tout logger pendant 2–3 semaines.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
            }

            // Nutrition timing block
            if let timing = timingData, timing.trainingDaysAnalyzed >= 5 {
                Divider().opacity(0.2)
                Text("TIMING PRÉ/POST SÉANCE")
                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                HStack(spacing: 12) {
                    if let prot = timing.preWorkout.avgProtein {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PRÉ-WORKOUT").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                            Text(String(format: "%.0fg prot", prot))
                                .font(.appLabel.weight(.black)).foregroundColor(.green)
                            if let cal = timing.preWorkout.avgCalories {
                                Text(String(format: "%.0f kcal", cal))
                                    .font(.system(size: 10)).foregroundColor(.gray)
                            }
                        }
                    }
                    if let prot = timing.postWorkout.avgProtein {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("POST-WORKOUT").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                            Text(String(format: "%.0fg prot", prot))
                                .font(.appLabel.weight(.black)).foregroundColor(Color.forge)
                            if let cal = timing.postWorkout.avgCalories {
                                Text(String(format: "%.0f kcal", cal))
                                    .font(.system(size: 10)).foregroundColor(.gray)
                                }
                            }
                        }
                    Spacer()
                }
                Text(timing.insight)
                    .font(.appCaption).foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
        .task(id: refreshID) {
            isLoading = true
            guard let url = URL(string: "\(APIConfig.base)/api/nutrition/correlations"),
                  let (raw, _) = try? await URLSession.authed.data(from: url),
                  let decoded  = try? APIService.decoder.decode(NutritionCorrelations.self, from: raw)
            else { isLoading = false; return }
            data = decoded
            isLoading = false
            // Load timing analysis in parallel
            if let tUrl = URL(string: "\(APIService.shared.baseURL)/api/nutrition_timing"),
               let (tRaw, _) = try? await URLSession.authed.data(from: tUrl),
               let tDecoded = try? APIService.decoder.decode(NutritionTimingData.self, from: tRaw) {
                timingData = tDecoded
            }
        }
    }

    private func hasInsights(_ d: NutritionCorrelations) -> Bool {
        d.protRpe != nil || d.calRec != nil || d.volCal != nil
    }
}

private struct NutritionCorrInsightRow: View {
    let icon:     String
    let title:    String
    let left:     (label: String, value: String)
    let right:    (label: String, value: String)
    let positive: Bool
    let note:     String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.appCaption)
                    .foregroundColor(.gray)
                Text(title)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(left.value)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(positive ? .green : .orange)
                    Text(left.label)
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10)).foregroundColor(.gray)

                VStack(spacing: 2) {
                    Text(right.value)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.gray.opacity(0.8))
                    Text(right.label)
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 4) {
                Image(systemName: positive ? "checkmark.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(positive ? .green : .yellow)
                Text(note)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
}

// MARK: - Nutrition Quality Badge

struct NutritionQualityBadge: View {
    let score: Int
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(qualityColor)
                .frame(width: 8, height: 8)
            Text("Qualité du jour")
                .font(.appLabel)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(score)/100")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(qualityColor)
            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.appLabel)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .alert("Qualité du jour", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Calories et protéines vs tes objectifs aujourd'hui")
        }
    }

    private var qualityColor: Color {
        if score > 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
}

// MARK: - Workout Timing Card

struct WorkoutTimingCard: View {
    let todayType: String?
    let totals: NutritionTotals?
    let settings: NutritionSettings?

    private struct Guidance {
        let icon: String
        let color: Color
        let title: String
        let body: String
    }

    private var guidance: Guidance? {
        let hour = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        let isTraining = ["heavy", "moderate", "light"].contains(todayType)
        let protConsumed = totals?.proteines ?? 0
        let protGoal = settings?.proteines ?? 0
        let calConsumed = totals?.calories ?? 0
        let calGoal = settings?.calories ?? 0
        let protDeficit = protGoal > 0 ? protGoal - protConsumed : 0
        let calDeficit = calGoal > 0 ? calGoal - calConsumed : 0

        if isTraining && (5...10).contains(hour) {
            return Guidance(
                icon: "bolt.fill",
                color: Color.forge,
                title: "Fenêtre pré-entraînement",
                body: "Vise +30–40g glucides + 20g protéines 1–2h avant ta séance."
            )
        }
        if isTraining && (12...16).contains(hour) {
            let msg = protDeficit > 15
                ? "Mange +\(Int(protDeficit))g protéines + des glucides dans les 2h."
                : "Continue sur ta lancée, fenêtre anabolique active."
            return Guidance(
                icon: "arrow.triangle.2.circlepath",
                color: .green,
                title: "Récupération post-entraînement",
                body: msg
            )
        }
        if (19...23).contains(hour) && protDeficit > 20 {
            return Guidance(
                icon: "moon.stars.fill",
                color: .blue,
                title: "Protéines avant de dormir",
                body: "Il te manque \(Int(protDeficit))g de protéines. Skyr ou cottage cheese pour la nuit."
            )
        }
        if (15...19).contains(hour) && calDeficit < -200 {
            return Guidance(
                icon: "exclamationmark.triangle.fill",
                color: .red,
                title: "Surplus calorique",
                body: "Tu as dépassé ton objectif de \(Int(-calDeficit)) kcal. Reste léger ce soir."
            )
        }
        return nil
    }

    var body: some View {
        if let g = guidance {
            HStack(spacing: 12) {
                Image(systemName: g.icon)
                    .font(.system(size: 18))
                    .foregroundColor(g.color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.title)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(g.body)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(g.color.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(g.color.opacity(0.2), lineWidth: 1))
            .cornerRadius(12)
        }
    }
}
