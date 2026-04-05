import SwiftUI
import Combine

struct NutritionView: View {
    @State private var settings: NutritionSettings? = nil
    @State private var entries: [NutritionEntry] = []
    @State private var totals: NutritionTotals? = nil
    @State private var history: [NutritionDayHistory] = []
    @State private var isLoading = true
    @State private var showAdd = false
    @State private var editTarget: NutritionEntry? = nil
    @State private var showSettings = false
    @AppStorage("special_session_logged_date") private var specialSessionDate: String = ""

    private var workoutBonusActive: Bool {
        specialSessionDate == DateFormatter.isoDate.string(from: Date())
    }

    private var effectiveSettings: NutritionSettings? {
        guard let s = settings else { return nil }
        guard workoutBonusActive else { return s }
        return NutritionSettings(calories: (s.calories ?? 2200) + 300,
                                 proteines: s.proteines,
                                 glucides: s.glucides,
                                 lipides: s.lipides)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)
                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Hero protéines
                            ProteinProgressCard(
                                current: totals?.proteines ?? 0,
                                target: settings?.proteines ?? 160
                            )
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            if workoutBonusActive {
                                WorkoutBonusBadge()
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.08)
                            }

                            // Résumé calories + macros
                            MacroSummaryCard(totals: totals, settings: effectiveSettings)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.1)

                            DailyRemainingCard(totals: totals, settings: effectiveSettings)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.13)

                            // Historique protéines 7j
                            if !history.isEmpty {
                                WeeklyProteinChart(history: history, target: settings?.proteines ?? 160)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.15)
                            }

                            // Historique calories 7j
                            if !history.isEmpty {
                                WeeklyCalorieChart(history: history, target: settings?.calories)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.2)
                            }

                            if !history.isEmpty {
                                AdherenceScoreCard(history: history, settings: settings)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.22)
                            }

                            // Entrées du jour
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
                                        NutritionEntryRow(
                                            entry: entry,
                                            onEdit: { editTarget = entry },
                                            onDelete: { Task { await deleteEntry(entry) } }
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                            .appearAnimation(delay: 0.25)

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
                    HStack(spacing: 16) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape").foregroundColor(.orange)
                        }
                        Button(action: { Task { await loadData() } }) {
                            Image(systemName: "arrow.clockwise").foregroundColor(.orange)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddNutritionSheet {
                    await loadData()
                    await AlertService.shared.fetch()
                }
            }
            .sheet(item: $editTarget) { entry in
                EditNutritionSheet(entry: entry) { await loadData() }
            }
            .sheet(isPresented: $showSettings) {
                NutritionSettingsSheet(settings: settings) { await loadData(silent: true) }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAdd = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
        }
        .task { await loadData() }
    }

    private func loadData(silent: Bool = false) async {
        if !silent { isLoading = true }
        let url = URL(string: "https://training-os-rho.vercel.app/api/nutrition_data")!
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = json["settings"] as? [String: Any] {
                settings = NutritionSettings(
                    calories: s["limite_calories"] as? Double ?? (s["calories"] as? Double),
                    proteines: s["objectif_proteines"] as? Double ?? (s["proteines"] as? Double),
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
                        time: (d["heure"] as? String) ?? (d["time"] as? String),
                        mealType: d["meal_type"] as? String
                    )
                }
            }
            if let h = json["history"] as? [[String: Any]] {
                history = h.compactMap { d in
                    guard let date = d["date"] as? String,
                          let cal = d["calories"] as? Double else { return nil }
                    let prot = (d["proteines"] as? Double) ?? 0
                    return NutritionDayHistory(date: date, calories: cal, proteines: prot)
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

// MARK: - Protein Progress Card

struct ProteinProgressCard: View {
    let current: Double
    let target: Double

    private var pct: Double { min(current / max(target, 1), 1.0) }
    private var remaining: Double { max(target - current, 0) }
    private var isReached: Bool { current >= target }
    private var isOver: Bool { current > target }

    private var ringColor: Color {
        if isOver { return .red }
        if isReached { return .green }
        return .blue
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("PROTÉINES DU JOUR")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                Text("Objectif : \(Int(target))g")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 28) {
                // Grand anneau
                ZStack {
                    Circle()
                        .stroke(Color(hex: "191926"), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: pct)
                    VStack(spacing: 0) {
                        Text("\(Int(current))")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(.white)
                        Text("g")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 12) {
                    // Message statut
                    if isOver {
                        Label("Dépassé de \(Int(current - target))g", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                    } else if isReached {
                        Label("Objectif atteint !", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Encore")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("\(Int(remaining))g")
                                .font(.system(size: 32, weight: .black))
                                .foregroundColor(.blue)
                            Text("à atteindre")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }

                    // Barre de progression
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: "191926")).frame(height: 6)
                                Capsule()
                                    .fill(ringColor)
                                    .frame(width: geo.size.width * pct, height: 6)
                                    .animation(.easeOut(duration: 0.6), value: pct)
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(pct * 100))% de l'objectif")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}

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
                .foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(history) { day in
                    let pct = day.proteines / maxProt
                    let isToday = day.date == DateFormatter.isoDate.string(from: Date())
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isToday ? Color.blue : Color.blue.opacity(0.4))
                                    .frame(height: max(geo.size.height * pct, 4))
                            }
                        }
                        .frame(height: 60)
                        Text(shortDay(day.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                        Text("\(Int(day.proteines))g")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isToday ? .blue : .gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.3)).frame(width: 20, height: 2)
                Text("Objectif \(Int(target))g prot")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
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

// MARK: - Weekly Calorie Chart

struct NutritionDayHistory: Identifiable {
    var id: String { date }
    let date: String
    let calories: Double
    let proteines: Double
}

struct WeeklyCalorieChart: View {
    let history: [NutritionDayHistory]
    let target: Double?

    var maxCal: Double { max(history.map(\.calories).max() ?? 0, target ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CALORIES — 7 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(history) { day in
                    let pct = day.calories / maxCal
                    let isToday = day.date == DateFormatter.isoDate.string(from: Date())
                    VStack(spacing: 4) {
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

// MARK: - Entry Row

struct NutritionEntryRow: View {
    let entry: NutritionEntry
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack {
            Group {
                if let mt = entry.mealType {
                    Image(systemName: mealTypeIcon(mt))
                        .font(.system(size: 12))
                        .foregroundColor(mealTypeColor(mt))
                } else {
                    Color.clear
                }
            }
            .frame(width: 18)
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
            if let onEdit {
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.orange.opacity(0.8))
                        .padding(.leading, 12)
                }
            }
            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.leading, 8)
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

    private func mealTypeIcon(_ type: String) -> String {
        switch type {
        case "matin":     return "sunrise.fill"
        case "midi":      return "sun.max.fill"
        case "soir":      return "moon.fill"
        case "collation": return "leaf.fill"
        default:          return "fork.knife"
        }
    }

    private func mealTypeColor(_ type: String) -> Color {
        switch type {
        case "matin":     return .yellow
        case "midi":      return .orange
        case "soir":      return .purple
        case "collation": return .green
        default:          return .gray
        }
    }
}

// MARK: - Add Nutrition Sheet

struct AddNutritionSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var catalog: [FoodItem] = FoodCatalogStore.load()
    @State private var selected: FoodItem? = nil
    @State private var quantity = ""
    @State private var manualMode = false
    @State private var showCatalog = false
    @State private var isSaving = false

    @State private var mealType: String = {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<10:  return "matin"
        case 10..<14: return "midi"
        case 14..<20: return "soir"
        default:      return "collation"
        }
    }()

    // Champs mode manuel
    @State private var manName = ""
    @State private var manCal = ""
    @State private var manProt = ""
    @State private var manGluc = ""
    @State private var manLip = ""

    private func p(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private func fmtN(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private var preview: (cal: Double, prot: Double, gluc: Double, lip: Double)? {
        guard let item = selected, let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let m = item.macros(for: qty)
        return m
    }

    private var canSave: Bool {
        if manualMode { return !manName.isEmpty && !manCal.isEmpty }
        return selected != nil && !quantity.isEmpty && p(quantity) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section("REPAS") {
                        Picker("", selection: $mealType) {
                            Text("Matin").tag("matin")
                            Text("Midi").tag("midi")
                            Text("Soir").tag("soir")
                            Text("Collation").tag("collation")
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    if !manualMode {
                        // ── Chips catalogue ─────────────────────────────
                        Section(header: HStack {
                            Text("CATALOGUE")
                            Spacer()
                            Button {
                                showCatalog = true
                            } label: {
                                Label("Gérer", systemImage: "slider.horizontal.3")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                        }) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(catalog) { item in
                                        let isSel = selected?.id == item.id
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selected = item
                                                quantity = ""
                                            }
                                        } label: {
                                            Text(item.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .padding(.horizontal, 12).padding(.vertical, 7)
                                                .background(isSel ? Color.blue.opacity(0.35) : Color.blue.opacity(0.12))
                                                .foregroundColor(isSel ? .white : .blue)
                                                .cornerRadius(20)
                                                .overlay(RoundedRectangle(cornerRadius: 20)
                                                    .stroke(isSel ? Color.blue : Color.blue.opacity(0.25),
                                                            lineWidth: isSel ? 1.5 : 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                            // ── Quantité inline (apparaît dès la sélection) ──
                            if let item = selected {
                                VStack(spacing: 8) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "scalemass.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(.blue.opacity(0.7))
                                        TextField("Quantité", text: $quantity)
                                            .keyboardType(.decimalPad)
                                            .foregroundColor(.white)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text(item.refUnit)
                                            .foregroundColor(.gray)
                                            .font(.system(size: 14))
                                    }
                                    Text("Réf : \(fmtN(item.refQty)) \(item.refUnit) = \(Int(item.calories)) kcal")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let m = preview {
                                        HStack(spacing: 0) {
                                            MacroPreviewPill(value: m.cal,  label: "kcal",    color: .orange)
                                            MacroPreviewPill(value: m.prot, label: "g prot",  color: .blue)
                                            MacroPreviewPill(value: m.gluc, label: "g carbs", color: .yellow)
                                            MacroPreviewPill(value: m.lip,  label: "g lip",   color: .pink)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .listRowBackground(Color(hex: "11111c"))

                        // ── Switch mode manuel ─────────────────────────
                        Section {
                            Button {
                                withAnimation { manualMode = true }
                            } label: {
                                Label("Entrée manuelle", systemImage: "pencil")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color(hex: "11111c"))

                    } else {
                        // ── Mode manuel ────────────────────────────────
                        Section("ALIMENT") {
                            TextField("Nom", text: $manName).foregroundColor(.white)
                            HStack {
                                TextField("Calories (kcal)", text: $manCal).keyboardType(.decimalPad).foregroundColor(.white)
                                Text("kcal").foregroundColor(.gray).font(.system(size: 13))
                            }
                        }.listRowBackground(Color(hex: "11111c"))

                        Section("MACROS (g) — optionnel") {
                            TextField("Protéines", text: $manProt).keyboardType(.decimalPad).foregroundColor(.white)
                            TextField("Glucides",  text: $manGluc).keyboardType(.decimalPad).foregroundColor(.white)
                            TextField("Lipides",   text: $manLip).keyboardType(.decimalPad).foregroundColor(.white)
                        }.listRowBackground(Color(hex: "11111c"))

                        Section {
                            Button {
                                withAnimation { manualMode = false; manName = ""; manCal = "" }
                            } label: {
                                Label("Retour au catalogue", systemImage: "list.bullet")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color(hex: "11111c"))
                    }

                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Ajouter aliment")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ajouter") { save() }
                        .foregroundColor(.orange).fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showCatalog, onDismiss: {
                catalog = FoodCatalogStore.load()
            }) {
                FoodCatalogView(items: $catalog)
            }
            .task {
                let remote = await APIService.shared.fetchFoodCatalog()
                if !remote.isEmpty {
                    catalog = remote
                    FoodCatalogStore.save(remote)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        Task {
            isSaving = true
            if manualMode {
                guard !manName.isEmpty, let cal = Double(manCal.replacingOccurrences(of: ",", with: ".")) else { isSaving = false; return }
                try? await APIService.shared.addNutritionEntry(
                    name: manName, calories: cal,
                    proteines: p(manProt), glucides: p(manGluc), lipides: p(manLip),
                    mealType: mealType
                )
            } else {
                guard let item = selected, let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")) else { isSaving = false; return }
                let m = item.macros(for: qty)
                try? await APIService.shared.addNutritionEntry(
                    name: item.name, calories: m.cal,
                    proteines: m.prot, glucides: m.gluc, lipides: m.lip,
                    mealType: mealType
                )
            }
            await onSaved()
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Edit Nutrition Sheet
struct EditNutritionSheet: View {
    let entry: NutritionEntry
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var calories: String
    @State private var proteines: String
    @State private var glucides: String
    @State private var lipides: String
    @State private var isSaving = false

    init(entry: NutritionEntry, onSaved: @escaping () async -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        _name      = State(initialValue: entry.name ?? "")
        _calories  = State(initialValue: entry.calories.map { String(Int($0)) } ?? "")
        _proteines = State(initialValue: entry.proteines.map { String(format: "%.1f", $0) } ?? "")
        _glucides  = State(initialValue: entry.glucides.map { String(format: "%.1f", $0) } ?? "")
        _lipides   = State(initialValue: entry.lipides.map { String(format: "%.1f", $0) } ?? "")
    }

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
                        TextField("Glucides",  text: $glucides).keyboardType(.decimalPad).foregroundColor(.white)
                        TextField("Lipides",   text: $lipides).keyboardType(.decimalPad).foregroundColor(.white)
                    }.listRowBackground(Color(hex: "11111c"))
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") { Task { await save() } }
                        .foregroundColor(.orange).fontWeight(.semibold)
                        .disabled(name.isEmpty || calories.isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        guard let eid = entry.entryId,
              let cal = Double(calories.replacingOccurrences(of: ",", with: ".")) else { return }
        isSaving = true
        var body: [String: Any] = ["id": eid, "nom": name, "calories": cal]
        if let v = Double(proteines.replacingOccurrences(of: ",", with: ".")) { body["proteines"] = v }
        if let v = Double(glucides.replacingOccurrences(of: ",", with: "."))  { body["glucides"]  = v }
        if let v = Double(lipides.replacingOccurrences(of: ",", with: "."))   { body["lipides"]   = v }
        let url = URL(string: "https://training-os-rho.vercel.app/api/nutrition/edit")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
        await onSaved()
        isSaving = false
        dismiss()
    }
}

private struct MacroPreviewPill: View {
    let value: Double
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Workout Bonus Badge

struct WorkoutBonusBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
            Text("+300 kcal · Séance enregistrée aujourd'hui")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Daily Remaining Card

struct DailyRemainingCard: View {
    let totals: NutritionTotals?
    let settings: NutritionSettings?

    private var remainingCal: Double  { max((settings?.calories  ?? 2200) - (totals?.calories  ?? 0), 0) }
    private var remainingProt: Double { max((settings?.proteines ?? 160)  - (totals?.proteines ?? 0), 0) }
    private var allDone: Bool         { remainingCal <= 0 && remainingProt <= 0 }

    private var suggestion: (icon: String, text: String, color: Color) {
        if allDone           { return ("checkmark.seal.fill", "Objectifs atteints !", .green) }
        if remainingProt >= 40 { return ("fork.knife", "Repas complet protéiné", .blue) }
        if remainingProt >= 20 { return ("cup.and.saucer.fill", "Collation protéinée", .blue) }
        if remainingProt >= 5  { return ("takeoutbag.and.cup.and.straw.fill", "Shake ou skyr", .blue) }
        if remainingCal > 200  { return ("leaf.fill", "Légumes ou fruit", .green) }
        return ("checkmark.seal.fill", "Objectifs atteints !", .green)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("RESTE AUJOURD'HUI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
            }

            if allDone {
                Label("Objectifs atteints !", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 2) {
                        Text("\(Int(remainingCal))")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(.orange)
                        Text("kcal restantes")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)

                    let s = suggestion
                    HStack(spacing: 6) {
                        Image(systemName: s.icon).font(.system(size: 13)).foregroundColor(s.color)
                        Text(s.text).font(.system(size: 12, weight: .medium)).foregroundColor(s.color)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(s.color.opacity(0.1))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}

// MARK: - Adherence Score Card

struct AdherenceScoreCard: View {
    let history: [NutritionDayHistory]
    let settings: NutritionSettings?

    private var protTarget: Double { settings?.proteines ?? 160 }
    private var calTarget:  Double { settings?.calories  ?? 2200 }

    private var successDays: Int {
        history.filter { $0.proteines >= protTarget * 0.9 && $0.calories <= calTarget * 1.1 }.count
    }
    private var score: Int {
        history.isEmpty ? 0 : Int(Double(successDays) / Double(history.count) * 100)
    }
    private var badge: (text: String, color: Color) {
        if score >= 85 { return ("Super semaine", .green) }
        if score >= 60 { return ("En progression", .yellow) }
        return ("À améliorer", .red)
    }
    private var pct: Double { Double(score) / 100.0 }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("ADHÉRENCE 7 JOURS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
            }

            if history.count < 3 {
                Text("Pas encore assez de données · Revenez dans \(3 - history.count) jour(s)")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 24) {
                    ZStack {
                        Circle().stroke(Color(hex: "191926"), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: pct)
                            .stroke(badge.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.6), value: pct)
                        Text("\(score)%")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                    }
                    .frame(width: 90, height: 90)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(badge.text)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(badge.color)
                        Text("\(successDays)/\(history.count) jours dans les objectifs")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text("Prot ≥ 90% · Cal ≤ 110%")
                            .font(.system(size: 10))
                            .foregroundColor(Color.gray.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}

// MARK: - Nutrition Settings Sheet

struct NutritionSettingsSheet: View {
    let settings: NutritionSettings?
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var calories:  String
    @State private var proteines: String
    @State private var glucides:  String
    @State private var lipides:   String
    @State private var isSaving = false
    @State private var saveError: String? = nil

    init(settings: NutritionSettings?, onSaved: @escaping () async -> Void) {
        self.settings = settings
        self.onSaved  = onSaved
        let fmt = { (v: Double?) -> String in v.map { "\(Int($0))" } ?? "" }
        _calories  = State(initialValue: fmt(settings?.calories))
        _proteines = State(initialValue: fmt(settings?.proteines))
        _glucides  = State(initialValue: fmt(settings?.glucides))
        _lipides   = State(initialValue: fmt(settings?.lipides))
    }

    private var canSave: Bool {
        Double(calories) != nil && Double(proteines) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section("OBJECTIF CALORIQUE") {
                        HStack {
                            TextField("2200", text: $calories)
                                .keyboardType(.numberPad)
                                .foregroundColor(.white)
                            Text("kcal / jour").foregroundColor(.gray).font(.system(size: 13))
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("OBJECTIFS MACROS (g / jour)") {
                        HStack {
                            TextField("160", text: $proteines).keyboardType(.numberPad).foregroundColor(.white)
                            Text("g protéines").foregroundColor(.gray).font(.system(size: 13))
                        }
                        HStack {
                            TextField("0", text: $glucides).keyboardType(.numberPad).foregroundColor(.white)
                            Text("g glucides").foregroundColor(.gray).font(.system(size: 13))
                        }
                        HStack {
                            TextField("0", text: $lipides).keyboardType(.numberPad).foregroundColor(.white)
                            Text("g lipides").foregroundColor(.gray).font(.system(size: 13))
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Objectifs nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") { Task { await save() } }
                        .foregroundColor(.orange).fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .alert("Erreur de sauvegarde", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func save() async {
        guard let cal  = Double(calories),
              let prot = Double(proteines) else { return }
        isSaving = true
        saveError = nil
        do {
            try await APIService.shared.updateNutritionSettings(
                calories: cal, proteines: prot,
                glucides: Double(glucides) ?? 0,
                lipides:  Double(lipides)  ?? 0
            )
            await onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
