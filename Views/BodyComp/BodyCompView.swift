import SwiftUI

struct BodyCompView: View {
    @ObservedObject private var units = UnitSettings.shared
    @State private var bodyWeight: [BodyWeightEntry] = []
    @State private var profile: UserProfile? = nil
    @State private var tendance = ""
    @State private var isLoading = true
    @State private var sheetEntry: BodyWeightEntry? = nil   // nil = add, non-nil = edit
    @State private var showSheet = false

    var latest: BodyWeightEntry? { bodyWeight.first }


    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .green)

                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Current weight card
                            VStack(spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("POIDS ACTUEL")
                                            .font(.system(size: 10, weight: .bold))
                                            .tracking(2).foregroundColor(.gray)
                                        if let w = latest?.weight {
                                            Text(units.format(w))
                                                .font(.system(size: 44, weight: .black))
                                                .foregroundColor(.orange)
                                                .glow(.orange)
                                                .contentTransition(.numericText())
                                        } else {
                                            Text("— \(units.label)")
                                                .font(.system(size: 44, weight: .black))
                                                .foregroundColor(.gray)
                                        }
                                        if let bf = latest?.bodyFat {
                                            Text("\(bf, specifier: "%.1f")% gras")
                                                .font(.system(size: 13)).foregroundColor(.blue)
                                        }
                                        if let wc = latest?.waistCm {
                                            Text("Tour: \(wc, specifier: "%.0f") cm")
                                                .font(.system(size: 13)).foregroundColor(.purple)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text(tendance)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(tendanceColor)
                                        if bodyWeight.count > 1 {
                                            let diff = (latest?.weight ?? 0) - (bodyWeight[1].weight)
                                            HStack(spacing: 4) {
                                                Image(systemName: diff >= 0 ? "arrow.up" : "arrow.down")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text("\(diff >= 0 ? "+" : "")\(units.format(diff))")
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                            .foregroundColor(diff >= 0 ? .orange.opacity(0.8) : .green.opacity(0.8))
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .glassCardAccent(.green)
                            .cornerRadius(16)
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // Chart
                            if !bodyWeight.isEmpty {
                                WeightChartView(entries: Array(bodyWeight.prefix(20).reversed()))
                                    .padding(.horizontal, 16)
                            }

                            // History list
                            VStack(alignment: .leading, spacing: 8) {
                                Text("HISTORIQUE")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)

                                ForEach(bodyWeight.prefix(30)) { entry in
                                    BodyWeightRow(
                                        entry: entry,
                                        onEdit: {
                                            sheetEntry = entry
                                            showSheet = true
                                        },
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
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, 80)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Body Comp")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSheet, onDismiss: { sheetEntry = nil }) {
                BodyWeightSheet(editEntry: sheetEntry, onSaved: { await loadData() })
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") {
                    sheetEntry = nil
                    showSheet = true
                }
                .padding(.trailing, 20)
                .padding(.bottom, fabBottomPadding + 16)
                .appearAnimation(delay: 0.3)
            }
        }
        .task { await loadData() }
    }

    var tendanceColor: Color {
        let t = tendance.lowercased()
        if t.contains("hausse") || t.contains("+") { return .orange }
        if t.contains("baisse") || t.contains("↓") { return .green }
        return .gray
    }

    private func loadData() async {
        isLoading = true
        if let (p, bw, t) = try? await APIService.shared.fetchProfilData() {
            profile = p; bodyWeight = bw; tendance = t
        }
        isLoading = false
    }
}

// MARK: - Row with inline CRUD buttons
struct BodyWeightRow: View {
    let entry: BodyWeightEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                if let bf = entry.bodyFat {
                    Text("\(bf, specifier: "%.1f")% gras")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                }
                if let wc = entry.waistCm {
                    Text("Tour: \(wc, specifier: "%.0f") cm")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                }
            }
            Spacer()
            Text(UnitSettings.shared.format(entry.weight))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.12))
                    .foregroundColor(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Delete button
            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "11111c"))
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
    @StateObject private var hk = HealthKitService.shared
    @ObservedObject private var units = UnitSettings.shared

    @State private var weightStr = ""
    @State private var bodyFatStr = ""
    @State private var waistStr = ""
    @State private var armsStr = ""
    @State private var chestStr = ""
    @State private var thighsStr = ""
    @State private var hipsStr = ""
    @State private var isSaving = false
    @State private var isLoadingHK = false

    var isEdit: Bool { editEntry != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 20) {
                    Text(isEdit ? "Modifier l'entrée" : "Ajouter poids")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    if let e = editEntry {
                        Text(e.date)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }

                    // HealthKit auto-fill (add mode only)
                    if editEntry == nil {
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
                        .padding(.horizontal, 20)
                    }

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POIDS (\(units.label.uppercased()))")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("0.0", text: $weightStr)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("% GRAS (optionnel)")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("ex: 18.5", text: $bodyFatStr)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("TOUR DE TAILLE cm (optionnel)")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("ex: 82", text: $waistStr)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Mensurations optionnelles
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MENSURATIONS cm (optionnel)")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.gray)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MesureField(label: "BRAS", placeholder: "34", text: $armsStr)
                            MesureField(label: "POITRINE", placeholder: "100", text: $chestStr)
                            MesureField(label: "CUISSES", placeholder: "56", text: $thighsStr)
                            MesureField(label: "HANCHES", placeholder: "95", text: $hipsStr)
                        }
                    }
                    .padding(.horizontal, 20)

                    Button(action: save) {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(isEdit ? "Enregistrer les modifications" : "Enregistrer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(weightStr.isEmpty ? Color.gray.opacity(0.3) : Color.orange)
                    .cornerRadius(14)
                    .disabled(weightStr.isEmpty || isSaving)
                    .padding(.horizontal, 20)
                    .buttonStyle(SpringButtonStyle())

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if let e = editEntry {
                weightStr  = units.inputStr(e.weight)
                bodyFatStr = e.bodyFat.map  { String(format: "%.1f", $0) } ?? ""
                waistStr   = e.waistCm.map  { String(format: "%.0f", $0) } ?? ""
                armsStr    = e.armsCm.map   { String(format: "%.0f", $0) } ?? ""
                chestStr   = e.chestCm.map  { String(format: "%.0f", $0) } ?? ""
                thighsStr  = e.thighsCm.map { String(format: "%.0f", $0) } ?? ""
                hipsStr    = e.hipsCm.map   { String(format: "%.0f", $0) } ?? ""
            }
        }
    }

    private func parse(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    private func fillFromHealthKit() {
        isLoadingHK = true
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isLoadingHK = false; return }
            async let weight  = hk.fetchLatestBodyWeight()
            async let bodyFat = hk.fetchLatestBodyFat()
            let (w, bf) = await (weight, bodyFat)
            // HealthKit returns kg; convert to storage unit (lbs) then to display unit
            if let w  { weightStr  = units.inputStr(w / 0.453592) }
            if let bf { bodyFatStr = String(format: "%.1f", bf) }
            isLoadingHK = false
        }
    }

    private func save() {
        guard let w = parse(weightStr).map({ units.toStorage($0) }) else { return }
        isSaving = true
        Task {
            if let e = editEntry {
                try? await APIService.shared.updateBodyWeight(
                    date: e.date, oldWeight: e.weight, newWeight: w,
                    bodyFat: parse(bodyFatStr), waistCm: parse(waistStr),
                    armsCm: parse(armsStr), chestCm: parse(chestStr),
                    thighsCm: parse(thighsStr), hipsCm: parse(hipsStr)
                )
            } else {
                try? await APIService.shared.addBodyWeight(
                    date: DateFormatter.isoDate.string(from: Date()), weight: w,
                    bodyFat: parse(bodyFatStr), waistCm: parse(waistStr),
                    armsCm: parse(armsStr), chestCm: parse(chestStr),
                    thighsCm: parse(thighsStr), hipsCm: parse(hipsStr)
                )
            }
            await onSaved()
            isSaving = false
            dismiss()
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
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad).foregroundColor(.white)
                .padding(10).background(Color(hex: "191926")).cornerRadius(8)
        }
    }
}

// MARK: - Chart
struct WeightChartView: View {
    let entries: [BodyWeightEntry]

    var minW: Double { entries.map(\.weight).min() ?? 0 }
    var maxW: Double { entries.map(\.weight).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ÉVOLUTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let range = maxW - minW == 0 ? 1 : maxW - minW

                ZStack(alignment: .bottomLeading) {
                    ForEach(0..<4) { i in
                        Path { path in
                            let y = h - (Double(i) / 3.0 * h)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }

                    if entries.count > 1 {
                        Path { path in
                            for (i, entry) in entries.enumerated() {
                                let x = (Double(i) / Double(entries.count - 1)) * Double(w)
                                let y = Double(h) - ((entry.weight - minW) / range * Double(h))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(entries.indices, id: \.self) { i in
                            let x = (Double(i) / Double(entries.count - 1)) * Double(w)
                            let y = Double(h) - ((entries[i].weight - minW) / range * Double(h))
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
            .frame(height: 120)
            .padding(.vertical, 8)
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}
