import SwiftUI
import UserNotifications

struct ObjectifsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var objectifs:   [ObjectifEntry]   = []
    @State private var smartGoals:  [SmartGoalEntry]  = []
    @State private var isLoading    = true
    @State private var networkError: String? = nil
    @State private var showAddGoal  = false
    @State private var showArchived = false
    @State private var selectedObjectif: ObjectifEntry? = nil
    @State private var selectedSmart:    SmartGoalEntry? = nil
    @State private var toast: ToastMessage? = nil

    private var active:   [ObjectifEntry] { objectifs.filter { !$0.achieved && !$0.archived } }
    private var achieved: [ObjectifEntry] { objectifs.filter { $0.achieved && !$0.archived } }
    private var archived: [ObjectifEntry] { objectifs.filter { $0.archived } }
    private var smartActive:   [SmartGoalEntry] { smartGoals.filter { !$0.achieved } }
    private var smartAchieved: [SmartGoalEntry] { smartGoals.filter {  $0.achieved } }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            if let err = networkError {
                                ErrorBannerView(error: err,
                                    onRetry: { Task { await loadData() } },
                                    onDismiss: { networkError = nil })
                            }

                            // ── Smart Goals (Santé & Performance) ──
                            if !smartGoals.isEmpty {
                                SectionHeader(title: "SANTÉ & PERFORMANCE")
                                ForEach(Array(smartActive.enumerated()), id: \.1.id) { i, sg in
                                    SmartGoalCard(goal: sg, onDelete: {
                                        Task { try? await APIService.shared.deleteSmartGoal(id: sg.id); await loadData(); toast = ToastMessage(message: "Objectif supprimé", style: .success) }
                                    })
                                    .appearAnimation(delay: Double(i) * 0.05)
                                }
                                if !smartAchieved.isEmpty {
                                    SectionHeader(title: "ATTEINTS (\(smartAchieved.count))")
                                    ForEach(Array(smartAchieved.enumerated()), id: \.1.id) { i, sg in
                                        SmartGoalCard(goal: sg, onDelete: {
                                            Task { try? await APIService.shared.deleteSmartGoal(id: sg.id); await loadData(); toast = ToastMessage(message: "Objectif supprimé", style: .success) }
                                        })
                                        .opacity(0.7)
                                        .appearAnimation(delay: Double(i) * 0.05)
                                    }
                                }
                            }

                            // ── Exercise Goals ──
                            if !objectifs.isEmpty {
                                SectionHeader(title: "EXERCICES")
                            }
                            if !active.isEmpty {
                                ForEach(Array(active.enumerated()), id: \.1.id) { i, obj in
                                    ObjectifCard(obj: obj, onArchive: nil)
                                        .onTapGesture { selectedObjectif = obj }
                                        .appearAnimation(delay: Double(i) * 0.06)
                                }
                            }
                            if !achieved.isEmpty {
                                SectionHeader(title: "ATTEINTS (\(achieved.count))")
                                ForEach(Array(achieved.enumerated()), id: \.1.id) { i, obj in
                                    ObjectifCard(obj: obj, onArchive: {
                                        Task { await archiveGoal(obj) }
                                    })
                                    .appearAnimation(delay: Double(i) * 0.06)
                                }
                            }
                            if !archived.isEmpty {
                                Button { withAnimation { showArchived.toggle() } } label: {
                                    HStack {
                                        SectionHeader(title: "ARCHIVÉS (\(archived.count))")
                                        Spacer()
                                        Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 11)).foregroundColor(.gray)
                                    }
                                }
                                .buttonStyle(.plain)
                                if showArchived {
                                    ForEach(Array(archived.enumerated()), id: \.1.id) { i, obj in
                                        ObjectifCard(obj: obj, onArchive: nil)
                                            .opacity(0.5)
                                            .appearAnimation(delay: Double(i) * 0.04)
                                    }
                                }
                            }

                            if objectifs.isEmpty && smartGoals.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "target").font(.system(size: 48)).foregroundColor(.gray)
                                    Text("Aucun objectif").foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }

                            Spacer(minLength: 80)
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Objectifs")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddGoal) {
                AddGoalSheet { await loadData() }
            }
            .sheet(item: $selectedObjectif) { obj in
                EditGoalSheet(obj: obj) { await loadData() }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAddGoal = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
        }
        .task { await loadData() }
        .toast($toast)
    }

    private func loadData() async {
        isLoading = true
        do {
            async let obj = APIService.shared.fetchObjectifsData()
            async let sgs = APIService.shared.fetchSmartGoals()
            objectifs  = try await obj
            smartGoals = try await sgs
            networkError = nil
        } catch {
            if objectifs.isEmpty { networkError = "Impossible de charger les objectifs" }
        }
        isLoading = false
    }

    private func archiveGoal(_ obj: ObjectifEntry) async {
        try? await APIService.shared.archiveObjectif(exercise: obj.exercise)
        if let idx = objectifs.firstIndex(where: { $0.id == obj.id }) {
            objectifs[idx] = ObjectifEntry(
                exercise: obj.exercise, current: obj.current, goal: obj.goal,
                achieved: obj.achieved, deadline: obj.deadline, note: obj.note, archived: true
            )
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold)).tracking(2)
            .foregroundColor(.gray)
    }
}

struct ObjectifCard: View {
    let obj: ObjectifEntry
    var onArchive: (() -> Void)? = nil
    @ObservedObject private var units = UnitSettings.shared
    @State private var celebrate = false

    var pct: Double {
        guard obj.goal > 0 else { return 0 }
        return min(obj.current / obj.goal, 1.0)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(obj.exercise)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    if !obj.deadline.isEmpty {
                        Text("Deadline: \(obj.deadline)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if obj.achieved {
                    HStack(spacing: 8) {
                        Label("Atteint", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                            .scaleEffect(celebrate ? 1.0 : 0.4)
                            .opacity(celebrate ? 1.0 : 0)
                        if let archive = onArchive {
                            Button(action: archive) {
                                Label("Archiver", systemImage: "archivebox")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color(hex: "191926")).cornerRadius(8)
                            }
                        }
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTUEL")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    Text(units.format(obj.current))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(obj.achieved ? .green : .orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("OBJECTIF")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    Text(units.format(obj.goal))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "191926"))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(obj.achieved ? Color.green : Color.orange)
                        .frame(width: geo.size.width * pct, height: 8)
                        .animation(.easeOut(duration: 0.5), value: pct)
                }
            }
            .frame(height: 8)

            Text("\(Int(pct * 100))% complété")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            }
            .padding(16)
            .glassCardAccent(obj.achieved ? .green : .orange)
            .cornerRadius(16)
            .scaleEffect(celebrate ? 1.03 : 1.0)

            // Sparkles overlay on achievement
            if celebrate {
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: CGFloat([10, 14, 8, 12, 10, 8][i])))
                        .foregroundColor(.green.opacity(0.7))
                        .offset(
                            x: CGFloat([-40, 40, -60, 60, 0, -20][i]),
                            y: CGFloat([-20, -15, 5, 10, -30, 20][i])
                        )
                        .opacity(celebrate ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(Double(i) * 0.05), value: celebrate)
                }
            }
        }
        .onAppear {
            if obj.achieved {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                    celebrate = true
                }
            }
        }
    }
}

// MARK: - Smart Goal Card

struct SmartGoalCard: View {
    let goal: SmartGoalCard.GoalVM
    let onDelete: () -> Void

    init(goal: SmartGoalEntry, onDelete: @escaping () -> Void) {
        self.goal     = SmartGoalCard.GoalVM(goal)
        self.onDelete = onDelete
    }

    struct GoalVM {
        let id: String; let label: String; let icon: String
        let color: Color; let current: String; let target: String
        let progress: Double; let achieved: Bool
        let daysLeft: Int?; let lowerIsBetter: Bool

        init(_ g: SmartGoalEntry) {
            id            = g.id
            label         = g.label
            icon          = g.icon
            color         = Color(hex: g.accentColor)
            current       = g.currentValue.map { g.formatValue($0) } ?? "—"
            target        = g.formatValue(g.targetValue)
            progress      = g.progress / 100
            achieved      = g.achieved
            lowerIsBetter = g.lowerIsBetter
            if !g.targetDate.isEmpty {
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
                daysLeft = df.date(from: g.targetDate).map { Int($0.timeIntervalSinceNow / 86400) }
            } else { daysLeft = nil }
        }
    }

    @State private var confirmDelete = false
    @State private var celebrate     = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: goal.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(goal.color)
                        .frame(width: 32, height: 32)
                        .background(goal.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.label)
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        if let d = goal.daysLeft {
                            Text(d > 0 ? "\(d) jours restants" : "Deadline dépassée")
                                .font(.system(size: 11)).foregroundColor(d > 0 ? .gray : .red)
                        }
                    }
                    Spacer()
                    if goal.achieved {
                        Label("Atteint", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                            .scaleEffect(celebrate ? 1.0 : 0.4).opacity(celebrate ? 1 : 0)
                    }
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12)).foregroundColor(.red.opacity(0.5))
                            .padding(6).background(Color.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ACTUEL").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(goal.current)
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(goal.achieved ? .green : goal.color)
                    }
                    Spacer()
                    Image(systemName: goal.lowerIsBetter ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 14)).foregroundColor(.gray.opacity(0.4))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("OBJECTIF").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(goal.target).font(.system(size: 22, weight: .black)).foregroundColor(.white)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: "191926")).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(goal.achieved ? Color.green : goal.color)
                            .frame(width: geo.size.width * CGFloat(min(goal.progress, 1.0)), height: 8)
                            .animation(.easeOut(duration: 0.6), value: goal.progress)
                    }
                }
                .frame(height: 8)

                Text("\(Int(min(goal.progress, 1.0) * 100))% complété")
                    .font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "11111c")))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(goal.color.opacity(0.18), lineWidth: 1))

            if celebrate {
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: CGFloat([10, 14, 8, 12, 10, 8][i])))
                        .foregroundColor(goal.color.opacity(0.7))
                        .offset(x: CGFloat([-40, 40, -60, 60, 0, -20][i]),
                                y: CGFloat([-20, -15, 5, 10, -30, 20][i]))
                        .opacity(celebrate ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(Double(i) * 0.05), value: celebrate)
                }
            }
        }
        .confirmationDialog("Supprimer cet objectif ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
        .onAppear {
            if goal.achieved {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) { celebrate = true }
            }
        }
    }
}

// MARK: - Add Goal Sheet

struct AddGoalSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    enum GoalMode { case exercise, health }

    // shared
    @State private var mode: GoalMode = .health
    @State private var deadline = Date()
    @State private var apiError: String? = nil

    // exercise mode
    @State private var exercise   = ""
    @State private var goalWeight = ""

    // health mode
    @State private var smartType  = SmartGoalOption.allCases.first!
    @State private var targetStr  = ""

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var canSave: Bool {
        mode == .exercise ? !exercise.isEmpty && !goalWeight.isEmpty
                          : !targetStr.isEmpty && Double(targetStr.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Mode picker
                        Picker("", selection: $mode) {
                            Text("Santé / Perf").tag(GoalMode.health)
                            Text("Exercice").tag(GoalMode.exercise)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        if mode == .health {
                            healthForm
                        } else {
                            exerciseForm
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Nouvel objectif")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") { save() }
                        .foregroundColor(canSave ? .orange : .gray)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
        }
        .presentationDetents([.large])
    }

    // ── Health form ──
    private var healthForm: some View {
        VStack(spacing: 16) {
            // Type picker
            VStack(alignment: .leading, spacing: 8) {
                Text("TYPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(SmartGoalOption.allCases) { opt in
                        Button {
                            smartType = opt
                            targetStr = ""
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: opt.icon)
                                    .font(.system(size: 13)).foregroundColor(opt.color)
                                Text(opt.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(10)
                            .background(smartType == opt ? opt.color.opacity(0.15) : Color(hex: "191926"))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(smartType == opt ? opt.color.opacity(0.5) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Target value
            VStack(alignment: .leading, spacing: 6) {
                Text("CIBLE (\(smartType.unit.uppercased()))")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                TextField(smartType.placeholder, text: $targetStr)
                    .keyboardType(.decimalPad)
                    .foregroundColor(.white)
                    .font(.system(size: 22, weight: .bold))
                    .padding(12)
                    .background(Color(hex: "191926"))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 20)

            deadlineSection
        }
    }

    // ── Exercise form ──
    private var exerciseForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EXERCICE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                TextField("ex: Squat", text: $exercise)
                    .foregroundColor(.white).padding(12)
                    .background(Color(hex: "191926")).cornerRadius(10)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("POIDS OBJECTIF (\(units.label.uppercased()))")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                TextField("0.0", text: $goalWeight)
                    .keyboardType(.decimalPad).foregroundColor(.white)
                    .font(.system(size: 22, weight: .bold))
                    .padding(12).background(Color(hex: "191926")).cornerRadius(10)
            }
            .padding(.horizontal, 20)

            deadlineSection
        }
    }

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEADLINE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 8) {
                ForEach([1, 3, 6], id: \.self) { months in
                    Button("\(months) mois") {
                        deadline = Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date()
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.orange)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12)).cornerRadius(8)
                }
                Spacer()
            }
            DatePicker("", selection: $deadline, displayedComponents: .date)
                .labelsHidden().tint(.orange)
        }
        .padding(.horizontal, 20)
    }

    private func save() {
        let deadlineStr = Self.isoFormatter.string(from: deadline)
        Task {
            do {
                if mode == .health {
                    guard let val = Double(targetStr.replacingOccurrences(of: ",", with: ".")) else { return }
                    try await APIService.shared.saveSmartGoal(type: smartType.rawValue, targetValue: val, targetDate: deadlineStr)
                } else {
                    guard !exercise.isEmpty, let gw = Double(goalWeight).map({ units.toStorage($0) }) else { return }
                    try await APIService.shared.setGoal(exercise: exercise, goalWeight: gw, deadline: deadlineStr)
                    scheduleGoalDeadlineNotifications(exercise: exercise, deadlineStr: deadlineStr)
                }
                await onSaved()
                dismiss()
            } catch {
                apiError = "Erreur réseau — réessaie"
            }
        }
    }
}

// MARK: - Smart Goal Option enum

enum SmartGoalOption: String, CaseIterable, Identifiable {
    case bodyFat           = "body_fat"
    case leanMass          = "lean_mass"
    case waistCm           = "waist_cm"
    case weeklyVolume      = "weekly_volume"
    case trainingFrequency = "training_frequency"
    case proteinDaily      = "protein_daily"
    case nutritionStreak   = "nutrition_streak"
    // ── Types avancés ─────────────────────────────────────────────────────────
    case estimated1RM      = "estimated_1rm"
    case monthlyDistance   = "monthly_distance"
    case restingHR         = "resting_hr"
    case pssAvg            = "pss_avg"
    case sleepStreak       = "sleep_streak"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bodyFat:           return "% Masse grasse"
        case .leanMass:          return "Masse maigre"
        case .waistCm:           return "Tour de taille"
        case .weeklyVolume:      return "Volume hebdo"
        case .trainingFrequency: return "Séances / sem."
        case .proteinDaily:      return "Protéines / jour"
        case .nutritionStreak:   return "Streak nutrition"
        case .estimated1RM:      return "1RM estimé"
        case .monthlyDistance:   return "Distance mensuelle"
        case .restingHR:         return "FC au repos"
        case .pssAvg:            return "Stress PSS moyen"
        case .sleepStreak:       return "Streak sommeil"
        }
    }

    var unit: String {
        switch self {
        case .bodyFat:           return "%"
        case .leanMass:          return "lbs"
        case .waistCm:           return "cm"
        case .weeklyVolume:      return "lbs"
        case .trainingFrequency: return "séances"
        case .proteinDaily:      return "g"
        case .nutritionStreak:   return "jours"
        case .estimated1RM:      return "lbs"
        case .monthlyDistance:   return "km"
        case .restingHR:         return "bpm"
        case .pssAvg:            return "pts"
        case .sleepStreak:       return "jours"
        }
    }

    var placeholder: String {
        switch self {
        case .bodyFat:           return "15.0"
        case .leanMass:          return "150.0"
        case .waistCm:           return "80.0"
        case .weeklyVolume:      return "80000"
        case .trainingFrequency: return "4"
        case .proteinDaily:      return "160"
        case .nutritionStreak:   return "30"
        case .estimated1RM:      return "200"
        case .monthlyDistance:   return "50"
        case .restingHR:         return "55"
        case .pssAvg:            return "10"
        case .sleepStreak:       return "14"
        }
    }

    var icon: String {
        switch self {
        case .bodyFat:           return "flame.fill"
        case .leanMass:          return "figure.strengthtraining.traditional"
        case .waistCm:           return "arrow.left.and.right"
        case .weeklyVolume:      return "chart.bar.fill"
        case .trainingFrequency: return "calendar.badge.checkmark"
        case .proteinDaily:      return "fork.knife"
        case .nutritionStreak:   return "checkmark.circle"
        case .estimated1RM:      return "trophy.fill"
        case .monthlyDistance:   return "figure.run"
        case .restingHR:         return "heart.fill"
        case .pssAvg:            return "brain.head.profile"
        case .sleepStreak:       return "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .bodyFat:           return Color(hex: "FF6B35")
        case .leanMass:          return Color(hex: "2ECC71")
        case .waistCm:           return Color(hex: "9B59B6")
        case .weeklyVolume:      return Color(hex: "3498DB")
        case .trainingFrequency: return Color(hex: "1ABC9C")
        case .proteinDaily:      return Color(hex: "F1C40F")
        case .nutritionStreak:   return Color(hex: "E74C3C")
        case .estimated1RM:      return Color(hex: "FFD700")
        case .monthlyDistance:   return Color(hex: "00B4D8")
        case .restingHR:         return Color(hex: "E63946")
        case .pssAvg:            return Color(hex: "7209B7")
        case .sleepStreak:       return Color(hex: "4361EE")
        }
    }
}

struct EditGoalSheet: View {
    let obj: ObjectifEntry
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    @State private var goalWeight: String
    @State private var deadline: Date
    @State private var apiError: String? = nil

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    init(obj: ObjectifEntry, onSaved: @escaping () async -> Void) {
        self.obj = obj
        self.onSaved = onSaved
        _goalWeight = State(initialValue: UnitSettings.shared.inputStr(obj.goal))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        _deadline = State(initialValue: f.date(from: obj.deadline) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 20) {
                    Text(obj.exercise)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POIDS OBJECTIF (\(units.label.uppercased()))")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("0.0", text: $goalWeight)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("DEADLINE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            DatePicker("", selection: $deadline, displayedComponents: .date)
                                .labelsHidden()
                                .tint(.orange)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)

                    Button(action: save) {
                        Text("Sauvegarder")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let gw = Double(goalWeight).map({ units.toStorage($0) }) else { return }
        let deadlineStr = Self.isoFormatter.string(from: deadline)
        Task {
            do {
                try await APIService.shared.setGoal(exercise: obj.exercise, goalWeight: gw, deadline: deadlineStr)
                scheduleGoalDeadlineNotifications(exercise: obj.exercise, deadlineStr: deadlineStr)
                await onSaved()
                dismiss()
            } catch {
                apiError = "Erreur réseau — réessaie"
            }
        }
    }
}

// MARK: - Goal deadline notifications helper

/// Schedules J-7 and J-1 notifications for a goal deadline.
/// Re-scheduling replaces any existing notification for the same goal.
private func scheduleGoalDeadlineNotifications(exercise: String, deadlineStr: String) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let deadline = f.date(from: deadlineStr) else { return }
        let now = Date()

        let alerts: [(daysOffset: Int, title: String, body: String)] = [
            (-7, "Objectif — 7 jours restants 🎯",  "Il te reste 7 jours pour atteindre ton objectif de \(exercise)."),
            (-1, "Objectif — demain dernier jour !",  "Dernière chance pour \(exercise) 🎯 Go !"),
        ]

        for (offset, title, body) in alerts {
            let fireDate = Calendar.current.date(byAdding: .day, value: offset, to: deadline)!
            guard fireDate > now else { continue }

            let content       = UNMutableNotificationContent()
            content.title     = title
            content.body      = body
            content.sound     = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            var triggerComps  = comps
            triggerComps.hour   = 9
            triggerComps.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
            let id      = "goal_\(offset < -1 ? "7d" : "1d")_\(exercise.lowercased().replacingOccurrences(of: " ", with: "_"))"
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}

#Preview {
    ObjectifsView()
        .environmentObject(AppState.shared)
}
