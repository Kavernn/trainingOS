import SwiftUI

// MARK: - Weekly Protein Chart

struct WeeklyProteinChart: View {
    let history: [NutritionDayHistory]
    let target: Double

    var maxProt: Double { max(history.map(\.proteines).max() ?? 0, target, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROTÉINES — 7 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.appTextSecondary)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(history) { day in
                    let pct = day.proteines / maxProt
                    let isToday = day.date == DateFormatter.isoDate.string(from: Date())
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isToday ? Color.statusBlue : Color.statusBlue.opacity(0.4))
                                    .frame(height: max(geo.size.height * pct, 4))
                            }
                        }
                        .frame(height: 60)
                        Text(shortDay(day.date))
                            .font(.appMicro.weight(.medium))
                            .foregroundColor(.appTextSecondary)
                        Text("\(Int(day.proteines))g")
                            .font(.appMicro.weight(.semibold))
                            .foregroundColor(isToday ? Color.statusBlue : .gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.statusBlue.opacity(0.3)).frame(width: 20, height: 2)
                Text("Objectif \(Int(target))g prot")
                    .font(.system(size: 10))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private func shortDay(_ date: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_CA"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: date) { f.dateFormat = "EEE"; return f.string(from: d).prefix(2).uppercased() }
        return date
    }
}

// MARK: - Weekly Calorie Chart

struct WeeklyCalorieChart: View {
    let history: [NutritionDayHistory]
    let target: Double?

    var maxCal: Double { max(history.map(\.calories).max() ?? 0, target ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CALORIES — 7 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.appTextSecondary)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(history) { day in
                    let pct = day.calories / maxCal
                    let isToday = day.date == DateFormatter.isoDate.string(from: Date())
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isToday ? Color.forge : Color.forge.opacity(0.4))
                                    .frame(height: max(geo.size.height * pct, 4))
                            }
                        }
                        .frame(height: 60)
                        Text(shortDay(day.date))
                            .font(.appMicro.weight(.medium))
                            .foregroundColor(.appTextSecondary)
                        Text("\(Int(day.calories))")
                            .font(.appMicro.weight(.semibold))
                            .foregroundColor(isToday ? Color.forge : .gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let t = target {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.forge.opacity(0.3)).frame(width: 20, height: 2)
                    Text("Objectif \(Int(t)) kcal")
                        .font(.system(size: 10))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private func shortDay(_ date: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_CA"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: date) { f.dateFormat = "EEE"; return f.string(from: d).prefix(2).uppercased() }
        return date
    }
}

// MARK: - Weekly Nutrition Chart (merged, tappable)
struct WeeklyNutritionChart: View {
    let history: [NutritionDayHistory]
    let protTarget: Double
    let calTarget: Double?

    enum Metric: String, CaseIterable {
        case calories = "Calories"
        case proteines = "Protéines"
    }

    @State private var metric: Metric = .calories
    @State private var selectedDay: NutritionDayHistory? = nil

    private var maxValue: Double {
        switch metric {
        case .calories:  return max(history.map(\.calories).max() ?? 0, calTarget ?? 0, 1)
        case .proteines: return max(history.map(\.proteines).max() ?? 0, protTarget, 1)
        }
    }

    private var target: Double? {
        switch metric {
        case .calories:  return calTarget
        case .proteines: return protTarget
        }
    }

    private var accentColor: Color { metric == .calories ? Color.forge : Color.statusBlue }

    private func value(for day: NutritionDayHistory) -> Double {
        metric == .calories ? day.calories : day.proteines
    }

    private func shortDay(_ date: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_CA"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: date) { f.dateFormat = "EEE"; return f.string(from: d).prefix(2).uppercased() }
        return date
    }

    private var displayDays: [(label: String, cal: Double, prot: Double, date: String)] {
        guard history.count > 31 else {
            return history.map { (shortDay($0.date), $0.calories, $0.proteines, $0.date) }
        }
        // Aggregate by ISO week for 90-day view
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var weeks: [(key: String, days: [NutritionDayHistory])] = []
        var seen: [String: Int] = [:]
        for day in history.sorted(by: { $0.date < $1.date }) {
            guard let d = fmt.date(from: day.date) else { continue }
            let tz = TimeZone.current.secondsFromGMT()
            let wIdx = (Int(d.timeIntervalSince1970) + tz) / 86400
            let key = "W\((wIdx + 3) / 7)"
            if let idx = seen[key] { weeks[idx].days.append(day) }
            else { seen[key] = weeks.count; weeks.append((key, [day])) }
        }
        return weeks.enumerated().map { idx, wk in
            let avgCal  = wk.days.reduce(0) { $0 + $1.calories }  / Double(wk.days.count)
            let avgProt = wk.days.reduce(0) { $0 + $1.proteines } / Double(wk.days.count)
            return ("S\(idx + 1)", avgCal, avgProt, wk.days.last?.date ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(history.count > 31 ? "PAR SEMAINE" : history.count > 7 ? "\(history.count) DERNIERS JOURS" : "7 DERNIERS JOURS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            let days = displayDays
            let maxVal = days.map { metric == .calories ? $0.cal : $0.prot }.max() ?? 1
            let isCompact = history.count > 7
            HStack(alignment: .bottom, spacing: isCompact ? 2 : 6) {
                ForEach(days, id: \.date) { day in
                    let v = metric == .calories ? day.cal : day.prot
                    let pct = v / maxVal
                    let isToday = day.date == DateFormatter.isoDate.string(from: Date())
                    let isSelected = selectedDay?.date == day.date
                    VStack(spacing: isCompact ? 2 : 4) {
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                                    .fill(isSelected ? accentColor : (isToday ? accentColor : accentColor.opacity(isCompact ? 0.5 : 0.35)))
                                    .frame(height: max(geo.size.height * pct, 3))
                                    .overlay(isSelected ? RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5) : nil)
                            }
                        }
                        .frame(height: 60)
                        if !isCompact || history.count > 31 {
                            Text(day.label)
                                .font(.system(size: isCompact ? 7 : 9, weight: .medium))
                                .foregroundColor(isToday ? .white : .gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDay = selectedDay?.date == day.date ? nil : NutritionDayHistory(date: day.date, calories: day.cal, proteines: day.prot)
                        }
                    }
                }
            }

            // Tapped day detail
            if let day = selectedDay {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(day.date)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Text("\(Int(day.calories)) kcal · \(Int(day.proteines))g prot")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                    }
                    if let t = target {
                        let v = value(for: day)
                        let pct = v / t
                        let ok = metric == .calories ? v <= t * 1.1 : v >= t * 0.9
                        Label(ok ? "Dans l'objectif" : "Hors objectif",
                              systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.appCaption)
                            .foregroundColor(ok ? Color.appSuccess : Color.appDanger)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06)).frame(height: 4)
                                Capsule()
                                    .fill(ok ? Color.appSuccess : Color.appDanger)
                                    .frame(width: max(4, geo.size.width * min(pct, 1.0)), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let t = target {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(accentColor.opacity(0.3)).frame(width: 20, height: 2)
                    Text("Objectif \(Int(t))\(metric == .calories ? " kcal" : "g prot")")
                        .font(.system(size: 10))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}
