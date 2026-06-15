import SwiftUI
import MapKit

// MARK: - CardioCoachNote

struct CardioCoachNote {
    let message: String
    let isPersonalized: Bool
}

// MARK: - CardioSummaryView

struct CardioSummaryView: View {
    let session: CompletedCardioSession
    let onDismiss: () -> Void

    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var showCancelConfirm = false
    @State private var readiness: ReadinessResponse? = nil
    @State private var todayRecovery: RecoveryEntry? = nil
    @State private var recentCardioSessions: [CardioEntry] = []
    @State private var isLoadingRecovery = true
    @State private var coachNote: CardioCoachNote? = nil
    @State private var hkAvgHR: Double? = nil
    @State private var hkCalories: Double? = nil

    // MARK: - Computed helpers

    private var typeInfo: CardioType {
        cardioTypes.first { $0.id == session.type }
            ?? CardioType(id: session.type, label: session.type.capitalized, description: "", icon: "figure.run")
    }

    private var sessionDateStr: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEEE d MMMM · HH:mm"
        return df.string(from: session.startTime).capitalized
    }

    private var durationStr: String {
        let h = session.durationSeconds / 3600
        let m = (session.durationSeconds % 3600) / 60
        let s = session.durationSeconds % 60
        if h > 0 { return String(format: "%dh %02dmin", h, m) }
        return String(format: "%dmin %02ds", m, s)
    }

    private var paceStr: String {
        guard let pace = session.paceAvgSeconds, session.distanceKm >= 0.1 else { return "—" }
        return String(format: "%d:%02d /km", pace / 60, pace % 60)
    }

    private var speedStr: String {
        guard let pace = session.paceAvgSeconds, pace > 0 else { return "—" }
        return String(format: "%.1f km/h", 3600.0 / Double(pace))
    }

    private var maxPaceStr: String {
        guard session.maxPaceSecondsPerKm > 0 else { return "—" }
        return String(format: "%d:%02d /km", session.maxPaceSecondsPerKm / 60, session.maxPaceSecondsPerKm % 60)
    }

    private var splits: [(km: Int, paceSeconds: Int)] {
        guard session.distanceKm >= 1.0, session.gpsPoints.count >= 2 else { return [] }
        var result: [(km: Int, paceSeconds: Int)] = []
        var kmStart = 0.0
        var kmStartTime = session.gpsPoints[0].timestamp
        var cumDist = 0.0
        var km = 1

        for i in 1..<session.gpsPoints.count {
            let prev = session.gpsPoints[i - 1]
            let curr = session.gpsPoints[i]
            let segDist = CLLocation(latitude: prev.lat, longitude: prev.lng)
                .distance(from: CLLocation(latitude: curr.lat, longitude: curr.lng))
            let segTime = curr.timestamp - prev.timestamp
            cumDist += segDist

            while cumDist - kmStart >= 1000 {
                let overshot = (cumDist - kmStart) - 1000
                let frac = segDist > 0 ? 1.0 - (overshot / segDist) : 1.0
                let crossTime = prev.timestamp + segTime * frac
                result.append((km: km, paceSeconds: Int(crossTime - kmStartTime)))
                km += 1
                kmStart += 1000
                kmStartTime = crossTime
            }
        }
        return result
    }

    private var avgSplitSeconds: Int {
        guard !splits.isEmpty else { return session.paceAvgSeconds ?? 0 }
        return splits.map { $0.paceSeconds }.reduce(0, +) / splits.count
    }

    private var isVelo: Bool { session.type == "velo" || session.type == "vélo" }
    private var showMaxPace: Bool {
        (session.type == "hiit" || session.type == "tempo") && session.maxPaceSecondsPerKm > 0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackground(color: .teal).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerSection
                        .padding(.top, 32)
                    metricsSection
                    mapSection
                    splitsSection
                    hkSection
                    coachSection
                    actionButtons
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear { if readiness == nil { Task { await loadRecovery() } } }
        .confirmationDialog("Abandonner la séance ?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Abandonner sans sauvegarder", role: .destructive) {
                CardioSessionManager.shared.cancel()
                onDismiss()
            }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("La séance sera définitivement perdue.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: typeInfo.icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(.teal)
            Text(typeInfo.label)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.appTextPrimary)
            Text(sessionDateStr)
                .font(.appLabel.weight(.regular))
                .foregroundColor(.appOnSurface.opacity(0.5))
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryMetric(label: "DURÉE",    value: durationStr,                                    color: .white)
            SummaryMetric(label: "DISTANCE", value: String(format: "%.2f km", session.distanceKm), color: .teal)
            if isVelo {
                SummaryMetric(label: "VITESSE MOY", value: speedStr,  color: .statusBlue)
            } else {
                SummaryMetric(label: "ALLURE MOY",  value: paceStr,   color: .statusBlue)
            }
            if showMaxPace {
                SummaryMetric(label: "ALLURE MAX", value: maxPaceStr, color: Color.statusYellow)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Map

    @ViewBuilder private var mapSection: some View {
        if session.gpsPoints.count >= 2 {
            StaticRouteMapView(gpsPoints: session.gpsPoints)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
        } else if session.gpsPoints.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .foregroundColor(Color.forge)
                Text("Aucun point GPS — GPS non autorisé ou signal absent")
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(Color.forge)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Splits

    @ViewBuilder private var splitsSection: some View {
        if !splits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SPLITS")
                    .font(.appCaption.weight(.bold)).tracking(1.5)
                    .foregroundColor(.appOnSurface.opacity(0.4))
                    .padding(.horizontal, 16)

                VStack(spacing: 1) {
                    ForEach(0..<splits.count, id: \.self) { i in
                        splitRow(index: i)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
    }

    private func splitRow(index: Int) -> some View {
        let split = splits[index]
        let isFaster = split.paceSeconds < avgSplitSeconds
        let splitPace = String(format: "%d:%02d /km", split.paceSeconds / 60, split.paceSeconds % 60)

        return HStack {
            Text("Km \(split.km)")
                .font(.appLabel)
                .foregroundColor(.appOnSurface.opacity(0.7))
            Spacer()
            Text(splitPace)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(isFaster ? .statusGreen : .statusRed)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.appSurfaceInset)
    }

    // MARK: - HealthKit Section

    @ViewBuilder private var hkSection: some View {
        if hkAvgHR != nil || hkCalories != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("DONNÉES SANTÉ")
                    .font(.appCaption.weight(.bold)).tracking(1.5)
                    .foregroundColor(.appOnSurface.opacity(0.4))
                    .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let hr = hkAvgHR {
                        SummaryMetric(label: "FC MOY", value: "\(Int(hr)) bpm", color: .statusRed)
                    }
                    if let cal = hkCalories {
                        SummaryMetric(label: "CALORIES", value: "\(Int(cal)) kcal", color: Color.forge)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Coach Section

    @ViewBuilder private var coachSection: some View {
        if isLoadingRecovery {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.appTitle.weight(.regular))
                    .foregroundColor(.teal.opacity(0.5))
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.appSurfaceInset).frame(height: 11)
                    RoundedRectangle(cornerRadius: 4).fill(Color.appSurfaceInset).frame(width: 160, height: 11)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        } else if let note = coachNote {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.appBody)
                        .foregroundColor(.teal)
                    Text("CONSEIL COACH")
                        .font(.appCaption.weight(.bold)).tracking(1.5)
                        .foregroundColor(.teal)
                    Spacer()
                    if note.isPersonalized {
                        Text("Basé sur tes données")
                            .font(.appCaption)
                            .foregroundColor(.appOnSurface.opacity(0.35))
                    }
                }
                Text(note.message)
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.appOnSurface.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.teal.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.teal.opacity(0.2), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let err = saveError {
                Text(err)
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.statusRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.black).scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(isSaving ? "Sauvegarde…" : "Sauvegarder")
                        .font(.appHeadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.teal)
                .foregroundColor(.black)
                .cornerRadius(16)
            }
            .disabled(isSaving)
            .padding(.horizontal, 16)

            Button { showCancelConfirm = true } label: {
                Text("Annuler — ne pas sauvegarder")
                    .font(.appBody)
                    .foregroundColor(.appOnSurface.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appSurfaceInset, lineWidth: 1))
            }
            .disabled(isSaving)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Recovery fetch

    private func loadRecovery() async {
        isLoadingRecovery = true

        readiness = try? await APIService.shared.fetchReadiness()

        if let entries = try? await APIService.shared.fetchRecoveryData() {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let todayStr = df.string(from: Date())
            todayRecovery = entries.first { $0.date == todayStr }
        }

        recentCardioSessions = (try? await APIService.shared.fetchCardioData()) ?? []

        hkAvgHR = await HealthKitService.shared.fetchWorkoutHR(start: session.startTime, end: session.endTime)
        hkCalories = await HealthKitService.shared.fetchWorkoutCalories(start: session.startTime, end: session.endTime)

        isLoadingRecovery = false

        coachNote = CardioCoachService.generateNote(
            type:             session.type,
            distanceKm:       session.distanceKm,
            durationSeconds:  session.durationSeconds,
            paceAvgSeconds:   session.paceAvgSeconds,
            readinessScore:   readiness?.score,
            hrv:              todayRecovery?.hrv,
            soreness:         todayRecovery?.soreness,
            recentSessions:   recentCardioSessions,
            splits:           splits
        )
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            try await saveToAPI()
            await writeToHealthKit()
            CardioSessionManager.shared.didSave()
            onDismiss()
        } catch {
            saveError = "Erreur lors de la sauvegarde — réessaie"
        }
        isSaving = false
    }

    private func saveToAPI() async throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let durationMin = Double(session.durationSeconds) / 60.0
        var avgPace: String? = nil
        if let pace = session.paceAvgSeconds, session.distanceKm >= 0.1 {
            avgPace = String(format: "%d:%02d", pace / 60, pace % 60)
        }

        let gpsArray: [[String: Double]] = session.gpsPoints.map {
            ["lat": $0.lat, "lng": $0.lng, "timestamp": $0.timestamp]
        }

        try await APIService.shared.logCardio(
            type:           session.type,
            durationMin:    durationMin,
            distanceKm:     session.distanceKm > 0 ? session.distanceKm : nil,
            avgPace:        avgPace,
            avgHr:          nil,
            cadence:        nil,
            calories:       nil,
            rpe:            nil,
            notes:          session.gpsPoints.isEmpty ? "Session sans GPS" : "Tracking GPS",
            startTime:      iso.string(from: session.startTime),
            endTime:        iso.string(from: session.endTime),
            paceAvgSeconds: session.paceAvgSeconds,
            gpsPoints:      session.gpsPoints.isEmpty ? nil : gpsArray,
            coachNote:      coachNote?.message
        )
    }

    private func writeToHealthKit() async {
        await HealthKitService.shared.saveCardioWorkout(
            type:       session.type,
            startDate:  session.startTime,
            endDate:    session.endTime,
            distanceKm: session.distanceKm > 0 ? session.distanceKm : nil
        )
    }
}

// MARK: - Static Route Map

private struct StaticRouteMapView: View {
    let gpsPoints: [GPSPoint]
    @State private var snapshot: UIImage? = nil

    var body: some View {
        ZStack {
            if let img = snapshot {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.appSurfaceInset
                    .overlay(ProgressView().tint(.appOnSurface.opacity(0.5)))
            }
        }
        .onAppear { Task { await generate() } }
    }

    private func generate() async {
        guard gpsPoints.count >= 2 else { return }
        let coords = gpsPoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }

        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let latMin = lats.min(), let latMax = lats.max(),
              let lngMin = lngs.min(), let lngMax = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude:  (latMin + latMax) / 2,
            longitude: (lngMin + lngMax) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max((latMax - latMin) * 1.5, 0.002),
            longitudeDelta: max((lngMax - lngMin) * 1.5, 0.002)
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.mapType = .mutedStandard
        options.size = CGSize(width: UIScreen.main.bounds.width - 32, height: 200)
        options.scale = UIScreen.main.scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return }

        let pts = coords.map { snap.point(for: $0) }
        let renderer = UIGraphicsImageRenderer(size: snap.image.size)
        let img = renderer.image { _ in
            snap.image.draw(at: .zero)

            // Route polyline
            let routePath = UIBezierPath()
            routePath.move(to: pts[0])
            pts.dropFirst().forEach { routePath.addLine(to: $0) }
            UIColor.systemTeal.withAlphaComponent(0.9).setStroke()
            routePath.lineWidth = 3.5
            routePath.lineCapStyle = .round
            routePath.lineJoinStyle = .round
            routePath.stroke()

            // Start marker — green
            let startOval = UIBezierPath(ovalIn: CGRect(x: pts[0].x - 8, y: pts[0].y - 8, width: 16, height: 16))
            UIColor.systemGreen.setFill()
            UIColor.white.setStroke()
            startOval.lineWidth = 2
            startOval.fill()
            startOval.stroke()

            // End marker — red
            let endPt = pts[pts.count - 1]
            let endOval = UIBezierPath(ovalIn: CGRect(x: endPt.x - 8, y: endPt.y - 8, width: 16, height: 16))
            UIColor.systemRed.setFill()
            UIColor.white.setStroke()
            endOval.lineWidth = 2
            endOval.fill()
            endOval.stroke()
        }

        snapshot = img
    }
}

// MARK: - CardioCoachService

enum CardioCoachService {

    static func generateNote(
        type: String,
        distanceKm: Double,
        durationSeconds: Int,
        paceAvgSeconds: Int?,
        readinessScore: Int?,
        hrv: Double?,
        soreness: Double?,
        recentSessions: [CardioEntry],
        splits: [(km: Int, paceSeconds: Int)]
    ) -> CardioCoachNote {
        switch type {
        case "hiit":
            return hiit(duration: durationSeconds, readiness: readinessScore)
        case "tempo", "course":
            return tempo(readiness: readinessScore, splits: splits)
        case "endurance":
            return endurance(distanceKm: distanceKm, hrv: hrv, soreness: soreness, recent: recentSessions)
        case "leger", "marche":
            return leger(readiness: readinessScore, soreness: soreness)
        case "velo", "vélo":
            return velo(durationSeconds: durationSeconds, paceAvgSeconds: paceAvgSeconds, recent: recentSessions)
        default:
            return CardioCoachNote(
                message: "Session complète. N'oublie pas de t'hydrater et de récupérer selon l'intensité de ton effort.",
                isPersonalized: false
            )
        }
    }

    private static func hiit(duration: Int, readiness: Int?) -> CardioCoachNote {
        if let score = readiness, score < 50 {
            return CardioCoachNote(
                message: "Ton score de récupération était bas ce matin (\(score)/100). Surveille ton HRV demain avant le prochain HIIT.",
                isPersonalized: true
            )
        }
        if duration < 1200 {
            return CardioCoachNote(
                message: "Bonne session courte. Les sprints stimulent l'adaptation neuromusculaire. 48h de récup avant le prochain HIIT.",
                isPersonalized: false
            )
        }
        return CardioCoachNote(
            message: "Bonne session HIIT. Recharge en protéines dans les 30 min pour maximiser la récupération.",
            isPersonalized: false
        )
    }

    private static func tempo(readiness: Int?, splits: [(km: Int, paceSeconds: Int)]) -> CardioCoachNote {
        if splits.count >= 2 {
            let paces = splits.map { $0.paceSeconds }
            let avg = paces.reduce(0, +) / paces.count
            let minP = paces.min() ?? avg
            let maxP = paces.max() ?? avg
            let variation = avg > 0 ? Double(maxP - minP) / Double(avg) : 0
            if variation > 0.10 {
                let minStr = String(format: "%d:%02d", minP / 60, minP % 60)
                let maxStr = String(format: "%d:%02d", maxP / 60, maxP % 60)
                return CardioCoachNote(
                    message: "Ton pace a varié de \(minStr) à \(maxStr) min/km — vise plus de régularité au prochain tempo pour rester au seuil.",
                    isPersonalized: true
                )
            }
        }
        if let score = readiness, score > 70 {
            return CardioCoachNote(
                message: "Pace régulier sur une bonne récupération (\(score)/100). Conditions idéales pour progresser au seuil.",
                isPersonalized: true
            )
        }
        return CardioCoachNote(
            message: "Bonne session tempo. Hydrate-toi bien dans l'heure qui suit.",
            isPersonalized: false
        )
    }

    private static func endurance(distanceKm: Double, hrv: Double?, soreness: Double?, recent: [CardioEntry]) -> CardioCoachNote {
        let maxDist = maxDistance30Days(from: recent, types: ["endurance", "course"])
        if distanceKm > maxDist && distanceKm > 3.0 {
            return CardioCoachNote(
                message: "Nouveau record de distance — \(String(format: "%.1f", distanceKm)) km ! Recharge en glucides dans les 2h.",
                isPersonalized: true
            )
        }
        if let s = soreness, s > 6 {
            return CardioCoachNote(
                message: "Tu as couru malgré des courbatures (\(Int(s))/10). Le mouvement aide la récupération — bien dormir cette nuit.",
                isPersonalized: true
            )
        }
        if let h = hrv {
            return CardioCoachNote(
                message: "Belle sortie avec un HRV à \(Int(h)) ms ce matin. Dors bien pour consolider les gains.",
                isPersonalized: true
            )
        }
        return CardioCoachNote(
            message: "Bonne sortie d'endurance. Le cardio aérobie améliore ta capacité de récupération sur le long terme.",
            isPersonalized: false
        )
    }

    private static func leger(readiness: Int?, soreness: Double?) -> CardioCoachNote {
        if let score = readiness, score < 40 {
            return CardioCoachNote(
                message: "Bon choix vu ton score de récup ce matin (\(score)/100). Le mouvement doux accélère la récupération.",
                isPersonalized: true
            )
        }
        if let s = soreness, s > 5 {
            return CardioCoachNote(
                message: "Le jogging léger aide à éliminer les métabolites des séances précédentes. Parfait pour les courbatures.",
                isPersonalized: true
            )
        }
        return CardioCoachNote(
            message: "Récupération active — le mouvement léger maintient la circulation et prépare ta prochaine séance.",
            isPersonalized: false
        )
    }

    private static func velo(durationSeconds: Int, paceAvgSeconds: Int?, recent: [CardioEntry]) -> CardioCoachNote {
        let vitesseMoy = paceAvgSeconds.map { 3600.0 / Double($0) } ?? 0
        let last7Avg = avgSpeed7Days(from: recent)
        if last7Avg > 0 && vitesseMoy > last7Avg * 1.05 {
            return CardioCoachNote(
                message: "Meilleure vitesse moyenne de la semaine — \(String(format: "%.1f", vitesseMoy)) km/h. Continue sur cette lancée.",
                isPersonalized: true
            )
        }
        if durationSeconds > 3600 {
            return CardioCoachNote(
                message: "Sortie longue — recharge en glucides dans les 30 min pour reconstituer tes stocks.",
                isPersonalized: false
            )
        }
        return CardioCoachNote(
            message: "Bonne session vélo. Le cyclisme est doux pour les articulations — idéal les jours de récupération.",
            isPersonalized: false
        )
    }

    private static func maxDistance30Days(from sessions: [CardioEntry], types: [String]) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let todayStr = df.string(from: Date())
        return sessions
            .filter { s in
                guard let d = s.date, let date = df.date(from: d) else { return false }
                return d != todayStr && date >= cutoff && types.contains(s.type ?? "")
            }
            .compactMap { $0.distanceKm }
            .max() ?? 0
    }

    private static func avgSpeed7Days(from sessions: [CardioEntry]) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let speeds = sessions
            .filter { s in
                guard let d = s.date, let date = df.date(from: d) else { return false }
                let isVelo = s.type == "velo" || s.type == "vélo"
                return date >= cutoff && isVelo
            }
            .compactMap { s -> Double? in
                guard let pace = s.paceAvgSeconds, pace > 0 else { return nil }
                return 3600.0 / Double(pace)
            }
        guard !speeds.isEmpty else { return 0 }
        return speeds.reduce(0, +) / Double(speeds.count)
    }
}

// MARK: - Summary Metric Card

private struct SummaryMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.appCaption.weight(.bold)).tracking(1.5)
                .foregroundColor(.appOnSurface.opacity(0.4))
            Text(value)
                .font(.appTitle)
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(color: .white, intensity: 0.05, cornerRadius: 12)
    }
}
