import SwiftUI

struct HomeView: View {
    @EnvironmentObject var mgr: WatchSessionManager

    var body: some View {
        NavigationStack {
            List {
                activeSessionRow
                NavigationLink(destination: MorningLogView()) {
                    Label("Log du matin", systemImage: "sun.horizon.fill")
                }
                NavigationLink(destination: RestTimerView()) {
                    Label("Timer repos", systemImage: "timer")
                }
            }
            .navigationTitle("VinceSeven")
        }
    }

    @ViewBuilder
    private var activeSessionRow: some View {
        if let session = mgr.activeSession {
            NavigationLink(destination: ActiveSessionView(session: session)) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(session.sessionName, systemImage: "figure.strengthtraining.traditional")
                        .font(.headline)
                    Text("\(session.exercises.count) exercices")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Label("Pas de séance active", systemImage: "figure.strengthtraining.traditional")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
