import SwiftUI

// MARK: - Navy Body Fat — Consultation View (reads from BodyCompService)

struct NavyCalculatorView: View {
    @ObservedObject private var bodyComp = BodyCompService.shared
    @ObservedObject private var units = UnitSettings.shared
    @State private var heightCm: Double = 178
    @State private var showEditSheet = false
    @State private var isMale: Bool = true
    @State private var sexUnknown: Bool = false
    @AppStorage("navy_formula_corrected_seen") private var bannerSeen = false

    var body: some View {
        ZStack {
            AmbientBackground(color: .green)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    content
                        .padding(.bottom, 40)
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Navy Body Fat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    BodyCompHistoryView()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.green)
                }
            }
        }
        .task {
            await bodyComp.refresh()
            await loadProfile()
        }
        .sheet(isPresented: $showEditSheet) {
            BodyWeightSheet(editEntry: bodyComp.latest, onSaved: {
                await bodyComp.refresh()
            })
        }
    }

    // MARK: - Profile loading

    private func loadProfile() async {
        guard let (profile, _, _) = try? await APIService.shared.fetchProfilData() else { return }
        if let sex = profile.sex, !sex.isEmpty {
            isMale = sex.uppercased().hasPrefix("M")
            sexUnknown = false
        } else {
            sexUnknown = true
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if !bannerSeen {
            correctionBanner
        }
        if bodyComp.latest == nil {
            neverLoggedView
        } else if sexUnknown {
            sexRequiredView
        } else if !bodyComp.navyMissingFields(isMale: isMale).isEmpty {
            incompleteView
        } else {
            heightPickerCard
            if let res = bodyComp.getNavyBodyFat(heightCm: heightCm, isMale: isMale) {
                resultCards(res)
                compositionBar(res)
                categoryBadge(res)
                stalenessRow
            }
        }
    }

    // MARK: - Correction banner (one-time)

    private var correctionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.appBody)
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Formule corrigée")
                    .font(.appLabel.weight(.semibold)).foregroundColor(.white)
                Text("Le calcul du % de gras est plus précis. L'ancienne formule surestimait de quelques points — ton nouveau chiffre est plus fiable.")
                    .font(.appCaption).foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { bannerSeen = true } label: {
                Image(systemName: "xmark")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .glassCardAccent(.yellow)
        .cornerRadius(14)
        .padding(.horizontal, 16)
    }

    // MARK: - Never logged

    private var neverLoggedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "scalemass")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text("Aucune entrée de poids")
                .font(.appBody.weight(.semibold)).foregroundColor(.white)
            Text("Commence par enregistrer ton poids dans Body Comp.")
                .font(.appLabel.weight(.regular)).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassCard()
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Sex unknown

    private var sexRequiredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36)).foregroundColor(Color.forge.opacity(0.7))
            Text("Sexe non renseigné")
                .font(.appBody.weight(.semibold)).foregroundColor(.white)
            Text("La formule Navy est différente pour l'homme et la femme. Indique ton sexe dans ton profil pour un calcul précis.")
                .font(.appLabel.weight(.regular)).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCardAccent(Color.forge)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Incomplete data

    private var incompleteView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Color.forge)
                Text("Données manquantes")
                    .font(.appLabel.weight(.semibold)).foregroundColor(.white)
            }
            Text("Pour calculer le % de gras, enregistre aussi :")
                .font(.appLabel.weight(.regular)).foregroundColor(.gray)
            ForEach(bodyComp.navyMissingFields(isMale: isMale), id: \.self) { field in
                HStack(spacing: 8) {
                    Circle().fill(Color.forge).frame(width: 6, height: 6)
                    Text(field.capitalized)
                        .font(.appLabel.weight(.regular)).foregroundColor(.white)
                }
            }

            Button {
                showEditSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.appCaption.weight(.semibold))
                    Text("Compléter mes mesures")
                        .font(.appLabel.weight(.semibold))
                }
                .foregroundColor(Color.forge)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardAccent(Color.forge)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Height picker

    private var heightPickerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TAILLE")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                .padding(.bottom, 14)

            HStack(spacing: 0) {
                Text("HAUTEUR")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 6) {
                    Button { heightCm = max(140, heightCm - 1) } label: {
                        Image(systemName: "minus")
                            .font(.appLabel.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(SpringButtonStyle(scale: 0.93))

                    Text(String(format: "%.0f cm", heightCm))
                        .font(.appBody.weight(.bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 70)
                        .multilineTextAlignment(.center)

                    Button { heightCm = min(220, heightCm + 1) } label: {
                        Image(systemName: "plus")
                            .font(.appLabel.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(SpringButtonStyle(scale: 0.93))
                }
            }

            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 12)

            if let e = bodyComp.latest {
                measuresRow(e)
            }
        }
        .padding(16)
        .glassCardAccent(.green)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private func measuresRow(_ e: BodyWeightEntry) -> some View {
        HStack(spacing: 16) {
            measureChip(label: "POIDS", value: units.format(e.weight))
            if let w = e.waistCm {
                measureChip(label: "TAILLE", value: String(format: "%.0f cm", w))
            }
            if let n = e.neckCm {
                measureChip(label: "COU", value: String(format: "%.0f cm", n))
            }
            if !isMale, let h = e.hipsCm {
                measureChip(label: "HANCHES", value: String(format: "%.0f cm", h))
            }
            Spacer()
        }
    }

    private func measureChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
            Text(value)
                .font(.appLabel.weight(.bold)).foregroundColor(.white)
        }
    }

    // MARK: - Result cards

    private func resultCards(_ res: NavyBodyFatResult) -> some View {
        HStack(spacing: 10) {
            resultCard(label: "% MG",
                       value: String(format: "%.1f%%", res.pct),
                       color: .blue,
                       subtitle: "±4% vs DEXA")
            resultCard(label: "MASSE GRASSE",
                       value: units.format(res.fatMassLbs),
                       color: Color.forge)
            resultCard(label: "MASSE MAIGRE",
                       value: units.format(res.leanMassLbs),
                       color: .green)
        }
        .padding(.horizontal, 16)
    }

    private func resultCard(label: String, value: String, color: Color, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.appMicro.weight(.black)).tracking(1)
                .foregroundColor(color.opacity(0.75))
            Text(value)
                .font(.appHeadline.weight(.black))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let sub = subtitle {
                Text(sub)
                    .font(.appMicro)
                    .foregroundColor(.gray.opacity(0.55))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardAccent(color)
        .cornerRadius(14)
    }

    // MARK: - Composition bar

    private func compositionBar(_ res: NavyBodyFatResult) -> some View {
        let weight = bodyComp.latest?.weight ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("COMPOSITION")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let leanFrac = CGFloat(res.leanMassLbs / weight)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.8))
                        .frame(width: geo.size.width * leanFrac)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.forge.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("Masse maigre").font(.appCaption).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.forge).frame(width: 7, height: 7)
                    Text("Masse grasse").font(.appCaption).foregroundColor(.gray)
                }
            }
        }
        .padding(16)
        .glassCard(color: .green, intensity: 0.04)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Category badge

    private func categoryBadge(_ res: NavyBodyFatResult) -> some View {
        let (label, color) = res.category(isMale: isMale)
        return HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
            Text("Catégorie : \(label)")
                .font(.appLabel.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            Text(String(format: "%.1f%%", res.pct))
                .font(.appLabel.weight(.black))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassCardAccent(color)
        .cornerRadius(14)
        .padding(.horizontal, 16)
    }

    // MARK: - Staleness

    private var stalenessRow: some View {
        let freshness = bodyComp.staleness()
        let label = freshness.label
        guard !label.isEmpty else { return AnyView(EmptyView()) }
        let color: Color = freshness.isProblematic ? .red : Color.forge
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundColor(color)
                Text(label)
                    .font(.appCaption).foregroundColor(color)
                Spacer()
            }
            .padding(.horizontal, 20)
        )
    }
}
