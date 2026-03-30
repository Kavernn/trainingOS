import Foundation

struct ProactiveAlert: Identifiable, Codable, Equatable {
    let id: String
    let type: String
    let severity: String   // "info" | "warning"
    let title: String
    let message: String
    let action: String     // "open_nutrition" | "open_dashboard"
}

struct ProactiveAlertsResponse: Codable {
    let alerts: [ProactiveAlert]
}
