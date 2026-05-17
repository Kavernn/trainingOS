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
    default:            return .orange
    }
}

struct ProfileView: View {
    @ObservedObject private var api      = APIService.shared
    @ObservedObject private var bodyComp = BodyCompService.shared

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
    @State private var phoenix: PhoenixScore?   = nil
    @State private var oath: OathModel?         = nil
    @State private var oathUnlocked             = false
    @State private var warRoomVictoryStreak: Int = 0
    @State private var warRoomEnabled           = false

    var profile: UserProfile? { api.dashboard?.profile }

    // MARK: - Computed

    private var sessionsThisMonth: Int {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        let key = fmt.string(from: Date())
        return api.dashboard?.sessions.keys.filter { $0.hasPrefix(key) }.count ?? 0
    }

    private var displayTotalSessions: Int {
        totalSessions > 0 ? totalSessions : (api.dashboard?.sessions.count ?? 0)
    }

    private var currentStreak: Int  { dna?.consistency.currentStreak  ?? 0 }
    private var longestStreak: Int  { dna?.consistency.longestStreak  ?? 0 }

    private var weightDelta30d: Double? {
        let sorted = bodyComp.history.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let ref = sorted.last(where: {
            guard let d = fmt.date(from: $0.date) else { return false }
            return d <= cutoff && $0.date != latest.date
        }) else { return nil }
        return latest.weight - ref.weight
    }

    private var allTimeVolumeFormatted: String {
        if allTimeVolumeLbs >= 1_000_000 {
            return String(format: "%.1fM lbs", allTimeVolumeLbs / 1_000_000)
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.groupingSeparator = " "
        fmt.maximumFractionDigits = 0
        return (fmt.string(from: NSNumber(value: allTimeVolumeLbs)) ?? "\(Int(allTimeVolumeLbs))") + " lbs"
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
                AmbientBackground(color: .orange).ignoresSafeArea()
                if isLoading {
                    AppLoadingView()
                } else {
                    profileScrollContent
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Modifier") { showEdit = true }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { Task { await exportData() } } label: {
                        if isExporting {
                            ProgressView().scaleEffect(0.75).tint(.gray)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14)).foregroundColor(.gray)
                        }
                    }
                    .disabled(isExporting)
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
        }
        .task { await loadData() }
    }

    // MARK: - Scroll Content

    private var profileScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if isProfileIncomplete { incompleteProfileBanner }
                headerSection
                if let px = phoenix { phoenixScoreCard(px) }
                statsGridSection
                bodyCompCard
                prsCard
                trendsSection
                oathCard
                settingsCard
                Spacer(minLength: contentBottomPadding)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Section 1 — Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                profilePhotoView
                Button(action: { showPhotoOptions = true }) {
                    ZStack {
                        Circle().fill(Color.orange).frame(width: 30, height: 30)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        if isUploadingPhoto {
                            ProgressView().tint(.white).scaleEffect(0.6)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                }
                .offset(x: 4, y: 4)
            }
            .padding(.bottom, 2)

            Text(profile?.name ?? "Athlète")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            if !memberSinceText.isEmpty {
                Text(memberSinceText)
                    .font(.system(size: 13))
                    .foregroundColor(.gray.opacity(0.8))
            }

            headerBadgesRow
        }
        .padding(.top, 8)
    }

    private var headerBadgesRow: some View {
        HStack(spacing: 8) {
            if let dna {
                let accent = dnaArchetypeAccent(dna.archetype.key)
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .bold))
                    Text(dna.archetype.label.uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                }
                .foregroundColor(accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(accent.opacity(0.15))
                .clipShape(Capsule())
            }
            if let px = phoenix {
                let state = px.phoenixState
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(state.label.uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                }
                .foregroundColor(state.scoreColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(state.scoreColor.opacity(0.15))
                .clipShape(Capsule())
            }
            if let goal = profile?.goal, !goal.isEmpty {
                Text(goal)
                    .font(.system(size: 11)).foregroundColor(.gray)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var profilePhotoView: some View {
        if let img = profileImage {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 88, height: 88).clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 2))
        } else if let urlStr = profile?.photoUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: 88, height: 88).clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 2))
                case .failure:
                    initialsCircle
                default:
                    Circle().fill(Color.orange.opacity(0.08)).frame(width: 88, height: 88)
                        .overlay(ProgressView().tint(.orange).scaleEffect(0.7))
                }
            }
        } else if let b64 = profile?.photoB64,
                  let data = Data(base64Encoded: b64.components(separatedBy: ",").last ?? ""),
                  let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 88, height: 88).clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 2))
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.orange.opacity(0.6), Color.red.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 88, height: 88)
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 2))
            Text(profile?.name?.prefix(1).uppercased() ?? "?")
                .font(.system(size: 38, weight: .black)).foregroundColor(.white)
        }
    }

    // MARK: - Section 2 — Phoenix Score

    private func phoenixScoreCard(_ px: PhoenixScore) -> some View {
        let state   = px.phoenixState
        let color   = state.scoreColor
        let delta7d = px.rawDelta
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PHOENIX SCORE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 13)).foregroundColor(color.opacity(0.7))
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(px.score))")
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(state.glowOpacity), radius: state.glowRadius)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.label.uppercased())
                        .font(.system(size: 12, weight: .bold)).tracking(1)
                        .foregroundColor(color)
                    if delta7d != 0 {
                        HStack(spacing: 3) {
                            Image(systemName: delta7d >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: "%.1f cette semaine", abs(delta7d)))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(delta7d >= 0 ? .green : .red)
                    }
                }
                Spacer()
            }

            HStack(spacing: 0) {
                phoenixAxisChip(icon: "dumbbell.fill",   label: "FORCE",      delta: px.axes.workout.delta,   color: .orange)
                Divider().background(Color.white.opacity(0.08)).padding(.vertical, 4)
                phoenixAxisChip(icon: "brain.head.profile", label: "MENTAL",  delta: px.axes.stress.delta,    color: .purple)
                Divider().background(Color.white.opacity(0.08)).padding(.vertical, 4)
                phoenixAxisChip(icon: "fork.knife",      label: "NUTRITION",  delta: px.axes.nutrition.delta, color: .green)
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
        }
        .padding(16)
        .background(state.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.15), lineWidth: 1))
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private func phoenixAxisChip(icon: String, label: String, delta: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color.opacity(0.8))
            if delta != 0 {
                HStack(spacing: 2) {
                    Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(String(format: "%.1f", abs(delta)))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(delta >= 0 ? .green : .red)
            } else {
                Text("—").font(.system(size: 10)).foregroundColor(.gray.opacity(0.4))
            }
            Text(label)
                .font(.system(size: 8, weight: .bold)).tracking(0.5)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Section 3 — Stats Grid

    private var statsGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ProfileStatSquare(
                value: displayTotalSessions > 0 ? "\(displayTotalSessions)" : "—",
                label: "SÉANCES", icon: "dumbbell.fill", color: .orange,
                subtitle: nil,
                hasData: displayTotalSessions > 0
            )
            ProfileStatSquare(
                value: currentStreak > 0 ? "\(currentStreak)j" : "—",
                label: "STREAK", icon: "flame.fill", color: .red,
                subtitle: longestStreak > 0 ? "record \(longestStreak)j" : nil,
                isRecord: currentStreak > 0 && currentStreak >= longestStreak,
                hasData: currentStreak > 0
            )
            ProfileStatSquare(
                value: allTimeVolumeLbs > 0 ? allTimeVolumeFormatted : "—",
                label: "VOLUME ALL-TIME", icon: "scalemass.fill", color: .blue,
                subtitle: nil,
                hasData: allTimeVolumeLbs > 0
            )
            ProfileStatSquare(
                value: "\(sessionsThisMonth)",
                label: "JOURS ACTIFS CE MOIS", icon: "calendar", color: .green,
                subtitle: nil,
                hasData: true
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Section 4 — Body Composition

    private var bodyCompCard: some View {
        let heightCm   = profile?.height ?? 178.0
        let navyResult = bodyComp.getNavyBodyFat(heightCm: heightCm)
        let latest     = bodyComp.latest
        let delta      = weightDelta30d
        let histSorted = bodyComp.history.sorted { $0.date < $1.date }

        return NavigationLink(destination: BodyCompView()) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("BODY COMP")
                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12)).foregroundColor(.gray.opacity(0.5))
                }

                if let latest {
                    HStack(spacing: 0) {
                        bodyCompWeightCol(latest: latest, delta: delta)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 52)
                        bodyCompFatCol(navyResult: navyResult)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 52)
                        weightSparklineMini(histSorted)
                            .frame(width: 72, height: 44)
                            .padding(.leading, 14)
                    }
                    Text("Données du \(formattedShortDate(latest.date))")
                        .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
                } else {
                    bodyCompEmptyState
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }

    private func bodyCompWeightCol(latest: BodyWeightEntry, delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%.1f lbs", latest.weight))
                .font(.system(size: 22, weight: .black)).foregroundColor(.white)
            if let d = delta {
                HStack(spacing: 3) {
                    Image(systemName: d > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%.1f lbs", abs(d)))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(d <= 0 ? .green : .orange)
            }
            Text("POIDS").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bodyCompFatCol(navyResult: NavyBodyFatResult?) -> some View {
        let cat      = navyResult?.category()
        let catColor = cat?.color ?? Color.clear
        let catLabel = cat?.label ?? ""
        let pctStr   = navyResult.map { String(format: "%.1f%%", $0.pct) } ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            Text(pctStr)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(navyResult != nil ? catColor : .white.opacity(0.3))
            if navyResult != nil {
                Text(catLabel)
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(catColor.opacity(0.8))
            } else {
                Text("Incomplet").font(.system(size: 10)).foregroundColor(.orange.opacity(0.7))
            }
            Text("% MG NAVY").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
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
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                Button("Ajouter maintenant") { showAddWeight = true }
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
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
                ctx.stroke(line, with: .color(.orange.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                var fill = line
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(.orange.opacity(0.12)))
            }
        } else {
            Text("—").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4))
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
                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12)).foregroundColor(.yellow.opacity(0.8))
                }
                .padding(.bottom, 12)

                ForEach(Array(lifts.prefix(5).enumerated()), id: \.offset) { idx, lift in
                    if idx > 0 {
                        Divider().background(Color.white.opacity(0.06)).padding(.vertical, 2)
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
        let prLbs     = lift.prKg * 2.20462
        let dateLabel = shortDate(lift.prDate)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(1)
                Text("Détruite le \(dateLabel)")
                    .font(.system(size: 11)).foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f lbs × %d", prLbs, lift.prReps))
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                if lift.progressionPct > 0 {
                    Text("↑ \(Int(lift.progressionPct))% — ancienne limite")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11)).foregroundColor(.gray.opacity(0.4))
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
                .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)

            if isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(height: 44)
                    .overlay(
                        Text("Pas assez de données")
                            .font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
                    )
            } else {
                chart
            }

            if !trendLabel.isEmpty {
                let trendColor: Color = trendPositive == nil ? .gray : (trendPositive! ? .green : .red)
                Text(trendLabel)
                    .font(.system(size: 10, weight: .semibold))
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
                         with: .color(.orange.opacity(isLast ? 0.9 : 0.45)))
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
        let lineColor: Color = improving ? .green : .red
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
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                    .labelStyle(.titleAndIcon)
                Spacer()
                if !oathUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11)).foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.bottom, 12)

            if let oath {
                if oathUnlocked {
                    Text(oath.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))

                    if warRoomEnabled && warRoomVictoryStreak > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill").foregroundColor(.orange)
                                .font(.system(size: 11))
                            Text("War Room — \(warRoomVictoryStreak)j de victoires consécutives")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                        }
                        .padding(.top, 10)
                    }
                } else {
                    VStack(spacing: 10) {
                        oathRedactedPreview(oath.text)
                        Button(action: authenticateOath) {
                            HStack(spacing: 6) {
                                Image(systemName: "faceid")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Tenir mon serment")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.orange)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "shield")
                        .font(.system(size: 22)).foregroundColor(.gray.opacity(0.35))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tu n'as pas encore prononcé ton serment.")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                        NavigationLink(destination: OathGateView()) {
                            Text("Écrire mon serment →")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "0F0F0F"))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.35), value: oathUnlocked)
    }

    private func oathRedactedPreview(_ text: String) -> some View {
        let words = text.split(separator: " ")
        let preview = words.prefix(12).joined(separator: " ")
        return Text(preview.isEmpty ? "···" : preview + " ···")
            .font(.system(size: 14))
            .foregroundColor(.clear)
            .overlay(
                Text(preview.isEmpty ? "···" : preview + " ···")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.15))
                    .blur(radius: 5)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func authenticateOath() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            oathUnlocked = true; return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "Accéder à ton serment") { ok, _ in
            DispatchQueue.main.async { if ok { oathUnlocked = true } }
        }
    }

    // MARK: - Section 8 — Settings

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "trophy.fill",         color: .yellow,  label: "Objectif & niveau",
                        detail: profile?.goal.flatMap { $0.isEmpty ? nil : $0 },
                        action: { showEdit = true })
            settingsDivider
            settingsRow(icon: "scalemass.fill",      color: .orange,  label: "Unités",         detail: "lbs",  action: nil)
            settingsDivider
            settingsRow(icon: "bell.fill",           color: .blue,    label: "Notifications",  detail: nil,    action: nil)
            settingsDivider
            settingsRow(icon: "square.and.arrow.up", color: .green,   label: "Export données", detail: nil,    action: {
                Task { await exportData() }
            })
            settingsDivider
            NavigationLink(destination: GraveyardView()) {
                graveyardRow
            }
            .buttonStyle(PlainButtonStyle())
            settingsDivider
            settingsRow(icon: "person.crop.circle",  color: .purple,  label: "Compte",         detail: nil,    action: {
                showEdit = true
            })
        }
        .background(Color.appCard)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private var graveyardRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: "2A1800"))
                    .frame(width: 30, height: 30)
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "FF6600"))
            }
            Text("Graveyard")
                .font(.system(size: 15))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }

    private var settingsDivider: some View {
        Divider().background(Color.white.opacity(0.06)).padding(.leading, 46)
    }

    private func settingsRow(icon: String, color: Color, label: String, detail: String?, action: (() -> Void)?) -> some View {
        let row = HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(color.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(label).font(.system(size: 15)).foregroundColor(.white)
            Spacer()
            if let detail {
                Text(detail).font(.system(size: 13)).foregroundColor(.gray)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12)).foregroundColor(.gray.opacity(0.4))
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
                    .font(.system(size: 22)).foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profil incomplet — l'IA travaille à l'aveugle.")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    Text("Taille et âge nécessaires pour calibrer les recommandations.")
                        .font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(14)
            .background(Color.orange.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    // MARK: - Helpers

    private func formattedShortDate(_ iso: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "d MMM yyyy"
        out.locale = Locale(identifier: "fr_FR")
        return out.string(from: date)
    }

    private func shortDate(_ iso: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "d MMM"
        out.locale = Locale(identifier: "fr_FR")
        return out.string(from: date)
    }

    private func buildMemberSince(isoDate: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: String(isoDate.prefix(10))) else { return "" }
        let months = Calendar.current.dateComponents([.month], from: date, to: Date()).month ?? 0
        let out = DateFormatter(); out.dateFormat = "MMMM yyyy"
        out.locale = Locale(identifier: "fr_FR")
        let label = out.string(from: date).capitalized
        if months < 1 { return "Warrior since today." }
        return "Warrior since \(label)"
    }

    // MARK: - Load

    private func loadData() async {
        isLoading = true
        await api.fetchDashboard()
        await BodyCompService.shared.refresh()
        async let dnaFetch       = APIService.shared.fetchWorkoutDNA()
        async let pssFetch       = APIService.shared.fetchPSSHistory()
        async let phoenixFetch   = APIService.shared.fetchPhoenixScore()
        async let oathFetch      = APIService.shared.getCurrentOath()
        async let warConfigFetch = APIService.shared.getWarRoomConfig()
        try? await APIService.shared.fetchStatsData()
        dna        = try? await dnaFetch
        pssHistory = (try? await pssFetch) ?? []
        phoenix    = try? await phoenixFetch
        oath       = try? await oathFetch
        if let config = try? await warConfigFetch, config.warStartDate != nil {
            warRoomEnabled = true
            if let summary = try? await APIService.shared.getWarRoomSummary() {
                warRoomVictoryStreak = summary.victoryStreak
            }
        }
        loadStatsSnapshot()
        isLoading = false
    }

    private func loadStatsSnapshot() {
        struct Snap: Decodable {
            let sessions: [String: SessionEntry]
            let weeklyTonnage: [WeeklyTonnageEntry]?
            enum CodingKeys: String, CodingKey {
                case sessions
                case weeklyTonnage = "weekly_tonnage"
            }
        }
        guard let data = CacheService.shared.load(for: "stats_data"),
              let r = try? JSONDecoder().decode(Snap.self, from: data) else { return }
        totalSessions    = r.sessions.count
        allTimeVolumeLbs = r.sessions.values.compactMap(\.sessionVolume).reduce(0, +)
        weeklyTonnage    = (r.weeklyTonnage ?? []).sorted { $0.weekStart < $1.weekStart }
        if let first = r.sessions.keys.sorted().first {
            memberSinceText = buildMemberSince(isoDate: first)
        }
    }

    private func exportData() async {
        isExporting = true
        defer { isExporting = false }
        guard let url = URL(string: "https://training-os-rho.vercel.app/api/export_data"),
              let (data, _) = try? await URLSession.authed.data(from: url) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trainingos_export_\(DateFormatter.isoDate.string(from: Date())).json")
        try? data.write(to: tmp)
        await MainActor.run { exportURL = tmp; showExportShare = true }
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
            let url = URL(string: "https://training-os-rho.vercel.app/api/update_profile_photo")!
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color.opacity(hasData ? 1 : 0.35))
                if isRecord {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10)).foregroundColor(.yellow)
                }
            }
            Text(value)
                .font(.system(size: 26, weight: .black))
                .foregroundColor(isRecord ? .yellow : .white.opacity(hasData ? 1 : 0.3))
                .lineLimit(1).minimumScaleFactor(0.6)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.6))
            }
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(1.5)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .opacity(hasData ? 1 : 0.7)
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
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
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
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(color)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 11)).foregroundColor(.gray)
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
                Text(exercise).font(.system(size: 13)).foregroundColor(.white)
                Spacer()
                Text("\(units.format(progress.current)) / \(units.format(progress.goal))")
                    .font(.system(size: 12))
                    .foregroundColor(progress.achieved ? .green : .gray)
            }
            GeometryReader { geo in
                let pct = progress.goal > 0 ? min(progress.current / progress.goal, 1.0) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "191926")).frame(height: 4)
                    Capsule()
                        .fill(progress.achieved ? Color.green : Color.orange)
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
            Text(value).foregroundColor(.white).fontWeight(.semibold)
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
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                        LabeledContent("Sexe") {
                            TextField("M / F", text: $sex)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                        LabeledContent("Âge") {
                            TextField("0", text: $age).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.appCard).foregroundColor(.gray)

                    Section("Mesures") {
                        LabeledContent("Poids (lbs)") {
                            TextField("0.0", text: $weight).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                        LabeledContent("Taille (cm)") {
                            TextField("0", text: $height).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.appCard).foregroundColor(.gray)

                    Section("Programme") {
                        LabeledContent("Objectif") {
                            TextField("Objectif", text: $goal)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                        LabeledContent("Niveau") {
                            TextField("Niveau", text: $level)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.appCard).foregroundColor(.gray)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .tint(.orange)
            }
            .navigationTitle("Ton identité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
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
                            ProgressView().tint(.orange)
                        } else {
                            Text("Confirmer").fontWeight(.semibold).foregroundColor(.orange)
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
