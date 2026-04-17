import SwiftUI
import Charts
#if os(iOS)
import HealthKit
#endif

struct CardioView: View {
    @EnvironmentObject private var appState: AppState
    @State private var log: [CardioEntry] = []
    @State private var isLoading = true
    @State private var showSheet = false
    @State private var isImportingHK = false
    @State private var apiError: String? = nil
    @State private var toast: ToastMessage? = nil
    @ObservedObject private var hk = HealthKitService.shared
    @AppStorage("cardio_max_hr") private var maxHR: Int = 190

    // KPIs
    var totalSessions: Int { log.count }
    var totalDistanceKm: Double { log.compactMap(\.distanceKm).reduce(0, +) }
    var avgRpe: Double {
        let r = log.compactMap(\.rpe); return r.isEmpty ? 0 : r.reduce(0, +) / Double(r.count)
    }
    var totalDurationMin: Double { log.compactMap(\.durationMin).reduce(0, +) }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .teal)
                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // KPI grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                KPICard(value: "\(totalSessions)",  label: "Sessions",   color: .teal)
                                KPICard(value: String(format: "%.1f km", totalDistanceKm), label: "Distance tot.", color: .blue)
                                KPICard(value: totalDurationMin > 0 ? String(format: "%.0f min", totalDurationMin) : "—",
                                        label: "Durée tot.", color: .orange)
                                KPICard(value: avgRpe > 0 ? String(format: "%.1f", avgRpe) : "—",
                                        label: "RPE moy.", color: .red)
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // Distance chart (last 8 sessions)
                            if log.filter({ $0.distanceKm != nil }).count >= 2 {
                                CardioDistanceChart(entries: Array(log.prefix(8).reversed()))
                                    .padding(.horizontal, 16)
                            }

                            // HR Zones
                            let hrEntries = log.compactMap(\.avgHr).filter { $0 > 0 }
                            if hrEntries.count >= 2 {
                                HRZonesCard(hrValues: hrEntries, maxHR: maxHR, onSetMaxHR: { maxHR = $0 })
                                    .padding(.horizontal, 16)
                            }

                            // Progression cardio
                            if let prog = cardioProgression {
                                CardioProgressionCard(suggestion: prog)
                                    .padding(.horizontal, 16)
                            }

                            // Session list
                            if log.isEmpty {
                                CardioEmptyState()
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("HISTORIQUE")
                                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        .padding(.horizontal, 16)
                                    ForEach(log) { entry in
                                        CardioRow(entry: entry, onDelete: {
                                            Task {
                                                do {
                                                    try await APIService.shared.deleteCardio(
                                                        date: entry.date ?? "", type: entry.type ?? ""
                                                    )
                                                    await MainActor.run { toast = ToastMessage(message: "Séance supprimée", style: .success) }
                                                } catch {
                                                    await MainActor.run { apiError = "Erreur réseau — réessaie" }
                                                }
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
                        .padding(.bottom, contentBottomPadding)
                    }
                }
            }
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: importFromHealthKit) {
                        HStack(spacing: 4) {
                            if isImportingHK {
                                ProgressView().tint(.orange).scaleEffect(0.7)
                            } else {
                                Image(systemName: "heart.text.square")
                                    .font(.system(size: 14))
                            }
                            Text("Santé")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.orange)
                    }
                    .disabled(isImportingHK)
                }
            }
            .sheet(isPresented: $showSheet) {
                LogCardioSheet(onSaved: { await loadData() })
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showSheet = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding + 16)
            }
        }
        .task { await loadData() }
        .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(apiError ?? "") }
        .toast($toast)
    }

    private func loadData() async {
        isLoading = true
        log = (try? await APIService.shared.fetchCardioData()) ?? []
        isLoading = false
    }

    // Progression cardio: compare last 2 sessions of the most common type
    struct CardioProg { let type: String; let msg: String }

    var cardioProgression: CardioProg? {
        guard log.count >= 2 else { return nil }
        let types = Dictionary(grouping: log.compactMap(\.type), by: { $0 })
        guard let topType = types.max(by: { $0.value.count < $1.value.count })?.key else { return nil }
        let same = log.filter { $0.type == topType }
        guard same.count >= 2 else { return nil }
        let cur = same[0]; let prev = same[1]

        // Distance progression
        if let cd = cur.distanceKm, let pd = prev.distanceKm, pd > 0 {
            let pct = (cd - pd) / pd * 100
            if pct > 0 {
                let target = round((cd + 0.5) * 10) / 10
                return CardioProg(type: topType, msg: "+\(String(format: "%.0f", pct))% distance. Vise \(String(format: "%.1f", target)) km la prochaine fois.")
            }
        }
        // Duration progression
        if let cd = cur.durationMin, let pd = prev.durationMin, pd > 0 {
            let diff = cd - pd
            if diff < 5 {
                return CardioProg(type: topType, msg: "Vise \(Int(cd) + 5) min la prochaine fois (+5 min).")
            }
        }
        return nil
    }

    private func importFromHealthKit() {
        isImportingHK = true
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isImportingHK = false; return }

            let workouts = await hk.fetchAllWorkouts(days: 30)
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let existing = Set(log.compactMap { e -> String? in
                guard let d = e.date, let t = e.type else { return nil }
                return "\(d)|\(t)"
            })

            for w in workouts {
                let entry = hk.workoutToCardioEntry(w)
                let dateStr = fmt.string(from: w.startDate)
                let key = "\(dateStr)|\(entry.type)"
                guard !existing.contains(key) else { continue }

                // Compute pace (min/km)
                var pace: String? = nil
                if let dist = entry.distanceKm, dist > 0 {
                    let secPerKm = w.duration / dist
                    let min = Int(secPerKm / 60)
                    let sec = Int(secPerKm.truncatingRemainder(dividingBy: 60))
                    pace = String(format: "%d:%02d", min, sec)
                }

                try? await APIService.shared.logCardio(
                    type: entry.type,
                    durationMin: entry.durationMin,
                    distanceKm: entry.distanceKm,
                    avgPace: pace,
                    avgHr: entry.avgHr,
                    cadence: nil,
                    calories: entry.calories,
                    rpe: nil,
                    notes: "Importé depuis Apple Santé"
                )
            }

            await loadData()
            isImportingHK = false
        }
    }
}

// MARK: - HR Zones Card
struct HRZonesCard: View {
    let hrValues: [Double]
    let maxHR: Int
    var onSetMaxHR: (Int) -> Void
    @State private var showMaxHRInput = false
    @State private var maxHRStr = ""

    private let zones: [(name: String, min: Double, max: Double, color: Color)] = [
        ("Z1 Récup.",   0.50, 0.60, .blue),
        ("Z2 Aérobie",  0.60, 0.70, .green),
        ("Z3 Seuil",    0.70, 0.80, .yellow),
        ("Z4 Anaéro.", 0.80, 0.90, .orange),
        ("Z5 VO2max",  0.90, 1.00, .red)
    ]

    private func zoneCounts() -> [Int] {
        let mhr = Double(maxHR)
        var counts = [0, 0, 0, 0, 0]
        for hr in hrValues {
            let pct = hr / mhr
            let idx = zones.firstIndex { pct >= $0.min && pct < $0.max } ?? (pct >= 0.9 ? 4 : 0)
            counts[idx] += 1
        }
        return counts
    }

    var body: some View {
        let counts = zoneCounts()
        let total = max(hrValues.count, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ZONES CARDIO")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Button("FCmax \(maxHR)") {
                    maxHRStr = "\(maxHR)"
                    showMaxHRInput = true
                }
                .font(.system(size: 11)).foregroundColor(.teal)
            }
            VStack(spacing: 5) {
                ForEach(zones.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text(zones[i].name)
                            .font(.system(size: 11)).foregroundColor(.gray).frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(zones[i].color.opacity(0.3))
                                .frame(height: 14)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(zones[i].color)
                                        .frame(width: geo.size.width * Double(counts[i]) / Double(total), height: 14)
                                }
                        }
                        .frame(height: 14)
                        Text("\(Int(Double(counts[i]) / Double(total) * 100))%")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(zones[i].color)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            Text("Basé sur \(hrValues.count) session(s) avec FC")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(14).glassCard().cornerRadius(14)
        .alert("FC maximale", isPresented: $showMaxHRInput) {
            TextField("Ex: 190", text: $maxHRStr).keyboardType(.numberPad)
            Button("OK") { if let v = Int(maxHRStr), v > 100 { onSetMaxHR(v) } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Utilise 220 − ton âge ou une mesure réelle.") }
    }
}

// MARK: - Cardio Progression Card
struct CardioProgressionCard: View {
    let suggestion: CardioView.CardioProg
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).foregroundColor(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("PROGRESSION — \(suggestion.type.uppercased())")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                Text(suggestion.msg)
                    .font(.system(size: 13)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(12).background(Color.teal.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Row
struct CardioRow: View {
    let entry: CardioEntry
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: typeIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(typeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(typeLabel)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(entry.date ?? "")
                    .font(.system(size: 11)).foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let d = entry.distanceKm {
                    Text(String(format: "%.2f km", d))
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.teal)
                }
                HStack(spacing: 6) {
                    if let dur = entry.durationMin {
                        Label(String(format: "%.0f min", dur), systemImage: "clock")
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }
                    if let pace = entry.avgPace {
                        Label(pace + "/km", systemImage: "speedometer")
                            .font(.system(size: 11)).foregroundColor(.blue)
                    }
                }
                HStack(spacing: 6) {
                    if let cad = entry.cadence {
                        Label(String(format: "%.0f spm", cad), systemImage: "metronome")
                            .font(.system(size: 11)).foregroundColor(.orange)
                    }
                    if let cal = entry.calories {
                        Label(String(format: "%.0f kcal", cal), systemImage: "flame.fill")
                            .font(.system(size: 11)).foregroundColor(.red)
                    }
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
        .confirmationDialog("Supprimer cette séance ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    var typeColor: Color {
        switch entry.type {
        case "course":    return .teal
        case "vélo":      return .yellow
        case "natation":  return .blue
        case "marche":    return .green
        case "elliptique":return .purple
        default:          return .orange
        }
    }

    var typeIcon: String {
        switch entry.type {
        case "course":    return "figure.run"
        case "vélo":      return "figure.outdoor.cycle"
        case "natation":  return "figure.pool.swim"
        case "marche":    return "figure.walk"
        case "elliptique":return "figure.elliptical"
        default:          return "heart.fill"
        }
    }

    var typeLabel: String { entry.type?.capitalized ?? "—" }
}

// MARK: - Distance Chart
struct CardioDistanceChart: View {
    let entries: [CardioEntry]
    var maxDist: Double { entries.compactMap(\.distanceKm).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISTANCE — DERNIÈRES SÉANCES")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let dist = e.distanceKm ?? 0
                    let pct = maxDist > 0 ? dist / maxDist : 0
                    let isLast = i == entries.count - 1
                    VStack(spacing: 2) {
                        if dist > 0 {
                            Text(String(format: "%.1f", dist))
                                .font(.system(size: 7)).foregroundColor(.teal.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? Color.teal : Color.teal.opacity(0.4))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
        }
        .padding(16).glassCard(color: .teal, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Empty State
struct CardioEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "figure.run", title: "Aucune séance cardio", subtitle: "Appuie sur + pour en ajouter une")
    }
}

// MARK: - Log Sheet
struct LogCardioSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    private let types = ["course", "vélo", "natation", "marche", "elliptique", "autre"]
    @State private var selectedType = "course"
    @State private var durationStr = ""
    @State private var distanceStr = ""
    @State private var paceStr = ""
    @State private var hrStr = ""
    @State private var caloriesStr = ""
    @State private var rpeValue: Double = 6
    @State private var notes = ""
    @State private var isSaving = false
    @State private var apiError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        // Type picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(types, id: \.self) { t in
                                        Button(action: { selectedType = t }) {
                                            Text(t.capitalized)
                                                .font(.system(size: 13, weight: .medium))
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(selectedType == t ? Color.teal : Color(hex: "191926"))
                                                .foregroundColor(selectedType == t ? .white : .gray)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                            }
                        }

                        // Fields grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            CardioField(label: "DURÉE (min)", placeholder: "30", text: $durationStr)
                            CardioField(label: "DISTANCE (km)", placeholder: "5.0", text: $distanceStr)
                            CardioField(label: "ALLURE (min/km)", placeholder: "5:30", text: $paceStr, keyboardType: .default)
                            CardioField(label: "FC MOY (bpm)", placeholder: "145", text: $hrStr)
                            CardioField(label: "CALORIES", placeholder: "350", text: $caloriesStr)
                        }

                        // RPE
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("RPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.0f / 10", rpeValue))
                                    .font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
                            }
                            Slider(value: $rpeValue, in: 1...10, step: 0.5).tint(.orange)
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Commentaire...", text: $notes, axis: .vertical)
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
                        .background(Color.teal).cornerRadius(14)
                        .buttonStyle(SpringButtonStyle())
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Nouvelle séance cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await APIService.shared.logCardio(
                    type:        selectedType,
                    durationMin: Double(durationStr.replacingOccurrences(of: ",", with: ".")),
                    distanceKm:  Double(distanceStr.replacingOccurrences(of: ",", with: ".")),
                    avgPace:     paceStr.isEmpty ? nil : paceStr,
                    avgHr:       Double(hrStr),
                    cadence:     nil,
                    calories:    Double(caloriesStr.replacingOccurrences(of: ",", with: ".")),
                    rpe:         rpeValue,
                    notes:       notes
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

struct CardioField: View {
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
    }
}
