import SwiftUI

// Entry point — decides which ritual phase to show
struct RitualView: View {
    @State private var ritual: RitualToday? = nil
    @State private var isLoading = true
    @State private var showDemons = false
    @Environment(\.dismiss) private var dismiss

    private var phase: RitualPhase {
        guard let r = ritual else { return .loading }
        if !r.morningDone { return .morning }
        if !r.eveningDone { return .evening }
        return .done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0A").ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(Color(hex: "FF2D20"))
                } else if let r = ritual {
                    switch phase {
                    case .morning:
                        RitualMorningView(ritual: r) { updated in ritual = updated }
                    case .evening:
                        RitualEveningView(ritual: r) { updated in ritual = updated }
                    case .done:
                        RitualDoneView(ritual: r, onDemons: { showDemons = true })
                    case .loading:
                        EmptyView()
                    }
                } else {
                    ritualUnavailableView
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.4))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showDemons) {
            DemonsView(demons: ritual?.demons ?? [])
        }
        .task { await load() }
    }

    private var ritualUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32)).foregroundColor(.gray)
            Text("Indisponible — réessaie dans un instant")
                .font(.system(size: 14)).foregroundColor(.gray)
            Button("Réessayer") { Task { await load() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "FF2D20"))
        }
    }

    private func load() async {
        isLoading = true
        // Clear cache before fetching — stale data breaks the phase state machine
        CacheService.shared.clear(for: "ritual_today")
        ritual    = try? await APIService.shared.fetchRitualToday()
        isLoading = false
    }
}

private enum RitualPhase { case loading, morning, evening, done }

// MARK: - F1: Ritual Biography — intention timeline

struct RitualBiographyView: View {
    @State private var entries: [RitualHistoryEntry] = []
    @State private var isLoading = true
    @State private var page = 0
    @State private var hasMore = true
    private let pageSize = 30
    private let red = Color(hex: "FF2D20")

    private var groupedByMonth: [(String, [RitualHistoryEntry])] {
        var dict: [String: [RitualHistoryEntry]] = [:]
        let fmtIn = DateFormatter(); fmtIn.dateFormat = "yyyy-MM-dd"
        let fmtOut = DateFormatter(); fmtOut.dateFormat = "MMMM yyyy"; fmtOut.locale = Locale(identifier: "fr_CA")
        for e in entries {
            let key: String
            if let d = fmtIn.date(from: String(e.date.prefix(10))) {
                key = fmtOut.string(from: d).capitalized
            } else { key = e.date }
            dict[key, default: []].append(e)
        }
        return dict.sorted { $0.key > $1.key }
    }

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()

            if isLoading && entries.isEmpty {
                ProgressView().tint(red)
            } else if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "flame.slash").font(.system(size: 36)).foregroundColor(Color(white: 0.25))
                    Text("Aucune intention enregistrée").font(.system(size: 14)).foregroundColor(Color(white: 0.35))
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
                        ForEach(groupedByMonth, id: \.0) { month, monthEntries in
                            Section(header: monthHeader(month)) {
                                ForEach(monthEntries) { entry in
                                    biographyRow(entry)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        if hasMore {
                            Button(action: loadMore) {
                                Text("Charger plus")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(white: 0.4))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Biographie")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func monthHeader(_ month: String) -> some View {
        Text(month.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(2)
            .foregroundColor(Color(white: 0.3))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "0A0A0A"))
    }

    private func biographyRow(_ entry: RitualHistoryEntry) -> some View {
        let outcomeColor: Color = entry.outcome == "burned" ? red : entry.outcome == "survived" ? Color(white: 0.4) : Color(white: 0.18)
        let outcomeIcon: String = entry.outcome == "burned" ? "flame.fill" : entry.outcome == "survived" ? "moon.fill" : "minus"

        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: outcomeIcon)
                    .font(.system(size: 12))
                    .foregroundColor(outcomeColor)
                    .frame(width: 24, height: 24)
                    .background(outcomeColor.opacity(0.12))
                    .clipShape(Circle())
                Rectangle().fill(Color(white: 0.1)).frame(width: 1)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formattedDate(entry.date))
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.3))
                    Spacer()
                    if entry.carryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "moon.stars.fill").font(.system(size: 9)).foregroundColor(Color(white: 0.25))
                            Text("×\(entry.carryCount)").font(.system(size: 9)).foregroundColor(Color(white: 0.25))
                        }
                    }
                }
                if let intention = entry.intention {
                    Text("«\u{202F}\(intention)\u{202F}»")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(entry.outcome == nil ? Color(white: 0.4) : .white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reflection = entry.reflection {
                    Text(reflection)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.4))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                Spacer(minLength: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDate(_ iso: String) -> String {
        let fmtIn = DateFormatter(); fmtIn.dateFormat = "yyyy-MM-dd"
        let fmtOut = DateFormatter(); fmtOut.dateFormat = "EEEE d"; fmtOut.locale = Locale(identifier: "fr_CA")
        guard let d = fmtIn.date(from: String(iso.prefix(10))) else { return iso }
        return fmtOut.string(from: d).capitalized
    }

    private func load() async {
        isLoading = true
        if let page0 = try? await APIService.shared.fetchRitualHistoryFull(limit: pageSize, offset: 0) {
            await MainActor.run {
                entries = page0.entries
                hasMore = page0.total > pageSize
                page    = 1
            }
        }
        await MainActor.run { isLoading = false }
    }

    private func loadMore() {
        Task {
            if let next = try? await APIService.shared.fetchRitualHistoryFull(limit: pageSize, offset: page * pageSize) {
                await MainActor.run {
                    entries.append(contentsOf: next.entries)
                    hasMore = entries.count < next.total
                    page   += 1
                }
            }
        }
    }
}

// ── Done state ───────────────────────────────────────────────────────────────

struct RitualDoneView: View {
    let ritual: RitualToday
    let onDemons: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // Outcome badge
                if ritual.burnedToday {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(hex: "FF2D20"))
                } else {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                }

                Text(ritual.burnedToday ? "BURNED" : "SURVIVED")
                    .font(.system(size: 13, weight: .black))
                    .tracking(4)
                    .foregroundColor(ritual.burnedToday ? Color(hex: "FF2D20") : .gray)

                // Phoenix streak
                if ritual.phoenixStreak > 0 {
                    VStack(spacing: 6) {
                        Text("\(ritual.phoenixStreak)")
                            .font(.system(size: 64, weight: .black))
                            .foregroundColor(.white)
                        Text("JOURS CONSÉCUTIFS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(3)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 8)
                }

                Text("\(ritual.phoenixTotalBurned) intentions tuées au total")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.4))
            }
            Spacer()

            VStack(spacing: 12) {
                // F6: heatmap shortcut
                NavigationLink(destination: RitualHeatMapView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.3))
                        Text("Voir le calendrier")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.3))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.2))
                    }
                    .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)

                // Demons link
                if !ritual.demons.isEmpty {
                    Button(action: onDemons) {
                        HStack(spacing: 6) {
                            Image(systemName: "moon.stars.fill").font(.system(size: 13))
                            Text("\(ritual.demons.count) démon\(ritual.demons.count > 1 ? "s" : "") en attente")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Color(white: 0.35))
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - F6: Ritual Heatmap Calendar

struct RitualHeatMapView: View {
    @State private var entries: [RitualHistoryEntry] = []
    @State private var isLoading = true
    private let red = Color(hex: "FF2D20")

    private var entriesByDate: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.compactMap { e -> (String, String)? in
            guard !e.date.isEmpty else { return nil }
            return (String(e.date.prefix(10)), e.outcome ?? "no_intention")
        })
    }

    private var months: [Date] {
        let cal = Calendar.current
        let today = Date()
        return (0..<6).reversed().compactMap {
            cal.date(byAdding: .month, value: -$0, to: cal.startOfMonth(for: today))
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()
            if isLoading {
                ProgressView().tint(red)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        legend
                        ForEach(months, id: \.self) { month in
                            monthGrid(month)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Calendrier")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: red, label: "Burned")
            legendItem(color: Color(white: 0.35), label: "Survived")
            legendItem(color: Color(white: 0.12), label: "Manqué")
            legendItem(color: Color(white: 0.06), label: "—")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(label).font(.system(size: 10)).foregroundColor(Color(white: 0.35))
        }
    }

    private func monthGrid(_ month: Date) -> some View {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"; fmt.locale = Locale(identifier: "fr_CA")
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekday = (cal.component(.weekday, from: month) + 5) % 7 // Monday = 0

        return VStack(alignment: .leading, spacing: 8) {
            Text(fmt.string(from: month).capitalized)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundColor(Color(white: 0.4))

            // Day of week headers
            HStack(spacing: 4) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { d in
                    Text(d).font(.system(size: 8)).foregroundColor(Color(white: 0.2))
                        .frame(width: 32)
                }
            }

            // Day cells
            let totalCells = firstWeekday + daysInMonth
            let rows = Int(ceil(Double(totalCells) / 7.0))
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        let cellIndex = row * 7 + col
                        let day = cellIndex - firstWeekday + 1
                        if day < 1 || day > daysInMonth {
                            Color.clear.frame(width: 32, height: 28)
                        } else {
                            let dateStr = dayString(month: month, day: day)
                            dayCell(dateStr: dateStr, day: day)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(dateStr: String, day: Int) -> some View {
        let outcome = entriesByDate[dateStr]
        let color: Color
        switch outcome {
        case "burned":      color = red
        case "survived":    color = Color(white: 0.35)
        case "no_intention": color = Color(white: 0.12)
        default:            color = Color(white: 0.06)
        }
        let isToday = dateStr == todayString
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(color)
            if isToday {
                RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.4), lineWidth: 1)
            }
            Text("\(day)").font(.system(size: 9)).foregroundColor(outcome != nil ? .white : Color(white: 0.25))
        }
        .frame(width: 32, height: 28)
    }

    private var todayString: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func dayString(month: Date, day: Int) -> String {
        let cal = Calendar.current
        guard let date = cal.date(bySetting: .day, value: day, of: month) else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private func load() async {
        isLoading = true
        if let page = try? await APIService.shared.fetchRitualHistoryFull(limit: 180, offset: 0) {
            await MainActor.run { entries = page.entries }
        }
        await MainActor.run { isLoading = false }
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
