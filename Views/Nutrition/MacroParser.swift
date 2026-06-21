import Foundation

struct MacroParseResult {
    var name: String
    var calories: String
    var proteines: String
    var glucides: String
    var lipides: String
}

enum MacroParser {

    static func parse(_ raw: String) -> MacroParseResult {
        let text = raw.lowercased()
        return MacroParseResult(
            name:      extractName(from: text),
            calories:  find(text, keywords: ["calories", "calorie", "kcal", "cal"]).map(fmt) ?? "",
            proteines: find(text, keywords: ["protéines", "protéine", "proteines", "proteine", "prot"]).map(fmt) ?? "",
            glucides:  find(text, keywords: ["glucides", "glucide", "carbs", "carb", "sucres", "sucre"]).map(fmt) ?? "",
            lipides:   find(text, keywords: ["lipides", "lipide", "graisses", "graisse", "gras"]).map(fmt) ?? ""
        )
    }

    // MARK: - Private

    private static let numRx = "([0-9]+(?:[.,][0-9]+)?)"

    private static func find(_ text: String, keywords: [String]) -> Double? {
        for kw in keywords {
            let esc = NSRegularExpression.escapedPattern(for: kw)
            if let v = capture(pattern: "\(numRx)\\s*\(esc)", in: text) { return v }
            if let v = capture(pattern: "\(esc)\\s*\(numRx)", in: text) { return v }
        }
        return nil
    }

    private static func capture(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        let r = m.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        let raw = ns.substring(with: r).replacingOccurrences(of: ",", with: ".")
        return Double(raw)
    }

    private static func extractName(from text: String) -> String {
        let allKeywords = [
            "calories", "calorie", "kcal", "cal",
            "protéines", "protéine", "proteines", "proteine", "prot",
            "glucides", "glucide", "carbs", "carb", "sucres", "sucre",
            "lipides", "lipide", "graisses", "graisse", "gras"
        ]
        var earliest = text.endIndex
        for kw in allKeywords {
            if let r = text.range(of: kw), r.lowerBound < earliest { earliest = r.lowerBound }
        }
        if let r = text.range(of: "[0-9]", options: .regularExpression), r.lowerBound < earliest {
            earliest = r.lowerBound
        }
        let raw = String(text[..<earliest]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}
