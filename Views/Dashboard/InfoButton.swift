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
                .font(.appLabel)
                .foregroundColor(.gray.opacity(0.5))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            InfoSheetView(title: title, entries: entries)
        }
    }
}

// MARK: - Tappable metric cell (recovery / wellness grids)

struct TappableMetricCell: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var valueColor: Color = .white
    var subtitle: String? = nil
    let infoEntry: InfoEntry

    @State private var showInfo = false

    var body: some View {
        Button { showInfo = true } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.appCaption)
                    .foregroundColor(color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(label)
                            .font(.appMicro.weight(.semibold))
                            .tracking(0.3)
                            .foregroundColor(.gray)
                        Image(systemName: "info.circle")
                            .font(.system(size: 8))
                            .foregroundColor(.gray.opacity(0.45))
                    }
                    Text(value)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(valueColor)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.appMicro)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showInfo) {
            InfoSheetView(title: label, entries: [infoEntry])
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
                Color.appBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(entries, id: \.term) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.term)
                                    .font(.appLabel.weight(.bold))
                                    .foregroundColor(.orange)
                                Text(entry.definition)
                                    .font(.appLabel.weight(.regular))
                                    .foregroundColor(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appCard)
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

    // Condition du jour / Readiness Score
    static let readinessEntries: [InfoEntry] = [
        InfoEntry(
            term: "Condition du jour — score 0–100",
            definition: "Score composite qui estime ta capacité physique aujourd'hui. Il combine plusieurs signaux biologiques pour répondre à une question simple : est-ce que mon corps est prêt à performer ?"
        ),
        InfoEntry(
            term: "HRV — Variabilité cardiaque (30 %)",
            definition: "La HRV mesure l'irrégularité entre tes battements cardiaques au repos. Une HRV élevée = système nerveux autonome bien récupéré. Une HRV basse = fatigue accumulée ou stress. C'est le signal le plus fiable de ton état de récupération.\n\nPour l'améliorer : dors 7–9h, réduis l'alcool, évite les séances intenses dos-à-dos, pratique la cohérence cardiaque."
        ),
        InfoEntry(
            term: "Sommeil (35 %)",
            definition: "La durée de ton sommeil cette nuit. Objectif optimal : 7–9h. En dessous de 6h, la récupération musculaire et hormonale est sévèrement compromise — une nuit courte peut faire chuter ton score de 20–30 points.\n\nPour l'améliorer : couche-toi à heure fixe, évite les écrans 30 min avant, baisse la température de ta chambre."
        ),
        InfoEntry(
            term: "FC de repos (25 %)",
            definition: "Ta fréquence cardiaque au repos ce matin. Plus elle est basse, mieux tu récupères. Une FC repos élevée par rapport à ta baseline est un signal de stress, de maladie ou de fatigue nerveuse.\n\nPour l'améliorer : cardio régulier à faible intensité (zone 2), sommeil suffisant, réduction du stress chronique."
        ),
        InfoEntry(
            term: "Douleurs musculaires (10 %)",
            definition: "Le niveau de courbatures ressenti (si renseigné). Un score de douleur élevé indique que tes muscles sont encore en phase de réparation — s'entraîner lourd dans cet état ralentit la progression.\n\nPour l'améliorer : intègre des jours de récupération active (marche, mobilité), optimise l'apport en protéines (≥ 1,6 g/kg)."
        ),
        InfoEntry(
            term: "Interprétation du score",
            definition: "76–100 → Optimal : conditions idéales pour une séance intense ou un test de force.\n61–75 → Bon : entraîne-toi normalement, reste attentif aux signaux.\n41–60 → Modéré : réduis le volume ou l'intensité de 15–20 %.\n0–40 → Repos : privilégie une récupération active (marche, étirements)."
        ),
    ]

    // Phoenix Score
    static let phoenixEntries: [InfoEntry] = [
        InfoEntry(
            term: "Phoenix Score — c'est quoi ?",
            definition: "Un score unique de –100 à +100 qui mesure ta transformation globale sur la semaine en cours. Il ne mesure pas ta forme du jour — il mesure si tu progresses ou tu régrèdes sur tous les axes de ta vie."
        ),
        InfoEntry(
            term: "CORPS — axe entraînement",
            definition: "Volume total de tes séances cette semaine vs la semaine précédente. Si tu t'entraînes plus (ou mieux), cet axe monte. Une semaine sans séance le fait chuter."
        ),
        InfoEntry(
            term: "MENTAL — axe stress",
            definition: "Basé sur ton PSS (Perceived Stress Scale) et ton Life Stress Score. Plus ton stress est bas et ta récupération mentale est bonne, plus cet axe est positif."
        ),
        InfoEntry(
            term: "FUEL — axe nutrition",
            definition: "Pourcentage de jours où tu as atteint tes objectifs de macros cette semaine. 100 % des jours = axe au max. Zéro log = axe négatif."
        ),
        InfoEntry(
            term: "ESPRIT — axe rituels",
            definition: "Taux de complétion de tes rituels quotidiens (matin + soir), séances de respiration, méditation et journaling. S'active après quelques jours de pratique."
        ),
        InfoEntry(
            term: "Les 7 états",
            definition: "Foundation → Cendres → Braises → Braises chaudes → Flamme → Envol → Supernova\n\nChaque état correspond à une plage de score. Supernova = tous les axes au maximum sur la semaine."
        ),
    ]

    // Body Budget
    static let bodyBudgetEntries: [InfoEntry] = [
        InfoEntry(
            term: "Body Budget — c'est quoi ?",
            definition: "Un score de 0 à 100 qui estime la capacité de charge de ton corps aujourd'hui. Pense-y comme un compte en banque : chaque séance, chaque nuit courte, chaque stress le dépense. Le repos et la nutrition le rechargent."
        ),
        InfoEntry(
            term: "Pilier Entraînement",
            definition: "Volume et intensité cumulés sur les 7 derniers jours. Un volume trop élevé dos-à-dos sans récupération vide ce pilier. Il recharge dès que tu intègres un jour de repos ou que tu réduis l'intensité."
        ),
        InfoEntry(
            term: "Pilier Stress",
            definition: "Charge mentale basée sur ton PSS et ta HRV. Un stress chronique élevé ou une HRV basse draine ce pilier — même si tu t'entraînes bien et manges correctement."
        ),
        InfoEntry(
            term: "Pilier Nutrition",
            definition: "Adéquation de ton alimentation par rapport à tes objectifs de macros. Déficit calorique prolongé ou macros manquées plusieurs jours consécutifs réduisent ce score."
        ),
        InfoEntry(
            term: "Interprétation",
            definition: "75–100 → Budget plein : ton corps absorbe et récupère bien. Vas-y fort.\n50–74 → Budget modéré : entraîne-toi, mais surveille le volume.\n25–49 → Budget bas : réduis l'intensité, priorise le sommeil.\n0–24 → Budget épuisé : repos actif seulement."
        ),
    ]

    // RPE / RIR — shown in exercise card header and post-session recap
    static let rpeRirEntries: [InfoEntry] = [
        InfoEntry(
            term: "RPE — Difficulté perçue (1–10)",
            definition: "Rate of Perceived Exertion. Une échelle simple pour mesurer l'intensité de ton effort :\n\n• RPE 10 → Échec : impossible de faire 1 rep de plus\n• RPE 9 → Très dur : peut-être 1 rep de plus\n• RPE 8 → Dur : 2 reps de plus max\n• RPE 7 → Challenge : 3 reps de réserve\n• RPE 6 et moins → Modéré à facile\n\nTon coach utilise cette valeur pour ajuster ton programme semaine après semaine."
        ),
        InfoEntry(
            term: "RIR — Reps en réserve",
            definition: "L'autre face du RPE. Plutôt que de noter la difficulté, tu indiques combien de reps tu aurais pu faire de plus avant l'échec :\n\n• RIR 0 → Échec total (= RPE 10)\n• RIR 1 → Très dur (= RPE 9)\n• RIR 2 → Dur mais propre (= RPE 8)\n• RIR 3 → Challenge contrôlé (= RPE 7)\n• RIR 4+ → Trop facile (= RPE 6 ou moins)\n\nPour progresser : vise RIR 1–3 sur la plupart de tes sets. RIR 0 (échec) doit rester rare — il épuise le système nerveux."
        ),
    ]

    // Recovery & sleep metrics — Énergie & Récupération tab
    static let readinessMetric = InfoEntry(
        term: "Readiness — Score de préparation",
        definition: "Score composite 0–100 qui estime si ton corps est prêt à performer aujourd'hui. Il combine HRV, sommeil, charge d'entraînement (ACWR), fatigue perçue et nutrition.\n\n76–100 → Optimal : séance intense ou test de force.\n61–75 → Bon : entraîne-toi normalement.\n41–60 → Modéré : réduis volume/intensité de 15–20 %.\n0–40 → Repos : récupération active seulement."
    )

    static let hrvMetric = InfoEntry(
        term: "HRV — Variabilité cardiaque",
        definition: "Mesure l'irrégularité entre tes battements au repos (en ms, RMSSD). Une HRV élevée indique un système nerveux bien récupéré ; une HRV basse signale fatigue, stress ou surentraînement.\n\nSynchronisée automatiquement depuis Apple Watch / HealthKit, idéalement mesurée au réveil.\n\nPour l'améliorer : dors 7–9h, évite l'alcool, espace les séances intenses, pratique la cohérence cardiaque."
    )

    static let restingHrMetric = InfoEntry(
        term: "FC Repos — Fréquence cardiaque au repos",
        definition: "Ton rythme cardiaque au repos (bpm). Plus elle est basse, mieux tu récupères. Une FC repos élevée par rapport à ta baseline peut indiquer stress, maladie, manque de sommeil ou surcharge d'entraînement.\n\nSource : Apple Watch (moyenne quotidienne) ou saisie manuelle."
    )

    static let stepsMetric = InfoEntry(
        term: "Pas — Activité quotidienne",
        definition: "Nombre de pas enregistrés aujourd'hui. Utilisé pour calculer ton NEAT (activité non sportive) dans le bilan énergétique.\n\n10 000 pas/jour est un repère courant, mais l'essentiel est la régularité et la tendance sur la semaine."
    )

    static let sorenessMetric = InfoEntry(
        term: "Courbatures",
        definition: "Niveau de douleur musculaire ressenti, sur une échelle de 1 à 10. Un score élevé indique que tes muscles sont encore en réparation — s'entraîner lourd dans cet état ralentit la progression.\n\nSaisie manuelle ou via le log matinal Apple Watch."
    )

    static let fatigueMetric = InfoEntry(
        term: "Fatigue perçue",
        definition: "Échelle Hooper 0–10 : comment tu te sens globalement (énergie, lourdeur, motivation). Complète la HRV pour capturer ce que les capteurs ne voient pas.\n\n7+ = fatigue significative — réduis l'intensité ou prends un jour de repos actif."
    )

    static let energyPreMetric = InfoEntry(
        term: "Énergie perçue",
        definition: "Ton niveau d'énergie avant l'entraînement (1–10). Indique si tu te sens prêt à pousser ou si tu devrais modérer l'effort, indépendamment des métriques objectives.\n\nSaisie via le log matinal Watch ou la fiche de récupération."
    )

    static let hrMorningMetric = InfoEntry(
        term: "FC Matin",
        definition: "Fréquence cardiaque moyenne entre 6h et 9h. Sert de référence pour comparer ta récupération cardiovasculaire dans la journée.\n\nUne FC matin anormalement élevée peut signaler un manque de récupération."
    )

    static let hrPostWorkoutMetric = InfoEntry(
        term: "FC Post-Séance",
        definition: "Fréquence cardiaque ~30 min après ta dernière séance. Comparée à la FC matin, elle indique si ton corps est revenu à un état de repos.\n\nUn écart important (delta FC) suggère une récupération cardiovasculaire incomplète."
    )

    static let hrEveningMetric = InfoEntry(
        term: "FC Soir",
        definition: "Fréquence cardiaque moyenne entre 21h et 23h. Une FC soir élevée peut indiquer un stress résiduel, une séance tardive ou un sommeil perturbé à venir."
    )

    static let deltaFcMetric = InfoEntry(
        term: "Delta FC — Écart matin / post-séance",
        definition: "Différence entre ta FC post-séance et ta FC matin. Un delta faible (≤ 10 bpm) = bonne récupération cardiovasculaire. 11–20 bpm = modéré. > 20 bpm = récupération incomplète — privilégie le repos ou une séance légère."
    )

    static let sleepDurationMetric = InfoEntry(
        term: "Durée de sommeil",
        definition: "Temps total de sommeil effectif cette nuit (heures). Objectif optimal : 7–9h.\n\n< 6h : récupération musculaire et hormonale compromise.\n6–7h : court mais acceptable ponctuellement.\n7–9h : optimal.\n> 9h : long — peut indiquer dette de sommeil ou fatigue accumulée.\n\nSource : Apple Watch (auto) ou saisie manuelle."
    )

    static let sleepQualityMetric = InfoEntry(
        term: "Qualité de sommeil",
        definition: "Évaluation subjective de la qualité de ta nuit (1–5 ou 1–10 selon la source). La Watch ne mesure pas la qualité ressentie — seule une saisie manuelle ou le log sommeil la renseigne.\n\nImpact direct sur le score de readiness (15 % du poids)."
    )

    static let sleepStreakMetric = InfoEntry(
        term: "Streak sommeil",
        definition: "Nombre de jours consécutifs avec au moins 7h de sommeil enregistrées. La régularité du sommeil est aussi importante que la durée d'une seule nuit."
    )

    static let activeEnergyMetric = InfoEntry(
        term: "Dépense active (HealthKit)",
        definition: "Calories brûlées par l'activité physique enregistrée par Apple Watch, hors métabolisme de base. Sur un jour de repos, une dépense > 800 kcal peut indiquer une activité élevée malgré l'absence de séance planifiée."
    )

    static let spo2Metric = InfoEntry(
        term: "SpO2 — Saturation en oxygène",
        definition: "Pourcentage d'oxygène dans ton sang, mesuré par Apple Watch Series 6+. Une valeur normale est 95–100 %. Une baisse persistante peut indiquer un problème de récupération, d'altitude ou de santé respiratoire."
    )

    static let wristTempMetric = InfoEntry(
        term: "Température au poignet",
        definition: "Écart de température par rapport à ta baseline personnelle (Apple Watch Series 8+). Une hausse peut signaler une maladie naissante, un stress ou une mauvaise récupération — avant même que tu ne le ressentes."
    )

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
