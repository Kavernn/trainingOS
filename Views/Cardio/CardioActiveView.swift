import SwiftUI
import MapKit

// MARK: - CardioType model

struct CardioType: Identifiable {
    let id: String
    let label: String
    let description: String
    let icon: String
}

let cardioTypes: [CardioType] = [
    CardioType(id: "hiit",      label: "Intensité haute", description: "Intervalles, sprints, effort max",   icon: "bolt.fill"),
    CardioType(id: "tempo",     label: "Cardio intense",  description: "Course soutenue, effort difficile",  icon: "flame.fill"),
    CardioType(id: "endurance", label: "Endurance",       description: "Course longue, effort modéré",       icon: "heart.fill"),
    CardioType(id: "leger",     label: "Léger",           description: "Marche rapide, jogging léger",       icon: "figure.walk"),
    CardioType(id: "velo",      label: "Vélo",            description: "Route, montagne, stationnaire",      icon: "bicycle"),
    CardioType(id: "autre",     label: "Autre",           description: "Natation, ski, activité custom",     icon: "figure.run"),
]

// MARK: - CardioTypeSelectionSheet

struct CardioTypeSelectionSheet: View {
    @AppStorage("lastCardioType") private var lastCardioType: String = "endurance"
    @State private var selectedId: String = ""

    let onStart: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.appOnSurface.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text("Type d'effort")
                .font(.appTitle)
                .foregroundColor(.appTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(cardioTypes) { type in
                        CardioTypeCard(type: type, isSelected: selectedId == type.id) {
                            selectedId = type.id
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Button {
                lastCardioType = selectedId
                onStart(selectedId)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("Démarrer")
                        .font(.appHeadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(selectedId.isEmpty ? Color.statusCyan.opacity(0.3) : Color.statusCyan)
                .foregroundColor(selectedId.isEmpty ? Color.black.opacity(0.4) : .black)
                .cornerRadius(16)
            }
            .disabled(selectedId.isEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .onAppear { selectedId = lastCardioType }
    }
}

// MARK: - CardioTypeCard

private struct CardioTypeCard: View {
    let type: CardioType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isSelected ? Color.statusCyan : Color.appOnSurface.opacity(0.7))
                    .frame(height: 34)

                Text(type.label)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)

                Text(type.description)
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(isSelected ? 0.7 : 0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.statusCyan.opacity(0.15) : Color.appSurfaceInset)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.statusCyan : Color.appSurfaceInset, lineWidth: isSelected ? 1.5 : 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CardioActiveView

struct CardioActiveView: View {
    @ObservedObject private var session = CardioSessionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AmbientBackground(color: Color.statusCyan).ignoresSafeArea()

            switch session.sessionState {
            case .idle:
                CardioIdleView()
            case .active, .paused:
                ActiveLayout()
            case .completed:
                if let completed = session.completedSession {
                    CardioSummaryView(session: completed, onDismiss: {
                        session.reset()
                        dismiss()
                    })
                }
            }

            if session.sessionState == .idle {
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.appBody.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding(.leading, 20)
                        .padding(.top, 56)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        // FIX: empêche le swipe-down accidentel pendant une session active ou en pause
        .interactiveDismissDisabled(
            session.sessionState == .active || session.sessionState == .paused
        )
        .onAppear {
            if session.authorizationStatus == .notDetermined {
                session.requestAuthorization()
            }
        }
    }
}

// MARK: - Idle

private struct CardioIdleView: View {
    @ObservedObject private var session = CardioSessionManager.shared
    @State private var showTypeSheet = false

    var body: some View {
        VStack(spacing: 0) {

            IdleMapView()
                .frame(maxWidth: .infinity)
                .frame(height: UIScreen.main.bounds.height * 0.48)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            VStack(spacing: 16) {
                Text("Nouvelle séance")
                    .font(.appTitle)
                    .foregroundColor(.appTextPrimary)
                    .padding(.top, 20)

                if session.authorizationStatus == .denied || session.authorizationStatus == .restricted {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "location.slash.fill")
                                .foregroundColor(Color.forge)
                            Text("GPS non autorisé — le tracé ne sera pas enregistré")
                                .font(.appLabel.weight(.regular))
                                .foregroundColor(Color.forge)
                        }
                        Button("Ouvrir Réglages") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.teal)
                    }
                    .padding(.horizontal, 16)
                }

                Button {
                    showTypeSheet = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Démarrer")
                            .font(.appHeadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.statusCyan)
                    .foregroundColor(.black)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }

            Spacer()
        }
        .sheet(isPresented: $showTypeSheet) {
            CardioTypeSelectionSheet { type in
                showTypeSheet = false
                session.start(type: type)
            }
            .presentationDetents([.fraction(0.82)])
            .presentationCornerRadius(24)
            .presentationBackground(Color(red: 0.06, green: 0.10, blue: 0.12))
        }
    }
}

// MARK: - Idle Map (position courante, pas de route)

private struct IdleMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.userTrackingMode = .follow
        map.mapType = .mutedStandard
        map.overrideUserInterfaceStyle = .dark
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}
}

// MARK: - Active Layout

private struct ActiveLayout: View {
    @ObservedObject private var session = CardioSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showFinishConfirm = false

    var body: some View {
        VStack(spacing: 0) {

            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.appLabel.weight(.semibold))
                        Text("Réduire")
                            .font(.appLabel)
                    }
                    .foregroundColor(Color.appOnSurface.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.appSurfaceInset)
                    .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            MetricsBlock()

            // Map
            RouteMapView(
                routePoints: session.routePoints,
                currentLocation: session.currentLocation
            )
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.height * 0.38)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)

            Spacer()

            // Buttons
            HStack(spacing: 16) {
                Button {
                    if session.sessionState == .active {
                        session.pause()
                    } else {
                        session.resume()
                    }
                } label: {
                    HStack {
                        Image(systemName: session.sessionState == .active ? "pause.fill" : "play.fill")
                        Text(session.sessionState == .active ? "Pause" : "Reprendre")
                            .font(.appBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appSurfaceInset)
                    .foregroundColor(.appTextPrimary)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appOnSurface.opacity(0.2), lineWidth: 1))
                    .cornerRadius(14)
                }

                Button {
                    showFinishConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Terminer")
                            .font(.appBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.statusCyan)
                    .foregroundColor(.black)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .confirmationDialog("Terminer la séance ?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Terminer", role: .destructive) { session.finish() }
            Button("Annuler", role: .cancel) {}
        }
    }
}

// MARK: - Metrics Block (type-aware)

private struct MetricsBlock: View {
    @ObservedObject private var session = CardioSessionManager.shared

    private var chronoStr: String {
        let h = session.elapsedSeconds / 3600
        let m = (session.elapsedSeconds % 3600) / 60
        let s = session.elapsedSeconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private var distanceStr: String {
        String(format: "%.2f km", session.distanceKm)
    }

    private var speedStr: String {
        guard let pace = session.paceAvgSeconds, pace > 0 else { return "— km/h" }
        return String(format: "%.1f km/h", 3600.0 / Double(pace))
    }

    var body: some View {
        VStack(spacing: 4) {
            switch session.selectedType {
            case "hiit":
                hiitMetrics
            case "endurance":
                enduranceMetrics
            case "leger", "marche":
                legerMetrics
            case "velo", "vélo":
                veloMetrics
            case "autre":
                autreMetrics
            default: // tempo, course, et tout autre legacy
                tempoMetrics
            }

            if session.sessionState == .paused {
                Text("EN PAUSE")
                    .font(.appCaption.weight(.bold)).tracking(2)
                    .foregroundColor(Color.forge)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // HIIT : chrono large | pace actuel | distance | badge pace max
    @ViewBuilder private var hiitMetrics: some View {
        primaryText(chronoStr)
        secondaryText(session.paceString)
        tertiaryText(distanceStr)
        if session.maxPaceSecondsPerKm > 0 {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.appCaption.weight(.semibold))
                Text("Max : \(session.maxPaceString)")
                    .font(.appLabel.weight(.semibold))
            }
            .foregroundColor(Color.statusYellow.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.statusYellow.opacity(0.12))
            .clipShape(Capsule())
            .padding(.top, 2)
        }
    }

    // TEMPO / COURSE (default) : chrono large | pace moyen | distance
    @ViewBuilder private var tempoMetrics: some View {
        primaryText(chronoStr)
        secondaryText(session.paceString)
        tertiaryText(distanceStr)
    }

    // ENDURANCE : distance large | chrono | pace moyen
    @ViewBuilder private var enduranceMetrics: some View {
        primaryText(distanceStr)
        secondaryText(chronoStr, color: .white)
        tertiaryText(session.paceString)
    }

    // LÉGER : distance large | chrono | pace discret
    @ViewBuilder private var legerMetrics: some View {
        primaryText(distanceStr)
        secondaryText(chronoStr, color: .white)
        tertiaryText(session.paceString, opacity: 0.4)
    }

    // VÉLO : distance large | vitesse km/h | chrono
    @ViewBuilder private var veloMetrics: some View {
        primaryText(distanceStr)
        secondaryText(speedStr)
        tertiaryText(chronoStr)
    }

    // AUTRE : chrono large | distance
    @ViewBuilder private var autreMetrics: some View {
        primaryText(chronoStr)
        secondaryText(distanceStr, color: .white)
    }

    // MARK: Helpers

    private func primaryText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 72, weight: .black, design: .monospaced))
            .foregroundColor(.appTextPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
            .minimumScaleFactor(0.5)
    }

    private func secondaryText(_ value: String, color: Color = .teal) -> some View {
        Text(value)
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(color)
    }

    private func tertiaryText(_ value: String, opacity: Double = 0.6) -> some View {
        Text(value)
            .font(.appTitle.weight(.medium))
            .foregroundColor(Color.appOnSurface.opacity(opacity))
    }
}

// MARK: - Route Map

struct RouteMapView: UIViewRepresentable {
    let routePoints: [CLLocation]
    let currentLocation: CLLocation?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .follow
        map.mapType = .mutedStandard
        map.overrideUserInterfaceStyle = .dark
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)

        guard routePoints.count >= 2 else {
            if let loc = currentLocation ?? routePoints.last {
                let region = MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
                map.setRegion(region, animated: true)
            }
            return
        }

        let coords = routePoints.map { $0.coordinate }
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(polyline)

        if let last = routePoints.last {
            let region = MKCoordinateRegion(
                center: last.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            map.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.strokeColor = UIColor.systemTeal
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
