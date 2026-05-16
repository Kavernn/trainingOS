import SwiftUI
import Combine
import PhotosUI
import Charts

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
    @ObservedObject private var api = APIService.shared
    @State private var bodyWeight: [BodyWeightEntry] = []
    @State private var tendance = ""
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showAddWeight = false
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var profileImage: UIImage? = nil
    @State private var isUploadingPhoto = false
    @State private var photoError: String? = nil
    @State private var isExporting = false
    @State private var exportURL: URL? = nil
    @State private var showExportShare = false
    @State private var dna: WorkoutDNAResponse? = nil
    @State private var totalSessions: Int = 0
    @State private var memberSinceText: String = ""

    var profile: UserProfile? { api.dashboard?.profile }

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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.orange)
                } else {
                    profileScrollContent
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Modifier") { showEdit = true }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await exportData() }
                    } label: {
                        if isExporting {
                            ProgressView().scaleEffect(0.75).tint(.gray)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
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
                    await loadBodyWeight()
                }
            }
            .sheet(isPresented: $showAddWeight) {
                BodyWeightSheet(editEntry: nil) { await loadBodyWeight() }
            }
            .alert("Erreur photo", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(photoError ?? "") }
            .sheet(isPresented: $showExportShare) {
                if let url = exportURL { ShareSheet(items: [url]) }
            }
        }
        .task { await loadData() }
    }

    private var isProfileIncomplete: Bool {
        let p = profile
        return p?.name == nil || p?.weight == nil || p?.height == nil
            || p?.age == nil || p?.goal == nil || p?.level == nil
    }

    // MARK: - Scroll content

    private var profileScrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isProfileIncomplete { incompleteProfileBanner }
                avatarSection
                    .padding(.top, isProfileIncomplete ? 4 : 20)
                statsSnapshotSection
                identityGrid
                    .padding(.horizontal, 16)
                prsVitrineSection
                weightSparklineSection
                    .padding(.horizontal, 16)
                goalsSection
                Spacer(minLength: 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Incomplete profile banner

    private var incompleteProfileBanner: some View {
        Button(action: { showEdit = true }) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark.fill")
                    .font(.system(size: 22)).foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Complète ton profil")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    Text("Poids, taille, niveau requis pour les suggestions IA")
                        .font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(14)
            .background(Color.orange.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                profilePhoto
                Button(action: { showPhotoOptions = true }) {
                    ZStack {
                        Circle().fill(Color.orange).frame(width: 28, height: 28)
                        if isUploadingPhoto {
                            ProgressView().tint(.white).scaleEffect(0.6)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                }
                .offset(x: 4, y: 4)
            }
            Text(profile?.name ?? "Athlète")
                .font(.system(size: 24, weight: .bold)).foregroundColor(.white)
            if let goal = profile?.goal {
                Text(goal).font(.system(size: 13)).foregroundColor(.gray)
            }
            profileBadgesRow
        }
    }

    private var profileBadgesRow: some View {
        HStack(spacing: 8) {
            if let dna {
                let accent = dnaArchetypeAccent(dna.archetype.key)
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .bold))
                    Text(dna.archetype.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundColor(accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(accent.opacity(0.15))
                .clipShape(Capsule())
            }
            if !memberSinceText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10))
                    Text(memberSinceText)
                        .font(.system(size: 11))
                }
                .foregroundColor(.gray)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var profilePhoto: some View {
        if let img = profileImage {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 96, height: 96).clipShape(Circle())
        } else if let urlStr = profile?.photoUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: 96, height: 96).clipShape(Circle())
                case .failure:
                    photoPlaceholder
                default:
                    Circle().fill(Color.orange.opacity(0.08))
                        .frame(width: 96, height: 96)
                        .overlay(ProgressView().tint(.orange).scaleEffect(0.7))
                }
            }
        } else if let b64 = profile?.photoB64,
                  let data = Data(base64Encoded: b64.components(separatedBy: ",").last ?? ""),
                  let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 96, height: 96).clipShape(Circle())
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            Circle().fill(Color.orange.opacity(0.15)).frame(width: 96, height: 96)
            Text(profile?.name?.prefix(1).uppercased() ?? "?")
                .font(.system(size: 44, weight: .black)).foregroundColor(.orange)
        }
    }

    // MARK: - Stats Snapshot

    private var statsSnapshotSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ProfileSnapshotPill(
                    label: "Séances", value: "\(displayTotalSessions)",
                    icon: "dumbbell.fill", color: .orange)
                if currentStreak > 0 {
                    ProfileSnapshotPill(
                        label: "Streak", value: "\(currentStreak)j",
                        icon: "flame.fill", color: .red)
                }
                if longestStreak > 0 {
                    ProfileSnapshotPill(
                        label: "Record", value: "\(longestStreak)j",
                        icon: "trophy.fill", color: .yellow)
                }
                ProfileSnapshotPill(
                    label: "Ce mois", value: "\(sessionsThisMonth)",
                    icon: "calendar", color: .green)
                if let sessPerWeek = dna?.consistency.sessionsPerWeek {
                    ProfileSnapshotPill(
                        label: "/ semaine", value: String(format: "%.1f", sessPerWeek),
                        icon: "chart.bar.fill", color: .blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Identity Grid

    private var identityGrid: some View {
        let units = UnitSettings.shared
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let w = bodyWeight.sorted(by: { $0.date < $1.date }).last?.weight {
                ProfileStatCard(icon: "scalemass.fill", label: "Poids", value: units.format(w), color: .orange)
            }
            if let h = profile?.height {
                ProfileStatCard(icon: "ruler.fill", label: "Taille", value: "\(Int(h)) cm", color: .blue)
            }
            if let age = profile?.age {
                ProfileStatCard(icon: "calendar", label: "Âge", value: "\(age) ans", color: .purple)
            }
            if let level = profile?.level {
                ProfileStatCard(icon: "chart.bar.fill", label: "Niveau", value: level, color: .green)
            }
        }
    }

    // MARK: - PRs Vitrine

    @ViewBuilder
    private var prsVitrineSection: some View {
        if let lifts = dna?.signatureLifts, !lifts.isEmpty {
            PRsVitrineCard(lifts: Array(lifts.prefix(3)))
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Weight Sparkline

    private var weightSparklineSection: some View {
        WeightSparklineCard(
            bodyWeight: bodyWeight,
            tendance: tendance,
            onAdd: { showAddWeight = true }
        )
    }

    // MARK: - Goals

    @ViewBuilder
    private var goalsSection: some View {
        if let goals = api.dashboard?.goals, !goals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("OBJECTIFS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                ForEach(goals.sorted(by: { $0.key < $1.key }), id: \.key) { ex, progress in
                    GoalProgressRow(exercise: ex, progress: progress)
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(14)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Load

    private func loadData() async {
        isLoading = true
        await api.fetchDashboard()
        await loadBodyWeight()
        dna = try? await APIService.shared.fetchWorkoutDNA()
        loadStatsSnapshot()
        isLoading = false
    }

    private func loadStatsSnapshot() {
        struct Snap: Decodable { let sessions: [String: SessionEntry] }
        guard let data = CacheService.shared.load(for: "stats_data"),
              let r = try? JSONDecoder().decode(Snap.self, from: data) else { return }
        totalSessions = r.sessions.count
        if let first = r.sessions.keys.sorted().first {
            memberSinceText = buildMemberSince(isoDate: first)
        }
    }

    private func buildMemberSince(isoDate: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: String(isoDate.prefix(10))) else { return "" }
        let months = Calendar.current.dateComponents([.month], from: date, to: Date()).month ?? 0
        if months < 1 { return "Nouveau membre" }
        return "Membre depuis \(months) mois"
    }

    private func exportData() async {
        isExporting = true
        defer { isExporting = false }
        guard let url = URL(string: "https://training-os-rho.vercel.app/api/export_data"),
              let (data, _) = try? await URLSession.authed.data(from: url) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trainingos_export_\(DateFormatter.isoDate.string(from: Date())).json")
        try? data.write(to: tmp)
        await MainActor.run {
            exportURL = tmp
            showExportShare = true
        }
    }

    private func loadBodyWeight() async {
        if let (_, bw, t) = try? await APIService.shared.fetchProfilData() {
            bodyWeight = bw
            tendance = t
        }
    }

    private func loadSelectedPhoto() async {
        guard let item = selectedPhoto else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
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

// MARK: - PRs Vitrine Card

private struct PRsVitrineCard: View {
    let lifts: [DNASignatureLift]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PERSONAL RECORDS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.system(size: 13)).foregroundColor(.yellow)
            }
            ForEach(Array(lifts.enumerated()), id: \.offset) { idx, lift in
                PRRow(lift: lift)
                if idx < lifts.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

private struct PRRow: View {
    let lift: DNASignatureLift

    private var prDateFormatted: String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: String(lift.prDate.prefix(10))) else { return lift.prDate }
        let out = DateFormatter()
        out.dateFormat = "d MMM yyyy"
        out.locale = Locale(identifier: "fr_FR")
        return out.string(from: date)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(lift.name)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(prDateFormatted)
                    .font(.system(size: 11)).foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                let prLbs = lift.prKg * 2.20462
                Text("\(UnitSettings.shared.format(prLbs)) × \(lift.prReps)")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                if lift.progressionPct > 0 {
                    Text("+\(lift.progressionPct, specifier: "%.0f")%")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Weight Sparkline Card

private struct WeightSparklineCard: View {
    let bodyWeight: [BodyWeightEntry]
    let tendance: String
    let onAdd: () -> Void

    private var sorted: [BodyWeightEntry] { bodyWeight.sorted { $0.date < $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POIDS CORPOREL")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if !tendance.isEmpty {
                    Text(tendance).font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                }
            }
            if sorted.isEmpty {
                Text("Aucune donnée")
                    .font(.system(size: 13)).foregroundColor(.gray).italic().padding(.vertical, 4)
            } else {
                currentWeightRow
                if sorted.count >= 2 { sparkline }
            }
            Button(action: onAdd) {
                Label("Ajouter poids", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.orange)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private var currentWeightRow: some View {
        let last = sorted.last!
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(UnitSettings.shared.format(last.weight))
                .font(.system(size: 32, weight: .black)).foregroundColor(.orange)
            if let bf = last.bodyFat {
                Text(String(format: "%.1f%% gras", bf))
                    .font(.system(size: 13)).foregroundColor(.blue).padding(.bottom, 3)
            }
        }
    }

    private var sparkline: some View {
        let pts = Array(sorted.suffix(30).enumerated())
        let weights = pts.map(\.element.weight)
        let minW = (weights.min() ?? 0)
        let maxW = (weights.max() ?? 1)
        let pad  = max((maxW - minW) * 0.15, 2.0)
        return Chart(pts, id: \.offset) { item in
            LineMark(
                x: .value("", item.offset),
                y: .value("", item.element.weight)
            )
            .foregroundStyle(.orange)
            .interpolationMethod(.catmullRom)
            AreaMark(
                x: .value("", item.offset),
                yStart: .value("", minW - pad),
                yEnd: .value("", item.element.weight)
            )
            .foregroundStyle(LinearGradient(
                colors: [.orange.opacity(0.28), .clear],
                startPoint: .top, endPoint: .bottom
            ))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (minW - pad)...(maxW + pad))
        .frame(height: 64)
    }
}

// MARK: - Snapshot Pill

struct ProfileSnapshotPill: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text(label)
                .font(.system(size: 10)).foregroundColor(.gray)
        }
        .frame(width: 76)
        .padding(.vertical, 14)
        .background(Color.appCard)
        .cornerRadius(14)
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

// MARK: - Subviews

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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.appCard)
        .cornerRadius(14)
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
                            TextField("0", text: $age)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.appCard)
                    .foregroundColor(.gray)

                    Section("Mesures") {
                        LabeledContent("Poids (lbs)") {
                            TextField("0.0", text: $weight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                        LabeledContent("Taille (cm)") {
                            TextField("0", text: $height)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.appCard)
                    .foregroundColor(.gray)

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
                    .listRowBackground(Color.appCard)
                    .foregroundColor(.gray)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .tint(.orange)
            }
            .navigationTitle("Modifier profil")
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
                            Text("Sauvegarder").fontWeight(.semibold).foregroundColor(.orange)
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
