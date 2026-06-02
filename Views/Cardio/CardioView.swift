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
                AmbientBackground(color: .teal)
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
                                KPICard(value: "\(totalSessions)", label: "Sessions", color: .teal)
                                KPICard(value: String(format: "%.1f km", totalDistanceKm), label: "Distance tot.", color: .blue)
                                KPICard(value: totalDurationMin > 0 ? String(format: "%.0f min", totalDurationMin) : "—",
                                        label: "Durée tot.", color: .orange)
                                KPICard(value: avgRpe > 0 ? String(format: "%.1f", avgRpe) : "—",
                                        label: "RPE moy.", color: .red)
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
                                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
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
                            Image(systemName: "location.fill").font(.system(size: 13))
                            Text("GPS").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(sessionManager.sessionState != .idle ? .red : .teal)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: importFromHealthKit) {
                        HStack(spacing: 4) {
                            if isImportingHK {
                                ProgressView().tint(.orange).scaleEffect(0.7)
                            } else {
                                Image(systemName: "heart.text.square").font(.system(size: 14))
                            }
                            Text("Santé").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.orange)
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
        metrics   = try? await APIService.shared.fetchCardioMetrics(maxHR: maxHR)
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
                let entry = hk.workoutToCardioEntry(w)
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
                    Image(systemName: "play.circle.fill").font(.system(size: 20))
                    Text("Démarrer une session GPS").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Color.teal)
                .cornerRadius(14)
            }
            .buttonStyle(SpringButtonStyle())

            HStack(spacing: 16) {
                if let last = lastSession {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 11)).foregroundColor(.gray)
                        Text("Dernière : \(last.type?.capitalized ?? "—")\(last.distanceKm.map { String(format: " %.1f km", $0) } ?? "")")
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                }
                Spacer()
                if monthDistanceKm > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 11)).foregroundColor(.teal.opacity(0.7))
                        Text(String(format: "%.1f km ce mois", monthDistanceKm))
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.teal.opacity(0.8))
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
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("Session en cours — Tap pour reprendre")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guides Section
struct CardioGuidesSection: View {
    let metrics: CardioMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INTELLIGENCE CARDIO")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            // VO2max
            CardioMetricCard(
                icon: "lungs.fill",
                color: vo2maxColor,
                title: "VO2max estimé",
                value: metrics.vo2maxEstimated.map { String(format: "%.1f mL/kg/min", $0) } ?? "—",
                badge: metrics.vo2maxCategory,
                guide: metrics.guides?.vo2max ?? "",
                methodology: "Formule Jack Daniels VDOT depuis pace + distance réels. Moyenne des estimations sur 30 jours (min. 3 sessions). Types pris en compte : course, tempo, endurance, léger. Catégories : < 36 Faible · 36-43 Moyen · 43-50 Bon · 50-56 Excellent · 56+ Élite."
            )

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
                    color: .orange,
                    title: "Seuil lactique estimé",
                    value: threshold + " /km",
                    badge: nil,
                    guide: metrics.guides?.threshold ?? "",
                    methodology: "Estimé à best_pace + 20s/km. Pour une mesure précise : cours 30 min à l'allure maximale que tu peux soutenir — la moyenne de ce pace correspond à ton seuil lactique réel."
                )
            }
        }
    }

    var vo2maxColor: Color {
        guard let v = metrics.vo2maxEstimated else { return .gray }
        if v >= 50 { return .green }
        if v >= 40 { return .teal }
        return .orange
    }

    func acwrColor(_ zone: String) -> Color {
        switch zone {
        case "optimal":  return .green
        case "under":    return .blue
        case "over":     return .orange
        case "critical": return .red
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
                Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
                Spacer()
                if let b = badge {
                    Text(b)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color.opacity(0.15))
                        .foregroundColor(color)
                        .cornerRadius(6)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))
            }
            Text(value)
                .font(.system(size: 26, weight: .bold)).foregroundColor(.white)
            if !guide.isEmpty {
                Text(guide)
                    .font(.system(size: 12)).foregroundColor(.secondary)
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
                                Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
                                if let b = badge {
                                    Text(b)
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(8)
                                }
                            }
                            Text(value)
                                .font(.system(size: 40, weight: .heavy)).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(color.opacity(0.07)).cornerRadius(16)

                        // Conseil
                        if !guide.isEmpty {
                            metricSection(title: "CONSEIL", icon: "lightbulb.fill", iconColor: .yellow, content: guide)
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
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(iconColor)
                Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
            }
            Text(content)
                .font(.system(size: 14)).foregroundColor(.white).lineSpacing(3)
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
    private let zoneColors: [Color] = [.blue, .green, .yellow, .orange, .red]

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
                Image(systemName: "heart.fill").font(.system(size: 14)).foregroundColor(.pink)
                Text("ZONES FC — FCmax \(zones.maxHr) bpm")
                    .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
                Spacer()
                Text(hrSourceLabel)
                    .font(.system(size: 9)).foregroundColor(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))
            }
            VStack(spacing: 4) {
                ForEach(zoneRanges, id: \.0) { name, color, range in
                    HStack {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(name).font(.system(size: 11)).foregroundColor(.gray).frame(width: 80, alignment: .leading)
                        Spacer()
                        Text(range).font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                    }
                }
            }
            if !guide.isEmpty {
                Text(guide)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.pink.opacity(0.12), lineWidth: 1))
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            CardioMetricDetailSheet(
                icon: "heart.fill", color: .pink,
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
            ("Easy",      .blue,   paceZones.easy),
            ("Moderate",  .green,  paceZones.moderate),
            ("Tempo",     .yellow, paceZones.tempo),
            ("Threshold", .orange, paceZones.threshold),
            ("Race",      .red,    paceZones.race),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "speedometer").font(.system(size: 14)).foregroundColor(.blue)
                Text("PACE ZONES")
                    .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
            }
            VStack(spacing: 4) {
                ForEach(rows, id: \.0) { name, color, range in
                    HStack {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(name).font(.system(size: 11)).foregroundColor(.gray).frame(width: 70, alignment: .leading)
                        Spacer()
                        Text(range + " /km").font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                    }
                }
            }
            if !guide.isEmpty {
                Text(guide)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.12), lineWidth: 1))
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
                    Button("Fermer") { dismiss() }.foregroundColor(.teal)
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
                Image(systemName: cardioIcon(e.type)).font(.system(size: 22)).foregroundColor(cardioColor(e.type))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.type?.capitalized ?? "Séance").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                Text(e.date ?? "—").font(.system(size: 13)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(16).background(Color.appCard).cornerRadius(14)

        // Métriques
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let v = e.distanceKm   { DetailKPI(label: "Distance",   value: String(format: "%.2f km", v),      color: .teal) }
            if let v = e.durationMin  { DetailKPI(label: "Durée",      value: String(format: "%.0f min", v),     color: .blue) }
            if let v = e.avgPace      { DetailKPI(label: "Allure",     value: v + " /km",                        color: .green) }
            if let v = e.avgHr        { DetailKPI(label: "FC moyenne", value: String(format: "%.0f bpm", v),     color: .red) }
            if let v = e.calories     { DetailKPI(label: "Calories",   value: String(format: "%.0f kcal", v),    color: .orange) }
            if let v = e.cadence      { DetailKPI(label: "Cadence",    value: String(format: "%.0f spm", v),     color: .purple) }
            if let v = e.rpe          { DetailKPI(label: "RPE",        value: String(format: "%.1f / 10", v),    color: .red) }
        }

        // GPS indicator
        if e.gpsPoints?.isEmpty == false {
            HStack(spacing: 8) {
                Image(systemName: "location.fill").foregroundColor(.teal).font(.system(size: 13))
                Text("Session GPS enregistrée — \(e.gpsPoints?.count ?? 0) points")
                    .font(.system(size: 13)).foregroundColor(.secondary)
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
                RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.15)).frame(width: 52, height: 52)
                Text("HIIT").font(.system(size: 10, weight: .black)).foregroundColor(.red)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.sessionType ?? "HIIT").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                Text(e.date ?? "—").font(.system(size: 13)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(16).background(Color.appCard).cornerRadius(14)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let v = e.rounds   { DetailKPI(label: "Rounds",    value: "\(v)",               color: .red) }
            if let v = e.workTime { DetailKPI(label: "Work",      value: "\(v)s",              color: .orange) }
            if let v = e.restTime { DetailKPI(label: "Repos",     value: "\(v)s",              color: .green) }
            if let v = e.rpe      { DetailKPI(label: "RPE",       value: String(format: "%.1f / 10", v), color: .red) }
        }

        if let notes = e.notes, !notes.isEmpty {
            detailSection(title: "NOTES", content: notes)
        }
    }

    @ViewBuilder
    func detailSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
            Text(content).font(.system(size: 14)).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Color.appCard).cornerRadius(12)
    }

    func cardioColor(_ type: String?) -> Color {
        switch type {
        case "course": return .teal;    case "vélo":      return .yellow
        case "natation": return .blue;  case "marche":    return .green
        case "elliptique": return .purple
        default: return .orange
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
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.gray)
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
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 42, height: 42)
                Text("HIIT")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.sessionType ?? "HIIT")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(entry.date ?? "")
                    .font(.system(size: 11)).foregroundColor(.gray)
                hiitDetails
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let rpe = entry.rpe {
                    Text(String(format: "RPE %.1f", rpe))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                }
            }

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.08), lineWidth: 1))
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
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        if let notes = entry.notes, !notes.isEmpty {
            Text(notes)
                .font(.system(size: 11)).foregroundColor(.secondary)
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
        ("Z1 Récup.",   0.50, 0.60, .blue),
        ("Z2 Aérobie",  0.60, 0.70, .green),
        ("Z3 Seuil",    0.70, 0.80, .yellow),
        ("Z4 Anaéro.", 0.80, 0.90, .orange),
        ("Z5 VO2max",  0.90, 1.00, .red)
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
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Button("FCmax \(maxHR)") {
                    maxHRStr = "\(maxHR)"
                    showMaxHRInput = true
                }
                .font(.system(size: 11)).foregroundColor(.teal)
            }
            VStack(spacing: 5) {
                ForEach(zones.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text(zones[i].name)
                            .font(.system(size: 11)).foregroundColor(.gray).frame(width: 80, alignment: .leading)
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
                            .font(.system(size: 10, weight: .bold)).foregroundColor(zones[i].color)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            Text("Basé sur \(hrValues.count) session(s) avec FC")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(14).glassCard().cornerRadius(14)
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
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).foregroundColor(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("PROGRESSION — \(type.uppercased())")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                Text(msg)
                    .font(.system(size: 13)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(12).background(Color.teal.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.2), lineWidth: 1))
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(typeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(typeLabel)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(entry.date ?? "")
                    .font(.system(size: 11)).foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let d = entry.distanceKm {
                    Text(String(format: "%.2f km", d))
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.teal)
                }
                HStack(spacing: 6) {
                    if let dur = entry.durationMin {
                        Label(String(format: "%.0f min", dur), systemImage: "clock")
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }
                    if let pace = entry.avgPace {
                        Label(pace + "/km", systemImage: "speedometer")
                            .font(.system(size: 11)).foregroundColor(.blue)
                    }
                }
                HStack(spacing: 6) {
                    if let cad = entry.cadence {
                        Label(String(format: "%.0f spm", cad), systemImage: "metronome")
                            .font(.system(size: 11)).foregroundColor(.orange)
                    }
                    if let cal = entry.calories {
                        Label(String(format: "%.0f kcal", cal), systemImage: "flame.fill")
                            .font(.system(size: 11)).foregroundColor(.red)
                    }
                }
            }

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red.opacity(0.8))
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
        case "course":    return .teal
        case "vélo":      return .yellow
        case "natation":  return .blue
        case "marche":    return .green
        case "elliptique":return .purple
        default:          return .orange
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
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let dist = e.distanceKm ?? 0
                    let pct = maxDist > 0 ? dist / maxDist : 0
                    let isLast = i == entries.count - 1
                    VStack(spacing: 2) {
                        if dist > 0 {
                            Text(String(format: "%.1f", dist))
                                .font(.system(size: 7)).foregroundColor(.teal.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? Color.teal : Color.teal.opacity(0.4))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
        }
        .padding(16).glassCard(color: .teal, intensity: 0.05).cornerRadius(14)
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
                            Text("TYPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(types, id: \.self) { t in
                                        Button(action: { selectedType = t }) {
                                            Text(t.capitalized)
                                                .font(.system(size: 13, weight: .medium))
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(selectedType == t ? Color.teal : Color(hex: "191926"))
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
                                Text("RPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.0f / 10", rpeValue))
                                    .font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
                            }
                            Slider(value: $rpeValue, in: 1...10, step: 0.5).tint(.orange)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Commentaire...", text: $notes, axis: .vertical)
                                .lineLimit(3, reservesSpace: true)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }

                        Button(action: save) {
                            Group {
                                if isSaving { ProgressView().tint(.white) }
                                else { Text("Enregistrer").font(.system(size: 15, weight: .semibold)).foregroundColor(.white) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.teal).cornerRadius(14)
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
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
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
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.white)
                .padding(10)
                .background(Color(hex: "191926"))
                .cornerRadius(8)
        }
    }
}
