import SwiftUI

struct RecoveryPerformanceBanner: View {
    let dashboard: DashboardData?
    let hrvAnalysis: HRVAnalysis?
    let recoveryScore: Double?
    var onTap: (() -> Void)? = nil

    private enum BannerState {
        case rest
        case hrvCritical
        case low(Double)
        case moderate
        case good(Double)
    }

    private var bannerState: BannerState? {
        guard let dash = dashboard else { return nil }
        let t = dash.today.lowercased()
        let isRest = t.isEmpty || t == "repos" || t == "rest"
        if isRest { return .rest }

        if let hrv = hrvAnalysis, hrv.baselineAvailable, hrv.hrvZone == "red" {
            return .hrvCritical
        }

        guard let score = recoveryScore else { return nil }
        if score < 40.0  { return .low(score) }
        if score <= 65.0 { return .moderate }
        return .good(score)
    }

    private typealias Cfg = (icon: String, text: String, color: Color)

    private func config(for state: BannerState) -> Cfg {
        switch state {
        case .rest:
            return ("moon.zzz.fill",
                    "Journée de repos — profites-en pour récupérer.",
                    .gray)
        case .hrvCritical:
            return ("waveform.path.ecg",
                    "HRV sous ta baseline — priorise la récupération, réduis l'intensité.",
                    .red)
        case .low(let s):
            return ("exclamationmark.triangle.fill",
                    "Récupération à \(Int(s))/100 — réduis le volume de ta séance aujourd'hui.",
                    Color.forge)
        case .moderate:
            return ("bolt.fill",
                    "Récupération modérée — reste sur le programme, écoute ton corps.",
                    Color(red: 1, green: 0.6, blue: 0))
        case .good(let s):
            return ("checkmark.circle.fill",
                    "Bonne récupération (\(Int(s))/100) — conditions optimales pour ta séance.",
                    .green)
        }
    }

    var body: some View {
        if let state = bannerState {
            let c = config(for: state)
            Button { onTap?() } label: {
                HStack(spacing: 10) {
                    Image(systemName: c.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(c.color)
                        .frame(width: 20)
                    Text(c.text)
                        .font(.appLabel)
                        .foregroundColor(Color(white: 0.85))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(c.color.opacity(0.08))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(c.color.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
        }
    }
}
