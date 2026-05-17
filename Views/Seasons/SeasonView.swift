import SwiftUI
import Combine

// MARK: - Main view

struct SeasonView: View {
    @StateObject private var vm = SeasonViewModel()
    @State private var showStart = false
    @State private var showClose = false
    @State private var selectedReport: SeasonReport?
    @State private var showReport = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if let active = vm.activeSeason {
                            activeCard(active)
                        } else {
                            noActiveCard
                        }

                        if !vm.completedSeasons.isEmpty {
                            chaptersSection
                        }
                    }
                    .padding(16)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MES CHAPITRES")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .tracking(4)
                }
            }
        }
        .task { await vm.load() }
        .fullScreenCover(isPresented: $showStart, onDismiss: { Task { await vm.load() } }) {
            SeasonStartView(
                seasonNumber: (vm.allSeasons.map(\.number).max() ?? 0) + 1,
                onStarted: {
                    showStart = false
                    Task { await vm.load() }
                },
                onDismiss: { showStart = false }
            )
        }
        .fullScreenCover(isPresented: $showClose, onDismiss: { Task { await vm.load() } }) {
            if let active = vm.activeSeason {
                SeasonCloseView(season: active) {
                    showClose = false
                    Task { await vm.load() }
                }
            }
        }
        .sheet(isPresented: $showReport) {
            if let r = selectedReport {
                seasonReportSheet(r)
            }
        }
    }

    // MARK: Active card

    private func activeCard(_ season: Season) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EN COURS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forge)
                        .tracking(4)
                    Text("SEASON \(season.number)")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .tracking(2)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("JOUR")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .tracking(2)
                    Text("\(season.dayNumber)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(Color.forge)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("/ 90")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }
            }

            ProgressView(value: min(Double(season.dayNumber) / 90.0, 1.0))
                .tint(Color.forge)
                .background(Color.secondary.opacity(0.2), in: Capsule())

            Text("Depuis le \(season.startFormatted)")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)

            if season.dayNumber >= 80 {
                Button {
                    showClose = true
                } label: {
                    Label("Clore la saison", systemImage: "checkmark.seal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.forge, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(20)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.forge.opacity(0.25), lineWidth: 1))
    }

    // MARK: No active season

    private var noActiveCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary)
            Text("Aucune saison active.")
                .font(.system(size: 15))
                .foregroundStyle(Color.secondary)
            Button("Commencer une saison") { showStart = true }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.forge)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.forge.opacity(0.12), in: Capsule())
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Chapters

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHAPITRES PRÉCÉDENTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(4)
                .padding(.horizontal, 4)

            ForEach(vm.completedSeasons) { season in
                chapterCard(season)
            }
        }
    }

    private func chapterCard(_ season: Season) -> some View {
        Button {
            Task {
                if let r = try? await APIService.shared.closeSeason(id: season.id) {
                    selectedReport = r
                    showReport = true
                }
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(arcColor(season.dominantArc).opacity(0.15))
                        .frame(width: 48, height: 48)
                    Text("\(season.number)")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundStyle(arcColor(season.dominantArc))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(season.displayTitle)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text("\(season.startFormatted) → \(season.endFormatted)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(16)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func seasonReportSheet(_ r: SeasonReport) -> some View {
        NavigationStack {
            SeasonReportView(report: r)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fermer") { showReport = false; selectedReport = nil }
                            .foregroundStyle(Color.secondary)
                    }
                }
        }
    }

    private func arcColor(_ arc: String?) -> Color {
        switch arc {
        case "rebirth":      return .purple
        case "comeback":     return Color.forge
        case "war":          return .red
        case "breakthrough": return .yellow
        case "ascent":       return .green
        case "descent":      return Color.red.opacity(0.7)
        case "plateau":      return .secondary
        default:             return .blue
        }
    }
}

// MARK: - Season banner (for DashboardView)

struct SeasonBannerView: View {
    let season: Season
    let onCloseTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SEASON \(season.number)  ·  JOUR \(season.dayNumber) / 90")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forge)
                    .tracking(2)
                if season.dayNumber >= 80 {
                    Text("La fin de saison approche.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            if season.dayNumber >= 80 {
                Button("Bilan") { onCloseTap() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.forge)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.forge.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.appCard.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.forge.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - ViewModel

@MainActor
class SeasonViewModel: ObservableObject {
    @Published var activeSeason: Season?
    @Published var allSeasons: [Season] = []
    @Published var isLoading = false

    var completedSeasons: [Season] { allSeasons.filter { !$0.isActive } }

    func load() async {
        isLoading = true
        activeSeason = try? await APIService.shared.getActiveSeason()
        allSeasons   = (try? await APIService.shared.getAllSeasons()) ?? []
        isLoading    = false
    }
}
