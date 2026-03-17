import SwiftUI
import HealthKit

struct CardioView: View {
    @State private var log: [CardioEntry] = []
    @State private var isLoading = true
    @State private var showSheet = false
    @State private var isImportingHK = false
    @StateObject private var hk = HealthKitService.shared

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
                    ProgressView().tint(.orange).scaleEffect(1.3)
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
                                                try? await APIService.shared.deleteCardio(
                                                    date: entry.date ?? "", type: entry.type ?? ""
                                                )
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
    }

    private func loadData() async {
        isLoading = true
        log = (try? await APIService.shared.fetchCardioData()) ?? []
        isLoading = false
    }

    private func importFromHealthKit() {
        isImportingHK = true
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isImportingHK = false; return }

            let workouts = await hk.fetchRecentRunningWorkouts(days: 30)
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
                        Text(String(format: "%.0f min", dur))
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }
                    if let pace = entry.avgPace {
                        Text(pace + "/km")
                            .font(.system(size: 11)).foregroundColor(.gray)
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
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 40)).foregroundColor(.teal.opacity(0.4))
            Text("Aucune séance cardio")
                .font(.system(size: 15, weight: .medium)).foregroundColor(.gray)
            Text("Appuie sur + pour en ajouter une")
                .font(.system(size: 13)).foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
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
                .keyboardOkButton()
            }
            .navigationTitle("Nouvelle séance cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            try? await APIService.shared.logCardio(
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
