import SwiftUI

struct RecoveryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var log: [RecoveryEntry] = []
    @State private var isLoading = true
    @State private var showSheet = false
    @State private var editTarget: RecoveryEntry? = nil
    @State private var apiError: String? = nil
    @State private var toast: ToastMessage? = nil
    @StateObject private var watchSync = WatchSyncService.shared
    @State private var isBackfilling = false
    @State private var backfillDone  = false

    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    private var entriesMissingHK: [RecoveryEntry] {
        log.filter { $0.restingHr == nil || $0.hrv == nil || $0.activeEnergy == nil }
    }

    private var alreadyLoggedToday: Bool {
        log.contains { $0.date == todayStr }
    }

    // KPIs
    var avgSleep: Double {
        let v = log.compactMap(\.sleepHours); return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }
    var avgSleepQuality: Double {
        let v = log.compactMap(\.sleepQuality); return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }
    var avgRestHR: Double {
        let v = log.compactMap(\.restingHr); return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }
    var avgSteps: Double {
        let v = log.compactMap(\.steps).map(Double.init); return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }
    var avgActiveEnergy: Double {
        let v = log.compactMap(\.activeEnergy); return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }
    var avgHRV: Double {
        let v = log.compactMap(\.hrv); return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .indigo)
                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // Watch sync status (iOS uniquement — HealthKit non dispo sur Mac)
                            #if !targetEnvironment(macCatalyst)
                            WatchSyncBannerView(sync: watchSync) {
                                Task {
                                    await watchSync.requestAuthorizationAndSync()
                                    await loadData()
                                }
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0)
                            #endif

                            // HealthKit backfill banner
                            #if !targetEnvironment(macCatalyst)
                            if !entriesMissingHK.isEmpty && !backfillDone {
                                HStack(spacing: 10) {
                                    Image(systemName: "heart.text.square.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 15))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(entriesMissingHK.count) entrée\(entriesMissingHK.count > 1 ? "s" : "") sans FC / HRV")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("Synchroniser depuis Apple Santé")
                                            .font(.system(size: 10))
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Button {
                                        Task { await backfillFromHealthKit() }
                                    } label: {
                                        if isBackfilling {
                                            ProgressView().tint(.white).scaleEffect(0.75)
                                        } else {
                                            Text("Sync")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(Color.red.opacity(0.8))
                                                .cornerRadius(8)
                                        }
                                    }
                                    .disabled(isBackfilling)
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                            }
                            #endif

                            // KPI grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                KPICard(value: avgSleep > 0 ? String(format: "%.1fh", avgSleep) : "—",
                                        label: "Sommeil moy.", color: .indigo)
                                KPICard(value: avgSleepQuality > 0 ? String(format: "%.1f/10", avgSleepQuality) : "—",
                                        label: "Qualité moy.", color: .purple)
                                KPICard(value: avgRestHR > 0 ? String(format: "%.0f bpm", avgRestHR) : "—",
                                        label: "FC repos moy.", color: .red)
                                KPICard(value: avgSteps > 0 ? String(format: "%.0f", avgSteps) : "—",
                                        label: "Pas moy./jour", color: .green)
                                KPICard(value: avgActiveEnergy > 0 ? String(format: "%.0f kcal", avgActiveEnergy) : "—",
                                        label: "Énergie active", color: .orange)
                                KPICard(value: avgHRV > 0 ? String(format: "%.0f ms", avgHRV) : "—",
                                        label: "HRV moy.", color: .green)
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // Readiness card
                            if let today = log.first(where: { $0.date == todayStr }) {
                                ReadinessCard(entry: today)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.08)
                            }

                            // HRV chart
                            let hrvEntries = Array(log.prefix(14).reversed())
                            if hrvEntries.filter({ $0.hrv != nil }).count >= 2 {
                                HRVChart(entries: hrvEntries)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.1)
                            }

                            // RHR chart
                            if hrvEntries.filter({ $0.restingHr != nil }).count >= 2 {
                                RHRChart(entries: hrvEntries)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.12)
                            }

                            // Sleep chart
                            if log.filter({ $0.sleepHours != nil }).count >= 2 {
                                SleepChart(entries: Array(log.prefix(10).reversed()))
                                    .padding(.horizontal, 16)
                            } else {
                                EmptyChartPlaceholder(message: "Logge au moins 2 nuits pour voir l'évolution du sommeil")
                                    .padding(.horizontal, 16)
                            }

                            // Steps chart
                            if log.filter({ $0.steps != nil }).count >= 2 {
                                StepsChart(entries: Array(log.prefix(10).reversed()))
                                    .padding(.horizontal, 16)
                            } else {
                                EmptyChartPlaceholder(message: "Logge au moins 2 jours de pas pour voir la tendance")
                                    .padding(.horizontal, 16)
                            }

                            // History
                            if log.isEmpty {
                                RecoveryEmptyState()
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("HISTORIQUE")
                                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        .padding(.horizontal, 16)
                                    ForEach(log) { entry in
                                        RecoveryRow(
                                            entry: entry,
                                            onEdit: { editTarget = entry },
                                            onDelete: {
                                                Task {
                                                    do {
                                                        try await APIService.shared.deleteRecovery(date: entry.date ?? "")
                                                        await MainActor.run { toast = ToastMessage(message: "Entrée supprimée", style: .success) }
                                                    } catch {
                                                        await MainActor.run { apiError = "Erreur réseau — réessaie" }
                                                    }
                                                    await loadData()
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }

                            Spacer(minLength: 32)
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, contentBottomPadding)
                    }
                }
            }
            .navigationTitle("Récupération")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSheet) {
                LogRecoverySheet(onSaved: { await loadData() })
            }
            .sheet(item: $editTarget) { entry in
                LogRecoverySheet(prefillEntry: entry, onSaved: { await loadData() })
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: alreadyLoggedToday ? "pencil" : "plus") {
                    if alreadyLoggedToday, let todayEntry = log.first(where: { $0.date == todayStr }) {
                        editTarget = todayEntry
                    } else {
                        showSheet = true
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, fabBottomPadding + 16)
            }
        }
        .task {
            await watchSync.syncIfNeeded()
            await loadData()
        }
        .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(apiError ?? "") }
        .toast($toast)
    }

    private func loadData() async {
        isLoading = true
        log = (try? await APIService.shared.fetchRecoveryData()) ?? []
        isLoading = false
    }

    private func backfillFromHealthKit() async {
        let hk = HealthKitService.shared
        let authorized = await hk.requestAuthorization()
        guard authorized else { return }

        isBackfilling = true
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var updated = 0

        for entry in entriesMissingHK {
            guard let dateStr = entry.date,
                  let date    = fmt.date(from: dateStr) else { continue }

            async let rhr = entry.restingHr    == nil ? hk.fetchRestingHR(for: date)    : nil
            async let hrv = entry.hrv           == nil ? hk.fetchHRV(for: date)           : nil
            async let ae  = entry.activeEnergy  == nil ? hk.fetchActiveEnergy(for: date)  : nil
            let (newRHR, newHRV, newAE) = await (rhr, hrv, ae)

            guard newRHR != nil || newHRV != nil || newAE != nil else { continue }

            try? await APIService.shared.logRecovery(
                sleepHours:   entry.sleepHours,
                sleepQuality: entry.sleepQuality,
                restingHr:    newRHR ?? entry.restingHr,
                hrv:          newHRV ?? entry.hrv,
                steps:        entry.steps,
                soreness:     entry.soreness,
                activeEnergy: newAE  ?? entry.activeEnergy,
                notes:        entry.notes ?? "",
                date:         dateStr
            )
            updated += 1
        }

        await loadData()
        await MainActor.run {
            isBackfilling = false
            backfillDone  = true
            if updated > 0 {
                toast = ToastMessage(
                    message: "\(updated) entrée\(updated > 1 ? "s" : "") mise\(updated > 1 ? "s" : "") à jour depuis Santé",
                    style: .success
                )
            } else {
                toast = ToastMessage(message: "Aucune donnée HealthKit trouvée pour ces dates", style: .success)
            }
        }
    }
}

// MARK: - Row
struct RecoveryRow: View {
    let entry: RecoveryEntry
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.date ?? "")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    if entry.isFromWatch {
                        Label("Watch", systemImage: "applewatch")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                HStack(spacing: 10) {
                    if let h = entry.sleepHours {
                        Label(String(format: "%.1fh", h), systemImage: "moon.fill")
                            .font(.system(size: 11)).foregroundColor(.indigo)
                    }
                    if let q = entry.sleepQuality {
                        Label(String(format: "%.0f/10", q), systemImage: "star.fill")
                            .font(.system(size: 11)).foregroundColor(.purple)
                    }
                    if let hr = entry.restingHr {
                        Label(String(format: "%.0f bpm", hr), systemImage: "heart.fill")
                            .font(.system(size: 11)).foregroundColor(.red)
                    }
                }
                if let s = entry.steps {
                    Label("\(s) pas", systemImage: "figure.walk")
                        .font(.system(size: 11)).foregroundColor(.green)
                }
            }

            Spacer()

            if let soreness = entry.soreness {
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", soreness))
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(sorenessColor(soreness))
                    Text("douleurs")
                        .font(.system(size: 9)).foregroundColor(.gray)
                }
            }

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .frame(width: 30, height: 30)
                        .background(Color.indigo.opacity(0.12))
                        .foregroundColor(.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(hex: "11111c"))
        .cornerRadius(12)
        .confirmationDialog("Supprimer cette entrée ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func sorenessColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
    }
}

// MARK: - Readiness Card

struct ReadinessCard: View {
    let entry: RecoveryEntry

    private var score: Double? {
        var total = 0.0; var count = 0
        if let q  = entry.sleepQuality  { total += q;                              count += 1 }
        if let s  = entry.soreness      { total += max(0, 10 - s);                 count += 1 }
        if let h  = entry.sleepHours    { total += min(10, h / 8 * 10);            count += 1 }
        if let hrv = entry.hrv          { total += min(10, hrv / 80 * 10);         count += 1 }
        if let hr  = entry.restingHr    { total += min(10, max(0, (85 - hr) / 45 * 10)); count += 1 }
        return count >= 2 ? round(total / Double(count) * 10) / 10 : nil
    }

    private var scoreColor: Color {
        guard let s = score else { return .gray }
        return s >= 7 ? .green : (s >= 5 ? .orange : .red)
    }

    private var scoreLabel: String {
        guard let s = score else { return "—" }
        return s >= 7 ? "Prêt" : (s >= 5 ? "Modéré" : "Fatigué")
    }

    var body: some View {
        HStack(spacing: 16) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 6)
                    .frame(width: 62, height: 62)
                if let s = score {
                    Circle()
                        .trim(from: 0, to: CGFloat(s / 10))
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 62, height: 62)
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(score.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                    Text("/10")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("READINESS DU JOUR")
                        .font(.system(size: 10, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    Text(scoreLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(scoreColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(scoreColor.opacity(0.15))
                        .cornerRadius(4)
                }
                HStack(spacing: 12) {
                    if let hrv = entry.hrv {
                        metricPill("HRV", String(format: "%.0f ms", hrv),
                                   hrv >= 50 ? .green : (hrv >= 30 ? .orange : .red))
                    }
                    if let hr = entry.restingHr {
                        metricPill("RHR", String(format: "%.0f bpm", hr),
                                   hr <= 55 ? .green : (hr <= 65 ? .orange : .red))
                    }
                    if let s = entry.soreness {
                        metricPill("Courbatures", String(format: "%.0f/10", s),
                                   s <= 3 ? .green : (s <= 6 ? .orange : .red))
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .glassCard(color: scoreColor, intensity: 0.06)
        .cornerRadius(14)
    }

    private func metricPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - HRV Chart

struct HRVChart: View {
    let entries: [RecoveryEntry]
    var maxHRV: Double { max(entries.compactMap(\.hrv).max() ?? 1, 80) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HRV — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let hrv   = e.hrv ?? 0
                    let pct   = maxHRV > 0 ? hrv / maxHRV : 0
                    let color: Color = hrv >= 50 ? .green : (hrv >= 30 ? .orange : .red)
                    VStack(spacing: 2) {
                        if hrv > 0 {
                            Text(String(format: "%.0f", hrv))
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hrv > 0 ? color.opacity(i == entries.count - 1 ? 1 : 0.55) : Color.clear)
                            .frame(height: max(hrv > 0 ? CGFloat(pct) * 60 : 0, hrv > 0 ? 2 : 0))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            HStack(spacing: 12) {
                legendDot(.green,  "≥50 ms")
                legendDot(.orange, "30-50 ms")
                legendDot(.red,    "<30 ms")
            }
        }
        .padding(16).glassCard(color: .green, intensity: 0.05).cornerRadius(14)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }
}

// MARK: - RHR Chart

struct RHRChart: View {
    let entries: [RecoveryEntry]
    // Inverted: lower RHR = better. Display as distance from ceiling (85 bpm).
    private let ceiling: Double = 85

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FC REPOS — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let hr    = e.restingHr ?? 0
                    // Normalize: bar height = how LOW the HR is (good = tall bar)
                    let pct   = hr > 0 ? max(0, (ceiling - hr) / (ceiling - 35)) : 0
                    let color: Color = hr > 0 ? (hr <= 55 ? .green : (hr <= 65 ? .orange : .red)) : .clear
                    VStack(spacing: 2) {
                        if hr > 0 {
                            Text(String(format: "%.0f", hr))
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hr > 0 ? color.opacity(i == entries.count - 1 ? 1 : 0.55) : Color.clear)
                            .frame(height: max(hr > 0 ? CGFloat(pct) * 60 : 0, hr > 0 ? 2 : 0))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            HStack(spacing: 12) {
                legendDot(.green,  "≤55 bpm")
                legendDot(.orange, "55-65 bpm")
                legendDot(.red,    ">65 bpm")
                Spacer()
                Text("Barre haute = FC basse = mieux")
                    .font(.system(size: 8)).foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(16).glassCard(color: .red, intensity: 0.04).cornerRadius(14)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }
}

// MARK: - Sleep Chart
struct SleepChart: View {
    let entries: [RecoveryEntry]
    var maxH: Double { max(entries.compactMap(\.sleepHours).max() ?? 1, 9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOMMEIL — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let h = e.sleepHours ?? 0
                    let pct = maxH > 0 ? h / maxH : 0
                    let color: Color = h >= 7 ? .indigo : (h >= 5 ? .orange : .red)
                    VStack(spacing: 2) {
                        if h > 0 {
                            Text(String(format: "%.0fh", h))
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(i == entries.count - 1 ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.indigo).frame(width: 6, height: 6)
                    Text("≥7h").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("5-7h").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("<5h").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .indigo, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Steps Chart
struct StepsChart: View {
    let entries: [RecoveryEntry]
    var maxSteps: Double { max(entries.compactMap(\.steps).map(Double.init).max() ?? 1, 10_000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAS — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let steps = Double(e.steps ?? 0)
                    let pct   = maxSteps > 0 ? steps / maxSteps : 0
                    let color: Color = steps >= 10_000 ? .green : (steps >= 7_000 ? .orange : .red)
                    VStack(spacing: 2) {
                        if steps > 0 {
                            Text(steps >= 1000 ? String(format: "%.0fk", steps / 1000) : "\(Int(steps))")
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(i == entries.count - 1 ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("≥10k").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("7k-10k").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("<7k").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .green, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Empty State
struct RecoveryEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "moon.zzz.fill", title: "Aucune donnée de récupération", subtitle: "Appuie sur + pour en ajouter une")
    }
}

// MARK: - Log Sheet
struct LogRecoverySheet: View {
    var prefillEntry: RecoveryEntry? = nil
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hk = HealthKitService.shared

    @State private var selectedDate = Date()
    @State private var sleepHoursStr = ""
    @State private var sleepQuality: Double = 7
    @State private var restingHrStr = ""
    @State private var hrvStr = ""
    @State private var stepsStr = ""
    @State private var activeEnergyStr = ""
    @State private var soreness: Double = 0
    @State private var notes = ""
    @State private var isSaving = false
    @State private var isLoadingHK = false
    @State private var apiError: String? = nil

    private var isEditing: Bool { prefillEntry != nil }

    private var dateStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {

                        // Date picker
                        DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(14).background(Color(hex: "11111c")).cornerRadius(12)

                        // HealthKit auto-fill button
                        Button(action: fillFromHealthKit) {
                            HStack(spacing: 8) {
                                if isLoadingHK {
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.system(size: 15))
                                }
                                Text(isLoadingHK ? "Lecture Health..." : "Remplir depuis Apple Santé")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(12)
                        }
                        .disabled(isLoadingHK)
                        .buttonStyle(SpringButtonStyle())

                        // Sleep
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SOMMEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            HStack(spacing: 12) {
                                RecoveryField(label: "DURÉE (h)", placeholder: "7.5", text: $sleepHoursStr)
                                RecoveryField(label: "FC REPOS (bpm)", placeholder: "58", text: $restingHrStr)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("QUALITÉ").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    Spacer()
                                    Text(String(format: "%.0f / 10", sleepQuality))
                                        .font(.system(size: 13, weight: .bold)).foregroundColor(.indigo)
                                }
                                Slider(value: $sleepQuality, in: 1...10, step: 1)
                                    .tint(.indigo)
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(12)

                        // Douleurs musculaires
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("DOULEURS MUSCULAIRES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.0f / 10", soreness))
                                    .font(.system(size: 13, weight: .bold)).foregroundColor(sorenessColor(soreness))
                            }
                            Slider(value: $soreness, in: 0...10, step: 1)
                                .tint(sorenessColor(soreness))
                            HStack {
                                Text("0 = Aucune").font(.system(size: 9)).foregroundColor(.gray)
                                Spacer()
                                Text("10 = Sévère").font(.system(size: 9)).foregroundColor(.gray)
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(12)

                        // Activité
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ACTIVITÉ QUOTIDIENNE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            HStack(spacing: 12) {
                                RecoveryField(label: "PAS", placeholder: "8500", text: $stepsStr, keyboardType: .numberPad)
                                RecoveryField(label: "HRV (ms)", placeholder: "45", text: $hrvStr)
                            }
                            HStack(spacing: 12) {
                                RecoveryField(label: "ÉNERGIE ACTIVE (kcal)", placeholder: "350", text: $activeEnergyStr, keyboardType: .numberPad)
                                Spacer().frame(maxWidth: .infinity)
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(12)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Comment tu te sens...", text: $notes, axis: .vertical)
                                .lineLimit(3, reservesSpace: true)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }

                        Button(action: save) {
                            Group {
                                if isSaving { ProgressView().tint(.white) }
                                else { Text("Enregistrer").font(.system(size: 15, weight: .semibold)).foregroundColor(.white) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.indigo).cornerRadius(14)
                        .buttonStyle(SpringButtonStyle())
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Modifier la récupération" : "Récupération du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
            .onAppear { prefill() }
        }
    }

    private func prefill() {
        if let e = prefillEntry {
            if let h  = e.sleepHours    { sleepHoursStr    = String(format: "%.1f", h) }
            if let q  = e.sleepQuality  { sleepQuality     = q }
            if let hr = e.restingHr     { restingHrStr     = String(format: "%.0f", hr) }
            if let v  = e.hrv           { hrvStr           = String(format: "%.0f", v) }
            if let s  = e.steps         { stepsStr         = "\(s)" }
            if let ae = e.activeEnergy  { activeEnergyStr  = String(format: "%.0f", ae) }
            if let so = e.soreness      { soreness         = so }
            notes = e.notes ?? ""
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = e.date, let parsed = f.date(from: d) { selectedDate = parsed }
        } else {
            // Nouvelle entrée → auto-fill depuis HealthKit
            fillFromHealthKit()
        }
    }

    private func sorenessColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
    }

    private func fillFromHealthKit() {
        isLoadingHK = true
        let date = selectedDate
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isLoadingHK = false; return }

            async let sleep = hk.fetchSleep(for: date)
            async let hr    = hk.fetchRestingHR(for: date)
            async let hrv   = hk.fetchHRV(for: date)
            async let steps = hk.fetchSteps(for: date)
            async let ae    = hk.fetchActiveEnergy(for: date)

            let (s, h, v, st, a) = await (sleep, hr, hrv, steps, ae)

            if let s  { sleepHoursStr   = String(format: "%.1f", s) }
            if let h  { restingHrStr    = String(format: "%.0f", h) }
            if let v  { hrvStr          = String(format: "%.0f", v) }
            if let st { stepsStr        = "\(st)" }
            if let a  { activeEnergyStr = String(format: "%.0f", a) }

            isLoadingHK = false
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await APIService.shared.logRecovery(
                    sleepHours:   Double(sleepHoursStr.replacingOccurrences(of: ",", with: ".")),
                    sleepQuality: sleepQuality,
                    restingHr:    Double(restingHrStr),
                    hrv:          Double(hrvStr),
                    steps:        stepsStr.isEmpty ? nil : (Int(stepsStr) ?? Int(Double(stepsStr.replacingOccurrences(of: ",", with: ".")) ?? 0)),
                    soreness:     soreness,
                    activeEnergy: activeEnergyStr.isEmpty ? nil : Double(activeEnergyStr),
                    notes:        notes,
                    date:         dateStr
                )
                await onSaved()
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                apiError = "Erreur réseau — réessaie"
            }
        }
    }
}

struct RecoveryField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.white)
                .padding(10)
                .background(Color(hex: "191926"))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Watch Sync Banner
struct WatchSyncBannerView: View {
    @ObservedObject var sync: WatchSyncService
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch")
                .font(.system(size: 14))
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Watch")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                if sync.isSyncing {
                    Text("Synchronisation...")
                        .font(.system(size: 10)).foregroundColor(.cyan)
                } else if let last = sync.lastSyncDate {
                    Text("Dernière sync : \(last, style: .relative)")
                        .font(.system(size: 10)).foregroundColor(.gray)
                } else if let err = sync.lastError {
                    Text(err)
                        .font(.system(size: 10)).foregroundColor(.red)
                } else {
                    Text("Appuyer pour synchroniser")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
            }

            Spacer()

            Button(action: onSync) {
                Group {
                    if sync.isSyncing {
                        ProgressView().tint(.cyan).scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(.cyan)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(sync.isSyncing)
        }
        .padding(12)
        .background(Color.cyan.opacity(0.08))
        .cornerRadius(12)
    }
}
