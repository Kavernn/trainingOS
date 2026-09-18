import SwiftUI
import Combine
import PhotosUI
import Charts
import LocalAuthentication

// Archetype accent — mirrors WorkoutDNAView, accessible app-wide from this file
func dnaArchetypeAccent(_ key: String) -> Color {
    switch key {
    case "powerlifter": return Color(red: 0.31, green: 0.43, blue: 0.97)
    case "bodybuilder": return Color(red: 0.98, green: 0.45, blue: 0.09)
    case "grinder":     return Color(red: 0.13, green: 0.77, blue: 0.37)
    case "warrior":     return Color(red: 0.66, green: 0.33, blue: 0.97)
    case "athlete":     return Color(red: 0.08, green: 0.72, blue: 0.64)
    default:            return Color.appWarning
    }
}

struct ProfileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ObservedObject private var api      = APIService.shared
    @ObservedObject private var bodyComp = BodyCompService.shared
    @ObservedObject private var units    = UnitSettings.shared

    @State private var isLoading          = true
    @State private var showEdit           = false
    @State private var showAddWeight      = false
    @State private var showPhotoOptions   = false
    @State private var showPhotoPicker    = false
    @State private var showCamera         = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var profileImage: UIImage? = nil
    @State private var isUploadingPhoto   = false
    @State private var photoError: String? = nil
    @State private var isExporting        = false
    @State private var exportURL: URL?    = nil
    @State private var showExportShare    = false
    @State private var dna: WorkoutDNAResponse? = nil
    @State private var totalSessions: Int = 0
    @State private var memberSinceText    = ""
    @State private var weeklyTonnage: [WeeklyTonnageEntry] = []
    @State private var pssHistory: [PSSRecord] = []
    @State private var allTimeVolumeLbs: Double = 0
    @State private var currentStreak: Int = 0
    @State private var longestStreak: Int = 0
    @State private var oath: OathModel?         = nil
    @State private var oathUnlocked             = false
    @State private var warRoomVictoryStreak: Int = 0
    @State private var warRoomEnabled           = false
    @AppStorage("hrv_onboarding_done") private var hrvOnboardingDone = false
    @State private var showHRVOnboarding        = false

    var profile: UserProfile? { api.dashboard?.profile }

    // MARK: - Computed

    private var sessionsThisMonth: Int {
        let key = DateFormatter.isoYearMonth.string(from: Date())
        return api.dashboard?.sessions.keys.filter { $0.hasPrefix(key) }.count ?? 0
    }

    private var displayTotalSessions: Int {
        totalSessions > 0 ? totalSessions : (api.dashboard?.sessions.count ?? 0)
    }

    private var weightDelta30d: Double? {
        let sorted = bodyComp.history.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }
        let cutoff = Calendar.mtl.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        guard let ref = sorted.last(where: {
            guard let d = DateFormatter.isoDate.date(from: $0.date) else { return false }
            return d <= cutoff && $0.date != latest.date
        }) else { return nil }
        return latest.weight - ref.weight
    }

    private var allTimeVolumeFormatted: String {
        let displayVol = units.display(allTimeVolumeLbs)
        if displayVol >= 1_000_000 {
            return String(format: "%.1fM \(units.label)", displayVol / 1_000_000)
        }
        return (NumberFormatter.spaceGrouped.string(from: NSNumber(value: Int(displayVol))) ?? "\(Int(displayVol))") + " \(units.label)"
    }

    private var volumeTrend: (pct: Double, positive: Bool)? {
        let items = weeklyTonnage.suffix(4)
        guard items.count >= 2,
              let last = items.last?.totalVolume,
              let first = items.first?.totalVolume,
              first > 0 else { return nil }
        let pct = (last - first) / first * 100
        return (abs(pct), pct >= 0)
    }

    private var pssTrend: (delta: Int, positive: Bool)? {
        let items = pssHistory.sorted { $0.date < $1.date }.suffix(4)
        guard items.count >= 2,
              let last = items.last?.score,
              let first = items.first?.score else { return nil }
        return (abs(last - first), last <= first)
    }

    private var isProfileIncomplete: Bool {
        let p = profile
        return p?.name == nil || p?.height == nil || p?.age == nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                AmbientBackground(color: Color.forge).ignoresSafeArea()
                if isLoading {
                    AppLoadingView()
                } else {
                    profileScrollContent
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Modifier") { showEdit = true }
                        .font(.appLabel).fontWeight(.semibold)
                        .foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { Task { await exportData() } } label: {
                        if isExporting {
                            ProgressView().scaleEffect(0.75).tint(.gray)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.appLabel).foregroundColor(.gray)
                        }
                    }
                    .disabled(isExporting)
                    .accessibilityLabel(isExporting ? "Export en cours" : "Exporter mes données")
                }
            }
            .confirmationDialog("Photo de profil", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                Button("Prendre une photo") { showCamera = true }
                Button("Choisir dans la galerie") { showPhotoPicker = true }
                Button("Annuler", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { Task { await loadSelectedPhoto() } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { image in Task { await uploadPhoto(image) } }.ignoresSafeArea()
            }
            .sheet(isPresented: $showEdit) {
                EditProfileSheet(profile: profile) {
                    await api.fetchDashboard()
                    await BodyCompService.shared.refresh()
                }
            }
            .sheet(isPresented: $showAddWeight) {
                BodyWeightSheet(editEntry: nil) { await BodyCompService.shared.refresh() }
            }
            .alert("Erreur photo",
                   isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(photoError ?? "") }
            .sheet(isPresented: $showExportShare) {
                if let url = exportURL { ShareSheet(items: [url]) }
            }
            .sheet(isPresented: $showHRVOnboarding) {
                HRVOnboardingView(onDone: { showHRVOnboarding = false })
            }
        }
        .task { await loadData() }
    }

    // MARK: - Scroll Content

    private var profileScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                if isProfileIncomplete { incompleteProfileBanner }
                headerSection
                statsGridSection
                bodyCompCard
                prsCard
                trendsSection
                oathCard
                profileActionsCard
            }
            .padding(.top, 4)
            .padding(.bottom, fabBottomPadding)
        }
    }

    // MARK: - Section 1 — Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                profilePhotoView
                Button(action: { showPhotoOptions = true }) {
                    ZStack {
                        Circle()
                            .fill(Color.forge)
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.forge.opacity(0.28), radius: 8, y: 3)
                        if isUploadingPhoto {
                            ProgressView().tint(.onAccent).scaleEffect(0.6)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.appLabel).fontWeight(.semibold).foregroundColor(.onAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifier la photo de profil")
            }

            Text(profile?.name ?? "Athlète")
                .font(.appTitle.weight(.bold))
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)

            if !memberSinceText.isEmpty {
                Text(memberSinceText)
                    .font(.appCaption).fontWeight(.regular)
                    .foregroundColor(.gray.opacity(0.8))
            }

            headerBadgesRow
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.appCard)
                Circle()
                    .fill(Color.forge.opacity(0.12))
                    .frame(width: 190, height: 190)
                    .blur(radius: 34)
                    .offset(y: -70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.forge.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var headerBadgesRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { identityBadges }
            VStack(spacing: 8) { identityBadges }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var identityBadges: some View {
            if let dna {
                let accent = dnaArchetypeAccent(dna.archetype.key)
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.appMicro).fontWeight(.bold)
                    Text(dna.archetype.label.uppercased())
                        .font(.appCaption).fontWeight(.bold).tracking(0.5)
                }
                .foregroundColor(accent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(accent.opacity(0.15))
                .clipShape(Capsule())
            }
            if let goal = profile?.goal, !goal.isEmpty {
                Text(Goal.label(for: goal))
                    .font(.appCaption).foregroundColor(.gray)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.appSurfaceInset)
                    .clipShape(Capsule())
            }
    }

    private var profilePhotoView: some View {
        ProfileAvatarView(profile: profile, overrideImage: profileImage, size: 112, showsLoading: true)
            .shadow(color: Color.forge.opacity(0.22), radius: 20, y: 8)
            .accessibilityHidden(true)
    }

    // MARK: - Section 2 — Stats Grid

    private var statsGridSection: some View {
        LazyVGrid(columns: statGridColumns, spacing: 10) {
            ProfileStatSquare(
                value: displayTotalSessions > 0 ? "\(displayTotalSessions)" : "—",
                label: "SÉANCES", icon: "dumbbell.fill", color: Color.forge,
                subtitle: nil,
                hasData: displayTotalSessions > 0
            )
            ProfileStatSquare(
                value: currentStreak > 0 ? "\(currentStreak)j" : "—",
                label: "STREAK", icon: "flame.fill", color: Color.appDanger,
                subtitle: longestStreak > 0 ? "record \(longestStreak)j" : nil,
                isRecord: currentStreak > 0 && currentStreak >= longestStreak,
                hasData: currentStreak > 0
            )
            ProfileStatSquare(
                value: allTimeVolumeLbs > 0 ? allTimeVolumeFormatted : "—",
                label: "VOLUME ALL-TIME", icon: "scalemass.fill", color: Color.statusBlue,
                subtitle: nil,
                hasData: allTimeVolumeLbs > 0
            )
            ProfileStatSquare(
                value: "\(sessionsThisMonth)",
                label: "JOURS ACTIFS CE MOIS", icon: "calendar", color: Color.appSuccess,
                subtitle: nil,
                hasData: true
            )
        }
        .padding(.horizontal, 16)
    }

    private var statGridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    // MARK: - Section 4 — Body Composition

    private var bodyCompCard: some View {
        let heightCm   = profile?.height ?? 178.0
        let isMale     = (profile?.sex ?? "M").uppercased().hasPrefix("M")
        let navyResult = bodyComp.getNavyBodyFat(heightCm: heightCm, isMale: isMale)
        let latest     = bodyComp.latest
        let delta      = weightDelta30d
        let histSorted = bodyComp.history.sorted { $0.date < $1.date }

        return NavigationLink(destination: BodyCompView()) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("COMPOSITION CORPORELLE", systemImage: "figure.arms.open")
                        .font(.appMicro).fontWeight(.bold).tracking(1.5)
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption).foregroundColor(.appTextSecondary.opacity(0.6))
                }

                if let latest {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            bodyCompWeightCol(latest: latest, delta: delta)
                            Divider().overlay(Color.appSeparatorSubtle)
                            bodyCompFatCol(navyResult: navyResult, isMale: isMale)
                                .padding(.horizontal, 0)
                            weightSparklineMini(histSorted)
                                .frame(height: 52)
                                .accessibilityHidden(true)
                        }
                    } else {
                        HStack(spacing: 0) {
                            bodyCompWeightCol(latest: latest, delta: delta)
                            Rectangle().fill(Color.appSeparatorSubtle).frame(width: 1, height: 52)
                            bodyCompFatCol(navyResult: navyResult, isMale: isMale)
                            Rectangle().fill(Color.appSeparatorSubtle).frame(width: 1, height: 52)
                            weightSparklineMini(histSorted)
                                .frame(width: 72, height: 44)
                                .padding(.leading, 14)
                                .accessibilityHidden(true)
                        }
                    }
                    Text("Données du \(formattedShortDate(latest.date))")
                        .font(.appCaption).foregroundColor(.gray.opacity(0.6))
                } else {
                    bodyCompEmptyState
                }
            }
            .padding(18)
            .background(Color.appCard)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.forge.opacity(0.16), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }

    private func bodyCompWeightCol(latest: BodyWeightEntry, delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(units.format(latest.weight))
                .font(.appTitle).fontWeight(.black).foregroundColor(.appTextPrimary)
            if let d = delta {
                HStack(spacing: 3) {
                    Image(systemName: d > 0 ? "arrow.up" : "arrow.down")
                        .font(.appMicro).fontWeight(.bold)
                    Text(units.format(abs(d)))
                        .font(.appCaption).fontWeight(.semibold)
                }
                .foregroundColor(d <= 0 ? Color.appSuccess : Color.appWarning)
            }
            Text("POIDS").font(.appMicro).fontWeight(.bold).tracking(1).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bodyCompFatCol(navyResult: NavyBodyFatResult?, isMale: Bool) -> some View {
        let cat = navyResult?.category(isMale: isMale)
        let catColor = cat?.color ?? Color.clear
        let catLabel = cat?.label ?? ""
        let pctStr   = navyResult.map { String(format: "%.1f%%", $0.pct) } ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            Text(pctStr)
                .font(.appTitle).fontWeight(.black)
                .foregroundColor(navyResult != nil ? catColor : Color.appOnSurface.opacity(0.3))
            if navyResult != nil {
                Text(catLabel)
                    .font(.appCaption).fontWeight(.semibold).foregroundColor(catColor.opacity(0.8))
            } else {
                Text("Incomplet").font(.appMicro).foregroundColor(Color.forge.opacity(0.7))
            }
            Text("% MG NAVY").font(.appMicro).fontWeight(.bold).tracking(1).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private var bodyCompEmptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass")
                .font(.system(size: 28)).foregroundColor(.gray.opacity(0.4))
            VStack(alignment: .leading, spacing: 4) {
                Text("Aucune donnée de poids")
                    .font(.appLabel).fontWeight(.semibold).foregroundColor(Color.appOnSurface.opacity(0.6))
                Button("Ajouter maintenant") { showAddWeight = true }
                    .font(.appCaption).fontWeight(.semibold).foregroundColor(Color.forge)
            }
        }
    }

    @ViewBuilder
    private func weightSparklineMini(_ sorted: [BodyWeightEntry]) -> some View {
        let pts = Array(sorted.suffix(90))
        if pts.count >= 3 {
            let weights = pts.map(\.weight)
            let minW    = (weights.min() ?? 0) - 1
            let maxW    = (weights.max() ?? 1) + 1
            Canvas { ctx, size in
                let step = size.width / CGFloat(max(pts.count - 1, 1))
                let ys: [CGFloat] = weights.map { w in
                    size.height * (1 - CGFloat((w - minW) / (maxW - minW)))
                }
                var line = Path()
                line.move(to: CGPoint(x: 0, y: ys[0]))
                for (i, y) in ys.dropFirst().enumerated() {
                    line.addLine(to: CGPoint(x: CGFloat(i + 1) * step, y: y))
                }
                ctx.stroke(line, with: .color(Color.forge.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                var fill = line
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(Color.forge.opacity(0.12)))
            }
        } else {
            Text("—").font(.appCaption).foregroundColor(.gray.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Section 5 — PRs

    @ViewBuilder
    private var prsCard: some View {
        if let lifts = dna?.signatureLifts, !lifts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("LIMITES DÉTRUITES")
                        .font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.appCaption).foregroundColor(Color.statusYellow.opacity(0.8))
                }
                .padding(.bottom, 12)

                ForEach(Array(lifts.prefix(5).enumerated()), id: \.offset) { idx, lift in
                    if idx > 0 {
                        Divider().background(Color.appSeparator).padding(.vertical, 2)
                    }
                    prRow(lift)
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(16)
            .padding(.horizontal, 16)
        }
    }

    private func prRow(_ lift: DNASignatureLift) -> some View {
        let dateLabel = shortDate(lift.prDate)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name)
                    .font(.appLabel).fontWeight(.semibold).foregroundColor(.appTextPrimary)
                    .lineLimit(1)
                Text("Détruite le \(dateLabel)")
                    .font(.appCaption).foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(units.format(lift.prLbs, decimals: 0)) × \(lift.prReps)")
                    .font(.appLabel).fontWeight(.bold).foregroundColor(.appTextPrimary)
                if lift.progressionPct > 0 {
                    Text("↑ \(Int(lift.progressionPct))% — ancienne limite")
                        .font(.appCaption).fontWeight(.semibold).foregroundColor(Color.appSuccess)
                }
            }
            Image(systemName: "chevron.right")
                .font(.appCaption).foregroundColor(.gray.opacity(0.4))
        }
        .padding(.vertical, 6)
    }

    // MARK: - Section 6 — Tendances

    private var trendsSection: some View {
        HStack(spacing: 10) {
            trendCard(
                title: "VOLUME HEBDO",
                chart: AnyView(volumeBarchartView),
                trendLabel: volumeTrendLabel,
                trendPositive: volumeTrend?.positive,
                isEmpty: weeklyTonnage.count < 2
            )
            trendCard(
                title: "STRESS PERÇU",
                chart: AnyView(pssSparklineView),
                trendLabel: pssTrendLabel,
                trendPositive: pssTrend?.positive,
                isEmpty: pssHistory.count < 2
            )
        }
        .padding(.horizontal, 16)
    }

    private func trendCard(title: String, chart: AnyView, trendLabel: String, trendPositive: Bool?, isEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appMicro).fontWeight(.bold).tracking(1.5).foregroundColor(.gray)

            if isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.appSeparator, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(height: 44)
                    .overlay(
                        Text("Pas assez de données")
                            .font(.appMicro).foregroundColor(.gray.opacity(0.5))
                    )
            } else {
                chart
            }

            if !trendLabel.isEmpty {
                let trendColor: Color = trendPositive == nil ? .gray : (trendPositive! ? Color.appSuccess : Color.appDanger)
                Text(trendLabel)
                    .font(.appMicro).fontWeight(.semibold)
                    .foregroundColor(trendColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private var volumeBarchartView: some View {
        let items = Array(weeklyTonnage.suffix(4))
        let maxV  = items.map(\.totalVolume).max() ?? 1
        return Canvas { ctx, size in
            let count   = CGFloat(items.count)
            let spacing = CGFloat(6)
            let barW    = (size.width - spacing * (count - 1)) / count
            for (i, entry) in items.enumerated() {
                let h    = CGFloat(entry.totalVolume / maxV) * size.height
                let x    = CGFloat(i) * (barW + spacing)
                let rect = CGRect(x: x, y: size.height - h, width: barW, height: h)
                let isLast = i == items.count - 1
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                         with: .color(Color.forge.opacity(isLast ? 0.9 : 0.45)))
            }
        }
        .frame(height: 44)
    }

    private var pssSparklineView: some View {
        let items  = Array(pssHistory.sorted { $0.date < $1.date }.suffix(4))
        let scores = items.map { Double($0.score) }
        let minS   = scores.min() ?? 0
        let maxS   = max(scores.max() ?? 1, minS + 1)
        let improving  = (scores.last ?? 0) <= (scores.first ?? 0)
        let lineColor: Color = improving ? Color.appSuccess : Color.appDanger
        return Canvas { ctx, size in
            guard scores.count >= 2 else { return }
            let step = size.width / CGFloat(scores.count - 1)
            let pts: [CGPoint] = scores.enumerated().map { i, s in
                CGPoint(x: CGFloat(i) * step,
                        y: size.height * (1 - CGFloat((s - minS) / (maxS - minS))))
            }
            var line = Path()
            line.move(to: pts[0])
            pts.dropFirst().forEach { line.addLine(to: $0) }
            ctx.stroke(line, with: .color(lineColor.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            var fill = line
            if let last = pts.last, let first = pts.first {
                fill.addLine(to: CGPoint(x: last.x, y: size.height))
                fill.addLine(to: CGPoint(x: first.x, y: size.height))
                fill.closeSubpath()
            }
            ctx.fill(fill, with: .color(lineColor.opacity(0.12)))
        }
        .frame(height: 44)
    }

    private var volumeTrendLabel: String {
        guard let t = volumeTrend else { return "" }
        let arrow = t.positive ? "↑" : "↓"
        let verdict = t.positive ? "Tu montes." : "Le rythme faiblit."
        return "\(arrow) \(String(format: "%.0f", t.pct))% vs mois préc. \(verdict)"
    }

    private var pssTrendLabel: String {
        guard let t = pssTrend else {
            return pssHistory.sorted { $0.date < $1.date }.last?.categoryLabel ?? ""
        }
        return t.positive ? "Stress en baisse. Tu récupères." : "Stress en hausse. Surveille la charge."
    }

    // MARK: - Section 7 — Oath

    @ViewBuilder
    private var oathCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("MON SERMENT", systemImage: "shield.fill")
                    .font(.appMicro).fontWeight(.bold).tracking(2).foregroundColor(.gray)
                    .labelStyle(.titleAndIcon)
                Spacer()
                if !oathUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.appCaption).foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.bottom, 12)

            if let oath {
                if oathUnlocked {
                    Text(oath.text)
                        .font(.appLabel).fontWeight(.regular)
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))

                    if warRoomEnabled && warRoomVictoryStreak > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill").foregroundColor(Color.forge)
                                .font(.appCaption)
                            Text("War Room — \(warRoomVictoryStreak)j de victoires consécutives")
                                .font(.appCaption).fontWeight(.semibold).foregroundColor(Color.forge)
                        }
                        .padding(.top, 10)
                    }
                } else {
                    VStack(spacing: 10) {
                        oathRedactedPreview(oath.text)
                        Button(action: authenticateOath) {
                            HStack(spacing: 6) {
                                Image(systemName: "faceid")
                                    .font(.appLabel).fontWeight(.semibold)
                                Text("Tenir mon serment")
                                    .font(.appLabel).fontWeight(.semibold)
                                Image(systemName: "chevron.right")
                                    .font(.appCaption)
                            }
                            .foregroundColor(Color.forge)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "shield")
                        .font(.appTitle).foregroundColor(.gray.opacity(0.35))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tu n'as pas encore prononcé ton serment.")
                            .font(.appLabel).fontWeight(.regular).foregroundColor(.white.opacity(0.5))
                        NavigationLink(destination: OathGateView()) {
                            Text("Écrire mon serment →")
                                .font(.appCaption).fontWeight(.semibold).foregroundColor(Color.forge)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSurfaceInset)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.35), value: oathUnlocked)
    }

    private func oathRedactedPreview(_ text: String) -> some View {
        let words = text.split(separator: " ")
        let preview = words.prefix(12).joined(separator: " ")
        return Text(preview.isEmpty ? "···" : preview + " ···")
            .font(.appLabel).fontWeight(.regular)
            .foregroundColor(.clear)
            .overlay(
                Text(preview.isEmpty ? "···" : preview + " ···")
                    .font(.appLabel).fontWeight(.regular)
                    .foregroundColor(.white.opacity(0.15))
                    .blur(radius: 5)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func authenticateOath() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            oathUnlocked = true; return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Accéder à ton serment") { ok, _ in
            DispatchQueue.main.async { if ok { oathUnlocked = true } }
        }
    }

    // MARK: - Section 8 — Profile actions

    private var profileActionsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "trophy.fill",         color: Color.statusYellow,  label: "Objectif & niveau",
                        detail: profile?.goal.flatMap { $0.isEmpty ? nil : Goal.label(for: $0) },
                        action: { showEdit = true })
            settingsDivider
            settingsRow(icon: "waveform.path.ecg", color: Color.statusCyan, label: "Revoir l'intro HRV", detail: nil, action: {
                hrvOnboardingDone = false
                showHRVOnboarding = true
            })
            settingsDivider
            NavigationLink(destination: SeasonView()) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.statusCyan.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: "calendar.badge.clock")
                            .font(.appLabel).fontWeight(.semibold)
                            .foregroundColor(Color.statusCyan)
                    }
                    Text("Mes chapitres")
                        .font(.appBody)
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.4))
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(Color.appCard)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }


    private var settingsDivider: some View {
        Divider().background(Color.appSeparator).padding(.leading, 46)
    }

    private func settingsRow(icon: String, color: Color, label: String, detail: String?, action: (() -> Void)?) -> some View {
        let row = HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(color.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.appLabel).fontWeight(.semibold)
                    .foregroundColor(color)
            }
            Text(label).font(.appBody).foregroundColor(.appTextPrimary)
            Spacer()
            if let detail {
                Text(detail).font(.appLabel).fontWeight(.regular).foregroundColor(.gray)
            }
            Image(systemName: "chevron.right")
                .font(.appCaption).foregroundColor(.gray.opacity(0.4))
        }
        .padding(.horizontal, 14).padding(.vertical, 14)

        if let action {
            return AnyView(Button(action: action) { row }.buttonStyle(PlainButtonStyle()))
        } else {
            return AnyView(row)
        }
    }

    // MARK: - Incomplete banner

    private var incompleteProfileBanner: some View {
        Button(action: { showEdit = true }) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark.fill")
                    .font(.appTitle).foregroundColor(Color.forge)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profil incomplet — l'IA travaille à l'aveugle.")
                        .font(.appLabel).fontWeight(.semibold).foregroundColor(.appTextPrimary)
                    Text("Taille et âge nécessaires pour calibrer les recommandations.")
                        .font(.appCaption).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.appCaption).foregroundColor(.gray)
            }
            .padding(14)
            .background(Color.forge.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.3), lineWidth: 1))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    // MARK: - Helpers

    private func formattedShortDate(_ iso: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: String(iso.prefix(10))) else { return iso }
        return DateFormatter.longDateFR.string(from: date)
    }

    private func shortDate(_ iso: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: String(iso.prefix(10))) else { return iso }
        return DateFormatter.shortDateFR.string(from: date)
    }

    private func buildMemberSince(isoDate: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: String(isoDate.prefix(10))) else { return "" }
        let months = Calendar.current.dateComponents([.month], from: date, to: Date()).month ?? 0
        let label = DateFormatter.monthYearFR.string(from: date).capitalized
        if months < 1 { return "Warrior since today." }
        return "Warrior since \(label)"
    }

    // MARK: - Load

    private func loadData() async {
        isLoading = true
        await api.fetchDashboard()
        await BodyCompService.shared.refresh()
        dna        = try? await APIService.shared.fetchWorkoutDNA()
        pssHistory = (try? await APIService.shared.fetchPSSHistory()) ?? []
        oath       = try? await APIService.shared.getCurrentOath()
        if let stats = try? await APIService.shared.fetchProfileStats() {
            totalSessions    = stats.totalSessions
            allTimeVolumeLbs = stats.allTimeVolumeLbs
            currentStreak    = stats.currentStreak
            longestStreak    = stats.longestStreak
            weeklyTonnage    = stats.weeklyTonnage.sorted { $0.weekStart < $1.weekStart }
            if let ms = stats.memberSince { memberSinceText = buildMemberSince(isoDate: ms) }
        }
        if let config = try? await APIService.shared.getWarRoomConfig(), config.warStartDate != nil {
            warRoomEnabled = true
            if let summary = try? await APIService.shared.getWarRoomSummary() {
                warRoomVictoryStreak = summary.victoryStreak
            }
        }
        isLoading = false
    }

    private func exportData() async {
        isExporting = true
        defer { isExporting = false }
        guard let url = try? await UserDataExporter.export() else { return }
        await MainActor.run { exportURL = url; showExportShare = true }
    }

    private func loadSelectedPhoto() async {
        guard let item = selectedPhoto,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await uploadPhoto(image)
    }

    private func uploadPhoto(_ image: UIImage) async {
        isUploadingPhoto = true
        let resized = image.resized(to: CGSize(width: 600, height: 600))
        guard let jpegData = resized.jpegData(compressionQuality: 0.7) else {
            isUploadingPhoto = false; return
        }
        let b64 = "data:image/jpeg;base64," + jpegData.base64EncodedString()
        guard b64.count < 500_000 else {
            isUploadingPhoto = false
            photoError = "Image trop lourde (\(jpegData.count / 1024)KB). Choisis une photo plus petite."
            return
        }
        do {
            guard let url = URL(string: "\(APIConfig.base)/api/update_profile_photo") else {
                photoError = "URL invalide"; isUploadingPhoto = false; return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["photo_b64": b64])
            let (_, _) = try await URLSession.authed.data(for: req)
            profileImage = resized
            await api.fetchDashboard()
        } catch {
            photoError = error.localizedDescription
        }
        isUploadingPhoto = false
    }
}

// MARK: - Shared Profile Avatar

struct ProfileAvatarView: View {
    let profile: UserProfile?
    var overrideImage: UIImage? = nil
    let size: CGFloat
    var showsLoading = false

    var body: some View {
        avatarContent
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [Color.forge, Color.statusPurple, Color.forge.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size >= 100 ? 3 : 2
                )
            }
            .contentShape(Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let overrideImage {
            Image(uiImage: overrideImage)
                .resizable()
                .scaledToFill()
        } else if let urlString = profile?.photoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallback
                default:
                    loadingPlaceholder
                }
            }
        } else if let encoded = profile?.photoB64,
                  let data = Data(base64Encoded: encoded.components(separatedBy: ",").last ?? ""),
                  let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
    }

    private var loadingPlaceholder: some View {
        ZStack {
            Circle().fill(Color.appSurfaceInset)
            if showsLoading {
                ProgressView().tint(Color.forge)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
            }
        }
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Color.forge.opacity(0.72), Color.statusPurple.opacity(0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(profile?.name?.prefix(1).uppercased() ?? "?")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundColor(.onAccent)
        }
    }
}

// MARK: - Stat Square Card

struct ProfileStatSquare: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var subtitle: String? = nil
    var isRecord: Bool    = false
    let hasData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.appLabel).fontWeight(.semibold)
                    .foregroundColor(color.opacity(hasData ? 1 : 0.35))
                    .accessibilityHidden(true)
                if isRecord {
                    Image(systemName: "trophy.fill")
                        .font(.appMicro).foregroundColor(Color.statusYellow)
                        .accessibilityHidden(true)
                }
            }
            Text(value)
                .font(.system(size: 26, weight: .black))
                .foregroundColor(isRecord ? Color.statusYellow : Color.appOnSurface.opacity(hasData ? 1 : 0.3))
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if let sub = subtitle {
                Text(sub)
                    .font(.appMicro)
                    .foregroundColor(.gray.opacity(0.6))
            }
            Text(label)
                .font(.appMicro).fontWeight(.bold).tracking(1.5)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appCard)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(hasData ? 0.2 : 0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(hasData ? 1 : 0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard hasData else { return "Aucune donnée pour \(label.lowercased())" }
        let detail = subtitle.map { ", \($0)" } ?? ""
        return "\(value), \(label.lowercased())\(detail)"
    }
}

// MARK: - Subviews kept for external usage

struct ProfileSnapshotPill: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.appBody).foregroundColor(color)
            Text(value).font(.appHeadline).fontWeight(.bold).foregroundColor(.appTextPrimary)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
        .frame(width: 76).padding(.vertical, 14)
        .background(Color.appCard).cornerRadius(14)
    }
}

struct ProfileStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.appTitle).foregroundColor(color)
            Text(value).font(.appHeadline).fontWeight(.bold).foregroundColor(.appTextPrimary)
            Text(label).font(.appCaption).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Color.appCard).cornerRadius(14)
    }
}

struct GoalProgressRow: View {
    let exercise: String
    let progress: GoalProgress
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(exercise).font(.appLabel).fontWeight(.regular).foregroundColor(.appTextPrimary)
                Spacer()
                Text("\(units.format(progress.current)) / \(units.format(progress.goal))")
                    .font(.appCaption)
                    .foregroundColor(progress.achieved ? Color.appSuccess : .gray)
            }
            GeometryReader { geo in
                let pct = progress.goal > 0 ? min(progress.current / progress.goal, 1.0) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appSurfaceInset).frame(height: 4)
                    Capsule()
                        .fill(progress.achieved ? Color.appSuccess : Color.appWarning)
                        .frame(width: geo.size.width * pct, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

struct ProfileRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.gray)
            Spacer()
            Text(value).foregroundColor(.appTextPrimary).fontWeight(.semibold)
        }
    }
}

// MARK: - Camera

struct CameraView: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Share Sheet

enum UserDataExporter {
    static func export() async throws -> URL {
        guard let url = URL(string: "\(APIConfig.base)/api/export_data") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.authed.data(from: url)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("trainingos_export_\(DateFormatter.isoDate.string(from: Date())).json")
        try data.write(to: destination, options: .atomic)
        return destination
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - UIImage resize helper

extension UIImage {
    func resized(to maxSize: CGSize) -> UIImage {
        let ratio = min(maxSize.width / size.width, maxSize.height / size.height, 1)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Edit Sheet

struct EditProfileSheet: View {
    let profile: UserProfile?
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared
    @State private var isSaving = false

    @State private var name: String
    @State private var weight: String
    @State private var height: String
    @State private var age: String
    @State private var goal: String
    @State private var level: String
    @State private var sex: String

    init(profile: UserProfile?, onSaved: @escaping () async -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _name   = State(initialValue: profile?.name ?? "")
        _weight = State(initialValue: profile?.weight.map { UnitSettings.shared.inputStr($0) } ?? "")
        _height = State(initialValue: profile?.height.map { String(Int($0)) } ?? "")
        _age    = State(initialValue: profile?.age.map(String.init) ?? "")
        _goal   = State(initialValue: profile?.goal ?? "")
        _level  = State(initialValue: profile?.level ?? "")
        _sex    = State(initialValue: profile?.sex ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Form {
                    Section("Identité") {
                        LabeledContent("Nom") {
                            TextField("Nom", text: $name)
                                .multilineTextAlignment(.trailing).foregroundColor(.appTextPrimary)
                        }
                        LabeledContent("Sexe") {
                            TextField("M / F", text: $sex)
                                .multilineTextAlignment(.trailing).foregroundColor(.appTextPrimary)
                        }
                        LabeledContent("Âge") {
                            TextField("0", text: $age).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.appTextPrimary)
                        }
                    }
                    .listRowBackground(Color.appCard).foregroundColor(.gray)

                    Section("Mesures") {
                        LabeledContent("Poids (\(units.label))") {
                            TextField("0.0", text: $weight).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.appTextPrimary)
                        }
                        LabeledContent("Taille (cm)") {
                            TextField("0", text: $height).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.appTextPrimary)
                        }
                    }
                    .listRowBackground(Color.appCard).foregroundColor(.gray)

                    Section("Programme") {
                        Picker("Objectif", selection: $goal) {
                            ForEach(Goal.options, id: \.key) { opt in
                                Text(opt.label).tag(opt.key)
                            }
                        }
                        LabeledContent("Niveau") {
                            TextField("Niveau", text: $level)
                                .multilineTextAlignment(.trailing).foregroundColor(.appTextPrimary)
                        }
                    }
                    .listRowBackground(Color.appCard).foregroundColor(.gray)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .tint(Color.forge)
            }
            .navigationTitle("Ton identité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSaving = true
                        Task {
                            let rawWeight = Double(weight.replacingOccurrences(of: ",", with: "."))
                                .map { units.toStorage($0) }
                            try? await APIService.shared.updateProfile(
                                name:   name.isEmpty ? nil : name,
                                weight: rawWeight,
                                height: Double(height),
                                age:    Int(age),
                                goal:   goal.isEmpty ? nil : goal,
                                level:  level.isEmpty ? nil : level,
                                sex:    sex.isEmpty ? nil : sex
                            )
                            await onSaved()
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView().tint(Color.forge)
                        } else {
                            Text("Confirmer").fontWeight(.semibold).foregroundColor(Color.forge)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}


#Preview {
    ProfileView()
        .environmentObject(AppState.shared)
}
