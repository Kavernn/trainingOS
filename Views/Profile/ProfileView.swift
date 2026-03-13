import SwiftUI
import PhotosUI

struct ProfileView: View {
    @StateObject private var api = APIService.shared
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

    var profile: UserProfile? { api.dashboard?.profile }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
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
        }
        .task { await loadData() }
    }

    private var profileScrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                avatarSection
                    .padding(.top, 20)
                statsGrid
                    .padding(.horizontal, 16)
                bodyWeightSection
                    .padding(.horizontal, 16)
                goalsSection
                Spacer(minLength: 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                profilePhoto
                Button(action: { showPhotoOptions = true }) {
                    ZStack {
                        Circle().fill(Color.orange).frame(width: 28, height: 28)
                        if isUploadingPhoto {
                            ProgressView().tint(.white).scaleEffect(0.6)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
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
        }
    }

    @ViewBuilder
    private var profilePhoto: some View {
        if let img = profileImage {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 96, height: 96).clipShape(Circle())
        } else if let b64 = profile?.photoB64,
                  let data = Data(base64Encoded: b64.components(separatedBy: ",").last ?? ""),
                  let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 96, height: 96).clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Color.orange.opacity(0.15)).frame(width: 96, height: 96)
                Text(profile?.name?.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 44, weight: .black)).foregroundColor(.orange)
            }
        }
    }

    private var statsGrid: some View {
        let units = UnitSettings.shared
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let w = profile?.weight {
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

    private var bodyWeightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POIDS CORPOREL")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if !tendance.isEmpty {
                    Text(tendance).font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                }
            }
            if bodyWeight.isEmpty {
                Text("Aucune donnée").font(.system(size: 13)).foregroundColor(.gray).italic().padding(.vertical, 4)
            } else {
                ForEach(bodyWeight.prefix(5)) { entry in
                    let units = UnitSettings.shared
                    HStack {
                        Text(entry.date).font(.system(size: 13)).foregroundColor(.gray)
                        Spacer()
                        if let bf = entry.bodyFat {
                            Text("\(bf, specifier: "%.1f")% gras").font(.system(size: 12)).foregroundColor(.blue)
                        }
                        Text(units.format(entry.weight))
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    }
                    .padding(.vertical, 5)
                    Divider().background(Color.white.opacity(0.06))
                }
            }
            Button(action: { showAddWeight = true }) {
                Label("Ajouter poids", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.orange)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }

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
            .background(Color(hex: "11111c"))
            .cornerRadius(14)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Load
    private func loadData() async {
        isLoading = true
        await api.fetchDashboard()
        await loadBodyWeight()
        isLoading = false
    }

    private func loadBodyWeight() async {
        if let (_, bw, t) = try? await APIService.shared.fetchProfilData() {
            bodyWeight = bw
            tendance = t
        }
    }

    // MARK: - Photo
    private func loadSelectedPhoto() async {
        guard let item = selectedPhoto else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await uploadPhoto(image)
    }

    private func uploadPhoto(_ image: UIImage) async {
        isUploadingPhoto = true
        // Resize to max 600px and compress
        let resized = image.resized(to: CGSize(width: 600, height: 600))
        guard let jpegData = resized.jpegData(compressionQuality: 0.7) else {
            isUploadingPhoto = false
            return
        }
        let b64 = "data:image/jpeg;base64," + jpegData.base64EncodedString()
        guard b64.count < 800_000 else { isUploadingPhoto = false; return }

        do {
            let url = URL(string: "https://training-os-rho.vercel.app/api/update_profile_photo")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["photo_b64": b64])
            let (_, _) = try await URLSession.shared.data(for: req)
            profileImage = resized
            await api.fetchDashboard()
        } catch {}
        isUploadingPhoto = false
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

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
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
        .background(Color(hex: "11111c"))
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
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section("Identité") {
                        LabeledContent("Nom") {
                            TextField("Nom", text: $name)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                        }
                        LabeledContent("Sexe") {
                            TextField("M / F", text: $sex)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                        }
                        LabeledContent("Âge") {
                            TextField("0", text: $age)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))
                    .foregroundColor(.gray)

                    Section("Mesures") {
                        LabeledContent("Unité de poids") {
                            Picker("", selection: $units.isKg) {
                                Text("lbs").tag(false)
                                Text("kg").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                        LabeledContent("Poids (\(units.label))") {
                            TextField("0.0", text: $weight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                        }
                        LabeledContent("Taille (cm)") {
                            TextField("0", text: $height)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))
                    .foregroundColor(.gray)

                    Section("Programme") {
                        LabeledContent("Objectif") {
                            TextField("Objectif", text: $goal)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                        }
                        LabeledContent("Niveau") {
                            TextField("Niveau", text: $level)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))
                    .foregroundColor(.gray)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .keyboardDismissable()
                .tint(.orange)
            }
            .navigationTitle("Modifier profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }
                        .foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSaving = true
                        Task {
                            let rawWeight = Double(weight.replacingOccurrences(of: ",", with: ".")).map { units.toStorage($0) }
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
