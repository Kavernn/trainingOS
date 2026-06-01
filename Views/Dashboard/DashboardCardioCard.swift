import SwiftUI

struct DashboardCardioCard: View {
    let entry: CardioEntry

    private var accentColor: Color {
        switch entry.type {
        case "course": return .teal
        case "vélo":   return .cyan
        case "marche": return .green
        default:       return .blue
        }
    }

    private var icon: String {
        switch entry.type {
        case "course": return "figure.run"
        case "vélo":   return "figure.outdoor.cycle"
        case "marche": return "figure.walk"
        default:       return "figure.mixed.cardio"
        }
    }

    private var typeLabel: String {
        (entry.type ?? "cardio").capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARDIO")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray.opacity(0.7))
                    Text(typeLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(accentColor)
                }
                Spacer()
                HStack(spacing: 4) {
                    PulsingDot(color: accentColor)
                    Text("Complété")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 16)

            // Metrics row
            HStack(spacing: 0) {
                if let dur = entry.durationMin {
                    MetricCell(
                        title: "Durée",
                        value: dur >= 60
                            ? String(format: "%dh%02d", Int(dur) / 60, Int(dur) % 60)
                            : String(format: "%.0f min", dur),
                        tint: accentColor,
                        size: .medium
                    )
                    .frame(minWidth: 56)
                }
                if let dist = entry.distanceKm, dist > 0 {
                    MetricCell(
                        title: "Distance",
                        value: String(format: "%.2f km", dist),
                        tint: accentColor,
                        size: .medium
                    )
                    .frame(minWidth: 56)
                }
                if let pace = entry.avgPace {
                    MetricCell(title: "Allure", value: pace + "/km", tint: .white.opacity(0.7), size: .medium)
                        .frame(minWidth: 56)
                }
                if let hr = entry.avgHr, hr > 0 {
                    MetricCell(
                        title: "FC moy",
                        value: String(format: "%.0f bpm", hr),
                        tint: .red.opacity(0.8),
                        size: .medium
                    )
                    .frame(minWidth: 56)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // GPS badge si tracé enregistré
            if let points = entry.gpsPoints, !points.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                        .foregroundColor(accentColor.opacity(0.7))
                    Text("Tracé GPS — \(points.count) points")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .glassCardAccent(accentColor)
    }
}

