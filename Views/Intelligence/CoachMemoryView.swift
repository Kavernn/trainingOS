import SwiftUI

// MARK: - Coach Memory View
// Displays the AI coach's persistent memory — facts accumulated over time.
// Accessible from the Intelligence tab toolbar.
struct CoachMemoryView: View {
    @StateObject private var store = CoachMemoryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false

    private var grouped: [(CoachMemoryEntry.MemType, [CoachMemoryEntry])] {
        var dict: [CoachMemoryEntry.MemType: [CoachMemoryEntry]] = [:]
        for e in store.entries { dict[e.type, default: []].append(e) }
        return CoachMemoryEntry.MemType.allCases.compactMap { type in
            guard let entries = dict[type], !entries.isEmpty else { return nil }
            return (type, entries.sorted { $0.confidence > $1.confidence })
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D0D14").ignoresSafeArea()

                if store.entries.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            infoBanner
                            ForEach(grouped, id: \.0) { type, entries in
                                MemorySection(type: type, entries: entries)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Mémoire du coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Tout effacer", role: .destructive) {
                            confirmDeleteAll = true
                        }
                        .foregroundColor(.red.opacity(0.7))
                        .font(.system(size: 13))
                    }
                }
            }
            .toolbarBackground(Color(hex: "0D0D14"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .confirmationDialog("Effacer toute la mémoire ?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) {
                    store.entries.forEach { store.delete(id: $0.id) }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Le coach repartira de zéro et reconstituera sa mémoire progressivement.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var infoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.purple)
            Text("Ces faits sont injectés dans chaque conversation pour que le coach te connaisse dans le temps.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.purple.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundColor(.purple.opacity(0.35))
            Text("Mémoire vide")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("Le coach accumule des faits sur ton entraînement au fil du temps. Reviens après quelques séances.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Memory Section
private struct MemorySection: View {
    let type: CoachMemoryEntry.MemType
    let entries: [CoachMemoryEntry]
    @StateObject private var store = CoachMemoryStore.shared

    private var accentColor: Color {
        switch type {
        case .pattern:     return .cyan
        case .milestone:   return .yellow
        case .correlation: return .blue
        case .risk:        return .orange
        case .preference:  return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentColor)
                Text(type.rawValue)
                    .font(.system(size: 10, weight: .black)).tracking(2)
                    .foregroundColor(accentColor.opacity(0.8))
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
            }

            VStack(spacing: 6) {
                ForEach(entries) { entry in
                    MemoryEntryRow(entry: entry, accentColor: accentColor) {
                        store.delete(id: entry.id)
                    }
                }
            }
        }
        .padding(14)
        .glassCard(color: accentColor, intensity: 0.04)
        .cornerRadius(14)
    }
}

// MARK: - Memory Entry Row
private struct MemoryEntryRow: View {
    let entry: CoachMemoryEntry
    let accentColor: Color
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Confidence dot
            Circle()
                .fill(accentColor.opacity(0.6 + entry.confidence * 0.4))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.content)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Confiance : \(Int(entry.confidence * 100))% · \(entry.updatedAt)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }
}
