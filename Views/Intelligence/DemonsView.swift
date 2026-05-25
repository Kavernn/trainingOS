import SwiftUI

struct DemonsView: View {
    let demons: [RitualDemon]
    @State private var localDemons: [RitualDemon] = []
    @State private var killingDate: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0A").ignoresSafeArea()
                if localDemons.isEmpty {
                    emptyState
                } else {
                    demonList
                }
            }
            .navigationTitle("Démons")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.4))
                }
            }
        }
        .onAppear { localDemons = demons }
    }

    private func killDemon(_ demon: RitualDemon) {
        guard killingDate == nil else { return }
        killingDate = demon.date
        localDemons.removeAll { $0.date == demon.date }
        Task {
            do {
                try await APIService.shared.killDemon(date: demon.date)
            } catch {
                await MainActor.run {
                    if !localDemons.contains(where: { $0.date == demon.date }) {
                        localDemons.append(demon)
                        localDemons.sort { $0.carryCount > $1.carryCount }
                    }
                }
            }
            await MainActor.run { killingDate = nil }
        }
    }

    // F5: keyword frequency across all demon intentions
    private var recurringThemes: [(String, Int)] {
        let stopWords: Set<String> = ["je", "tu", "il", "elle", "nous", "vous", "ils", "elles",
            "le", "la", "les", "un", "une", "des", "du", "de", "et", "ou", "à", "au",
            "en", "sur", "par", "pour", "dans", "avec", "sans", "que", "qui", "ne", "pas",
            "plus", "me", "te", "se", "ma", "ta", "sa", "mon", "ton", "son", "mes", "tes",
            "ses", "ce", "cet", "cette", "ces", "my", "i", "to", "the", "a", "an", "of",
            "in", "is", "it", "and", "or", "for", "with", "not", "no", "be", "do", "at",
            "aujourd", "hui", "vais", "fais", "ferai", "dois", "veux", "moi", "ça", "c"]
        var freq: [String: Int] = [:]
        for demon in localDemons {
            let words = demon.intention
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .flatMap { $0.components(separatedBy: CharacterSet.punctuationCharacters) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 4 && !stopWords.contains($0) }
            for w in words { freq[w, default: 0] += 1 }
        }
        return freq.filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { $0 }
    }

    private var demonList: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Ces intentions ont survécu. Elles attendent d'être tuées.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                // F5: Pattern recognition section
                if !recurringThemes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("THÈMES RÉCURRENTS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundColor(Color(white: 0.25))
                            .padding(.leading, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recurringThemes, id: \.0) { word, count in
                                    HStack(spacing: 4) {
                                        Text(word)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Color(white: 0.55))
                                        Text("×\(count)")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(white: 0.3))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(white: 0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.12), lineWidth: 1))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(localDemons.sorted(by: { $0.carryCount > $1.carryCount })) { demon in
                    DemonCard(demon: demon, isKilling: killingDate == demon.date) {
                        killDemon(demon)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 32)
            }
            .padding(.top, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 32))
                .foregroundColor(Color(white: 0.15))
            Text("Aucun démon")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.3))
            Text("Toutes tes intentions ont été tuées.")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.2))
        }
    }
}

private struct DemonCard: View {
    let demon: RitualDemon
    let isKilling: Bool
    let onKill: () -> Void

    private let red = Color(hex: "FF2D20")

    // Fade older demons: opacity drops to 0.45 after 5+ days
    private var textOpacity: Double {
        let nights = demon.carryCount
        if nights >= 5 { return 0.45 }
        return 1.0 - Double(nights) * 0.11
    }

    private var formattedDate: String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: demon.date) else { return demon.date }
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        out.locale = Locale(identifier: "fr_FR")
        return out.string(from: date)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left ghost border
            Rectangle()
                .fill(Color(white: 0.2))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("\"")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(Color(white: 0.15))
                    + Text(demon.intention)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: textOpacity))
                    + Text("\"")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(Color(white: 0.15))

                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.25))
                    Text("Survécu · \(demon.carryCount) nuit\(demon.carryCount > 1 ? "s" : "") · \(formattedDate)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.25))
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 16)
            .padding(.trailing, 12)

            Spacer()

            Button(action: onKill) {
                Group {
                    if isKilling {
                        ProgressView().tint(red).scaleEffect(0.7)
                    } else {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(red.opacity(0.6))
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isKilling)
            .padding(.trailing, 8)
        }
        .background(Color(white: 0.05))
        .cornerRadius(10)
    }
}
