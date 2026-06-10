import SwiftUI
import Charts

// MARK: - LSS Sparkline Row
struct LSSSparklineRow: View {
    let trend: [LifeStressScore]   // index 0 = today (most recent)
    let currentLss: Double?
    let accentColor: Color

    private var sorted: [LifeStressScore] { trend.sorted { $0.date < $1.date } }

    private var avg: Double {
        let scores = trend.map { $0.score }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    private var delta: Double {
        guard let lss = currentLss else { return 0 }
        return lss - avg
    }

    var body: some View {
        HStack(spacing: 10) {
            Chart {
                ForEach(sorted.indices, id: \.self) { i in
                    LineMark(
                        x: .value("j", i),
                        y: .value("LSS", sorted[i].score)
                    )
                    .foregroundStyle(accentColor.opacity(0.8))
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("j", i),
                        y: .value("LSS", sorted[i].score)
                    )
                    .foregroundStyle(accentColor.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .frame(width: 72, height: 28)

            let d = delta
            HStack(spacing: 3) {
                Image(systemName: d >= 3 ? "arrow.up.right" : d <= -3 ? "arrow.down.right" : "arrow.right")
                    .font(.appMicro.weight(.bold))
                Text("\(d >= 0 ? "+" : "")\(String(format: "%.0f", d)) pts vs moy 7j")
                    .font(.appCaption)
            }
            .foregroundColor(d >= 5 ? .green : d <= -5 ? .orange : .gray)

            Spacer()
        }
    }
}

// MARK: - LSS Gauge
struct LSSGauge: View {
    let score: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 6)
                Capsule()
                    .fill(LinearGradient(
                        colors: [.red, .orange, .yellow, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * score / 100, height: 6)
                    .animation(.easeOut(duration: 0.7), value: score)
                // Curseur
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .shadow(color: color.opacity(0.5), radius: 4)
                    .offset(x: max(0, geo.size.width * score / 100 - 5))
                    .animation(.easeOut(duration: 0.7), value: score)
            }
        }
        .frame(height: 10)
    }
}

// MARK: - LSS Components Row
struct LSSComponentsRow: View {
    let components: MorningBriefComponents

    private var items: [(String, String, Double?)] {
        [
            ("moon.fill",       "Sommeil",   components.sleepQuality),
            ("waveform.path.ecg", "HRV",     components.hrvTrend),
            ("heart.fill",      "FC repos",  components.rhrTrend),
            ("brain.head.profile", "Stress", components.subjectiveStress),
            ("flame.fill",      "Fatigue",   components.trainingFatigue),
        ]
    }

    var body: some View {
        let available = items.filter { $0.2 != nil }
        if available.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("DÉTAIL LSS")
                    .font(.appMicro.weight(.bold)).tracking(2)
                    .foregroundColor(.gray)
                HStack(spacing: 6) {
                    ForEach(available, id: \.0) { icon, label, value in
                        if let v = value {
                            VStack(spacing: 4) {
                                Image(systemName: icon)
                                    .font(.appMicro)
                                    .foregroundColor(scoreColor(v))
                                GeometryReader { geo in
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.07))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(scoreColor(v))
                                            .frame(height: geo.size.height * v / 100)
                                    }
                                }
                                .frame(width: 6, height: 24)
                                .animation(.easeOut(duration: 0.6), value: v)
                                Text(label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        )
    }

    private func scoreColor(_ v: Double) -> Color {
        if v >= 70 { return .green }
        if v >= 45 { return .yellow }
        return .red
    }
}

// MARK: - Peak Prediction Card
struct PeakPredictionCard: View {
    let prediction: PeakPredictionResponse

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "go":         return .green
        case "go_caution": return .yellow
        case "reduce":     return .orange
        default:           return .red
        }
    }

    private func dayLabel(_ dateStr: String) -> String {
        guard let d = DateFormatter.isoDate.date(from: dateStr) else { return "?" }
        let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "fr_CA")
        return f.string(from: d).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.appCaption.weight(.bold)).foregroundColor(.purple)
                Text("PRÉVISION 7 JOURS")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("base LSS \(String(format: "%.0f", prediction.baseline))")
                    .font(.appCaption).foregroundColor(.gray)
                CardInfoButton(title: "Prévision 7 jours", entries: InfoEntry.predictionEntries)
            }

            HStack(spacing: 6) {
                ForEach(prediction.days) { day in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(levelColor(day.level).opacity(day.isPeak ? 0.3 : 0.1))
                                .frame(width: 36, height: 36)
                            if day.isPeak {
                                Circle()
                                    .stroke(Color.forge, lineWidth: 1.5)
                                    .frame(width: 36, height: 36)
                            }
                            Text("\(Int(day.predictedLss))")
                                .font(.appCaption.weight(day.isPeak ? .black : .semibold))
                                .foregroundColor(day.isPeak ? Color.forge : levelColor(day.level))
                        }
                        Text(dayLabel(day.date))
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(day.isPeak ? Color.forge : .gray)
                        if day.isPeak {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7)).foregroundColor(Color.forge)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Fix #6: CTA toward best training day
            if let peakDay = prediction.days.first(where: { $0.isPeak }) {
                NavigationLink(destination: StatsView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.appCaption)
                            .foregroundColor(Color.forge)
                        Text("Jour optimal : \(dayLabel(peakDay.date)) — Voir les stats")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.forge)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.forge.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(color: .purple, intensity: 0.04)
        .cornerRadius(16)
    }
}

// MARK: - Deload Compact Chip (fix #7 — level 1 only)
struct DeloadChipView: View {
    let report: DeloadReport

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.appCaption)
                .foregroundColor(Color.forge)
            Text("Fatigue accumulée détectée — score \(report.fatigueScore)/100")
                .font(.appLabel)
                .foregroundColor(.white)
            Spacer()
            Text("Niv. \(report.fatigueLevel)")
                .font(.appCaption.weight(.semibold))
                .foregroundColor(Color.forge)
            CardInfoButton(title: "Fatigue & déload", entries: InfoEntry.deloadEntries)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.forge.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.25), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Mood Card (fix #8 — proper card instead of raw button)
struct MoodCardView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.yellow.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: "face.smiling.fill")
                        .font(.appHeadline.weight(.regular))
                        .foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ÉTAT INTERNE")
                        .font(.appMicro.weight(.bold)).tracking(2)
                        .foregroundColor(.gray)
                    Text("Aujourd'hui — où tu en es ?")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.gray)
            }
            .padding(14)
            .glassCard(color: .yellow, intensity: 0.05)
            .cornerRadius(16)
        }
        .buttonStyle(SpringButtonStyle())
    }
}

// MARK: - Sleep Prompt Card

struct SleepPromptCard: View {
    let onDone: () -> Void
    var onError: (String) -> Void = { _ in }

    @State private var bedtime: Date = {
        let tz = TimeZone.current.secondsFromGMT()
        let local = Int(Date().timeIntervalSince1970) + tz
        return Date(timeIntervalSince1970: TimeInterval(local - (local % 86400) + 23 * 3600 - tz))
    }()
    @State private var wakeTime: Date = {
        let tz = TimeZone.current.secondsFromGMT()
        let local = Int(Date().timeIntervalSince1970) + tz
        return Date(timeIntervalSince1970: TimeInterval(local - (local % 86400) + 7 * 3600 - tz))
    }()
    @State private var isSaving = false
    @State private var hkImported = false

    private var durationHours: Double {
        let d = wakeTime.timeIntervalSince(bedtime) / 3600
        return d < 0 ? d + 24 : d
    }

    private var durationColor: Color {
        if durationHours < 6  { return .red }
        if durationHours < 7  { return .yellow }
        if durationHours <= 9 { return .green }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.appBody)
                    .foregroundColor(.blue)
                Text("Ton sommeil cette nuit")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    onDone() // dismiss without saving
                } label: {
                    Image(systemName: "xmark")
                        .font(.appCaption.weight(.bold))
                        .foregroundColor(.gray)
                        .padding(6)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if hkImported {
                Label("Horaires détectés depuis Santé", systemImage: "heart.fill")
                    .font(.appCaption)
                    .foregroundColor(.red.opacity(0.8))
            }

            // Pickers
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COUCHÉ")
                        .font(.appMicro.weight(.bold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEVÉ")
                        .font(.appMicro.weight(.bold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                Spacer()
                // Duration badge
                VStack(spacing: 2) {
                    Text(String(format: "%.1fh", durationHours))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(durationColor)
                    Text("durée")
                        .font(.appMicro)
                        .foregroundColor(.gray)
                }
            }

            // Save button
            Button {
                Task { await save() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(Color.onAccent).scaleEffect(0.8)
                    } else {
                        Text("Enregistrer")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(Color.onAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.forge)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isSaving || durationHours <= 0 || durationHours > 16)

            // Fix #16: explain why save is disabled
            if durationHours <= 0 || durationHours > 16 {
                Text("Durée invalide — ajuste l'heure de coucher ou de réveil")
                    .font(.appCaption)
                    .foregroundColor(Color.forge.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.25), lineWidth: 1))
        )
        .task { await tryHealthKitImport() }
    }

    private func tryHealthKitImport() async {
        guard let window = await HealthKitService.shared.fetchLastNightSleepWindow() else { return }
        await MainActor.run {
            bedtime    = window.bedtime
            wakeTime   = window.wakeTime
            hkImported = true
        }
    }

    private func save() async {
        isSaving = true
        do {
            try await APIService.shared.logRecovery(
                sleepHours:   durationHours,
                sleepQuality: nil,
                restingHr:    nil,
                hrv:          nil,
                steps:        nil,
                soreness:     nil,
                notes:        ""
            )
            await MainActor.run {
                isSaving = false
                onDone()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                onError("Impossible d'enregistrer le sommeil pour le moment.")
            }
        }
    }
}

// MARK: - Insights Card

struct DashboardInsightsCard: View {
    let insights: [InsightEntry]

    private func color(for level: String) -> Color {
        switch level {
        case "warning": return .orange
        case "success": return .green
        default:        return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "INTELLIGENCE", icon: "brain.head.profile")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ForEach(Array(insights.enumerated()), id: \.element.id) { idx, insight in
                if idx > 0 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.horizontal, 16)
                }
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color(for: insight.level).opacity(0.15))
                            .frame(width: 34, height: 34)
                        Image(systemName: insight.icon)
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(color(for: insight.level))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(insight.title)
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.white)
                        Text(insight.message)
                            .font(.appCaption)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Spacer(minLength: 4)
        }
        .glassCard(color: .purple, intensity: 0.05)
    }
}

// MARK: - LSS Mini Card (dashboard)

struct LSSMiniCard: View {
    let trend: [LifeStressScore]

    private var today: LifeStressScore? { trend.first }

    private var color: Color {
        guard let s = today?.score else { return .gray }
        if s >= 70 { return .green }
        if s >= 40 { return .orange }
        return .red
    }

    private var delta: Double? {
        guard trend.count >= 2 else { return nil }
        return trend[0].score - trend[1].score
    }

    var body: some View {
        guard let lss = today else { return AnyView(EmptyView()) }

        return AnyView(
            NavigationLink(destination: MentalAmeView()) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Text("\(Int(lss.score))")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STRESS DE VIE")
                            .font(.appMicro.weight(.bold))
                            .tracking(2)
                            .foregroundColor(.gray)
                        HStack(spacing: 6) {
                            Text("\(Int(lss.score))/100")
                                .font(.appLabel.weight(.bold))
                                .foregroundColor(color)
                            if let d = delta {
                                HStack(spacing: 2) {
                                    Image(systemName: d >= 3 ? "arrow.up.right" : d <= -3 ? "arrow.down.right" : "arrow.right")
                                        .font(.appMicro.weight(.bold))
                                    Text("\(d >= 0 ? "+" : "")\(Int(d))")
                                        .font(.appCaption)
                                }
                                .foregroundColor(d >= 3 ? .green : d <= -3 ? .orange : .gray)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.appCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.18), lineWidth: 1))
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        )
    }
}
