import SwiftUI
import Combine

struct NutritionView: View {
    @State private var settings: NutritionSettings? = nil
    @State private var entries: [NutritionEntry] = []
    @State private var totals: NutritionTotals? = nil
    @State private var history: [NutritionDayHistory] = []
    @State private var isLoading = true
    @State private var showAdd = false


    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)
                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            MacroSummaryCard(totals: totals, settings: settings)
                                .padding(.horizontal, 16)

                            // 7-day history
                            if !history.isEmpty {
                                WeeklyCalorieChart(history: history, target: settings?.calories)
                                    .padding(.horizontal, 16)
                            }

                            // Today's entries
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AUJOURD'HUI")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)

                                if entries.isEmpty {
                                    Text("Aucun aliment enregistré")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                        .italic()
                                        .padding(.horizontal, 16)
                                } else {
                                    ForEach(entries) { entry in
                                        NutritionEntryRow(entry: entry) {
                                            Task { await deleteEntry(entry) }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }

                            Spacer(minLength: 80)
                        }
                        .padding(.vertical, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await loadData() } }) {
                        Image(systemName: "arrow.clockwise").foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddNutritionSheet { await loadData() }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAdd = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        let url = URL(string: "https://training-os-rho.vercel.app/api/nutrition_data")!
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = json["settings"] as? [String: Any] {
                settings = NutritionSettings(
                    calories: s["calories"] as? Double,
                    proteines: s["proteines"] as? Double,
                    glucides: s["glucides"] as? Double,
                    lipides: s["lipides"] as? Double
                )
            }
            if let t = json["totals"] as? [String: Any] {
                totals = NutritionTotals(
                    calories: t["calories"] as? Double,
                    proteines: t["proteines"] as? Double,
                    glucides: t["glucides"] as? Double,
                    lipides: t["lipides"] as? Double
                )
            }
            if let e = json["entries"] as? [[String: Any]] {
                entries = e.map { d in
                    NutritionEntry(
                        entryId: d["id"] as? String,
                        name: (d["nom"] as? String) ?? (d["name"] as? String),
                        calories: (d["calories"] as? Double) ?? (d["calories"] as? Int).map(Double.init),
                        proteines: d["proteines"] as? Double,
                        glucides: d["glucides"] as? Double,
                        lipides: d["lipides"] as? Double,
                        quantity: d["quantity"] as? Double,
                        unit: d["unit"] as? String,
                        time: (d["heure"] as? String) ?? (d["time"] as? String)
                    )
                }
            }
            if let h = json["history"] as? [[String: Any]] {
                history = h.compactMap { d in
                    guard let date = d["date"] as? String,
                          let cal = d["calories"] as? Double else { return nil }
                    return NutritionDayHistory(date: date, calories: cal)
                }
            }
        }
        isLoading = false
    }

    private func deleteEntry(_ entry: NutritionEntry) async {
        guard let eid = entry.entryId else { return }
        let url = URL(string: "https://training-os-rho.vercel.app/api/nutrition/delete")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": eid])
        _ = try? await URLSession.shared.data(for: req)
        await loadData()
    }
}

// MARK: - Weekly Calorie Chart
struct NutritionDayHistory: Identifiable {
    var id: String { date }
    let date: String
    let calories: Double
}

struct WeeklyCalorieChart: View {
    let history: [NutritionDayHistory]
    let target: Double?

    var maxCal: Double { max(history.map(\.calories).max() ?? 0, target ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(history) { day in
                    VStack(spacing: 4) {
                        let pct = day.calories / maxCal
                        let isToday = day.date == DateFormatter.isoDate.string(from: Date())
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isToday ? Color.orange : Color.orange.opacity(0.4))
                                    .frame(height: max(geo.size.height * pct, 4))
                            }
                        }
                        .frame(height: 60)
                        Text(shortDay(day.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                        Text("\(Int(day.calories))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isToday ? .orange : .gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let t = target {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.3)).frame(width: 20, height: 2)
                    Text("Objectif \(Int(t)) kcal")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }

    private func shortDay(_ date: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_CA"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: date) { f.dateFormat = "EEE"; return f.string(from: d).prefix(2).uppercased() }
        return date
    }
}

// MARK: - Macro Summary Card
struct MacroSummaryCard: View {
    let totals: NutritionTotals?
    let settings: NutritionSettings?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CALORIES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.gray)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(Int(totals?.calories ?? 0))")
                            .font(.system(size: 40, weight: .black))
                            .foregroundColor((totals?.calories ?? 0) > (settings?.calories ?? .infinity) ? .red : .orange)
                        if let target = settings?.calories {
                            Text("/ \(Int(target)) kcal")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                if let target = settings?.calories, target > 0 {
                    let pct = min((totals?.calories ?? 0) / target, 1.0)
                    let over = (totals?.calories ?? 0) > target
                    ZStack {
                        Circle().stroke(Color(hex: "191926"), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: pct)
                            .stroke(over ? Color.red : Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(over ? .red : .orange)
                    }
                    .frame(width: 60, height: 60)
                    .animation(.easeOut, value: pct)
                }
            }

            if let target = settings?.calories {
                let pct = min((totals?.calories ?? 0) / target, 1.0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "191926")).frame(height: 6)
                        Capsule()
                            .fill(pct > 1 ? Color.red : Color.orange)
                            .frame(width: geo.size.width * pct, height: 6)
                    }
                }
                .frame(height: 6)
                .animation(.easeOut, value: pct)
            }

            Divider().background(Color.white.opacity(0.07))

            HStack(spacing: 0) {
                MacroBar(label: "Prot", current: totals?.proteines ?? 0, target: settings?.proteines, color: .blue)
                Divider().background(Color.white.opacity(0.07)).frame(height: 40)
                MacroBar(label: "Carbs", current: totals?.glucides ?? 0, target: settings?.glucides, color: .yellow)
                Divider().background(Color.white.opacity(0.07)).frame(height: 40)
                MacroBar(label: "Lip", current: totals?.lipides ?? 0, target: settings?.lipides, color: .pink)
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}

struct MacroBar: View {
    let label: String
    let current: Double
    let target: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(Int(current))g")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            if let t = target {
                Text("/ \(Int(t))g")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "191926")).frame(height: 4)
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * min(current / t, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 8)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct NutritionEntryRow: View {
    let entry: NutritionEntry
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? "—")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    if let p = entry.proteines { Text("\(Int(p))g prot").font(.system(size: 11)).foregroundColor(.blue) }
                    if let c = entry.glucides  { Text("\(Int(c))g carbs").font(.system(size: 11)).foregroundColor(.yellow) }
                    if let l = entry.lipides   { Text("\(Int(l))g lip").font(.system(size: 11)).foregroundColor(.pink) }
                }
            }
            Spacer()
            Text("\(Int(entry.calories ?? 0)) kcal")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.orange)
            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.leading, 12)
            }
        }
        .padding(12)
        .background(Color(hex: "11111c"))
        .cornerRadius(10)
        .confirmationDialog("Supprimer \(entry.name ?? "cet aliment") ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }
}

struct AddNutritionSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var calories = ""
    @State private var proteines = ""
    @State private var glucides = ""
    @State private var lipides = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section("Aliment") {
                        TextField("Nom", text: $name).foregroundColor(.white)
                        TextField("Calories (kcal)", text: $calories).keyboardType(.decimalPad).foregroundColor(.white)
                    }.listRowBackground(Color(hex: "11111c"))

                    Section("Macros (g)") {
                        TextField("Protéines", text: $proteines).keyboardType(.decimalPad).foregroundColor(.white)
                        TextField("Glucides", text: $glucides).keyboardType(.decimalPad).foregroundColor(.white)
                        TextField("Lipides", text: $lipides).keyboardType(.decimalPad).foregroundColor(.white)
                    }.listRowBackground(Color(hex: "11111c"))
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .keyboardDismissable()
            }
            .navigationTitle("Ajouter aliment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ajouter") { save() }.foregroundColor(.orange).fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !name.isEmpty,
              let cal = Double(calories.replacingOccurrences(of: ",", with: ".")) else { return }
        let prot = Double(proteines.replacingOccurrences(of: ",", with: ".")) ?? 0
        let gluc = Double(glucides.replacingOccurrences(of: ",", with: ".")) ?? 0
        let lip  = Double(lipides.replacingOccurrences(of: ",", with: ".")) ?? 0
        Task {
            try? await APIService.shared.addNutritionEntry(
                name: name, calories: cal, proteines: prot, glucides: gluc, lipides: lip
            )
            await onSaved()
            dismiss()
        }
    }
}
