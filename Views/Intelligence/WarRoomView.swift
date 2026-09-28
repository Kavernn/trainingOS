import SwiftUI
import Combine

struct WarRoomView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var progressStore = WarRoomProgressStore.shared
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
                    Button {
                        tab = .arsenal
                    } label: {
                        Label("Besoin d’un coup de main", systemImage: "bolt.shield.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .foregroundStyle(Color.forge)
                    .padding(.horizontal, 16)
                    tabContent
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
        .task(id: scenePhase) {
            if scenePhase == .active { await progressStore.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            progressStore.reprojectForCurrentDate()
        }
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
            WarRoomProgressView(store: progressStore)
        case .trigger:
            TriggerHistoryView(vm: vm, showSheet: $showTriggerSheet)
        case .arsenal:
            ArsenalView(vm: vm, showAdd: $showAddArsenal)
        case .patterns:
            PatternReportView(vm: vm)
        }
    }
}

// MARK: - Tabs

enum WarRoomTab: CaseIterable {
    case counter, trigger, arsenal, patterns

    var label: String {
        switch self {
        case .counter:  return "Victoires"
        case .trigger:  return "Journal"
        case .arsenal:  return "Arsenal"
        case .patterns: return "Patterns"
        }
    }

    var icon: String {
        switch self {
        case .counter:  return "shield.fill"
        case .trigger:  return "exclamationmark.triangle.fill"
        case .arsenal:  return "bolt.fill"
        case .patterns: return "waveform.path.ecg"
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

    private let api = APIService.shared

    func loadAll() async {
        isLoading = true
        error = nil
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await WarRoomProgressStore.shared.refresh() }
            g.addTask { await self.loadTriggers() }
            g.addTask { await self.loadArsenal() }
            g.addTask { await self.loadOath() }
        }
        isLoading = false
    }

    func loadOath() async {
        currentOath = try? await api.getCurrentOath()
    }

    func loadSummary() async {
        summary = try? await api.getWarRoomSummary()
    }

    func loadBattles() async {
        await WarRoomProgressStore.shared.refresh(force: true)
        if let progress = WarRoomProgressStore.shared.progress { battles = progress.history.battles }
    }

    func loadTriggers() async {
        if let result = try? await api.getWarRoomTriggers() { triggers = result }
    }

    func loadArsenal() async {
        if let result = try? await api.getWarRoomArsenal() { arsenal = result }
    }

    func loadPatterns() async {
        patterns = try? await api.getWarRoomPatterns()
    }

    func loadWarMap() async {
        warMap = (try? await api.getWarMap()) ?? []
    }

    func logBattle(_ status: BattleStatus, force: Bool = false) async {
        let prevStreak = summary?.victoryStreak ?? 0
        let today = DateFormatter.isoDate.string(from: Date())
        do {
            let s = try await api.upsertBattle(date: today, status: status, force: force)
            if status == .lost && prevStreak > 0 && s.victoryStreak == 0 {
                streakJustReset = true
            }
            summary = s
        } catch APIError.queuedOffline {
            // mutation enfilée hors-ligne — rien à signaler à l'user
        } catch let err as APIError {
            if case .serverError(409, _) = err {
                await loadSummary()  // re-sync : un log existe déjà côté serveur
            }
            error = err.localizedDescription
        } catch {
            self.error = error.localizedDescription
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
