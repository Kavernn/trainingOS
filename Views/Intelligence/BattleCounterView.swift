import SwiftUI

struct BattleCounterView: View {
    @ObservedObject var vm: WarRoomViewModel
    @State private var logging = false
    @State private var pulsing = false

    var body: some View {
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
    }

    // MARK: Streak card

    private func streakCard(_ s: WarRoomSummary) -> some View {
        VStack(spacing: 6) {
            Text("\(s.victoryStreak)")
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundStyle(streakColor(s.victoryStreak))
                .scaleEffect(pulsing ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.4), value: pulsing)

            Text(s.victoryStreak == 1 ? "JOUR TENU" : "JOURS TENUS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(3)

            if s.bestStreak > 0 {
                Text("Record : \(s.bestStreak)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(cardBg(s.victoryStreak), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(streakColor(s.victoryStreak).opacity(0.25), lineWidth: 1))
        .onAppear { pulsing = true }
    }

    private func cardBg(_ streak: Int) -> some ShapeStyle {
        if streak >= 7 {
            return LinearGradient(colors: [Color.forge.opacity(0.18), Color.appCard], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color.appCard, Color.appCard], startPoint: .top, endPoint: .bottom)
    }

    private func streakColor(_ streak: Int) -> Color {
        streak >= 30 ? .forge : streak >= 7 ? Color.orange : streak >= 1 ? Color.primary : Color.secondary
    }

    // MARK: Stats row

    private func statsRow(_ s: WarRoomSummary) -> some View {
        HStack(spacing: 12) {
            statCell(value: s.totalVictories, label: "VICTOIRES")
            statCell(value: s.totalBattles,   label: "BATAILLES")
            let rate = s.totalBattles > 0 ? Int(Double(s.totalVictories) / Double(s.totalBattles) * 100) : 0
            statCell(value: rate, label: "RATIO %")
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
                        Task { await vm.logBattle(status == .victory ? .lost : .victory) }
                    }
                    .font(.system(size: 13))
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
    }

    private func statusColor(_ s: BattleStatus) -> Color {
        switch s {
        case .victory: return Color.forge
        case .lost:    return Color.secondary
        case .active:  return Color.orange
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
}
