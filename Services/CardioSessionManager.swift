import Foundation
import CoreLocation
import Combine
import OSLog

// MARK: - GPS Point

struct GPSPoint: Codable {
    let lat: Double
    let lng: Double
    let timestamp: Double  // Unix timestamp

    var clLocation: CLLocation {
        CLLocation(latitude: lat, longitude: lng)
    }
}

// MARK: - Session State

enum CardioSessionState: String {
    case idle, active, paused, completed
}

// MARK: - Completed Session Data

struct CompletedCardioSession {
    let type: String
    let startTime: Date
    let endTime: Date
    let durationSeconds: Int
    let distanceKm: Double
    let paceAvgSeconds: Int?
    let maxPaceSecondsPerKm: Int
    let gpsPoints: [GPSPoint]
}

// MARK: - CardioSessionManager

final class CardioSessionManager: NSObject, ObservableObject {

    static let shared = CardioSessionManager()
    private let logger = Logger(subsystem: "TrainingOS", category: "cardio_session")

    // Published state
    @Published var sessionState: CardioSessionState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var distanceKm: Double = 0.0
    @Published var currentLocation: CLLocation?
    @Published var routePoints: [CLLocation] = []
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var completedSession: CompletedCardioSession?

    // Session metadata
    @Published var selectedType: String = "course"

    // Fastest pace seen this session (lowest seconds/km = fastest)
    @Published var maxPaceSecondsPerKm: Int = 0

    // Computed pace — nil if distance < 0.1km
    var paceString: String {
        guard distanceKm >= 0.1 else { return "—/km" }
        let secsPerKm = Double(elapsedSeconds) / distanceKm
        let mins = Int(secsPerKm) / 60
        let secs = Int(secsPerKm) % 60
        return String(format: "%d:%02d /km", mins, secs)
    }

    var paceAvgSeconds: Int? {
        guard distanceKm >= 0.1 else { return nil }
        return Int(Double(elapsedSeconds) / distanceKm)
    }

    var maxPaceString: String {
        guard maxPaceSecondsPerKm > 0 else { return "—" }
        let mins = maxPaceSecondsPerKm / 60
        let secs = maxPaceSecondsPerKm % 60
        return String(format: "%d:%02d /km", mins, secs)
    }

    // Internal
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var accumulatedGPSPoints: [GPSPoint] = []
    private var startTime: Date?
    private var pausedElapsed: Int = 0  // seconds accumulated before current pause

    // UserDefaults keys for background persistence
    private enum UDKey {
        static let isActive     = "cardio_session_active"
        static let startTime    = "cardio_session_start_time"
        static let pausedElapsed = "cardio_session_paused_elapsed"
        static let gpsPoints    = "cardio_session_gps_points"
        static let sessionType  = "cardio_session_type"
        static let state        = "cardio_session_state"
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        authorizationStatus = locationManager.authorizationStatus
        recoverSessionIfNeeded()
    }

    // MARK: - Public API

    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func start(type: String) {
        guard sessionState == .idle else { return }
        selectedType = type
        startTime = Date()
        pausedElapsed = 0
        accumulatedGPSPoints = []
        routePoints = []
        distanceKm = 0.0
        elapsedSeconds = 0

        persistSession()
        sessionState = .active
        startLocationUpdates()
        startTimer()
    }

    func pause() {
        guard sessionState == .active else { return }
        pausedElapsed = elapsedSeconds
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        sessionState = .paused
        persistSession()
    }

    func resume() {
        guard sessionState == .paused else { return }
        // Adjust startTime so elapsed continues from where we left off
        startTime = Date().addingTimeInterval(-Double(pausedElapsed))
        persistSession()
        sessionState = .active
        startLocationUpdates()
        startTimer()
    }

    func finish() {
        guard sessionState == .active || sessionState == .paused else { return }
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()

        let endTime = Date()
        let duration = elapsedSeconds
        completedSession = CompletedCardioSession(
            type: selectedType,
            startTime: startTime ?? endTime.addingTimeInterval(-Double(duration)),
            endTime: endTime,
            durationSeconds: duration,
            distanceKm: distanceKm,
            paceAvgSeconds: paceAvgSeconds,
            maxPaceSecondsPerKm: maxPaceSecondsPerKm,
            gpsPoints: accumulatedGPSPoints
        )
        sessionState = .completed
    }

    func cancel() {
        clearPersistedSession()
        reset()
    }

    func didSave() {
        clearPersistedSession()
        reset()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        startTime = nil
        pausedElapsed = 0
        accumulatedGPSPoints = []
        routePoints = []
        distanceKm = 0.0
        elapsedSeconds = 0
        maxPaceSecondsPerKm = 0
        completedSession = nil
        sessionState = .idle
    }

    // MARK: - Private helpers

    private func startLocationUpdates() {
        locationManager.startUpdatingLocation()
        // Allow background location delivery
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    private func startTimer() {
        let base = startTime ?? Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds = self.pausedElapsed + Int(Date().timeIntervalSince(base))
        }
        guard let t = timer else { return }
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: - Max Pace

    private func updateMaxPace() {
        guard accumulatedGPSPoints.count >= 2 else { return }
        let last = accumulatedGPSPoints[accumulatedGPSPoints.count - 1]
        let prev = accumulatedGPSPoints[accumulatedGPSPoints.count - 2]
        let timeDelta = last.timestamp - prev.timestamp
        let distDelta = last.clLocation.distance(from: prev.clLocation) / 1000.0
        guard timeDelta > 0.5, distDelta > 0.002 else { return }
        let segPace = Int(timeDelta / distDelta)
        // Filtre GPS glitch : < 60s/km serait > 60 km/h (impossible à pied ou en vélo normal)
        guard segPace >= 60 else { return }
        if maxPaceSecondsPerKm == 0 || segPace < maxPaceSecondsPerKm {
            maxPaceSecondsPerKm = segPace
        }
    }

    // MARK: - Persistence

    private func persistSession() {
        let ud = UserDefaults.standard
        ud.set(true,              forKey: UDKey.isActive)
        ud.set(startTime,         forKey: UDKey.startTime)
        ud.set(pausedElapsed,     forKey: UDKey.pausedElapsed)
        ud.set(selectedType,      forKey: UDKey.sessionType)
        ud.set(sessionState.rawValue, forKey: UDKey.state)

        do {
            ud.set(try JSONEncoder().encode(accumulatedGPSPoints), forKey: UDKey.gpsPoints)
        } catch {
            logger.error("CardioSession GPS persist failed: \(error)")
        }
    }

    private func persistGPSPoints() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(accumulatedGPSPoints), forKey: UDKey.gpsPoints)
        } catch {
            logger.error("CardioSession GPS points persist failed: \(error)")
        }
    }

    private func clearPersistedSession() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: UDKey.isActive)
        ud.removeObject(forKey: UDKey.startTime)
        ud.removeObject(forKey: UDKey.pausedElapsed)
        ud.removeObject(forKey: UDKey.gpsPoints)
        ud.removeObject(forKey: UDKey.sessionType)
        ud.removeObject(forKey: UDKey.state)
    }

    private func recoverSessionIfNeeded() {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: UDKey.isActive),
              let savedStart = ud.object(forKey: UDKey.startTime) as? Date,
              let savedState = ud.string(forKey: UDKey.state),
              let state = CardioSessionState(rawValue: savedState),
              state == .active || state == .paused
        else { return }

        selectedType = ud.string(forKey: UDKey.sessionType) ?? "course"
        pausedElapsed = ud.integer(forKey: UDKey.pausedElapsed)
        startTime = savedStart

        if let data = ud.data(forKey: UDKey.gpsPoints),
           let points = try? JSONDecoder().decode([GPSPoint].self, from: data) {
            accumulatedGPSPoints = points
            routePoints = points.map { $0.clLocation }
            distanceKm = computeDistance(from: routePoints)
        }

        if state == .active {
            elapsedSeconds = pausedElapsed + Int(Date().timeIntervalSince(savedStart))
            sessionState = .active
            startLocationUpdates()
            startTimer()
        } else {
            elapsedSeconds = pausedElapsed
            sessionState = .paused
        }
    }

    private func computeDistance(from locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<locations.count {
            total += locations[i].distance(from: locations[i - 1])
        }
        return total / 1000.0
    }
}

// MARK: - CLLocationManagerDelegate

extension CardioSessionManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let point = GPSPoint(lat: loc.coordinate.latitude,
                             lng: loc.coordinate.longitude,
                             timestamp: loc.timestamp.timeIntervalSince1970)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionState == .active else { return }
            self.currentLocation = loc
            self.accumulatedGPSPoints.append(point)
            self.routePoints.append(loc)
            self.distanceKm = self.computeDistance(from: self.routePoints)
            self.updateMaxPace()
            self.persistGPSPoints()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {}
}
