import SwiftUI

struct BodyCompView: View {
    @ObservedObject private var units = UnitSettings.shared
    @State private var bodyWeight: [BodyWeightEntry] = []
    @State private var profile: UserProfile? = nil
    @State private var tendance = ""
    @State private var isLoading = true
    @State private var sheetEntry: BodyWeightEntry? = nil
    @State private var showSheet = false
    @State private var projection: BodyProjectionData? = nil

    var latest: BodyWeightEntry? { bodyWeight.first }

    var entriesWithBF: [BodyWeightEntry] { bodyWeight.filter { $0.bodyFat != nil } }

    var latestWHR: Double? {
        guard let w = latest?.waistCm, let h = latest?.hipsCm, h > 0 else { return nil }
        return w / h
    }

    var hasMeasurements: Bool {
        guard let l = latest else { return false }
        return l.armsCm != nil || l.chestCm != nil || l.thighsCm != nil || l.hipsCm != nil || l.waistCm != nil || l.neckCm != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .statusGreen)
                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // 1 — Poids actuel + chips maigre/gras
                            currentWeightCard

                            // 2 — Courbe composition (masse maigre vs masse grasse)
                            if entriesWithBF.count >= 2 {
                                CompositionChartCard(
                                    entries: Array(entriesWithBF.prefix(30).reversed()),
                                    units: units
                                )
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.1)
                            }

                            // 3 — Ratio taille/hanches
                            if let whr = latestWHR {
                                WHRCard(
                                    ratio: whr,
                                    isMale: profile?.sex?.uppercased().hasPrefix("M") ?? true
                                )
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.15)
                            }

                            // 4 — Mensurations (barres + delta)
                            if hasMeasurements {
                                MeasurementsCard(entries: Array(bodyWeight.prefix(30)))
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.2)
                            }

                            // 5 — Tableau comparatif entre deux dates
                            if bodyWeight.count >= 2 {
                                ComparisonTableCard(entries: Array(bodyWeight.prefix(30)))
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.22)
                            }

                            // 6 — Courbe poids brut
                            if bodyWeight.count >= 2 {
                                WeightChartView(entries: Array(bodyWeight.prefix(20).reversed()))
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.25)
                            }

                            // 7 — Projection objectifs
                            if let proj = projection, !proj.projections.isEmpty {
                                BodyProjectionCard(projection: proj)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.28)
                            }

                            // 8 — Historique
                            historySection
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, contentBottomPadding)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Body Comp")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSheet, onDismiss: { sheetEntry = nil }) {
                BodyWeightSheet(editEntry: sheetEntry, onSaved: { await loadData() })
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: NavyCalculatorView()) {
                        Image(systemName: "ruler.fill")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(.teal)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { sheetEntry = nil; showSheet = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding + 16)
                    .appearAnimation(delay: 0.3)
            }
        }
        .task { await loadData() }
    }

    // MARK: - Current weight card
    private var currentWeightCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("POIDS ACTUEL")
                        .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                    if let w = latest?.weight {
                        Text(units.format(w))
                            .font(.system(size: 44, weight: .black))
                            .foregroundColor(Color.forge).glow(Color.forge)
                            .contentTransition(.numericText())
                    } else {
                        Text("— \(units.label)")
                            .font(.system(size: 44, weight: .black)).foregroundColor(.gray)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(tendance)
                        .font(.appBody.weight(.bold)).foregroundColor(tendanceColor)
                    if bodyWeight.count > 1 {
                        let diff = (latest?.weight ?? 0) - bodyWeight[1].weight
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: diff >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.appCaption.weight(.bold))
                                Text("\(diff >= 0 ? "+" : "")\(units.format(diff))")
                                    .font(.appCaption.weight(.semibold))
                            }
                            .foregroundColor(diff >= 0 ? Color.statusOrange.opacity(0.8) : Color.statusGreen.opacity(0.8))
                            Text("vs hier")
                                .font(.appMicro)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                }
            }

            // Masse maigre / masse grasse si body fat dispo
            if let bf = latest?.bodyFat, (3...60).contains(bf), let w = latest?.weight {
                let lean = w * (1 - bf / 100)
                let fat  = w * bf / 100
                HStack(spacing: 8) {
                    CompChip(label: "MASSE MAIGRE", value: units.format(lean), color: .statusGreen)
                    CompChip(label: "MASSE GRASSE", value: "\(units.format(fat)) · \(String(format: "%.1f", bf))%", color: .statusBlue)
                }
            }
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .appearAnimation(delay: 0.05)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORIQUE")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                .padding(.horizontal, 16)
            ForEach(bodyWeight.prefix(30)) { entry in
                BodyWeightRow(
                    entry: entry,
                    onEdit: { sheetEntry = entry; showSheet = true },
                    onDelete: {
                        Task {
                            try? await APIService.shared.deleteBodyWeight(date: entry.date, weight: entry.weight)
                            await loadData()
                        }
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        .appearAnimation(delay: 0.3)
    }

    var tendanceColor: Color {
        let t = tendance.lowercased()
        if t.contains("hausse") || t.contains("+") { return .statusOrange }
        if t.contains("baisse") || t.contains("↓") { return .statusGreen }
        return .gray
    }

    private func loadData() async {
        isLoading = true
        if let (p, bw, t) = try? await APIService.shared.fetchProfilData() {
            profile = p; bodyWeight = bw; tendance = t
        }
        // Load body projection asynchronously
        Task {
            guard let url = URL(string: "\(APIService.shared.baseURL)/api/body_projection"),
                  let (data, _) = try? await URLSession.authed.data(from: url),
                  let proj = try? APIService.decoder.decode(BodyProjectionData.self, from: data)
            else { return }
            await MainActor.run { projection = proj }
        }
        isLoading = false
    }
}

// MARK: - Comp Chip
struct CompChip: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.appMicro.weight(.black)).tracking(1)
                .foregroundColor(color.opacity(0.7))
            Text(value)
                .font(.appBody.weight(.bold)).foregroundColor(.appTextPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Composition Chart (masse maigre vs masse grasse)
struct CompositionChartCard: View {
    let entries: [BodyWeightEntry]   // chronologique, oldest first, all have bodyFat
    let units: UnitSettings

    private var leanSeries: [Double] { entries.compactMap { e in e.bodyFat.map { e.weight * (1 - $0 / 100) } } }
    private var fatSeries:  [Double] { entries.compactMap { e in e.bodyFat.map { e.weight * $0 / 100 } } }
    private var allValues:  [Double] { leanSeries + fatSeries }
    private var minVal: Double { (allValues.min() ?? 0) * 0.97 }
    private var maxVal: Double { (allValues.max() ?? 1) * 1.01 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COMPOSITION")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 12) {
                    LegendDot(color: .statusGreen, label: "Masse maigre")
                    LegendDot(color: .statusBlue,  label: "Masse grasse")
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let range = max(maxVal - minVal, 1.0)
                let n = entries.count
                let xPos: (Int) -> CGFloat = { i in n < 2 ? w / 2 : CGFloat(i) / CGFloat(n - 1) * w }
                let yPos: (Double) -> CGFloat = { val in h - CGFloat((val - minVal) / range) * h }

                ZStack {
                    // Grid
                    ForEach(0..<4, id: \.self) { i in
                        Path { p in
                            let y = h * CGFloat(i) / 3
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.appSurfaceInset, lineWidth: 1)
                    }

                    // Lean line + fill
                    if leanSeries.count > 1 {
                        Path { p in
                            for (i, v) in leanSeries.enumerated() {
                                let pt = CGPoint(x: xPos(i), y: yPos(v))
                                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                            }
                        }
                        .stroke(Color.statusGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        ForEach(leanSeries.indices, id: \.self) { i in
                            Circle().fill(Color.statusGreen).frame(width: 5, height: 5)
                                .position(x: xPos(i), y: yPos(leanSeries[i]))
                        }
                    }

                    // Fat line
                    if fatSeries.count > 1 {
                        Path { p in
                            for (i, v) in fatSeries.enumerated() {
                                let pt = CGPoint(x: xPos(i), y: yPos(v))
                                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                            }
                        }
                        .stroke(Color.statusBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        ForEach(fatSeries.indices, id: \.self) { i in
                            Circle().fill(Color.statusBlue).frame(width: 5, height: 5)
                                .position(x: xPos(i), y: yPos(fatSeries[i]))
                        }
                    }
                }
            }
            .frame(height: 150)

            // Valeurs actuelles
            if let last = entries.last, let bf = last.bodyFat {
                HStack {
                    Spacer()
                    Text("Maigre \(units.format(last.weight * (1 - bf/100)))")
                        .font(.appCaption.weight(.semibold)).foregroundColor(.statusGreen)
                    Text("·").foregroundColor(.gray)
                    Text("Gras \(units.format(last.weight * bf/100))")
                        .font(.appCaption.weight(.semibold)).foregroundColor(.statusBlue)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

struct LegendDot: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.appCaption).foregroundColor(.gray)
        }
    }
}

// MARK: - WHR Card
struct WHRCard: View {
    let ratio: Double
    let isMale: Bool

    private var thresholds: (good: Double, ok: Double) { isMale ? (0.90, 0.95) : (0.85, 0.90) }
    private var statusColor: Color {
        ratio < thresholds.good ? .statusGreen : ratio < thresholds.ok ? .statusOrange : .statusRed
    }
    private var statusLabel: String {
        ratio < thresholds.good ? "Excellent" : ratio < thresholds.ok ? "Correct" : "À surveiller"
    }
    private let gaugeMin = 0.65, gaugeMax = 1.05
    private var gaugeFill: Double { (min(ratio, gaugeMax) - gaugeMin) / (gaugeMax - gaugeMin) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RATIO TAILLE / HANCHES")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(statusLabel)
                    .font(.appCaption.weight(.bold)).foregroundColor(statusColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(statusColor.opacity(0.12)).clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", ratio))
                    .font(.system(size: 40, weight: .black)).foregroundColor(statusColor)
                Text("WHR").font(.appLabel.weight(.semibold)).foregroundColor(.gray)
            }

            // Jauge colorée
            GeometryReader { geo in
                let w = geo.size.width
                let goodX = w * CGFloat((thresholds.good - gaugeMin) / (gaugeMax - gaugeMin))
                let okX   = w * CGFloat((thresholds.ok   - gaugeMin) / (gaugeMax - gaugeMin))

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.statusGreen.opacity(0.25)).frame(width: goodX)
                        Rectangle().fill(Color.forge.opacity(0.25)).frame(width: okX - goodX)
                        Rectangle().fill(Color.statusRed.opacity(0.25))
                    }
                    .clipShape(Capsule()).frame(height: 8)

                    Circle().fill(statusColor)
                        .frame(width: 18, height: 18)
                        .shadow(color: statusColor.opacity(0.5), radius: 6)
                        .offset(x: w * CGFloat(gaugeFill) - 9)
                }
            }
            .frame(height: 18)

            Text("Référence \(isMale ? "H" : "F") : < \(String(format: "%.2f", thresholds.good)) optimal · < \(String(format: "%.2f", thresholds.ok)) acceptable")
                .font(.appCaption).foregroundColor(.gray)
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Measurements Card
struct MeasurementsCard: View {
    let entries: [BodyWeightEntry]

    private struct MeasureItem: Identifiable {
        var id: String { label }
        let label: String
        let icon: String
        let color: Color
        let current: Double
        let reference: Double?
        var delta: Double? { reference.map { current - $0 } }
    }

    private var items: [MeasureItem] {
        guard let l = entries.first else { return [] }
        let ref = entries.count > 1 ? entries.last : nil
        let defs: [(String, String, Color, Double?, Double?)] = [
            ("Taille",    "arrow.left.and.right",                   .statusPurple, l.waistCm,  ref?.waistCm),
            ("Cou",       "bolt.ring.closed",                       .teal,   l.neckCm,   ref?.neckCm),
            ("Bras",      "figure.strengthtraining.traditional",     Color.forge, l.armsCm,   ref?.armsCm),
            ("Poitrine",  "heart.fill",                             .statusRed,    l.chestCm,  ref?.chestCm),
            ("Cuisses",   "figure.walk",                            .statusBlue,   l.thighsCm, ref?.thighsCm),
            ("Hanches",   "oval.portrait",                          .pink,   l.hipsCm,   ref?.hipsCm),
        ]
        return defs.compactMap { label, icon, color, cur, refVal in
            guard let c = cur else { return nil }
            return MeasureItem(label: label, icon: icon, color: color, current: c, reference: refVal)
        }
    }

    private var maxValue: Double { items.map(\.current).max() ?? 100 }

    private var periodLabel: String {
        guard entries.count > 1,
              let first = entries.last?.date, let last = entries.first?.date else { return "" }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let d1 = df.date(from: first), let d2 = df.date(from: last) else { return "" }
        let days = Int(d2.timeIntervalSince(d1) / 86400)
        return days > 0 ? "Δ \(days) j" : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MENSURATIONS cm")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if !periodLabel.isEmpty {
                    Text(periodLabel).font(.appCaption).foregroundColor(.gray)
                }
            }

            ForEach(items) { item in
                VStack(spacing: 7) {
                    HStack {
                        Image(systemName: item.icon)
                            .font(.appCaption).foregroundColor(item.color).frame(width: 20)
                        Text(item.label)
                            .font(.appLabel).foregroundColor(.appTextPrimary)
                        Spacer()
                        if let d = item.delta, abs(d) >= 0.5 {
                            Text("\(d >= 0 ? "+" : "")\(d, specifier: "%.0f")")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(d <= 0 ? .statusGreen : .statusOrange)
                        }
                        Text("\(item.current, specifier: "%.0f")")
                            .font(.appBody.weight(.bold)).foregroundColor(.appTextPrimary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.appSurfaceInset).frame(height: 5)
                            Capsule()
                                .fill(item.color.opacity(0.75))
                                .frame(width: geo.size.width * CGFloat(item.current / maxValue), height: 5)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Comparison Table (deux dates côte à côte)
struct ComparisonTableCard: View {
    let entries: [BodyWeightEntry]   // newest first
    @ObservedObject private var units = UnitSettings.shared

    private var newest: BodyWeightEntry? { entries.first }
    private var oldest: BodyWeightEntry? {
        entries.dropFirst().last {
            $0.armsCm != nil || $0.chestCm != nil || $0.waistCm != nil || $0.neckCm != nil || $0.bodyFat != nil
        }
    }

    private func monthLabel(_ date: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let out = DateFormatter(); out.dateFormat = "MMM yyyy"
        out.locale = Locale(identifier: "fr_CA")
        return df.date(from: date).map { out.string(from: $0) } ?? date
    }

    private struct Row: Identifiable {
        let id: String
        let label: String
        let old: String?
        let new: String?
        let delta: Double?
        let higherIsBetter: Bool   // true = vert si Δ>0 (ex: bras), false = vert si Δ<0
    }

    private func fmt(_ v: Double?, decimals: Int = 1) -> String? {
        guard let v else { return nil }
        return String(format: decimals == 0 ? "%.0f" : "%.1f", v)
    }

    private func d(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return a - b
    }

    private var rows: [Row] {
        guard let n = newest, let o = oldest else { return [] }
        let nw = n.weight; let ow = o.weight
        let nLean = n.bodyFat.map { n.weight * (1 - $0 / 100) }
        let oLean = o.bodyFat.map { o.weight * (1 - $0 / 100) }
        return [
            Row(id: "poids",    label: "Poids (lbs)",              old: fmt(ow),                         new: fmt(nw),                         delta: nw - ow,              higherIsBetter: false),
            Row(id: "bf",       label: "Masse grasse %",          old: fmt(o.bodyFat),                  new: fmt(n.bodyFat),                  delta: d(n.bodyFat, o.bodyFat),  higherIsBetter: false),
            Row(id: "lean",     label: "Masse maigre (lbs)",       old: fmt(oLean),                      new: fmt(nLean),                      delta: d(nLean, oLean),          higherIsBetter: true),
            Row(id: "taille",   label: "Taille (cm)",             old: fmt(o.waistCm,  decimals: 0),    new: fmt(n.waistCm,  decimals: 0),    delta: d(n.waistCm,  o.waistCm),  higherIsBetter: false),
            Row(id: "cou",      label: "Cou (cm)",                old: fmt(o.neckCm,   decimals: 0),    new: fmt(n.neckCm,   decimals: 0),    delta: d(n.neckCm,   o.neckCm),   higherIsBetter: false),
            Row(id: "bras",     label: "Bras (cm)",               old: fmt(o.armsCm,   decimals: 0),    new: fmt(n.armsCm,   decimals: 0),    delta: d(n.armsCm,   o.armsCm),   higherIsBetter: true),
            Row(id: "poitrine", label: "Poitrine (cm)",           old: fmt(o.chestCm,  decimals: 0),    new: fmt(n.chestCm,  decimals: 0),    delta: d(n.chestCm,  o.chestCm),  higherIsBetter: false),
            Row(id: "cuisses",  label: "Cuisses (cm)",            old: fmt(o.thighsCm, decimals: 0),    new: fmt(n.thighsCm, decimals: 0),    delta: d(n.thighsCm, o.thighsCm), higherIsBetter: false),
            Row(id: "hanches",  label: "Hanches (cm)",            old: fmt(o.hipsCm,   decimals: 0),    new: fmt(n.hipsCm,   decimals: 0),    delta: d(n.hipsCm,   o.hipsCm),   higherIsBetter: false),
        ].filter { $0.old != nil || $0.new != nil }
    }

    var body: some View {
        guard let n = newest, let o = oldest, o.date != n.date else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("ÉVOLUTION").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                    Spacer()
                }
                // Column labels
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text(monthLabel(o.date))
                        .font(.appCaption.weight(.semibold)).foregroundColor(.gray)
                        .frame(width: 68, alignment: .center)
                    Text(monthLabel(n.date))
                        .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                        .frame(width: 68, alignment: .center)
                    Text("Δ")
                        .font(.appCaption.weight(.semibold)).foregroundColor(.gray)
                        .frame(width: 52, alignment: .trailing)
                }
                Divider().background(Color.appSeparatorStrong)
                // Data rows
                ForEach(rows) { row in
                    HStack {
                        Text(row.label)
                            .font(.appCaption.weight(.medium)).foregroundColor(.appTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.old ?? "—")
                            .font(.appCaption).foregroundColor(.gray)
                            .frame(width: 68, alignment: .center)
                        Text(row.new ?? "—")
                            .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                            .frame(width: 68, alignment: .center)
                        Group {
                            if let d = row.delta, abs(d) >= 0.05 {
                                let good = row.higherIsBetter ? d > 0 : d < 0
                                Text("\(d >= 0 ? "+" : "")\(d, specifier: abs(d) < 10 ? "%.1f" : "%.0f")")
                                    .foregroundColor(good ? .statusGreen : .statusOrange)
                            } else {
                                Text("=").foregroundColor(.gray)
                            }
                        }
                        .font(.appCaption.weight(.semibold))
                        .frame(width: 52, alignment: .trailing)
                    }
                    Divider().background(Color.appSeparatorSubtle)
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(14)
        )
    }
}

// MARK: - Row with inline CRUD buttons
struct BodyWeightRow: View {
    let entry: BodyWeightEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var units = UnitSettings.shared
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date)
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.gray)
                if let bf = entry.bodyFat {
                    Text("\(bf, specifier: "%.1f")% gras")
                        .font(.appCaption)
                        .foregroundColor(.statusBlue)
                }
                if let wc = entry.waistCm {
                    Text("Tour: \(wc, specifier: "%.0f") cm")
                        .font(.appCaption)
                        .foregroundColor(.statusPurple)
                }
            }
            Spacer()
            Text(units.format(entry.weight))
                .font(.appBody.weight(.semibold))
                .foregroundColor(.appTextPrimary)

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.appLabel.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.forge.opacity(0.12))
                    .foregroundColor(Color.forge)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Delete button
            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.appLabel.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.statusRed.opacity(0.1))
                    .foregroundColor(Color.statusRed.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.appCard)
        .cornerRadius(10)
        .confirmationDialog("Supprimer cette entrée ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }
}

// MARK: - Add / Edit Sheet
struct BodyWeightSheet: View {
    let editEntry: BodyWeightEntry?     // nil = add mode
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var units = UnitSettings.shared

    @State private var weightStr = ""
    @State private var bodyFatStr = ""
    @State private var waistStr = ""
    @State private var neckStr = ""
    @State private var armsStr = ""
    @State private var chestStr = ""
    @State private var thighsStr = ""
    @State private var hipsStr = ""
    @State private var isSaving = false
    @State private var isLoadingHK = false
    @State private var saveError: String? = nil
    private enum BodyFocus: Hashable { case weight, bodyFat }
    @FocusState private var bodyFocus: BodyFocus?

    var isEdit: Bool { editEntry != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // HealthKit auto-fill (add mode only)
                        if editEntry == nil {
                            Button(action: fillFromHealthKit) {
                                HStack(spacing: 8) {
                                    if isLoadingHK {
                                        ProgressView().tint(.onAccent).scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "heart.text.square.fill")
                                            .font(.appBody)
                                    }
                                    Text(isLoadingHK ? "Lecture Health..." : "Remplir depuis Apple Santé")
                                        .font(.appLabel.weight(.semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.statusRed.opacity(0.85))
                                .cornerRadius(12)
                            }
                            .disabled(isLoadingHK)
                            .buttonStyle(SpringButtonStyle())
                        }

                        // Poids + % gras — champs principaux
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("POIDS (LBS)")
                                    .font(.appCaption.weight(.bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                TextField("0.0", text: $weightStr)
                                    .keyboardType(.decimalPad)
                                    .focused($bodyFocus, equals: .weight)
                                    .foregroundColor(.appTextPrimary)
                                    .font(.appTitle)
                                    .padding(12)
                                    .background(Color.appSurfaceInset)
                                    .cornerRadius(10)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("% GRAS")
                                    .font(.appCaption.weight(.bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                let fatInvalid = !bodyFatStr.isEmpty && {
                                    let v = Double(bodyFatStr.replacingOccurrences(of: ",", with: ".")) ?? -1
                                    return v < 3 || v > 60
                                }()
                                TextField("—", text: $bodyFatStr)
                                    .keyboardType(.decimalPad)
                                    .focused($bodyFocus, equals: .bodyFat)
                                    .foregroundColor(fatInvalid ? .statusRed : .white)
                                    .font(.appTitle)
                                    .padding(12)
                                    .background(Color.appSurfaceInset)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.statusRed.opacity(fatInvalid ? 0.7 : 0), lineWidth: 1.5)
                                    )
                                if fatInvalid {
                                    Text("Valeur entre 3% et 60%")
                                        .font(.appCaption).foregroundColor(Color.statusRed.opacity(0.8))
                                }
                            }
                        }

                        // Mensurations — section collapsible visuellement
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MENSURATIONS cm — optionnel")
                                .font(.appCaption.weight(.bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                MesureField(label: "TAILLE", placeholder: "82", text: $waistStr)
                                MesureField(label: "COU",    placeholder: "38", text: $neckStr)
                                MesureField(label: "BRAS", placeholder: "34", text: $armsStr)
                                MesureField(label: "POITRINE", placeholder: "100", text: $chestStr)
                                MesureField(label: "CUISSES", placeholder: "56", text: $thighsStr)
                                MesureField(label: "HANCHES", placeholder: "95", text: $hipsStr)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, contentBottomPadding) // espace sous le bouton épinglé
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(weightStr.isEmpty ? .white : Color.onAccent).scaleEffect(0.85) }
                        Text(isEdit ? "Enregistrer les modifications" : "Enregistrer")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(weightStr.isEmpty ? Color(white: 0.4) : Color.onAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(weightStr.isEmpty ? Color.gray.opacity(0.3) : Color.forge)
                .cornerRadius(14)
                .disabled(weightStr.isEmpty || isSaving)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .buttonStyle(SpringButtonStyle())
                .background(Color.appBg.opacity(0.95))
            }
            .navigationTitle(isEdit ? "Modifier" : "Ajouter poids")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if bodyFocus == .weight {
                        Button("% Gras →") { bodyFocus = .bodyFat }
                            .font(.appBody.weight(.semibold)).foregroundColor(Color.forge)
                    } else {
                        Button("Ok") { bodyFocus = nil }
                            .font(.appBody.weight(.semibold)).foregroundColor(Color.forge)
                    }
                }
            }
            .alert("Erreur", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let e = editEntry {
                weightStr  = String(format: "%.1f", e.weight)
                bodyFatStr = e.bodyFat.map  { String(format: "%.1f", $0) } ?? ""
                waistStr   = e.waistCm.map  { String(format: "%.0f", $0) } ?? ""
                neckStr    = e.neckCm.map   { String(format: "%.0f", $0) } ?? ""
                armsStr    = e.armsCm.map   { String(format: "%.0f", $0) } ?? ""
                chestStr   = e.chestCm.map  { String(format: "%.0f", $0) } ?? ""
                thighsStr  = e.thighsCm.map { String(format: "%.0f", $0) } ?? ""
                hipsStr    = e.hipsCm.map   { String(format: "%.0f", $0) } ?? ""
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    bodyFocus = .weight
                }
            }
        }
    }

    private func parse(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    private func fillFromHealthKit() {
        isLoadingHK = true
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isLoadingHK = false; return }
            // sequential — async let LIFO crash on iOS 26 beta
            let w  = await hk.fetchLatestBodyWeight()
            let bf = await hk.fetchLatestBodyFat()
            // fetchLatestBodyWeight() already returns lbs — use directly
            if let w  { weightStr  = String(format: "%.1f", w) }
            if let bf { bodyFatStr = String(format: "%.1f", bf) }
            isLoadingHK = false
        }
    }

    private func save() {
        guard let w = parse(weightStr) else {
            saveError = "Valeur de poids invalide: '\(weightStr)'"
            return
        }
        isSaving = true
        Task {
            do {
                if let e = editEntry {
                    try await APIService.shared.updateBodyWeight(
                        date: e.date, oldWeight: e.weight, newWeight: w,
                        bodyFat: parse(bodyFatStr), waistCm: parse(waistStr),
                        neckCm: parse(neckStr),
                        armsCm: parse(armsStr), chestCm: parse(chestStr),
                        thighsCm: parse(thighsStr), hipsCm: parse(hipsStr)
                    )
                } else {
                    try await APIService.shared.addBodyWeight(
                        date: DateFormatter.isoDate.string(from: Date()), weight: w,
                        bodyFat: parse(bodyFatStr), waistCm: parse(waistStr),
                        neckCm: parse(neckStr),
                        armsCm: parse(armsStr), chestCm: parse(chestStr),
                        thighsCm: parse(thighsStr), hipsCm: parse(hipsStr)
                    )
                }
                await onSaved()
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - Mensure Field
struct MesureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                .padding(10).background(Color.appSurfaceInset).cornerRadius(8)
        }
    }
}

// MARK: - Chart
struct WeightChartView: View {
    let entries: [BodyWeightEntry]
    @ObservedObject private var units = UnitSettings.shared

    private var minW: Double { (entries.map(\.weight).min() ?? 0) - 0.5 }
    private var maxW: Double { (entries.map(\.weight).max() ?? 1) + 0.5 }
    private var current: Double { entries.last?.weight ?? 0 }
    private var first: Double   { entries.first?.weight ?? 0 }
    private var delta: Double   { current - first }

    private var deltaColor: Color {
        if abs(delta) < 0.2 { return .gray }
        return delta < 0 ? .statusGreen : .statusOrange
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let o = DateFormatter(); o.locale = Locale(identifier: "fr_CA"); o.dateFormat = "d MMM"
        return f.date(from: iso).map { o.string(from: $0) } ?? iso
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("POIDS CORPOREL")
                        .font(.appCaption.weight(.bold))
                        .tracking(2)
                        .foregroundColor(.gray)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", units.display(current)))
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(.appTextPrimary)
                        Text(units.label)
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                // Delta depuis le début de la période
                if entries.count >= 2 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SUR LA PÉRIODE")
                            .font(.appMicro.weight(.bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                        HStack(spacing: 3) {
                            Image(systemName: delta < -0.2 ? "arrow.down" : delta > 0.2 ? "arrow.up" : "minus")
                                .font(.appCaption.weight(.bold))
                            Text(String(format: "%+.1f %@", units.display(delta), units.label))
                                .font(.appLabel.weight(.bold))
                        }
                        .foregroundColor(deltaColor)
                        if let bf = entries.last?.bodyFat {
                            Text(String(format: "%.1f%% BF", bf))
                                .font(.appCaption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            // Courbe
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let range = maxW - minW == 0 ? 1 : maxW - minW

                ZStack(alignment: .bottomLeading) {
                    // Grille horizontale avec labels Y
                    ForEach(0..<4) { i in
                        let val = minW + (Double(i) / 3.0) * range
                        let y = h - (Double(i) / 3.0 * h)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.appSurfaceInset, lineWidth: 1)
                        Text(String(format: "%.0f", units.display(val)))
                            .font(.system(size: 8))
                            .foregroundColor(.gray.opacity(0.6))
                            .position(x: 16, y: y - 6)
                    }

                    if entries.count > 1 {
                        // Aire sous la courbe
                        Path { path in
                            for (i, entry) in entries.enumerated() {
                                let x = (Double(i) / Double(entries.count - 1)) * Double(w)
                                let y = Double(h) - ((entry.weight - minW) / range * Double(h))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            path.addLine(to: CGPoint(x: Double(w), y: Double(h)))
                            path.addLine(to: CGPoint(x: 0, y: Double(h)))
                            path.closeSubpath()
                        }
                        .fill(LinearGradient(
                            colors: [Color.forge.opacity(0.18), Color.forge.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        ))

                        // Ligne
                        Path { path in
                            for (i, entry) in entries.enumerated() {
                                let x = (Double(i) / Double(entries.count - 1)) * Double(w)
                                let y = Double(h) - ((entry.weight - minW) / range * Double(h))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.forge, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Points
                        ForEach(entries.indices, id: \.self) { i in
                            let x = (Double(i) / Double(entries.count - 1)) * Double(w)
                            let y = Double(h) - ((entries[i].weight - minW) / range * Double(h))
                            Circle()
                                .fill(i == entries.count - 1 ? Color.forge : Color.forge.opacity(0.5))
                                .frame(width: i == entries.count - 1 ? 8 : 5,
                                       height: i == entries.count - 1 ? 8 : 5)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
            .frame(height: 110)

            // Labels dates X
            if entries.count >= 2 {
                HStack {
                    Text(entries.first.map { shortDate($0.date) } ?? "")
                        .font(.appMicro).foregroundColor(.gray)
                    Spacer()
                    Text("\(entries.count) entrées")
                        .font(.appMicro).foregroundColor(.gray.opacity(0.5))
                    Spacer()
                    Text(entries.last.map { shortDate($0.date) } ?? "")
                        .font(.appMicro).foregroundColor(.gray)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Body Projection Card

struct BodyProjectionCard: View {
    let projection: BodyProjectionData

    private func formatDate(_ iso: String?) -> String {
        guard let iso else { return "—" }
        guard let d = DateFormatter.isoDate.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "fr_CA")
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.statusCyan)
                Text("PROJECTIONS OBJECTIFS")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
            }

            ForEach(projection.projections) { proj in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        let isBodyFat = proj.goalType == "body_fat"
                        Text(isBodyFat ? "Masse grasse" : "Masse maigre")
                            .font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                        Spacer()
                        if let date = proj.projectedDate {
                            Text(formatDate(date))
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(.statusCyan)
                        } else {
                            Text("Tendance insuffisante")
                                .font(.appCaption).foregroundColor(.gray)
                        }
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ACTUEL")
                                .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                            let unit = proj.goalType == "body_fat" ? "%" : " lbs"
                            Text(String(format: "%.1f\(unit)", proj.current))
                                .font(.appBody.weight(.black)).foregroundColor(.appTextPrimary)
                        }
                        Image(systemName: "arrow.right")
                            .font(.appCaption).foregroundColor(.gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OBJECTIF")
                                .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                            let unit = proj.goalType == "body_fat" ? "%" : " lbs"
                            Text(String(format: "%.1f\(unit)", proj.target))
                                .font(.appBody.weight(.black)).foregroundColor(.statusCyan)
                        }
                        Spacer()
                        if let r2 = proj.r2 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("FIABILITÉ")
                                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                                Text(String(format: "%.0f%%", r2 * 100))
                                    .font(.appLabel.weight(.bold))
                                    .foregroundColor(r2 >= 0.7 ? .statusGreen : r2 >= 0.4 ? .statusYellow : .statusOrange)
                            }
                        }
                    }
                    let rate = proj.slopePerWeek
                    let rateStr = rate < 0 ? String(format: "%.2f/sem", rate) : String(format: "+%.2f/sem", rate)
                    Text("Tendance : \(rateStr)")
                        .font(.appCaption).foregroundColor(.gray.opacity(0.7))
                }
                .padding(12)
                .background(Color.appSurfaceInset)
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(16)
    }
}
