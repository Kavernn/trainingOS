import SwiftUI

struct WarMapView: View {
    @ObservedObject var vm: WarRoomViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if vm.warMap.isEmpty {
                    ProgressView().tint(Color.forge).padding(.top, 60)
                } else {
                    ForEach(vm.warMap) { month in
                        monthBlock(month)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBg)
        .task { await vm.loadWarMap() }
    }

    private func monthBlock(_ month: WarMapMonth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(formattedMonth(month.month))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(2)

            let dayMap = Dictionary(uniqueKeysWithValues: month.days.map { ($0.date, $0.status) })

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(daysInMonth(month.month), id: \.self) { iso in
                    dayCell(iso, status: dayMap[iso] ?? nil)
                }
            }
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14))
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
        case .active:  return Color.orange.opacity(0.4)
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
        f.dateFormat = "yyyy-MM"
        guard let base = f.date(from: ym) else { return [] }
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: base) else { return [] }
        return range.map { day -> String in
            let d = cal.date(bySetting: .day, value: day, of: base)!
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: d)
        }
    }
}
