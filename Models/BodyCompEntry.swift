import SwiftData
import Foundation

@Model
final class BodyCompEntry {
    var date: Date
    var weightLbs: Double
    var bodyFatPct: Double
    var fatMassLbs: Double
    var leanMassLbs: Double

    init(date: Date = .now,
         weightLbs: Double,
         bodyFatPct: Double,
         fatMassLbs: Double,
         leanMassLbs: Double) {
        self.date        = date
        self.weightLbs   = weightLbs
        self.bodyFatPct  = bodyFatPct
        self.fatMassLbs  = fatMassLbs
        self.leanMassLbs = leanMassLbs
    }
}
