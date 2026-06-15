import SwiftUI

struct WarMapView: View {
    @ObservedObject var vm: WarRoomViewModel
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !loaded {
                    ProgressView().tint(Color.forge).padding(.top, 60)
                } else if vm.warMap.isEmpty {
                    Text("Aucune bataille enregistrée.")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 60)
                } else {
                    ForEach(vm.warMap) { month in
                        monthBlock(month)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBg)
        .task {
            await vm.loadWarMap()
            loaded = true
        }
    }

    private func monthBlock(_ month: WarMapMonth) -> some View {
        var dayMap: [String: BattleStatus?] = [:]
        for day in month.days { dayMap[day.date] = day.status }

        let days    = daysInMonth(month.month)
        let offset  = weekdayOffset(month.month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return VStack(alignment: .leading, spacing: 10) {
            Text(formattedMonth(month.month))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(2)

            weekdayHeader

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0 ..< offset, id: \.self) { _ in Color.clear.frame(height: 28) }
                ForEach(days, id: \.self) { iso in
                    dayCell(iso, status: dayMap[iso] ?? nil)
                }
            }
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private var weekdayHeader: some View {
        let labels = ["L", "M", "M", "J", "V", "S", "D"]
        return HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(.appMicro.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ iso: String, status: BattleStatus?) -> some View {
        let day = Int(iso.suffix(2)) ?? 0
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor(status))
                .frame(height: 28)
            Text("\(day)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(status == .victory ? Color.white : Color.secondary)
        }
    }

    private func cellColor(_ status: BattleStatus?) -> Color {
        switch status {
        case .victory: return Color.forge.opacity(0.85)
        case .lost:    return Color.white.opacity(0.06)
        case .active:  return Color.statusOrange.opacity(0.4)
        default:       return Color.white.opacity(0.03)
        }
    }

    private func formattedMonth(_ ym: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "fr_CA")
        guard let d = f.date(from: ym) else { return ym }
        f.dateFormat = "MMMM yyyy"
        return f.string(from: d).capitalized
    }

    private func daysInMonth(_ ym: String) -> [String] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        guard let base = f.date(from: "\(ym)-01") else { return [] }
        guard let range = cal.range(of: .day, in: .month, for: base) else { return [] }
        return range.compactMap { day in
            cal.date(bySetting: .day, value: day, of: base).map { f.string(from: $0) }
        }
    }

    private func weekdayOffset(_ ym: String) -> Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let first = f.date(from: "\(ym)-01") else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let weekday = cal.component(.weekday, from: first)
        return (weekday + 5) % 7
    }
}
