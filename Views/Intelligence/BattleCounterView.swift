import SwiftUI

struct BattleCounterView: View {
    @ObservedObject var vm: WarRoomViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logging          = false
    @State private var pulsing          = false
    @State private var showOathRecall   = false
    @State private var showMilestone    = false
    @State private var milestoneDay     = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    if vm.isLoading && vm.summary == nil {
                        ProgressView().tint(Color.forge).padding(.top, 60)
                    } else if let s = vm.summary {
                        streakCard(s)
                        statsRow(s)
                        todayCard(s)
                        if let start = s.warStartDate {
                            warDayLabel(start: start, days: s.warDays)
                        }
                    }
                }
                .padding(16)
            }

            if showOathRecall, let oath = vm.currentOath {
                oathRecallBanner(oath)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.4), value: showOathRecall)
        .onChange(of: vm.streakJustReset) { _, reset in
            if reset { showOathRecall = true }
        }
        .onChange(of: vm.summary?.warDays) { _, days in
            guard let d = days else { return }
            checkMilestone(d)
        }
        .sheet(isPresented: $showMilestone) {
            oathMilestoneSheet(day: milestoneDay, oath: vm.currentOath)
        }
        .alert("Note", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    // MARK: Streak card

    private func streakCard(_ s: WarRoomSummary) -> some View {
        VStack(spacing: 6) {
            if let rate30 = s.winRate30d {
                Text("\(rate30)%")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(progressionColor(rate30))
                    .scaleEffect(pulsing ? 1.04 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.4), value: pulsing)
                Text("VICTOIRES SUR 30 JOURS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .tracking(3)
            } else {
                Text("\(s.victoryStreak)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(streakColor(s.victoryStreak))
                    .scaleEffect(pulsing ? 1.04 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.4), value: pulsing)
                Text(s.victoryStreak == 1 ? "JOUR TENU" : "JOURS TENUS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .tracking(3)
            }

            HStack(spacing: 12) {
                if s.victoryStreak > 0 {
                    Text("Série : \(s.victoryStreak)j")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                if s.bestStreak > 0 {
                    Text("Record : \(s.bestStreak)j")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(cardBg(s.victoryStreak), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(streakColor(s.victoryStreak).opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Taux de victoire 30 jours : \(s.winRate30d.map { "\($0)%" } ?? "–"). Série actuelle : \(s.victoryStreak) jour\(s.victoryStreak != 1 ? "s" : ""). Record : \(s.bestStreak).")
        .onAppear { pulsing = true }
    }

    private func progressionColor(_ rate: Int) -> Color {
        rate >= 80 ? .forge : rate >= 60 ? Color.forge : Color(white: 0.5)
    }

    private func cardBg(_ streak: Int) -> some ShapeStyle {
        if streak >= 7 {
            return LinearGradient(colors: [Color.forge.opacity(0.18), Color.appCard], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color.appCard, Color.appCard], startPoint: .top, endPoint: .bottom)
    }

    private func streakColor(_ streak: Int) -> Color {
        streak >= 30 ? .forge : streak >= 7 ? Color.forge : streak >= 1 ? Color.primary : Color.secondary
    }

    // MARK: Stats row

    private func statsRow(_ s: WarRoomSummary) -> some View {
        HStack(spacing: 12) {
            if let rateWeek = s.winRateWeek {
                statCell(value: rateWeek, label: "SEMAINE %")
            } else {
                statCellPlaceholder(label: "SEMAINE %")
            }
            statCell(value: s.totalVictories, label: "VICTOIRES")
            statCell(value: s.totalBattles,   label: "BATAILLES")
            if let rate90 = s.winRate90d {
                statCell(value: rate90, label: "TAUX 90J %")
            } else {
                statCellPlaceholder(label: "TAUX 90J %")
            }
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized) : \(value)")
    }

    private func statCellPlaceholder(label: String) -> some View {
        VStack(spacing: 4) {
            Text("—")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.secondary)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized) : pas assez de données")
    }

    // MARK: Today card

    private func todayCard(_ s: WarRoomSummary) -> some View {
        VStack(spacing: 16) {
            Text("AUJOURD'HUI")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let status = s.todayStatus {
                HStack {
                    Image(systemName: status == .victory ? "checkmark.shield.fill" : status == .lost ? "xmark.shield.fill" : "shield.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(statusColor(status))
                    Text(statusLabel(status))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(statusColor(status))
                    Spacer()
                    Button("Modifier") {
                        Task { await vm.logBattle(status == .victory ? .lost : .victory, force: true) }
                    }
                    .font(.appLabel)
                    .foregroundStyle(Color.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    battleButton("Victoire", status: .victory, icon: "checkmark.shield.fill", color: Color.forge)
                    battleButton("Perdu",    status: .lost,    icon: "xmark.shield.fill",    color: Color(white: 0.5))
                }
            }
        }
        .padding(16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private func battleButton(_ label: String, status: BattleStatus, icon: String, color: Color) -> some View {
        Button {
            Task {
                logging = true
                await vm.logBattle(status)
                logging = false
            }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(logging)
        .accessibilityHint(status == .victory ? "Marque aujourd'hui comme une victoire" : "Marque aujourd'hui comme une défaite")
    }

    private func statusColor(_ s: BattleStatus) -> Color {
        switch s {
        case .victory: return Color.forge
        case .lost:    return Color.secondary
        case .active:  return Color.statusOrange
        }
    }

    private func statusLabel(_ s: BattleStatus) -> String {
        switch s {
        case .victory: return "Victoire tenue"
        case .lost:    return "Journée perdue"
        case .active:  return "En cours"
        }
    }

    // MARK: War day label

    private func warDayLabel(start: String, days: Int) -> some View {
        HStack {
            Image(systemName: "flag.fill").foregroundStyle(Color.forge.opacity(0.6)).font(.system(size: 12))
            Text("Jour \(days) depuis le \(formattedDate(start))")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale    = Locale(identifier: "fr_CA")
        return f.string(from: d)
    }

    // MARK: Oath recall banner

    private func oathRecallBanner(_ oath: OathModel) -> some View {
        VStack(spacing: 0) {
            Divider().background(Color.forge.opacity(0.4))
            VStack(spacing: 8) {
                Text("TON SERMENT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forge.opacity(0.7))
                    .tracking(4)
                Text("\u{201C}\(oath.text)\u{201D}")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
                Button("Fermer") {
                    showOathRecall = false
                    vm.streakJustReset = false
                    Task { try? await APIService.shared.logOathRecall(oathId: oath.id, trigger: "streak_reset") }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .padding(.top, 4)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.appCard)
        }
    }

    // MARK: Milestone

    private func checkMilestone(_ days: Int) {
        let milestones = [30, 90, 180, 365]
        guard milestones.contains(days) else { return }
        let key = "oath_last_milestone_shown"
        let last = UserDefaults.standard.integer(forKey: key)
        guard last != days else { return }
        UserDefaults.standard.set(days, forKey: key)
        milestoneDay = days
        showMilestone = true
        if let oath = vm.currentOath {
            Task { try? await APIService.shared.logOathRecall(oathId: oath.id, trigger: "milestone") }
        }
    }

    @ViewBuilder
    private func oathMilestoneSheet(day: Int, oath: OathModel?) -> some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: "seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.forge)
                VStack(spacing: 12) {
                    Text("JOUR \(day)")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.forge)
                    Text("Tu tiens ton serment.")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Color.primary)
                }
                if let oath {
                    Text("\u{201C}\(oath.text)\u{201D}")
                        .font(.system(size: 15, weight: .light, design: .serif))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
                Button("Continuer le combat") { showMilestone = false }
                    .font(.appBody.weight(.semibold))
                    .foregroundStyle(Color.forge)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.forge.opacity(0.12), in: Capsule())
                    .padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium])
    }
}
