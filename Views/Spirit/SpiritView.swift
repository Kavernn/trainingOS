import SwiftUI
import Combine

// MARK: - Entry point

struct SpiritView: View {
    @StateObject private var vm  = SpiritViewModel()
    @State private var tab: SpiritTab = .breath

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voidBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    spiritTabBar
                    tabContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("THE VOID")
                            .font(.system(size: 11, weight: .light, design: .monospaced))
                            .foregroundStyle(Color.moonlight.opacity(0.5))
                            .tracking(5)
                        Text("Respiration · Méditation · Journal")
                            .font(.appMicro.weight(.light))
                            .foregroundStyle(Color.moonlight.opacity(0.25))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SpiritSettingsView(vm: vm)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Color.moonlight.opacity(0.4))
                            .font(.system(size: 14))
                    }
                }
            }
        }
        .task { await vm.loadSummary() }
    }

    // MARK: - Tab bar

    private var spiritTabBar: some View {
        HStack(spacing: 0) {
            ForEach(SpiritTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.icon)
                            .font(.system(size: 14, weight: tab == t ? .medium : .light))
                        Text(t.label)
                            .font(.system(size: 10, weight: tab == t ? .medium : .light))
                        Text(t.subtitle)
                            .font(.system(size: 8, weight: .light))
                            .opacity(0.6)
                    }
                    .foregroundStyle(tab == t ? Color.moonlight : Color.moonlight.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if tab == t {
                            Rectangle()
                                .fill(Color.moonlight.opacity(0.4))
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .background(Color.voidBg)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .breath:    SpiritBreathTabView(vm: vm)
        case .meditate:  SpiritMeditationTabView(vm: vm)
        case .journal:   SpiritJournalGateView(vm: vm)
        }
    }
}

// MARK: - Tabs

enum SpiritTab: CaseIterable {
    case breath, meditate, journal

    var label: String {
        switch self {
        case .breath:   return "Respiration"
        case .meditate: return "Méditation"
        case .journal:  return "Journal"
        }
    }

    var subtitle: String {
        switch self {
        case .breath:   return "Exercices guidés"
        case .meditate: return "Timer silencieux"
        case .journal:  return "Privé · Face ID"
        }
    }

    var icon: String {
        switch self {
        case .breath:   return "wind"
        case .meditate: return "circle"
        case .journal:  return "lock.fill"
        }
    }
}

// MARK: - ViewModel

@MainActor
class SpiritViewModel: ObservableObject {
    @Published var breathSessions:  [SpiritBreathSession] = []
    @Published var medSessions:     [MeditationSession] = []
    @Published var journalStubs:    [SpiritJournalStub] = []
    @Published var patterns:        SpiritPatterns?
    @Published var config:          SpiritConfig?
    @Published var isLoading = false

    private let api = APIService.shared

    func loadSummary() async {
        isLoading = true
        breathSessions = (try? await api.getSpiritBreathSessions(limit: 10)) ?? []
        medSessions    = (try? await api.getMeditationSessions(limit: 10)) ?? []
        journalStubs   = (try? await api.getSpiritJournalStubs(limit: 30)) ?? []
        config         = try? await api.getSpiritConfig()
        isLoading = false
    }

    func reloadBreath() async {
        breathSessions = (try? await api.getSpiritBreathSessions(limit: 10)) ?? []
    }

    func reloadMed() async {
        medSessions = (try? await api.getMeditationSessions(limit: 10)) ?? []
    }

    func reloadJournal() async {
        journalStubs = (try? await api.getSpiritJournalStubs(limit: 30)) ?? []
    }

    func loadPatterns() async {
        patterns = try? await api.getSpiritPatterns()
    }

    func todayHasJournal() -> Bool {
        let today = DateFormatter.isoDate.string(from: Date())
        return journalStubs.contains { $0.date == today }
    }
}

// MARK: - Settings

struct SpiritSettingsView: View {
    @ObservedObject var vm: SpiritViewModel
    @State private var phoenix = false
    @State private var loaded  = false

    var body: some View {
        Form {
            Section("Phoenix Score") {
                Toggle("Axe Spirit (20%)", isOn: $phoenix)
                    .tint(Color.moonlight)
                    .onChange(of: phoenix) { _, v in
                        guard loaded else { return }
                        Task { try? await APIService.shared.updateSpiritConfig(["integration_phoenix": v]) }
                    }
            }
            .listRowBackground(Color.voidBg.opacity(0.8))

            Section {
                Text("Le journal intime n'est jamais transmis au coach IA ni inclus dans les analytics.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.moonlight.opacity(0.4))
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(Color.voidBg)
        .navigationTitle("Esprit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            phoenix = vm.config?.integrationPhoenix ?? false
            loaded  = true
        }
    }
}
