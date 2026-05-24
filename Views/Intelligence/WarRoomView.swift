import SwiftUI
import Combine

struct WarRoomView: View {
    @StateObject private var vm = WarRoomViewModel()
    @State private var tab: WarRoomTab = .counter
    @State private var showTriggerSheet  = false
    @State private var showAddArsenal    = false
    @State private var showOath          = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.appBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    tabBar
                    tabContent
                }

                // Emergency FAB — always accessible
                if tab != .arsenal {
                    Button {
                        tab = .arsenal
                    } label: {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.forge, in: Circle())
                            .shadow(color: Color.forge.opacity(0.40), radius: 10, y: 4)
                    }
                    .accessibilityLabel("Arsenal — ouvrir mes armes contre le craving")
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
                }
            }
            .navigationTitle("War Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("WAR ROOM")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forge)
                        .tracking(3)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showOath = true } label: {
                            Image(systemName: "text.quote")
                                .foregroundStyle(Color.secondary)
                                .font(.system(size: 14))
                        }
                        NavigationLink {
                            WarRoomSettingsView(vm: vm)
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
        }
        .task { await vm.loadAll() }
        .sheet(isPresented: $showOath) {
            OathGateView()
        }
        .sheet(isPresented: $showTriggerSheet, onDismiss: { Task { await vm.loadAll() } }) {
            TriggerLogView(vm: vm)
        }
        .sheet(isPresented: $showAddArsenal, onDismiss: { Task { await vm.loadArsenal() } }) {
            AddArsenalView(vm: vm)
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(WarRoomTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon)
                            .font(.system(size: 15, weight: tab == t ? .bold : .regular))
                        Text(t.label)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(tab == t ? Color.forge : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if tab == t {
                            Rectangle().fill(Color.forge).frame(height: 2)
                        }
                    }
                }
            }
        }
        .background(Color.appCard)
    }

    // MARK: Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .counter:
            BattleCounterView(vm: vm)
        case .trigger:
            TriggerHistoryView(vm: vm, showSheet: $showTriggerSheet)
        case .arsenal:
            ArsenalView(vm: vm, showAdd: $showAddArsenal)
        case .patterns:
            PatternReportView(vm: vm)
        case .map:
            WarMapView(vm: vm)
        }
    }
}

// MARK: - Tabs

enum WarRoomTab: CaseIterable {
    case counter, trigger, arsenal, patterns, map

    var label: String {
        switch self {
        case .counter:  return "Compteur"
        case .trigger:  return "Journal"
        case .arsenal:  return "Arsenal"
        case .patterns: return "Patterns"
        case .map:      return "Carte"
        }
    }

    var icon: String {
        switch self {
        case .counter:  return "shield.fill"
        case .trigger:  return "exclamationmark.triangle.fill"
        case .arsenal:  return "bolt.fill"
        case .patterns: return "waveform.path.ecg"
        case .map:      return "map.fill"
        }
    }
}

// MARK: - ViewModel

@MainActor
class WarRoomViewModel: ObservableObject {
    @Published var summary:        WarRoomSummary?
    @Published var battles:        [WarRoomBattle]      = []
    @Published var triggers:       [WarRoomTrigger]     = []
    @Published var arsenal:        [WarRoomArsenalItem] = []
    @Published var patterns:       WarRoomPatterns?
    @Published var warMap:         [WarMapMonth]        = []
    @Published var currentOath:    OathModel?           = nil
    @Published var streakJustReset = false
    @Published var isLoading       = false
    @Published var error: String?
    // G5: Phoenix demons as active threats
    @Published var phoenixDemons: [RitualDemon] = []

    private let api = APIService.shared

    func loadAll() async {
        isLoading = true
        error = nil
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadSummary() }
            g.addTask { await self.loadBattles() }
            g.addTask { await self.loadTriggers() }
            g.addTask { await self.loadArsenal() }
            g.addTask { await self.loadOath() }
            g.addTask { await self.loadPhoenixDemons() }
        }
        isLoading = false
    }

    func loadPhoenixDemons() async {
        if let ritual = try? await api.fetchRitualToday() {
            await MainActor.run {
                phoenixDemons = ritual.demons.sorted { $0.carryCount > $1.carryCount }
            }
        }
    }

    func loadOath() async {
        currentOath = try? await api.getCurrentOath()
    }

    func loadSummary() async {
        summary = try? await api.getWarRoomSummary()
    }

    func loadBattles() async {
        battles = (try? await api.getWarRoomBattles()) ?? []
    }

    func loadTriggers() async {
        triggers = (try? await api.getWarRoomTriggers()) ?? []
    }

    func loadArsenal() async {
        arsenal = (try? await api.getWarRoomArsenal()) ?? []
    }

    func loadPatterns() async {
        patterns = try? await api.getWarRoomPatterns()
    }

    func loadWarMap() async {
        warMap = (try? await api.getWarMap()) ?? []
    }

    func logBattle(_ status: BattleStatus) async {
        let prevStreak = summary?.victoryStreak ?? 0
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10).description
        if let s = try? await api.upsertBattle(date: today, status: status) {
            if status == .lost && prevStreak > 0 && s.victoryStreak == 0 {
                streakJustReset = true
            }
            summary = s
        }
        await loadBattles()
    }

    func deployWeapon(_ item: WarRoomArsenalItem) async {
        try? await api.deployArsenalItem(item.id)
        await loadArsenal()
    }

    func deleteWeapon(_ item: WarRoomArsenalItem) async {
        try? await api.deleteArsenalItem(item.id)
        await loadArsenal()
    }
}
