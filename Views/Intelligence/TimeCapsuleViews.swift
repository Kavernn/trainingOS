import SwiftUI
import UserNotifications

// ── Gold palette — exclusive to Time Capsule ─────────────────────────────────
private let capsuleGoldDim    = Color(red: 0.79, green: 0.66, blue: 0.30)
private let capsuleGoldBright = Color(red: 0.91, green: 0.83, blue: 0.54)
private let capsuleBg         = Color(red: 0.035, green: 0.035, blue: 0.060)

// MARK: - Section (embedded in IntelligenceView patterns tab)

struct TimeCapsuleSection: View {
    @State private var capsules: [TimeCapsule] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var revealCapsule: TimeCapsule? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "capsule.fill")
                        .font(.appCaption).fontWeight(.bold)
                        .foregroundColor(capsuleGoldDim)
                    Text("TIME CAPSULE")
                        .font(.appMicro).fontWeight(.bold)
                        .foregroundColor(Color(white: 0.40))
                        .tracking(0.8)
                }
                Spacer()
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                        .font(.appBody).fontWeight(.medium)
                        .foregroundColor(capsuleGoldDim)
                        .frame(width: 30, height: 30)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if isLoading && capsules.isEmpty {
                CapsuleSkeletonRow()
            } else if capsules.filter({ !$0.isOpened }).isEmpty {
                CapsuleEmptyState { showCreate = true }
            } else {
                VStack(spacing: 10) {
                    ForEach(capsules.filter { !$0.isOpened }) { capsule in
                        if capsule.isUnlocked {
                            CapsuleUnlockedCard(capsule: capsule) {
                                revealCapsule = capsule
                            }
                        } else {
                            CapsuleLockedCard(capsule: capsule)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .task { await loadCapsules() }
        .background(
            EmptyView()
                .sheet(isPresented: $showCreate, onDismiss: {
                    Task { await loadCapsules() }
                }) {
                    TimeCapsuleCreateView { Task { await loadCapsules() } }
                }
                .fullScreenCover(item: $revealCapsule) { capsule in
                    TimeCapsuleRevealView(capsule: capsule) {
                        revealCapsule = nil
                        Task { await loadCapsules() }
                    }
                }
        )
    }

    private func loadCapsules() async {
        isLoading = true
        capsules  = (try? await APIService.shared.fetchTimeCapsules()) ?? []
        isLoading = false
    }
}

// MARK: - Locked Card

struct CapsuleLockedCard: View {
    let capsule: TimeCapsule

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(capsuleGoldDim.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: "capsule.fill")
                    .font(.appHeadline)
                    .foregroundColor(capsuleGoldDim.opacity(0.55))
                Image(systemName: "lock.fill")
                    .font(.appMicro).fontWeight(.bold)
                    .foregroundColor(capsuleGoldDim)
                    .offset(x: 12, y: 12)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(capsule.formattedCreatedDate)
                    .font(.appLabel).fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.85))
                Text(capsule.message != nil ? "Message inclus" : "Capsule scellée")
                    .font(.appCaption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(capsule.daysUntilUnlock)")
                    .font(.appTitle).fontWeight(.black)
                    .foregroundColor(capsuleGoldDim)
                Text("jours")
                    .font(.appMicro)
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(capsuleGoldDim.opacity(0.18), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Unlocked Card

struct CapsuleUnlockedCard: View {
    let capsule: TimeCapsule
    let onTap: () -> Void
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(capsuleGoldDim.opacity(0.18))
                        .scaleEffect(pulse)
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "capsule.fill")
                        .font(.appHeadline)
                        .foregroundColor(.black)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("OUVRE-MOI")
                        .font(.appMicro).fontWeight(.black)
                        .foregroundColor(capsuleGoldBright)
                        .tracking(1.2)
                    Text("Capsule du \(capsule.formattedCreatedDate)")
                        .font(.appLabel)
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.appCaption).fontWeight(.semibold)
                    .foregroundColor(capsuleGoldDim)
            }
            .padding(14)
            .background(LinearGradient(
                colors: [capsuleGoldDim.opacity(0.12), capsuleGoldDim.opacity(0.05)],
                startPoint: .leading, endPoint: .trailing
            ))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                LinearGradient(colors: [capsuleGoldBright.opacity(0.5), capsuleGoldDim.opacity(0.2)],
                               startPoint: .leading, endPoint: .trailing), lineWidth: 1
            ))
            .cornerRadius(12)
        }
        .buttonStyle(SpringButtonStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = 1.14
            }
        }
    }
}

// MARK: - Empty State

private struct CapsuleEmptyState: View {
    let onCreate: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "capsule")
                .font(.system(size: 28))
                .foregroundColor(capsuleGoldDim.opacity(0.35))
            Text("Capture cet instant")
                .font(.appLabel).fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.65))
            Text("Scelle tes stats d'aujourd'hui et découvre ta progression dans 1, 3 ou 6 mois.")
                .font(.appCaption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Button(action: onCreate) {
                Text("Créer ma première capsule")
                    .font(.appLabel).fontWeight(.semibold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                              startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(20)
            }
            .buttonStyle(SpringButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct CapsuleSkeletonRow: View {
    var body: some View {
        HStack {
            Circle().fill(Color.white.opacity(0.05)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.05)).frame(width: 110, height: 10)
                Capsule().fill(Color.white.opacity(0.04)).frame(width: 70, height: 8)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Create View (4-step sheet)

struct TimeCapsuleCreateView: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var step             = 1
    @State private var snapshot: CapsuleSnapshot? = nil
    @State private var isLoadingSnap    = false
    @State private var snapFailed       = false
    @State private var message          = ""
    @State private var selectedDuration = 3
    @State private var isSealing        = false
    @State private var sealDone         = false

    var body: some View {
        NavigationStack {
            ZStack { capsuleBg.ignoresSafeArea()
                Group {
                    switch step {
                    case 1: step1View
                    case 2: step2View
                    case 3: step3View
                    default: step4View
                    }
                }
            }
            .navigationTitle(step < 4 ? stepTitles[step - 1] : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step < 4 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .task { await loadSnapshot() }
    }

    private let stepTitles = ["Aujourd'hui", "Ton message", "Délai"]

    // ── Step 1: Snapshot preview ──────────────────────────────────────────

    private var step1View: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voici qui tu es aujourd'hui")
                        .font(.appTitle).fontWeight(.black)
                        .foregroundColor(.white)
                    Text("Ces stats seront figées dans ta capsule.")
                        .font(.appLabel)
                        .foregroundColor(.gray)
                }

                if isLoadingSnap {
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            Capsule().fill(Color.white.opacity(0.05)).frame(height: 38).padding(.vertical, 5)
                        }
                    }
                    .padding(.horizontal, 4)
                } else if snapFailed {
                    VStack(spacing: 12) {
                        Text("Impossible de charger le snapshot.")
                            .font(.appLabel)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await loadSnapshot() }
                        } label: {
                            Text("Réessayer")
                                .font(.appLabel).fontWeight(.semibold)
                                .foregroundColor(capsuleGoldDim)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 20)
                } else if let snap = snapshot {
                    SnapshotPreviewCard(snapshot: snap)
                }

                GoldCTAButton(title: "Continuer →", disabled: isLoadingSnap || (snapshot == nil && !snapFailed)) {
                    step = 2
                }
            }
            .padding(20)
            .padding(.bottom, 16)
        }
    }

    // ── Step 2: Message ───────────────────────────────────────────────────

    private var step2View: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Écris à ton futur toi")
                        .font(.appTitle).fontWeight(.black)
                        .foregroundColor(.white)
                    Text("Optionnel. 280 caractères max.")
                        .font(.appLabel)
                        .foregroundColor(.gray)
                }

                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .font(.appBody)
                    .padding(14)
                    .frame(minHeight: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0.10, green: 0.10, blue: 0.14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(capsuleGoldDim.opacity(0.22), lineWidth: 1))
                    )
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Dans 3 mois je veux bench 225...")
                                .foregroundColor(.gray.opacity(0.45))
                                .font(.appBody)
                                .padding(.top, 22)
                                .padding(.leading, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: message) { _, newValue in
                        if newValue.count > 280 { message = String(newValue.prefix(280)) }
                    }

                HStack {
                    Spacer()
                    Text("\(message.count)/280")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }

                VStack(spacing: 10) {
                    GoldCTAButton(title: "Ajouter") { step = 3 }
                    Button { message = ""; step = 3 } label: {
                        Text("Passer")
                            .font(.appLabel)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 16)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // ── Step 3: Duration ──────────────────────────────────────────────────

    private var step3View: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quand l'ouvrir ?")
                    .font(.appTitle).fontWeight(.black)
                    .foregroundColor(.white)
                Text("Impossible de modifier après la création.")
                    .font(.appLabel)
                    .foregroundColor(.gray)
            }

            VStack(spacing: 12) {
                ForEach([1, 3, 6], id: \.self) { months in
                    DurationButton(months: months, selected: selectedDuration == months) {
                        selectedDuration = months
                    }
                }
            }

            Spacer()

            GoldCTAButton(title: "Sceller la capsule →", isLoading: isSealing) {
                await sealCapsule()
            }
        }
        .padding(20)
    }

    // ── Step 4: Seal animation ────────────────────────────────────────────

    private var step4View: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [capsuleGoldDim.opacity(0.14), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 110, height: 110)
                Image(systemName: "capsule.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                                    startPoint: .top, endPoint: .bottom))
                if sealDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appTitle)
                        .foregroundColor(capsuleGoldBright)
                        .offset(x: 30, y: -30)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 140)
            .animation(.spring(duration: 0.4), value: sealDone)

            VStack(spacing: 8) {
                Text(sealDone ? "Capsule scellée" : "Scellement en cours...")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                if sealDone {
                    Text("S'ouvre le \(unlockDateLabel)")
                        .font(.appLabel)
                        .foregroundColor(capsuleGoldDim)
                        .transition(.opacity)
                }
            }

            Spacer()

            if sealDone {
                Button { onCreated(); dismiss() } label: {
                    Text("Fermer")
                        .font(.appBody).fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(20)
        .animation(.easeInOut(duration: 0.5), value: sealDone)
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private var unlockDateLabel: String {
        let d = Calendar.current.date(byAdding: .month, value: selectedDuration, to: Date()) ?? Date()
        let f = DateFormatter()
        f.locale    = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func loadSnapshot() async {
        isLoadingSnap = true
        snapFailed    = false
        do {
            snapshot = try await APIService.shared.fetchCapsuleSnapshot()
        } catch {
            snapFailed = true
        }
        isLoadingSnap = false
    }

    private func sealCapsule() async {
        isSealing = true
        step      = 4
        do {
            let msg     = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let capsule = try await APIService.shared.createTimeCapsule(
                durationMonths: selectedDuration,
                message: msg.isEmpty ? nil : msg
            )
            scheduleUnlockNotifications(capsuleId: capsule.id, durationMonths: selectedDuration)
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation { sealDone = true }
        } catch {
            step = 3
        }
        isSealing = false
    }

    private func scheduleUnlockNotifications(capsuleId: String, durationMonths: Int) {
        guard let unlockDate = Calendar.current.date(byAdding: .month, value: durationMonths, to: Date()) else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            func schedule(id: String, title: String, body: String, date: Date) {
                let c         = UNMutableNotificationContent()
                c.title       = title
                c.body        = body
                c.sound       = .default
                var comps     = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
                comps.hour    = 9
                comps.minute  = 0
                let trigger   = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
            }

            schedule(id: "cap_\(capsuleId)_0",
                     title: "Ta capsule est prête 🔓",
                     body:  "Vois qui tu es devenu.",
                     date:  unlockDate)

            if let d1 = Calendar.current.date(byAdding: .day, value: 1, to: unlockDate) {
                schedule(id: "cap_\(capsuleId)_1",
                         title: "Ta capsule t'attend",
                         body:  "Tu n'as pas encore découvert ta progression.",
                         date:  d1)
            }
        }
    }
}

// MARK: - Duration Button

private struct DurationButton: View {
    let months: Int
    let selected: Bool
    let onTap: () -> Void

    private var unlockDateLabel: String {
        let d = Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date()
        let f = DateFormatter()
        f.locale    = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        return f.string(from: d)
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(months) mois")
                        .font(.appBody).fontWeight(.bold)
                        .foregroundColor(selected ? .black : .white)
                    Text("Ouvre le \(unlockDateLabel)")
                        .font(.appCaption)
                        .foregroundColor(selected ? .black.opacity(0.55) : .gray)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.black.opacity(0.65))
                }
            }
            .padding(16)
            .background(
                Group {
                    if selected {
                        LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                       startPoint: .leading, endPoint: .trailing)
                    } else {
                        LinearGradient(colors: [Color(white: 0.09), Color(white: 0.09)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                }
            )
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.clear : capsuleGoldDim.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(SpringButtonStyle())
    }
}

// MARK: - Snapshot Preview Card

private struct SnapshotPreviewCard: View {
    let snapshot: CapsuleSnapshot

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].0)
                        .font(.appLabel)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(rows[i].1)
                        .font(.appLabel).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                if i < rows.count - 1 {
                    Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 16)
                }
            }
        }
        .background(Color(white: 0.07))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(capsuleGoldDim.opacity(0.12), lineWidth: 1))
    }

    private var rows: [(String, String)] {
        var r: [(String, String)] = []
        for (key, pr) in snapshot.prs.sorted(by: { $0.key < $1.key }) {
            r.append((key.replacingOccurrences(of: "_", with: " ").capitalized,
                      "\(Int(pr.weight)) kg × \(pr.reps)"))
        }
        r.append(("Volume hebdo moy.", "\(Int(snapshot.weeklyVolumeAvgKg / 1000)) t"))
        r.append(("Séances ce mois",   "\(Int(snapshot.sessionsPerMonthAvg))"))
        if let bw = snapshot.bodyWeightKg {
            r.append(("Poids", String(format: "%.1f kg", bw)))
        }
        if snapshot.macrosAvg.proteinG > 0 {
            r.append(("Protéines moy./j", "\(Int(snapshot.macrosAvg.proteinG)) g"))
        }
        return r
    }
}

// MARK: - Gold CTA Button

private struct GoldCTAButton: View {
    let title: String
    var disabled: Bool  = false
    var isLoading: Bool = false
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.black).scaleEffect(0.85)
                } else {
                    Text(title).font(.appBody).fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                       startPoint: .leading, endPoint: .trailing))
            .foregroundColor(.black)
            .cornerRadius(14)
            .opacity(disabled ? 0.4 : 1)
        }
        .disabled(disabled || isLoading)
        .buttonStyle(SpringButtonStyle())
    }
}

// MARK: - Reveal View (full-screen)

struct TimeCapsuleRevealView: View {
    let capsule: TimeCapsule
    let onDismiss: () -> Void

    @State private var openedCapsule: TimeCapsule? = nil
    @State private var phase: RevealPhase = .intro
    @State private var introOpacity: Double = 0
    @State private var staggerIndex = 0
    @State private var showVerdict  = false
    @State private var showCTAs     = false
    @State private var showShare    = false

    private enum RevealPhase { case intro, letter, comparison, verdict, ctas }

    private var display: TimeCapsule { openedCapsule ?? capsule }

    var body: some View {
        ZStack {
            capsuleBg.ignoresSafeArea()
            switch phase {
            case .intro:      introView
            case .letter:     letterView
            case .comparison: comparisonView
            case .verdict:    verdictView
            case .ctas:       ctaView
            }
        }
        .task {
            openedCapsule = try? await APIService.shared.openTimeCapsule(id: capsule.id)
            withAnimation(.easeIn(duration: 1.4)) { introOpacity = 1 }
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if phase == .intro { advance() }
        }
        .sheet(isPresented: $showShare) {
            TimeCapsuleShareSheet(capsule: display)
        }
    }

    // ── Phase 1: Atmospheric intro ────────────────────────────────────────

    private var introView: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(display.formattedCreatedDate.uppercased())
                .font(.appCaption).fontWeight(.semibold)
                .foregroundColor(capsuleGoldDim)
                .tracking(3)
            Text("\(display.durationMonths) mois plus tard...")
                .font(.appHero).fontWeight(.black)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Spacer()
            Text("Touche pour continuer")
                .font(.appCaption)
                .foregroundColor(.gray.opacity(0.5))
                .padding(.bottom, 48)
        }
        .opacity(introOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .padding(.horizontal, 32)
    }

    // ── Phase 2: Letter ───────────────────────────────────────────────────

    @ViewBuilder
    private var letterView: some View {
        if let msg = display.message, !msg.isEmpty {
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.open.fill").foregroundColor(capsuleGoldDim)
                        Text("TON MESSAGE")
                            .font(.appCaption).fontWeight(.bold)
                            .foregroundColor(capsuleGoldDim)
                            .tracking(1.5)
                    }
                    Text(msg)
                        .font(.system(size: 19, weight: .medium, design: .serif))
                        .foregroundColor(.white.opacity(0.90))
                        .lineSpacing(7)
                        .italic()
                }
                .padding(24)
                .background(Color(red: 0.10, green: 0.10, blue: 0.14))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(capsuleGoldDim.opacity(0.28), lineWidth: 1))
                .cornerRadius(16)
                .padding(.horizontal, 24)
                Spacer()
                Button { advance() } label: {
                    Text("Voir ma progression →")
                        .font(.appLabel).fontWeight(.semibold)
                        .foregroundColor(capsuleGoldDim)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 48)
            }
        } else {
            Color.clear.onAppear { advance() }
        }
    }

    // ── Phase 3: Comparison ───────────────────────────────────────────────

    private var comparisonView: some View {
        let metrics = display.comparisonMetrics()
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("AVANT  ·  MAINTENANT")
                        .font(.appCaption).fontWeight(.bold)
                        .foregroundColor(capsuleGoldDim)
                        .tracking(2)
                    Text("\(display.formattedCreatedDate)  →  Aujourd'hui")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
                .padding(.top, 52)

                if metrics.isEmpty {
                    Text("Pas encore assez de données pour comparer.")
                        .font(.appLabel)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 0) {
                        ForEach(metrics.indices, id: \.self) { i in
                            ComparisonRow(metric: metrics[i], visible: i < staggerIndex)
                            if i < metrics.count - 1 {
                                Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color(white: 0.07))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(capsuleGoldDim.opacity(0.12), lineWidth: 1))
                    .padding(.horizontal, 20)
                }

                Button { advance() } label: {
                    Text("Continuer →")
                        .font(.appLabel).fontWeight(.semibold)
                        .foregroundColor(capsuleGoldDim)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 48)
                .opacity(staggerIndex >= metrics.count ? 1 : 0)
                .animation(.easeIn(duration: 0.4), value: staggerIndex)
            }
        }
        .onAppear {
            for i in 0..<metrics.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.20 + 0.4) {
                    withAnimation(.easeOut(duration: 0.3)) { staggerIndex = i + 1 }
                }
            }
            if metrics.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { advance() }
            }
        }
    }

    // ── Phase 4: Verdict ──────────────────────────────────────────────────

    private var verdictView: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(display.motivationalVerdict)
                .font(.appHero).fontWeight(.black)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .opacity(showVerdict ? 1 : 0)
                .animation(.easeIn(duration: 0.9), value: showVerdict)
            Spacer()
            Button { advance() } label: {
                Text("Continuer →")
                    .font(.appLabel)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 48)
            .opacity(showVerdict ? 1 : 0)
            .animation(.easeIn(duration: 0.4).delay(0.9), value: showVerdict)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation { showVerdict = true }
            }
        }
    }

    // ── Phase 5: CTAs ─────────────────────────────────────────────────────

    private var ctaView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "capsule.fill")
                .font(.system(size: 44))
                .foregroundStyle(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                                startPoint: .top, endPoint: .bottom))
                .opacity(showCTAs ? 1 : 0)
            Spacer()
            VStack(spacing: 12) {
                Button { showShare = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Partager mon avant/après")
                            .font(.appBody).fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.black)
                    .cornerRadius(14)
                }
                .buttonStyle(SpringButtonStyle())

                Button { onDismiss() } label: {
                    Text("Fermer")
                        .font(.appLabel)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .opacity(showCTAs ? 1 : 0)
            .animation(.easeIn(duration: 0.5), value: showCTAs)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { showCTAs = true }
            }
        }
    }

    // ── Advance helper ────────────────────────────────────────────────────

    private func advance() {
        withAnimation(.easeInOut(duration: 0.35)) {
            switch phase {
            case .intro:      phase = (display.message?.isEmpty == false) ? .letter : .comparison
            case .letter:     phase = .comparison
            case .comparison: phase = .verdict
            case .verdict:    phase = .ctas
            case .ctas:       onDismiss()
            }
        }
    }
}

// MARK: - Comparison Row

private struct ComparisonRow: View {
    let metric: CapsuleMetric
    let visible: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(metric.label)
                .font(.appCaption)
                .foregroundColor(.gray)
                .frame(width: 100, alignment: .leading)

            Text(metric.before)
                .font(.appCaption).fontWeight(.medium)
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .center)

            Image(systemName: "arrow.right")
                .font(.appMicro)
                .foregroundColor(Color(white: 0.35))

            Text(metric.after)
                .font(.appCaption).fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(metric.delta)
                .font(.appCaption).fontWeight(.bold)
                .foregroundColor(
                    metric.isNeutral
                        ? .gray
                        : metric.deltaPositive
                            ? .green
                            : Color(red: 0.97, green: 0.50, blue: 0.50)
                )
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 8)
        .animation(.easeOut(duration: 0.28), value: visible)
    }
}

// MARK: - Share Sheet

struct TimeCapsuleShareSheet: View {
    let capsule: TimeCapsule
    @Environment(\.dismiss) private var dismiss
    @State private var showActivity = false
    @State private var shareImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Aperçu")
                    .font(.appBody).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.top, 16)

                TimeCapsuleShareCard(capsule: capsule)
                    .frame(width: 300, height: 300)
                    .cornerRadius(16)
                    .shadow(color: capsuleGoldDim.opacity(0.25), radius: 20)

                Text("PSS et données de santé mentale exclus du partage.")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    let renderer = ImageRenderer(content:
                        TimeCapsuleShareCard(capsule: capsule).frame(width: 400, height: 400)
                    )
                    renderer.scale = 3.0
                    shareImage   = renderer.uiImage
                    showActivity = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Exporter").font(.appBody).fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 24)

                Spacer()
            }
            .background(capsuleBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }
                }
            }
            .sheet(isPresented: $showActivity) {
                if let img = shareImage {
                    ShareSheetController(items: [img])
                }
            }
        }
    }
}

// MARK: - Share Card (rendered to image)

struct TimeCapsuleShareCard: View {
    let capsule: TimeCapsule

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.04, blue: 0.09),
                         Color(red: 0.09, green: 0.07, blue: 0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TRAININGOS")
                            .font(.appMicro).fontWeight(.black)
                            .foregroundColor(capsuleGoldDim)
                            .tracking(2.5)
                        Text("TIME CAPSULE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.gray)
                            .tracking(1.5)
                    }
                    Spacer()
                    Image(systemName: "capsule.fill")
                        .font(.appBody)
                        .foregroundColor(capsuleGoldDim)
                }

                Text("\(capsule.formattedCreatedDate)  →  Aujourd'hui")
                    .font(.appCaption).fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.8))

                Rectangle().fill(capsuleGoldDim.opacity(0.35)).frame(height: 1)

                let metrics = capsule.comparisonMetrics().prefix(5)
                VStack(spacing: 6) {
                    ForEach(metrics) { m in
                        HStack {
                            Text(m.label)
                                .font(.appMicro)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(m.before) → \(m.after)")
                                .font(.appMicro).fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.75))
                            Text(m.delta)
                                .font(.appMicro).fontWeight(.bold)
                                .foregroundColor(m.isNeutral ? .gray
                                    : m.deltaPositive ? .green
                                    : Color(red: 0.97, green: 0.50, blue: 0.50))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                if let msg = capsule.message, !msg.isEmpty {
                    Rectangle().fill(capsuleGoldDim.opacity(0.2)).frame(height: 1)
                    Text("« \(msg) »")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(.white.opacity(0.65))
                        .italic()
                        .lineLimit(2)
                }

                Spacer()

                Rectangle()
                    .fill(LinearGradient(colors: [capsuleGoldDim, capsuleGoldBright],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3)
                    .cornerRadius(2)
            }
            .padding(20)
        }
    }
}

// MARK: - UIActivityViewController wrapper

private struct ShareSheetController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
