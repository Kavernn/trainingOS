import SwiftUI

// MARK: - Shared info button used across dashboard / stats cards

struct InfoEntry {
    let term: String
    let definition: String
}

struct CardInfoButton: View {
    let title: String
    let entries: [InfoEntry]
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray.opacity(0.5))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            InfoSheetView(title: title, entries: entries)
        }
    }
}

struct InfoSheetView: View {
    let title: String
    let entries: [InfoEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(entries, id: \.term) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.term)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.orange)
                                Text(entry.definition)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "11111c"))
                            .cornerRadius(12)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Info content definitions

extension InfoEntry {
    // LSS / Morning Brief
    static let lssEntries: [InfoEntry] = [
        InfoEntry(
            term: "LSS — Life Stress Score",
            definition: "Score composite de 0 à 100 qui mesure ta charge de stress globale. Il combine l'entraînement, le sommeil, la HRV et la FC de repos. Plus il est élevé, plus ton corps est sous pression."
        ),
        InfoEntry(
            term: "Go  (LSS < 40)",
            definition: "Conditions optimales. Ton corps est frais et récupéré. Tu peux t'entraîner à pleine intensité."
        ),
        InfoEntry(
            term: "Prudence  (40–60)",
            definition: "Légère accumulation de fatigue. Entraîne-toi, mais écoute ton corps. Réduis si tu te sens à plat en cours de séance."
        ),
        InfoEntry(
            term: "Réduire  (60–75)",
            definition: "Fatigue significative. Baisse le volume et l'intensité de 15–25 %. Priorise le sommeil et la nutrition."
        ),
        InfoEntry(
            term: "Reporter  (LSS > 75)",
            definition: "Ton système nerveux et musculaire est saturé. Une séance lourde aujourd'hui ferait plus de mal que de bien. Préfère un repos actif ou une récupération légère."
        ),
        InfoEntry(
            term: "HRV Drop",
            definition: "La variabilité de la fréquence cardiaque a chuté par rapport à ta moyenne personnelle — signal fiable d'un système nerveux peu récupéré."
        ),
        InfoEntry(
            term: "Surcharge d'entraînement",
            definition: "Volume ou fréquence trop élevés sur les derniers jours. Le corps n'a pas eu assez de temps pour récupérer entre les séances."
        ),
    ]

    // LSS Prediction
    static let predictionEntries: [InfoEntry] = [
        InfoEntry(
            term: "LSS prédit",
            definition: "Estimation du Life Stress Score pour chaque jour des 7 prochains jours, basée sur ton programme planifié et ta tendance de récupération récente."
        ),
        InfoEntry(
            term: "Meilleure journée (★)",
            definition: "Le jour où ton LSS projeté est le plus bas = la fenêtre optimale pour une séance intense, un test de force ou un effort maximal."
        ),
        InfoEntry(
            term: "Base LSS",
            definition: "Ton niveau de stress de référence sans séance planifiée — calculé à partir de ta récupération moyenne récente (sommeil, HRV, FC repos)."
        ),
    ]

    // Déload / Fatigue
    static let deloadEntries: [InfoEntry] = [
        InfoEntry(
            term: "Déload",
            definition: "Semaine intentionnellement allégée (−20 à −40 % de volume) pour permettre une récupération complète. Le déload préserve les gains, réduit l'inflammation chronique et prévient les blessures."
        ),
        InfoEntry(
            term: "Fatigue chronique",
            definition: "Accumulation de stress sur 2 à 4 semaines. Différente de la fatigue aiguë post-séance, elle ne disparaît qu'avec une réduction durable du volume — une bonne nuit ne suffit pas."
        ),
        InfoEntry(
            term: "RPE (Rate of Perceived Exertion)",
            definition: "Intensité perçue de la séance sur une échelle de 1 à 10. Un RPE moyen > 8 sur 7 jours consécutifs est un signal fort de surcharge — ton corps te dit qu'il récupère mal."
        ),
    ]

    // Volume landmarks (MEV / MAV / MRV)
    static let volumeLandmarkEntries: [InfoEntry] = [
        InfoEntry(
            term: "MEV — Minimum Effective Volume",
            definition: "Le volume minimal de séries par semaine pour qu'un groupe musculaire continue de progresser. En dessous de ce seuil, tu maintiens au mieux tes acquis mais tu ne gagnes pas."
        ),
        InfoEntry(
            term: "MAV — Maximum Adaptive Volume",
            definition: "La plage de volume où tu progresses le mieux. Ton entraînement est efficace et ta récupération suffisante. C'est la zone cible."
        ),
        InfoEntry(
            term: "MRV — Maximum Recoverable Volume",
            definition: "Le plafond de volume que ton corps peut absorber et dont il peut récupérer entre les séances. Dépasser régulièrement le MRV mène à la stagnation, la sur-fatigue, voire la blessure."
        ),
        InfoEntry(
            term: "Source",
            definition: "Basé sur la recherche de Renaissance Periodization (Dr. Mike Israetel et al.). Les valeurs varient selon le groupe musculaire, l'expérience et le niveau de récupération individuel."
        ),
    ]
}
