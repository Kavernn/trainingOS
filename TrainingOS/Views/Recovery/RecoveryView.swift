import SwiftUI

struct RecoveryView: View {
    @State private var log: [RecoveryEntry] = []
    @State private var isLoading = true
    @State private var showSheet = false

    private var todayStr: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
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

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .indigo)
                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // KPI grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                KPICard(value: avgSleep > 0 ? String(format: "%.1fh", avgSleep) : "—",
                                        label: "Sommeil moy.", color: .indigo)
                                KPICard(value: avgSleepQuality > 0 ? String(format: "%.1f/10", avgSleepQuality) : "—",
                                        label: "Qualité moy.", color: .purple)
                                KPICard(value: avgRestHR > 0 ? String(format: "%.0f bpm", avgRestHR) : "—",
                                        label: "FC repos moy.", color: .red)
                                KPICard(value: avgSteps > 0 ? String(format: "%.0f", avgSteps) : "—",
                                        label: "Pas moy./jour", color: .green)
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // Sleep chart
                            if log.filter({ $0.sleepHours != nil }).count >= 2 {
                                SleepChart(entries: Array(log.prefix(10).reversed()))
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
                                        RecoveryRow(entry: entry, onDelete: {
                                            Task {
                                                try? await APIService.shared.deleteRecovery(date: entry.date ?? "")
                                                await loadData()
                                            }
                                        })
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }

                            Spacer(minLength: 32)
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, 80)
                    }
                }
            }
            .navigationTitle("Récupération")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSheet) {
                LogRecoverySheet(onSaved: { await loadData() })
            }
            .overlay(alignment: .bottomTrailing) {
                if !alreadyLoggedToday {
                    FAB(icon: "plus") { showSheet = true }
                        .padding(.trailing, 20)
                        .padding(.bottom, fabBottomPadding + 16)
                }
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        log = (try? await APIService.shared.fetchRecoveryData()) ?? []
        isLoading = false
    }
}

// MARK: - Row
struct RecoveryRow: View {
    let entry: RecoveryEntry
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date ?? "")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
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
                        Label(String(format: "%.0f", hr), systemImage: "heart.fill")
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

// MARK: - Empty State
struct RecoveryEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40)).foregroundColor(.indigo.opacity(0.4))
            Text("Aucune donnée de récupération")
                .font(.system(size: 15, weight: .medium)).foregroundColor(.gray)
            Text("Appuie sur + pour en ajouter une")
                .font(.system(size: 13)).foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Log Sheet
struct LogRecoverySheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hk = HealthKitService.shared

    @State private var sleepHoursStr = ""
    @State private var sleepQuality: Double = 7
    @State private var restingHrStr = ""
    @State private var hrvStr = ""
    @State private var stepsStr = ""
    @State private var soreness: Double = 3
    @State private var notes = ""
    @State private var isSaving = false
    @State private var isLoadingHK = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {

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
                                RecoveryField(label: "PAS", placeholder: "8500", text: $stepsStr)
                                RecoveryField(label: "HRV (ms)", placeholder: "45", text: $hrvStr)
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
            }
            .navigationTitle("Récupération du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }

    private func sorenessColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
    }

    private func fillFromHealthKit() {
        isLoadingHK = true
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isLoadingHK = false; return }

            async let sleep    = hk.fetchLastNightSleep()
            async let hr       = hk.fetchLatestRestingHR()
            async let hrv      = hk.fetchLatestHRV()
            async let steps    = hk.fetchTodaySteps()

            let (s, h, v, st) = await (sleep, hr, hrv, steps)

            if let s { sleepHoursStr = String(format: "%.1f", s) }
            if let h { restingHrStr  = String(format: "%.0f", h) }
            if let v { hrvStr        = String(format: "%.0f", v) }
            if let st { stepsStr     = "\(st)" }

            isLoadingHK = false
        }
    }

    private func save() {
        isSaving = true
        Task {
            try? await APIService.shared.logRecovery(
                sleepHours:   Double(sleepHoursStr.replacingOccurrences(of: ",", with: ".")),
                sleepQuality: sleepQuality,
                restingHr:    Double(restingHrStr),
                hrv:          Double(hrvStr),
                steps:        Int(stepsStr),
                soreness:     soreness,
                notes:        notes
            )
            await onSaved()
            isSaving = false
            dismiss()
        }
    }
}

struct RecoveryField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .foregroundColor(.white)
                .padding(10)
                .background(Color(hex: "191926"))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
}
