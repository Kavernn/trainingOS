import Foundation

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

    // MARK: - HIIT

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

    // MARK: - Tempo

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

    // MARK: - Endurance

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

    // MARK: - Léger

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

    // MARK: - Vélo

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

    // MARK: - Helpers

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
