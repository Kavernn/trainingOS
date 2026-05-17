import SwiftUI

// MARK: - Graveyard View

struct GraveyardView: View {
    @State private var response: GraveyardResponse?
    @State private var isLoading = true
    @State private var selectedTombstone: Tombstone?

    var body: some View {
        ZStack {
            Color(hex: "0B0B0B").ignoresSafeArea()
            if isLoading {
                graveyardLoadingView
            } else if let r = response, !r.tombstones.isEmpty {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        graveyardHeader(r)
                        graveyardContent(r.tombstones)
                        Spacer(minLength: 40)
                    }
                }
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Graveyard")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color(hex: "0B0B0B"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedTombstone) { TombstoneDetailSheet(tombstone: $0) }
        .task { await load() }
    }

    private func load() async {
        do {
            response = try await APIService.shared.fetchGraveyard()
        } catch {
            response = GraveyardResponse(tombstones: [], totalCount: 0, inceptionDate: nil)
        }
        isLoading = false
    }

    // MARK: - Header

    @ViewBuilder
    private func graveyardHeader(_ r: GraveyardResponse) -> some View {
        VStack(spacing: 6) {
            Text("\(r.totalCount) LIMITES ENTERRÉES")
                .font(.system(size: 13, weight: .black)).tracking(2)
                .foregroundColor(.white.opacity(0.85))
            if let inception = r.inceptionDate {
                Text("depuis \(frenchDate(inception))")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }

    // MARK: - Grouped content

    @ViewBuilder
    private func graveyardContent(_ tombstones: [Tombstone]) -> some View {
        let groups = grouped(tombstones)
        ForEach(groups, id: \.0) { monthYear, items in
            VStack(spacing: 0) {
                HStack {
                    Text(monthYear)
                        .font(.system(size: 10, weight: .black)).tracking(2)
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                    Text("\(items.count) limite\(items.count > 1 ? "s" : "")")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.2))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)

                ForEach(items) { tombstone in
                    TombstoneCard(tombstone: tombstone)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .onTapGesture { selectedTombstone = tombstone }
                        // Tombstones fraîches arrivent après les vieilles — encore chaudes
                        .appearAnimationHot(delay: tombstone.daysSinceDeath < 7 ? 0.8 : 0)
                }
            }
        }
    }

    // MARK: - Grouping

    private func grouped(_ tombstones: [Tombstone]) -> [(String, [Tombstone])] {
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "fr_CA")
        monthFmt.dateFormat = "MMMM yyyy"

        var result: [(String, Date, [Tombstone])] = []
        for t in tombstones {
            let d = isoFmt.date(from: t.deathDate) ?? Date.distantPast
            let key = monthFmt.string(from: d).uppercased()
            if let idx = result.firstIndex(where: { $0.0 == key }) {
                result[idx].2.append(t)
            } else {
                result.append((key, d, [t]))
            }
        }
        // Ancien → récent : le user scroll vers le bas pour trouver ses victoires fraîches
        return result.reversed().map { ($0.0, $0.2) }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.15))
            Text("Le cimetière est vide.")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            Text("Tu n'as pas encore tué quoi que ce soit.\nContinue — les limites viennent.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var graveyardLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white.opacity(0.3))
            Text("Exhumation en cours…")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    private func frenchDate(_ iso: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_CA")
        out.dateFormat = "d MMMM yyyy"
        return out.string(from: d)
    }
}

// MARK: - Tombstone Card

struct TombstoneCard: View {
    let tombstone: Tombstone

    private var daysOld: Int { tombstone.daysSinceDeath }

    private var glowIntensity: Double {
        guard daysOld < 7 else { return 0 }
        return max(0, 1.0 - Double(daysOld) / 7.0)
    }

    private var cardBackground: Color {
        switch daysOld {
        case 0..<7:    return Color(hex: "2A1800")
        case 7..<30:   return Color(hex: "1E1208")
        case 30..<90:  return Color(hex: "161412")
        case 90..<365: return Color(hex: "111010")
        default:       return Color(hex: "0F0F0F")
        }
    }

    private var epitaphOpacity: Double {
        switch daysOld {
        case 0..<30:   return 0.85
        case 30..<90:  return 0.70
        case 90..<365: return 0.55
        default:       return 0.40
        }
    }

    private var freshnessLabel: String {
        switch daysOld {
        case 0..<7:    return "FRAÎCHE"
        case 7..<30:   return "RÉCENTE"
        case 30..<90:  return "INSTALLÉE"
        case 90..<365: return "ANCIENNE"
        default:       return "HISTOIRE"
        }
    }

    private var freshnessColor: Color {
        switch daysOld {
        case 0..<7:  return Color(hex: "FF8C00")
        case 7..<30: return Color(hex: "A0522D")
        default:     return Color.white.opacity(0.2)
        }
    }

    // Decay bar: 0..<90 days → bar depletes from 100% to 0%
    private var decayFill: Double {
        max(0, 1.0 - Double(daysOld) / 90.0)
    }

    private var ttype: TombstoneType { tombstone.tombstoneType }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Type + freshness
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: ttype.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(ttype.label)
                        .font(.system(size: 9, weight: .black)).tracking(1.2)
                }
                .foregroundColor(ttype.accentColor.opacity(0.75))

                Spacer()

                Text(freshnessLabel)
                    .font(.system(size: 8, weight: .bold)).tracking(1.5)
                    .foregroundColor(freshnessColor)
            }

            // Title
            Text(tombstone.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white.opacity(daysOld < 365 ? 0.92 : 0.6))

            // Epitaph
            Text(tombstone.epitaph)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(epitaphOpacity))
                .lineSpacing(3)

            // Decay bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    Capsule()
                        .fill(decayBarGradient)
                        .frame(width: geo.size.width * decayFill, height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .overlay(
            // Ember glow at bottom for fresh tombstones
            VStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color(hex: "FF6600").opacity(0.15 * glowIntensity)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(height: 30)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
        .shadow(color: Color(hex: "FF6600").opacity(0.15 * glowIntensity), radius: 12, y: 4)
    }

    private var decayBarGradient: LinearGradient {
        if daysOld < 7 {
            return LinearGradient(colors: [Color(hex: "FF6600"), Color(hex: "FF3300")],
                                  startPoint: .leading, endPoint: .trailing)
        } else if daysOld < 30 {
            return LinearGradient(colors: [Color(hex: "A0522D"), Color(hex: "8B4513")],
                                  startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.15)],
                                  startPoint: .leading, endPoint: .trailing)
        }
    }
}

// MARK: - Detail Sheet

struct TombstoneDetailSheet: View {
    let tombstone: Tombstone
    @Environment(\.dismiss) private var dismiss

    private var ttype: TombstoneType { tombstone.tombstoneType }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D0D0D").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Enlarged tombstone card (non-tappable)
                        TombstoneCard(tombstone: tombstone)

                        // Stats
                        if tombstone.oldValue != nil || tombstone.newValue != nil {
                            statsSection
                        }

                        // Context
                        contextSection

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(ttype.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "0D0D0D"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHIFFRES")
                .font(.system(size: 9, weight: .black)).tracking(2)
                .foregroundColor(.white.opacity(0.3))

            HStack(spacing: 0) {
                if let old = tombstone.oldValue {
                    statPill(label: "Ancienne limite", value: formattedValue(old))
                }
                if tombstone.oldValue != nil && tombstone.newValue != nil {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 40)
                }
                if let newV = tombstone.newValue {
                    statPill(label: "Ce qui l'a tuée", value: formattedValue(newV))
                }
                if let old = tombstone.oldValue, let newV = tombstone.newValue, old > 0 {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 40)
                    let pct = abs((newV - old) / old * 100)
                    statPill(label: "Différence", value: String(format: "%.1f%%", pct))
                }
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTEXTE")
                .font(.system(size: 9, weight: .black)).tracking(2)
                .foregroundColor(.white.opacity(0.3))
            Text(contextText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.55))
                .lineSpacing(4)
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(0.5)
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var contextText: String {
        switch ttype {
        case .prKilled:
            let name = tombstone.exerciseName ?? "cet exercice"
            return "Chaque rep sur \(name) après cette date a été construit sur les ruines de cette limite. La progression ne s'arrête pas — elle enterre."
        case .streakSlain:
            return "Un record de régularité ne tombe pas par hasard. Il tombe parce que tu t'es présenté encore, et encore, même quand c'était difficile."
        case .stressFloor:
            return "Un nouveau bas de stress est une victoire silencieuse. Ton système nerveux récupère. Ton corps apprend à performer sous moins de pression."
        case .bodycompShed:
            return "Ce poids représentait une version de toi qui n'existe plus. Le corps change plus lentement que l'esprit — mais il change."
        case .plateauBuried:
            return "Un plateau brisé est la preuve que la résistance cède. Tu as continué quand ça ne bougeait pas."
        }
    }

    private func formattedValue(_ v: Double) -> String {
        if v == v.rounded() {
            return "\(Int(v))"
        }
        return String(format: "%.1f", v)
    }
}
