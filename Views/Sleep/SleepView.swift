import SwiftUI
import Charts

struct SleepView: View {
    @State private var history: [SleepEntry] = []
    @State private var stats: SleepStats?
    @State private var todayEntry: SleepEntry?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var nextOffset: Int? = nil
    @State private var showLogSheet = false
    @State private var entryToDelete: SleepEntry?

    private let accentColor = Color.indigo

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AmbientBackground(color: accentColor)

            ScrollView {
                VStack(spacing: 16) {

                    // KPI row
                    if let s = stats {
                        HStack(spacing: 12) {
                            SleepKPI(
                                icon:  "moon.zzz.fill",
                                label: "Moy. durée",
                                value: s.avgDuration.map { String(format: "%.1fh", $0) } ?? "—",
                                color: accentColor
                            )
                            SleepKPI(
                                icon:  "star.fill",
                                label: "Moy. qualité",
                                value: s.avgQuality.map { String(format: "%.1f/5", $0) } ?? "—",
                                color: .yellow
                            )
                            SleepKPI(
                                icon:  "flame.fill",
                                label: "Streak",
                                value: "\(s.streak)j",
                                color: .orange
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }

                    // Tonight / today entry
                    if let entry = todayEntry {
                        SleepTodayCard(entry: entry)
                            .padding(.horizontal, 16)
                    }

                    // 7-night bar chart
                    if history.count >= 2 {
                        SleepBarChart(entries: Array(history.prefix(7).reversed()))
                            .padding(.horizontal, 16)
                    }

                    // Insights from latest entry
                    if let first = history.first, !first.insights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("INSIGHTS")
                                .font(.system(size: 11, weight: .black))
                                .tracking(2)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 20)

                            VStack(spacing: 6) {
                                ForEach(first.insights, id: \.self) { insight in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(insight)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(hex: "11111c"))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // History list
                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HISTORIQUE")
                                .font(.system(size: 11, weight: .black))
                                .tracking(2)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 20)

                            VStack(spacing: 6) {
                                ForEach(history) { entry in
                                    SleepHistoryRow(entry: entry)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                entryToDelete = entry
                                            } label: {
                                                Label("Supprimer", systemImage: "trash")
                                            }
                                        }
                                }
                                if hasMore {
                                    Button { Task { await loadMore() } } label: {
                                        HStack {
                                            Spacer()
                                            if isLoadingMore {
                                                ProgressView().scaleEffect(0.8)
                                            } else {
                                                Text("Charger plus…")
                                                    .font(.subheadline).foregroundColor(accentColor)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 100)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // FAB
            Button { showLogSheet = true } label: {
                Image(systemName: todayEntry == nil ? "plus" : "arrow.clockwise")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(18)
                    .background(accentColor)
                    .clipShape(Circle())
                    .shadow(color: accentColor.opacity(0.5), radius: 8, y: 4)
            }
            .padding(24)
        }
        .navigationTitle("Sommeil")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogSheet, onDismiss: { Task { await loadData() } }) {
            SleepLogSheet(existing: todayEntry)
        }
        .alert("Supprimer cette nuit ?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Supprimer", role: .destructive) {
                if let e = entryToDelete { Task { await deleteEntry(e) } }
            }
            Button("Annuler", role: .cancel) {}
        }
        .task { await loadData() }
    }

    private func loadData() async {
        async let pg = try? APIService.shared.fetchSleepHistory()
        async let s  = try? APIService.shared.fetchSleepStats()
        async let t  = try? APIService.shared.fetchSleepToday()
        let (page, st, to) = await (pg, s, t)
        await MainActor.run {
            if let page {
                history    = page.items
                hasMore    = page.hasMore
                nextOffset = page.nextOffset
            }
            stats      = st
            todayEntry = to
            isLoading  = false
        }
    }

    private func loadMore() async {
        guard let offset = nextOffset, !isLoadingMore else { return }
        isLoadingMore = true
        if let pg = try? await APIService.shared.fetchSleepHistory(offset: offset) {
            history.append(contentsOf: pg.items)
            hasMore    = pg.hasMore
            nextOffset = pg.nextOffset
        }
        isLoadingMore = false
    }

    private func deleteEntry(_ entry: SleepEntry) async {
        try? await APIService.shared.deleteSleepEntry(id: entry.id)
        await loadData()
    }
}

// MARK: - KPI Card

private struct SleepKPI: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Today Card

private struct SleepTodayCard: View {
    let entry: SleepEntry

    private var durationColor: Color {
        switch entry.durationCategory {
        case "insuffisant": return .red
        case "court":       return .yellow
        case "optimal":     return .green
        default:            return .blue
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("CETTE NUIT")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2)
                        .foregroundColor(.gray)
                    Text("✓")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }
                Text(String(format: "%.1fh", entry.durationHours))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(durationColor)
                Text("\(entry.bedtime) → \(entry.wakeTime)")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(spacing: 6) {
                Text(entry.qualityEmoji)
                    .font(.system(size: 30))
                Text(entry.qualityLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(durationColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Bar Chart (7 nuits)

private struct SleepBarChart: View {
    let entries: [SleepEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7 DERNIÈRES NUITS")
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundColor(.gray)

            Chart(entries) { entry in
                BarMark(
                    x: .value("Date", shortDate(entry.date)),
                    y: .value("Heures", entry.durationHours)
                )
                .foregroundStyle(barColor(entry.durationCategory))
                .cornerRadius(4)

                RuleMark(y: .value("Optimal min", 7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Color.green.opacity(0.4))
            }
            .chartYScale(domain: 0...12)
            .chartYAxis {
                AxisMarks(values: [0, 4, 7, 9, 12]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .foregroundStyle(Color.gray)
                        .font(.system(size: 10))
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel()
                        .foregroundStyle(Color.gray)
                        .font(.system(size: 10))
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2])/\(parts[1])"
    }

    private func barColor(_ category: String) -> Color {
        switch category {
        case "insuffisant": return .red
        case "court":       return .yellow
        case "optimal":     return .indigo
        default:            return .blue
        }
    }
}

// MARK: - History Row

private struct SleepHistoryRow: View {
    let entry: SleepEntry

    private var durationColor: Color {
        switch entry.durationCategory {
        case "insuffisant": return .red
        case "court":       return .yellow
        case "optimal":     return .green
        default:            return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.qualityEmoji)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate(entry.date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(entry.bedtime) → \(entry.wakeTime)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1fh", entry.durationHours))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(durationColor)
                Text(entry.qualityLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formattedDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        let months = ["", "Jan", "Fév", "Mar", "Avr", "Mai", "Jun",
                      "Jul", "Aoû", "Sep", "Oct", "Nov", "Déc"]
        let m = Int(parts[1]) ?? 0
        return "\(parts[2]) \(months[m])"
    }
}

// MARK: - Log Sheet

struct SleepLogSheet: View {
    let existing: SleepEntry?
    @Environment(\.dismiss) private var dismiss

    @State private var bedtime  = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var wakeTime = Calendar.current.date(bySettingHour: 7,  minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quality  = 3
    @State private var notes    = ""
    @State private var isSaving = false
    @State private var error: String?

    private let qualityLabels = ["", "Très mauvais", "Mauvais", "Moyen", "Bon", "Excellent"]
    private let qualityEmojis = ["", "😫", "😕", "😐", "😊", "🌟"]
    private let accentColor   = Color.indigo

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: accentColor)
                Form {
                    Section("Horaires") {
                        DatePicker("Couché", selection: $bedtime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .foregroundColor(.white)
                        DatePicker("Levé",   selection: $wakeTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .foregroundColor(.white)
                    }

                    Section("Qualité du sommeil") {
                        VStack(spacing: 12) {
                            Text("\(qualityEmojis[quality])  \(qualityLabels[quality])")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)

                            HStack(spacing: 12) {
                                ForEach(1...5, id: \.self) { q in
                                    Button {
                                        quality = q
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text(qualityEmojis[q])
                                                .font(.system(size: 26))
                                            Text("\(q)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(quality == q ? accentColor : .gray)
                                        }
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(quality == q ? accentColor.opacity(0.15) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(quality == q ? accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Notes (optionnel)") {
                        TextField("Ex : sommeil agité, cauchemar…", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    if let error {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.system(size: 13))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(existing == nil ? "Logger le sommeil" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") { Task { await save() } }
                            .bold()
                    }
                }
            }
            .keyboardOkButton()
        }
        .onAppear {
            if let e = existing {
                // Prefill from existing entry
                let cal = Calendar.current
                let now = Date()
                if let bh = Int(e.bedtime.split(separator: ":").first ?? ""),
                   let bm = Int(e.bedtime.split(separator: ":").last  ?? "") {
                    bedtime = cal.date(bySettingHour: bh, minute: bm, second: 0, of: now) ?? now
                }
                if let wh = Int(e.wakeTime.split(separator: ":").first ?? ""),
                   let wm = Int(e.wakeTime.split(separator: ":").last  ?? "") {
                    wakeTime = cal.date(bySettingHour: wh, minute: wm, second: 0, of: now) ?? now
                }
                quality = e.quality
                notes   = e.notes ?? ""
            }
        }
    }

    private func save() async {
        isSaving = true
        error    = nil
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let bed  = fmt.string(from: bedtime)
        let wake = fmt.string(from: wakeTime)
        do {
            _ = try await APIService.shared.logSleep(
                bedtime:  bed,
                wakeTime: wake,
                quality:  quality,
                notes:    notes.isEmpty ? nil : notes
            )
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                self.error   = "Erreur : \(error.localizedDescription)"
                self.isSaving = false
            }
        }
    }
}
