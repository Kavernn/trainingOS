import Foundation

struct ComebackArcData: Codable {
    let hasData: Bool
    let inComeback: Bool
    let ruptureStart: String?
    let ruptureEnd: String?
    let ruptureLength: Int?
    let daysSinceRupture: Int?
    let activeDays: Int?
    let activeSincePct: Int?
    let message: String

    var arcColor: String {
        guard let pct = activeSincePct else { return "8E8E93" }
        if pct >= 80 { return "34C759" }
        if pct >= 50 { return "FF9500" }
        return "FF6B6B"
    }

    var arcLabel: String {
        guard let pct = activeSincePct else { return "—" }
        if pct >= 80 { return "Solide" }
        if pct >= 50 { return "En cours" }
        return "Fragile"
    }
}
