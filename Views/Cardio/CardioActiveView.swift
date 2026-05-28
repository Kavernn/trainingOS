import SwiftUI
import MapKit

// MARK: - CardioActiveView

struct CardioActiveView: View {
    @ObservedObject private var session = CardioSessionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        }
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
    @State private var selectedType = "course"

    private let types: [(String, String, String)] = [
        ("course",    "figure.run",     "Course"),
        ("vélo",      "figure.outdoor.cycle", "Vélo"),
        ("marche",    "figure.walk",    "Marche"),
        ("autre",     "figure.mixed.cardio", "Autre"),
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Nouvelle séance")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            // Type selector
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(types, id: \.0) { type in
                    let isSelected = selectedType == type.0
                    Button {
                        selectedType = type.0
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.1)
                                .font(.system(size: 28))
                            Text(type.2)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(isSelected ? Color.teal.opacity(0.25) : Color.white.opacity(0.06))
                        .foregroundColor(isSelected ? .teal : .white.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? Color.teal : Color.white.opacity(0.1), lineWidth: 1.5)
                        )
                        .cornerRadius(14)
                    }
                }
            }
            .padding(.horizontal, 24)

            // GPS permission warning
            if session.authorizationStatus == .denied || session.authorizationStatus == .restricted {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundColor(.orange)
                    Text("GPS non autorisé — active dans Réglages")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 24)
            }

            Button {
                session.start(type: selectedType)
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Démarrer")
                        .font(.system(size: 18, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.teal)
                .foregroundColor(.black)
                .cornerRadius(16)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

// MARK: - Active Layout

private struct ActiveLayout: View {
    @ObservedObject private var session = CardioSessionManager.shared
    @State private var showFinishConfirm = false

    var body: some View {
        VStack(spacing: 0) {

            // Metrics block
            VStack(spacing: 4) {
                // Chrono
                let h = session.elapsedSeconds / 3600
                let m = (session.elapsedSeconds % 3600) / 60
                let s = session.elapsedSeconds % 60
                let chronoStr = h > 0
                    ? String(format: "%d:%02d:%02d", h, m, s)
                    : String(format: "%02d:%02d", m, s)

                Text(chronoStr)
                    .font(.system(size: 72, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(String(format: "%.2f km", session.distanceKm))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.teal)

                Text(session.paceString)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                if session.sessionState == .paused {
                    Text("EN PAUSE")
                        .font(.system(size: 11, weight: .bold)).tracking(2)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

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
                // Pause / Resume
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
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .cornerRadius(14)
                }

                // Terminate
                Button {
                    showFinishConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Terminer")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.teal)
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
        // Remove old overlays
        map.removeOverlays(map.overlays)

        guard routePoints.count >= 2 else {
            // Center on current location when no route yet
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

        // Center on last point
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
