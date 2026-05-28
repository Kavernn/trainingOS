import SwiftUI
import MapKit

struct CardioSummaryView: View {
    let session: CompletedCardioSession
    let onDismiss: () -> Void

    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var showCancelConfirm = false

    private var hasGPSData: Bool { !session.gpsPoints.isEmpty }

    private var durationStr: String {
        let h = session.durationSeconds / 3600
        let m = (session.durationSeconds % 3600) / 60
        let s = session.durationSeconds % 60
        if h > 0 { return String(format: "%dh %02dmin", h, m) }
        return String(format: "%dmin %02ds", m, s)
    }

    private var paceStr: String {
        guard let pace = session.paceAvgSeconds, session.distanceKm >= 0.1 else { return "—/km" }
        let mins = pace / 60
        let secs = pace % 60
        return String(format: "%d:%02d /km", mins, secs)
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: .teal).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: typeIcon(session.type))
                            .font(.system(size: 36))
                            .foregroundColor(.teal)
                        Text("Séance terminée")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text(session.type.capitalized)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 32)

                    // Metrics grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        SummaryMetric(label: "DURÉE",    value: durationStr,                                      color: .white)
                        SummaryMetric(label: "DISTANCE", value: String(format: "%.2f km", session.distanceKm),   color: .teal)
                        SummaryMetric(label: "ALLURE",   value: paceStr,                                          color: .blue)
                        SummaryMetric(label: "POINTS GPS", value: hasGPSData ? "\(session.gpsPoints.count)" : "—", color: hasGPSData ? .white.opacity(0.6) : .orange)
                    }
                    .padding(.horizontal, 16)

                    // Avertissement si aucun point GPS
                    if !hasGPSData {
                        HStack(spacing: 8) {
                            Image(systemName: "location.slash.fill")
                                .foregroundColor(.orange)
                            Text("Aucun point GPS — GPS non autorisé ou signal absent")
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 16)
                    }

                    // Map with full route
                    if session.gpsPoints.count >= 2 {
                        let locations = session.gpsPoints.map { CLLocation(latitude: $0.lat, longitude: $0.lng) }
                        RouteMapView(routePoints: locations, currentLocation: nil)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 16)
                    }

                    // Save / Cancel
                    VStack(spacing: 12) {
                        if let err = saveError {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView().tint(.black).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text(isSaving ? "Sauvegarde…" : "Sauvegarder")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.teal)
                            .foregroundColor(.black)
                            .cornerRadius(16)
                        }
                        .disabled(isSaving)

                        // FIX: confirmation avant d'annuler pour éviter perte accidentelle
                        Button {
                            showCancelConfirm = true
                        } label: {
                            Text("Annuler — ne pas sauvegarder")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
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
            let mins = pace / 60
            let secs = pace % 60
            avgPace = String(format: "%d:%02d", mins, secs)
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
            notes:          hasGPSData ? "Tracking GPS" : "Session sans GPS",
            startTime:      iso.string(from: session.startTime),
            endTime:        iso.string(from: session.endTime),
            paceAvgSeconds: session.paceAvgSeconds,
            gpsPoints:      hasGPSData ? gpsArray : nil
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

    private func typeIcon(_ type: String) -> String {
        switch type {
        case "course": return "figure.run"
        case "vélo":   return "figure.outdoor.cycle"
        case "marche": return "figure.walk"
        default:       return "figure.mixed.cardio"
        }
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
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(color: .white, intensity: 0.05, cornerRadius: 12)
    }
}
