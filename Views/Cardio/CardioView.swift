import SwiftUI
import Charts
import OSLog
#if os(iOS)
import HealthKit
#endif

private let logger = Logger(subsystem: "TrainingOS", category: "Cardio")

struct CardioView: View {
    @EnvironmentObject private var appState: AppState
    @State private var cardioLog: [CardioEntry] = []
    @State private var hiitLog:   [HIITEntry]   = []
    @State private var metrics:   CardioMetrics? = nil
    @State private var isLoading = true
    @State private var showSheet = false
    @State private var showActiveSession = false
    @State private var isImportingHK = false
    @State private var apiError: String? = nil
    @State private var toast: ToastMessage? = nil
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var sessionManager = CardioSessionManager.shared
    @AppStorage("cardio_max_hr") private var maxHR: Int = 190

    // MARK: Computed KPIs
    var totalSessions: Int    { cardioLog.count + hiitLog.count }
    var totalDistanceKm: Double { cardioLog.compactMap(\.distanceKm).reduce(0, +) }
    var avgRpe: Double {
        let r = cardioLog.compactMap(\.rpe); return r.isEmpty ? 0 : r.reduce(0, +) / Double(r.count)
    }
    var totalDurationMin: Double { cardioLog.compactMap(\.durationMin).reduce(0, +) }

    var monthDistanceKm: Double {
        let prefix = String(Date().ISO8601Format().prefix(7))
        return cardioLog.filter { ($0.date ?? "").hasPrefix(prefix) }
            .compactMap(\.distanceKm).reduce(0, +)
    }

    var unifiedHistory: [UnifiedCardioEntry] {
        let c = cardioLog.map { UnifiedCardioEntry.cardio($0) }
        let h = hiitLog.map  { UnifiedCardioEntry.hiit($0) }
        return (c + h).sorted { ($0.date ?? "") > ($1.date ?? "") }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: Color.statusCyan)
                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // 1 — Header CTA
                            CardioHeaderSection(
                                lastSession: cardioLog.first,
                                monthDistanceKm: monthDistanceKm,
                                onStart: { showActiveSession = true }
                            )
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.0)

                            // 2 — Session active (inline)
                            if sessionManager.sessionState != .idle {
                                ActiveSessionBanner { showActiveSession = true }
                                    .padding(.horizontal, 16)
                            }

                            // 3 — KPI grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                KPICard(value: "\(totalSessions)", label: "Sessions", color: Color.statusCyan)
                                KPICard(value: String(format: "%.1f km", totalDistanceKm), label: "Distance tot.", color: Color.statusBlue)
                                KPICard(value: totalDurationMin > 0 ? String(format: "%.0f min", totalDurationMin) : "—",
                                        label: "Durée tot.", color: Color.forge)
                                KPICard(value: avgRpe > 0 ? String(format: "%.1f", avgRpe) : "—",
                                        label: "RPE moy.", color: Color.appDanger)
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // 4 — Distance chart
                            if cardioLog.filter({ $0.distanceKm != nil }).count >= 2 {
                                CardioDistanceChart(entries: Array(cardioLog.prefix(8).reversed()))
                                    .padding(.horizontal, 16)
                            }

                            // 5 — Guide dynamique
                            if let m = metrics {
                                CardioGuidesSection(metrics: m)
                                    .padding(.horizontal, 16)
                            }

                            // 6 — Historique unifié
                            let history = unifiedHistory
                            if history.isEmpty {
                                CardioEmptyState()
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("HISTORIQUE")
                                        .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                                        .padding(.horizontal, 16)
                                    ForEach(history) { entry in
                                        UnifiedHistoryRow(entry: entry, onDelete: {
                                            await deleteEntry(entry)
                                        })
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }

                            Spacer(minLength: 32)
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, contentBottomPadding)
                    }
                    .refreshable { await loadData() }
                }
            }
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showActiveSession = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill").font(.appLabel.weight(.regular))
                            Text("GPS").font(.appLabel)
                        }
                        .foregroundColor(sessionManager.sessionState != .idle ? Color.appDanger : Color.statusCyan)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: importFromHealthKit) {
                        HStack(spacing: 4) {
                            if isImportingHK {
                                ProgressView().tint(Color.forge).scaleEffect(0.7)
                            } else {
                                Image(systemName: "heart.text.square").font(.appLabel.weight(.regular))
                            }
                            Text("Santé").font(.appLabel)
                        }
                        .foregroundColor(Color.forge)
                    }
                    .disabled(isImportingHK)
                }
            }
            .sheet(isPresented: $showSheet) {
                LogCardioSheet(onSaved: { await loadData() })
            }
            .fullScreenCover(isPresented: $showActiveSession) {
                CardioActiveView()
                    .onDisappear { Task { await loadData() } }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showSheet = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding + 16)
            }
        }
        .task { await loadData() }
        .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(apiError ?? "") }
        .toast($toast)
    }

    // MARK: Data loading (sequential — iOS 26 async let bug)
    private func loadData() async {
        isLoading = true
        cardioLog = (try? await APIService.shared.fetchCardioData()) ?? []
        hiitLog   = (try? await APIService.shared.fetchHIITData()) ?? []
        metrics   = try? await APIService.shared.fetchCardioMetrics(maxHR: max(100, min(220, maxHR)))
        isLoading = false
    }

    private func deleteEntry(_ entry: UnifiedCardioEntry) async {
        do {
            switch entry {
            case .cardio(let e):
                try await APIService.shared.deleteCardio(date: e.date ?? "", type: e.type ?? "")
            case .hiit(let e):
                try await APIService.shared.deleteHIIT(date: e.date ?? "", sessionType: e.sessionType ?? "")
            }
            await MainActor.run { toast = ToastMessage(message: "Séance supprimée", style: .success) }
        } catch {
            await MainActor.run { apiError = "Erreur réseau — réessaie" }
        }
        await loadData()
    }

    private func importFromHealthKit() {
        isImportingHK = true
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isImportingHK = false; return }

            let workouts = await hk.fetchAllWorkouts(days: 30)
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let existing = Set(cardioLog.compactMap { e -> String? in
                guard let d = e.date, let t = e.type else { return nil }
                return "\(d)|\(t)"
            })

            for w in workouts {
                guard let entry = hk.workoutToCardioEntry(w) else { continue }
                let dateStr = fmt.string(from: w.startDate)
                let key = "\(dateStr)|\(entry.type)"
                guard !existing.contains(key) else { continue }

                var pace: String? = nil
                if let dist = entry.distanceKm, dist > 0 {
                    let secPerKm = w.duration / dist
                    let min = Int(secPerKm / 60)
                    let sec = Int(secPerKm.truncatingRemainder(dividingBy: 60))
                    pace = String(format: "%d:%02d", min, sec)
                }
                do {
                    try await APIService.shared.logCardio(
                        type: entry.type, durationMin: entry.durationMin,
                        distanceKm: entry.distanceKm, avgPace: pace,
                        avgHr: entry.avgHr, cadence: nil,
                        calories: entry.calories, rpe: nil,
                        notes: "Importé depuis Apple Santé"
                    )
                } catch {
                    logger.error("HealthKit import failed: \(error)")
                }
            }
            await loadData()
            isImportingHK = false
        }
    }
}

// MARK: - Header CTA
struct CardioHeaderSection: View {
    let lastSession: CardioEntry?
    let monthDistanceKm: Double
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onStart) {
                HStack(spacing: 10) {
                    Image(systemName: "play.circle.fill").font(.appTitle.weight(.regular))
                    Text("Démarrer une session GPS").font(.appBody.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.appLabel.weight(.regular))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Color.statusCyan)
                .cornerRadius(14)
            }
            .buttonStyle(SpringButtonStyle())

            HStack(spacing: 16) {
                if let last = lastSession {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.appCaption).foregroundColor(.gray)
                        Text("Dernière : \(last.type?.capitalized ?? "—")\(last.distanceKm.map { String(format: " %.1f km", $0) } ?? "")")
                            .font(.appCaption).foregroundColor(.gray)
                    }
                }
                Spacer()
                if monthDistanceKm > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.appCaption).foregroundColor(Color.statusCyan.opacity(0.7))
                        Text(String(format: "%.1f km ce mois", monthDistanceKm))
                            .font(.appCaption.weight(.medium)).foregroundColor(Color.statusCyan.opacity(0.8))
                    }
                }
            }
        }
    }
}

// MARK: - Active Session Banner
struct ActiveSessionBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle().fill(Color.appDanger).frame(width: 8, height: 8)
                Text("Session en cours — Tap pour reprendre")
                    .font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.appCaption).foregroundColor(.gray)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.appCard)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appDanger.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guides Section
struct CardioGuidesSection: View {
    let metrics: CardioMetrics
    @State private var hkVO2Max: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INTELLIGENCE CARDIO")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)

            // VO2max estimé (Jack Daniels)
            CardioMetricCard(
                icon: "lungs.fill",
                color: vo2maxColor,
                title: "VO2max estimé",
                value: metrics.vo2maxEstimated.map { String(format: "%.1f mL/kg/min", $0) } ?? "—",
                badge: metrics.vo2maxCategory,
                guide: metrics.guides?.vo2max ?? "",
                methodology: "Formule Jack Daniels VDOT depuis pace + distance réels. Moyenne des estimations sur 30 jours (min. 3 sessions). Types pris en compte : course, tempo, endurance, léger. Catégories : < 36 Faible · 36-43 Moyen · 43-50 Bon · 50-56 Excellent · 56+ Élite."
            )

            // VO2 max Apple Watch (si disponible — mesure directe)
            if let v = hkVO2Max {
                CardioMetricCard(
                    icon: "lungs",
                    color: Color.statusCyan,
                    title: "VO2 max (Apple Watch)",
                    value: String(format: "%.1f mL/kg/min", v),
                    badge: vo2CategoryLabel(v),
                    guide: "VO2 max mesuré par l'Apple Watch pendant les séances de course en plein air. Disponible après plusieurs sessions avec GPS.",
                    methodology: "Apple Watch croise FC et vitesse GPS pour estimer le VO2 max. Mis à jour automatiquement via HealthKit."
                )
            }

            // ACWR Cardio
            if let acwr = metrics.acwrCardio {
                CardioMetricCard(
                    icon: "waveform.path.ecg",
                    color: acwrColor(acwr.zone),
                    title: "Charge cardio (ACWR)",
                    value: acwr.ratio > 0 ? String(format: "%.2f", acwr.ratio) : "—",
                    badge: acwrLabel(acwr.zone),
                    guide: metrics.guides?.acwr ?? "",
                    methodology: "Acute:Chronic Workload Ratio — cardio uniquement. Charge aiguë (7 derniers jours) ÷ charge chronique moyenne (28 jours). Volume = distance km si disponible, sinon durée ÷ 10. Zones : < 0.8 sous-charge · 0.8-1.3 optimal · 1.3-1.5 sur-charge · > 1.5 critique."
                )
            }

            // FC Zones
            if let zones = metrics.fcZones {
                FCZonesSummaryCard(
                    zones: zones,
                    guide: metrics.guides?.zones ?? "",
                    hrSource: metrics.hrSource ?? "formula"
                )
            }

            // Pace Zones
            if let pz = metrics.paceZones, metrics.dataCoverage?.hasPace == true {
                PaceZonesCard(paceZones: pz, guide: metrics.guides?.pace ?? "")
            }

            // Seuil lactique
            if let threshold = metrics.thresholdPaceMinPerKm {
                CardioMetricCard(
                    icon: "flame.fill",
                    color: Color.forge,
                    title: "Seuil lactique estimé",
                    value: threshold + " /km",
                    badge: nil,
                    guide: metrics.guides?.threshold ?? "",
                    methodology: "Estimé à best_pace + 20s/km. Pour une mesure précise : cours 30 min à l'allure maximale que tu peux soutenir — la moyenne de ce pace correspond à ton seuil lactique réel."
                )
            }
        }
        .task {
            hkVO2Max = await HealthKitService.shared.fetchLatestVO2Max()
        }
    }

    private func vo2CategoryLabel(_ v: Double) -> String? {
        if v >= 56 { return "Élite" }
        if v >= 50 { return "Excellent" }
        if v >= 43 { return "Bon" }
        if v >= 36 { return "Moyen" }
        return "Faible"
    }

    var vo2maxColor: Color {
        guard let v = metrics.vo2maxEstimated else { return .gray }
        if v >= 50 { return Color.appSuccess }
        if v >= 40 { return Color.statusCyan }
        return Color.appWarning
    }

    func acwrColor(_ zone: String) -> Color {
        switch zone {
        case "optimal":  return Color.appSuccess
        case "under":    return Color.statusBlue
        case "over":     return Color.appWarning
        case "critical": return Color.appDanger
        default:         return .gray
        }
    }

    func acwrLabel(_ zone: String) -> String? {
        switch zone {
        case "optimal":  return "Optimal"
        case "under":    return "Sous-charge"
        case "over":     return "Sur-charge"
        case "critical": return "⚠️ Critique"
        case "no_data":  return "Pas de données"
        default:         return nil
        }
    }
}

struct CardioMetricCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let badge: String?
    let guide: String
    var methodology: String = ""

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.appLabel.weight(.regular)).foregroundColor(color)
                Text(title.uppercased())
                    .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.gray)
                Spacer()
                if let b = badge {
                    Text(b)
                        .font(.appCaption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color.opacity(0.15))
                        .foregroundColor(color)
                        .cornerRadius(6)
                }
                Image(systemName: "chevron.right")
                    .font(.appCaption).foregroundColor(.gray.opacity(0.5))
            }
            Text(value)
                .font(.system(size: 26, weight: .bold)).foregroundColor(.appTextPrimary)
            if !guide.isEmpty {
                Text(guide)
                    .font(.appCaption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            CardioMetricDetailSheet(
                icon: icon, color: color, title: title,
                value: value, badge: badge, guide: guide,
                methodology: methodology
            )
        }
    }
}

// MARK: - Metric Detail Sheet
struct CardioMetricDetailSheet: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let badge: String?
    let guide: String
    let methodology: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header avec valeur
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: icon).font(.appHeadline.weight(.regular)).foregroundColor(color)
                                if let b = badge {
                                    Text(b)
                                        .font(.appCaption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(8)
                                }
                            }
                            Text(value)
                                .font(.system(size: 40, weight: .heavy)).foregroundColor(.appTextPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(color.opacity(0.07)).cornerRadius(16)

                        // Conseil
                        if !guide.isEmpty {
                            metricSection(title: "CONSEIL", icon: "lightbulb.fill", iconColor: Color.statusYellow, content: guide)
                        }

                        // Méthodologie
                        if !methodology.isEmpty {
                            metricSection(title: "MÉTHODE DE CALCUL", icon: "function", iconColor: .gray, content: methodology)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundColor(color)
                }
            }
        }
    }

    @ViewBuilder
    func metricSection(title: String, icon: String, iconColor: Color, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.appCaption).foregroundColor(iconColor)
                Text(title).font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.gray)
            }
            Text(content)
                .font(.appLabel.weight(.regular)).foregroundColor(.appTextPrimary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Color.appCard).cornerRadius(12)
    }
}

struct FCZonesSummaryCard: View {
    let zones: FCZones
    let guide: String
    var hrSource: String = "formula"

    @State private var showDetail = false

    private let zoneNames  = ["Z1 Récup.", "Z2 Aérobie", "Z3 Modéré", "Z4 Seuil", "Z5 VO2max"]
    private let zoneColors: [Color] = [Color.statusBlue, Color.appSuccess, Color.statusYellow, Color.appWarning, Color.appDanger]

    var zoneRanges: [(String, Color, String)] {
        [
            (zoneNames[0], zoneColors[0], "\(zones.zone1[0])–\(zones.zone1[1]) bpm"),
            (zoneNames[1], zoneColors[1], "\(zones.zone2[0])–\(zones.zone2[1]) bpm"),
            (zoneNames[2], zoneColors[2], "\(zones.zone3[0])–\(zones.zone3[1]) bpm"),
            (zoneNames[3], zoneColors[3], "\(zones.zone4[0])–\(zones.zone4[1]) bpm"),
            (zoneNames[4], zoneColors[4], "\(zones.zone5[0])–\(zones.zone5[1]) bpm"),
        ]
    }

    var hrSourceLabel: String {
        switch hrSource {
        case "manual":   return "FC max manuelle"
        case "observed": return "Max observé ×1.10"
        default:         return "220 − âge"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.fill").font(.appLabel.weight(.regular)).foregroundColor(Color.statusRed)
                Text("ZONES FC — FCmax \(zones.maxHr) bpm")
                    .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.gray)
                Spacer()
                Text(hrSourceLabel)
                    .font(.appMicro).foregroundColor(.secondary)
                Image(systemName: "chevron.right").font(.appCaption).foregroundColor(.gray.opacity(0.5))
            }
            VStack(spacing: 4) {
                ForEach(zoneRanges, id: \.0) { name, color, range in
                    HStack {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(name).font(.appCaption).foregroundColor(.gray).frame(width: 80, alignment: .leading)
                        Spacer()
                        Text(range).font(.appCaption.weight(.medium)).foregroundColor(.appTextPrimary)
                    }
                }
            }
            if !guide.isEmpty {
                Text(guide)
                    .font(.appCaption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusRed.opacity(0.12), lineWidth: 1))
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            CardioMetricDetailSheet(
                icon: "heart.fill", color: Color.statusRed,
                title: "Zones FC",
                value: "FCmax \(zones.maxHr) bpm",
                badge: hrSourceLabel,
                guide: guide,
                methodology: "5 zones basées sur ta FC max. Priorité : réglage manuel (Réglages → FCmax) > max observé ×1.10 > formule 220−âge.\n\nZ1 Récupération (50–60%) · Z2 Aérobie de base (60–70%) · Z3 Aérobie modéré (70–80%) · Z4 Seuil anaérobie (80–90%) · Z5 VO2max/Maximal (90–100%)"
            )
        }
    }
}

struct PaceZonesCard: View {
    let paceZones: PaceZones
    let guide: String

    var rows: [(String, Color, String)] {
        [
            ("Easy",      Color.statusBlue,   paceZones.easy),
            ("Moderate",  Color.appSuccess,   paceZones.moderate),
            ("Tempo",     Color.statusYellow, paceZones.tempo),
            ("Threshold", Color.forge,        paceZones.threshold),
            ("Race",      Color.appDanger,    paceZones.race),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "speedometer").font(.appLabel.weight(.regular)).foregroundColor(Color.statusBlue)
                Text("PACE ZONES")
                    .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.gray)
            }
            VStack(spacing: 4) {
                ForEach(rows, id: \.0) { name, color, range in
                    HStack {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(name).font(.appCaption).foregroundColor(.gray).frame(width: 70, alignment: .leading)
                        Spacer()
                        Text(range + " /km").font(.appCaption.weight(.medium)).foregroundColor(.appTextPrimary)
                    }
                }
            }
            if !guide.isEmpty {
                Text(guide)
                    .font(.appCaption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusBlue.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Unified History Row
struct UnifiedHistoryRow: View {
    let entry: UnifiedCardioEntry
    let onDelete: () async -> Void
    @State private var showDetail = false

    var body: some View {
        Group {
            switch entry {
            case .cardio(let e):
                CardioRow(entry: e, onDelete: { Task { await onDelete() } })
            case .hiit(let e):
                HIITHistoryRow(entry: e, onDelete: { Task { await onDelete() } })
            }
        }
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            CardioHistoryDetailSheet(entry: entry)
        }
    }
}

// MARK: - History Detail Sheet
struct CardioHistoryDetailSheet: View {
    let entry: UnifiedCardioEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        switch entry {
                        case .cardio(let e): cardioDetail(e)
                        case .hiit(let e):   hiitDetail(e)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundColor(Color.statusCyan)
                }
            }
        }
    }

    var detailTitle: String {
        switch entry {
        case .cardio(let e): return e.type?.capitalized ?? "Séance"
        case .hiit(let e):   return e.sessionType ?? "HIIT"
        }
    }

    @ViewBuilder
    func cardioDetail(_ e: CardioEntry) -> some View {
        // Header
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(cardioColor(e.type).opacity(0.15)).frame(width: 52, height: 52)
                Image(systemName: cardioIcon(e.type)).font(.appTitle.weight(.regular)).foregroundColor(cardioColor(e.type))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.type?.capitalized ?? "Séance").font(.appHeadline.weight(.bold)).foregroundColor(.appTextPrimary)
                Text(e.date ?? "—").font(.appLabel.weight(.regular)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(16).background(Color.appCard).cornerRadius(14)

        // Métriques
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let v = e.distanceKm   { DetailKPI(label: "Distance",   value: String(format: "%.2f km", v),      color: Color.statusCyan) }
            if let v = e.durationMin  { DetailKPI(label: "Durée",      value: String(format: "%.0f min", v),     color: Color.statusBlue) }
            if let v = e.avgPace      { DetailKPI(label: "Allure",     value: v + " /km",                        color: Color.appSuccess) }
            if let v = e.avgHr        { DetailKPI(label: "FC moyenne", value: String(format: "%.0f bpm", v),     color: Color.appDanger) }
            if let v = e.calories     { DetailKPI(label: "Calories",   value: String(format: "%.0f kcal", v),    color: Color.forge) }
            if let v = e.cadence      { DetailKPI(label: "Cadence",    value: String(format: "%.0f spm", v),     color: Color.statusPurple) }
            if let v = e.rpe          { DetailKPI(label: "RPE",        value: String(format: "%.1f / 10", v),    color: Color.appDanger) }
        }

        // GPS indicator
        if e.gpsPoints?.isEmpty == false {
            HStack(spacing: 8) {
                Image(systemName: "location.fill").foregroundColor(Color.statusCyan).font(.appLabel.weight(.regular))
                Text("Session GPS enregistrée — \(e.gpsPoints?.count ?? 0) points")
                    .font(.appLabel.weight(.regular)).foregroundColor(.secondary)
            }
            .padding(12).background(Color.appCard).cornerRadius(10)
        }

        // Notes
        if let notes = e.notes, !notes.isEmpty {
            detailSection(title: "NOTES", content: notes)
        }

        if let note = e.coachNote, !note.isEmpty {
            detailSection(title: "CONSEIL COACH", content: note)
        }
    }

    @ViewBuilder
    func hiitDetail(_ e: HIITEntry) -> some View {
        // Header
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.appDanger.opacity(0.15)).frame(width: 52, height: 52)
                Text("HIIT").font(.appCaption.weight(.black)).foregroundColor(Color.appDanger)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.sessionType ?? "HIIT").font(.appHeadline.weight(.bold)).foregroundColor(.appTextPrimary)
                Text(e.date ?? "—").font(.appLabel.weight(.regular)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(16).background(Color.appCard).cornerRadius(14)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let v = e.rounds   { DetailKPI(label: "Rounds",    value: "\(v)",               color: Color.appDanger) }
            if let v = e.workTime { DetailKPI(label: "Work",      value: "\(v)s",              color: Color.forge) }
            if let v = e.restTime { DetailKPI(label: "Repos",     value: "\(v)s",              color: Color.appSuccess) }
            if let v = e.rpe      { DetailKPI(label: "RPE",       value: String(format: "%.1f / 10", v), color: Color.appDanger) }
        }

        if let notes = e.notes, !notes.isEmpty {
            detailSection(title: "NOTES", content: notes)
        }
    }

    @ViewBuilder
    func detailSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.gray)
            Text(content).font(.appLabel.weight(.regular)).foregroundColor(.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Color.appCard).cornerRadius(12)
    }

    func cardioColor(_ type: String?) -> Color {
        switch type {
        case "course": return Color.statusCyan;    case "vélo":      return Color.statusYellow
        case "natation": return Color.statusBlue;  case "marche":    return Color.appSuccess
        case "elliptique": return Color.statusPurple
        default: return Color.appWarning
        }
    }

    func cardioIcon(_ type: String?) -> String {
        switch type {
        case "course": return "figure.run";       case "vélo":       return "figure.outdoor.cycle"
        case "natation": return "figure.pool.swim"; case "marche":   return "figure.walk"
        case "elliptique": return "figure.elliptical"
        default: return "heart.fill"
        }
    }
}

struct DetailKPI: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.appTitle).foregroundColor(color)
            Text(label).font(.appCaption.weight(.medium)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.appCard)
        .cornerRadius(10)
    }
}

struct HIITHistoryRow: View {
    let entry: HIITEntry
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            // HIIT badge (replaces type icon)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appDanger.opacity(0.15))
                    .frame(width: 42, height: 42)
                Text("HIIT")
                    .font(.appMicro.weight(.black))
                    .foregroundColor(Color.appDanger)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.sessionType ?? "HIIT")
                    .font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                Text(entry.date ?? "")
                    .font(.appCaption).foregroundColor(.gray)
                hiitDetails
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let rpe = entry.rpe {
                    Text(String(format: "RPE %.1f", rpe))
                        .font(.appCaption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.appDanger.opacity(0.12))
                        .foregroundColor(Color.appDanger)
                        .cornerRadius(6)
                }
            }

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.appCaption)
                    .frame(width: 30, height: 30)
                    .background(Color.appDanger.opacity(0.1))
                    .foregroundColor(Color.appDanger.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appDanger.opacity(0.08), lineWidth: 1))
        .confirmationDialog("Supprimer cette séance ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    @ViewBuilder
    var hiitDetails: some View {
        let parts: [String] = [
            entry.rounds.map { "\($0) rounds" },
            entry.workTime.map { "\($0)s work" },
            entry.restTime.map { "\($0)s rest" },
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.appCaption).foregroundColor(.secondary)
        }
        if let notes = entry.notes, !notes.isEmpty {
            Text(notes)
                .font(.appCaption).foregroundColor(.secondary)
                .italic()
                .lineLimit(1)
        }
    }
}

// MARK: - HR Zones Card
struct HRZonesCard: View {
    let hrValues: [Double]
    let maxHR: Int
    var onSetMaxHR: (Int) -> Void
    @State private var showMaxHRInput = false
    @State private var maxHRStr = ""

    private let zones: [(name: String, min: Double, max: Double, color: Color)] = [
        ("Z1 Récup.",   0.50, 0.60, Color.statusBlue),
        ("Z2 Aérobie",  0.60, 0.70, Color.appSuccess),
        ("Z3 Seuil",    0.70, 0.80, Color.statusYellow),
        ("Z4 Anaéro.", 0.80, 0.90, Color.forge),
        ("Z5 VO2max",  0.90, 1.00, Color.appDanger)
    ]

    private func zoneCounts() -> [Int] {
        let mhr = Double(maxHR)
        var counts = [0, 0, 0, 0, 0]
        for hr in hrValues {
            let pct = hr / mhr
            let idx = zones.firstIndex { pct >= $0.min && pct < $0.max } ?? (pct >= 0.9 ? 4 : 0)
            counts[idx] += 1
        }
        return counts
    }

    var body: some View {
        let counts = zoneCounts()
        let total = max(hrValues.count, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ZONES CARDIO")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Button("FCmax \(maxHR)") {
                    maxHRStr = "\(maxHR)"
                    showMaxHRInput = true
                }
                .font(.appCaption).foregroundColor(Color.statusCyan)
            }
            VStack(spacing: 5) {
                ForEach(zones.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text(zones[i].name)
                            .font(.appCaption).foregroundColor(.gray).frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(zones[i].color.opacity(0.3))
                                .frame(height: 14)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(zones[i].color)
                                        .frame(width: geo.size.width * Double(counts[i]) / Double(total), height: 14)
                                }
                        }
                        .frame(height: 14)
                        Text("\(Int(Double(counts[i]) / Double(total) * 100))%")
                            .font(.appCaption.weight(.bold)).foregroundColor(zones[i].color)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            Text("Basé sur \(hrValues.count) session(s) avec FC")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(14).glassCard()
        .alert("FC maximale", isPresented: $showMaxHRInput) {
            TextField("Ex: 190", text: $maxHRStr).keyboardType(.numberPad)
            Button("OK") { if let v = Int(maxHRStr), v > 100 { onSetMaxHR(v) } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Utilise 220 − ton âge ou une mesure réelle.") }
    }
}

// MARK: - Cardio Progression Card
struct CardioProgressionCard: View {
    let type: String
    let msg: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill").font(.appTitle.weight(.regular)).foregroundColor(Color.statusCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("PROGRESSION — \(type.uppercased())")
                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                Text(msg)
                    .font(.appLabel.weight(.regular)).foregroundColor(.appTextPrimary)
            }
            Spacer()
        }
        .padding(12).background(Color.statusCyan.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.statusCyan.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Row
struct CardioRow: View {
    let entry: CardioEntry
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: typeIcon)
                    .font(.appHeadline)
                    .foregroundColor(typeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(typeLabel)
                    .font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                Text(entry.date ?? "")
                    .font(.appCaption).foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let d = entry.distanceKm {
                    Text(String(format: "%.2f km", d))
                        .font(.appLabel.weight(.bold)).foregroundColor(Color.statusCyan)
                }
                HStack(spacing: 6) {
                    if let dur = entry.durationMin {
                        Label(String(format: "%.0f min", dur), systemImage: "clock")
                            .font(.appCaption).foregroundColor(.gray)
                    }
                    if let pace = entry.avgPace {
                        Label(pace + "/km", systemImage: "speedometer")
                            .font(.appCaption).foregroundColor(Color.statusBlue)
                    }
                }
                HStack(spacing: 6) {
                    if let cad = entry.cadence {
                        Label(String(format: "%.0f spm", cad), systemImage: "metronome")
                            .font(.appCaption).foregroundColor(Color.forge)
                    }
                    if let cal = entry.calories {
                        Label(String(format: "%.0f kcal", cal), systemImage: "flame.fill")
                            .font(.appCaption).foregroundColor(Color.appDanger)
                    }
                }
            }

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.appCaption)
                    .frame(width: 30, height: 30)
                    .background(Color.appDanger.opacity(0.1))
                    .foregroundColor(Color.appDanger.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(12)
        .confirmationDialog("Supprimer cette séance ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    var typeColor: Color {
        switch entry.type {
        case "course":    return Color.statusCyan
        case "vélo":      return Color.statusYellow
        case "natation":  return Color.statusBlue
        case "marche":    return Color.appSuccess
        case "elliptique":return Color.statusPurple
        default:          return Color.appWarning
        }
    }

    var typeIcon: String {
        switch entry.type {
        case "course":    return "figure.run"
        case "vélo":      return "figure.outdoor.cycle"
        case "natation":  return "figure.pool.swim"
        case "marche":    return "figure.walk"
        case "elliptique":return "figure.elliptical"
        default:          return "heart.fill"
        }
    }

    var typeLabel: String { entry.type?.capitalized ?? "—" }
}

// MARK: - Distance Chart
struct CardioDistanceChart: View {
    let entries: [CardioEntry]
    var maxDist: Double { entries.compactMap(\.distanceKm).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISTANCE — DERNIÈRES SÉANCES")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let dist = e.distanceKm ?? 0
                    let pct = maxDist > 0 ? dist / maxDist : 0
                    let isLast = i == entries.count - 1
                    VStack(spacing: 2) {
                        if dist > 0 {
                            Text(String(format: "%.1f", dist))
                                .font(.system(size: 7)).foregroundColor(Color.statusCyan.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? Color.statusCyan : Color.statusCyan.opacity(0.4))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
        }
        .padding(16).glassCard(color: Color.statusCyan, intensity: 0.05)
    }
}

// MARK: - Empty State
struct CardioEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "figure.run", title: "Aucune séance cardio", subtitle: "Appuie sur + pour en ajouter une")
    }
}

// MARK: - Log Sheet
struct LogCardioSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    private let types = ["course", "vélo", "natation", "marche", "elliptique", "autre"]
    @State private var selectedType = "course"
    @State private var durationStr = ""
    @State private var distanceStr = ""
    @State private var paceStr = ""
    @State private var hrStr = ""
    @State private var caloriesStr = ""
    @State private var rpeValue: Double = 6
    @State private var notes = ""
    @State private var isSaving = false
    @State private var apiError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(types, id: \.self) { t in
                                        Button(action: { selectedType = t }) {
                                            Text(t.capitalized)
                                                .font(.appLabel)
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(selectedType == t ? Color.statusCyan : Color.appSurfaceInset)
                                                .foregroundColor(selectedType == t ? .white : .gray)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            CardioField(label: "DURÉE (min)", placeholder: "30", text: $durationStr)
                            CardioField(label: "DISTANCE (km)", placeholder: "5.0", text: $distanceStr)
                            CardioField(label: "ALLURE (min/km)", placeholder: "5:30", text: $paceStr, keyboardType: .default)
                            CardioField(label: "FC MOY (bpm)", placeholder: "145", text: $hrStr)
                            CardioField(label: "CALORIES", placeholder: "350", text: $caloriesStr)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("RPE").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.0f / 10", rpeValue))
                                    .font(.appLabel.weight(.bold)).foregroundColor(Color.forge)
                            }
                            Slider(value: $rpeValue, in: 1...10, step: 0.5).tint(Color.forge)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                            TextField("Commentaire...", text: $notes, axis: .vertical)
                                .lineLimit(3, reservesSpace: true)
                                .foregroundColor(.appTextPrimary)
                                .padding(12)
                                .background(Color.appSurfaceInset)
                                .cornerRadius(10)
                        }

                        Button(action: save) {
                            Group {
                                if isSaving { ProgressView().tint(.white) }
                                else { Text("Enregistrer").font(.appBody.weight(.semibold)).foregroundColor(.white) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.statusCyan).cornerRadius(14)
                        .buttonStyle(SpringButtonStyle())
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Nouvelle séance cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await APIService.shared.logCardio(
                    type:        selectedType,
                    durationMin: Double(durationStr.replacingOccurrences(of: ",", with: ".")),
                    distanceKm:  Double(distanceStr.replacingOccurrences(of: ",", with: ".")),
                    avgPace:     paceStr.isEmpty ? nil : paceStr,
                    avgHr:       Double(hrStr),
                    cadence:     nil,
                    calories:    Double(caloriesStr.replacingOccurrences(of: ",", with: ".")),
                    rpe:         rpeValue,
                    notes:       notes
                )
                await onSaved()
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                apiError = "Erreur réseau — réessaie"
            }
        }
    }
}

struct CardioField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.appTextPrimary)
                .padding(10)
                .background(Color.appSurfaceInset)
                .cornerRadius(8)
        }
    }
}
