import Foundation

// Standalone regression harness: compile with Models/NutritionModels.swift.
// No simulator, Xcode project changes, or application build required.
@main
struct NutritionCatchupTargetChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        let resolved = Data("""
        {"date":"2026-09-27","day_type":"heavy","calories":2800,
         "proteines":180,"glucides":330,"lipides":75,"workout_label":"Lower B"}
        """.utf8)
        let target = try decoder.decode(DailyNutritionTarget.self, from: resolved)
        precondition(target.isValid && target.dayType == "heavy")
        precondition(target.date == "2026-09-27")
        let full = target.estimate(pctCalories: 100, pctProteines: 100)
        precondition(full.calories == 2800 && full.proteines == 180)
        let estimate = target.estimate(pctCalories: 75, pctProteines: 80)
        precondition(estimate.calories == 2100 && estimate.proteines == 144)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(estimate)) as! [String: Any]
        precondition(payload["date"] as? String == "2026-09-27")
        precondition(payload["calories"] as? Int == estimate.calories)
        precondition(payload["proteines"] as? Int == estimate.proteines)
        let rounded = target.estimate(pctCalories: 0.375, pctProteines: 2.5)
        precondition(rounded.calories == 11 && rounded.proteines == 5)
        for suffix in ["", ",\"target\":null,\"target_error\":\"Indisponible\""] {
            let data = Data("{\"date\":\"2026-09-27\",\"calories\":0,\"proteines\":0,\"entries_count\":0\(suffix)}".utf8)
            let day = try decoder.decode(NutritionDaySummary.self, from: data)
            precondition(day.target == nil) // Loading/unavailable cannot supply fake estimates.
            precondition(day.target?.estimate(pctCalories: 100, pctProteines: 100) == nil)
        }
        print("PASS: resolved target, 100%, 75%/80%, rounding, payload equality, loading/unavailable")
    }
}
