import SwiftUI

// MARK: - Scan Label Sheet

struct ScanLabelSheet: View {
    var onSaved: () async -> Void
    var onLogged: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    enum ScanStep { case capture, analyzing, review }
    @State private var step: ScanStep = .capture

    @State private var showCameraPicker = false
    @State private var pickedImage: UIImage? = nil

    @State private var quantity = "1"
    @State private var unit = "serving"

    @State private var nom       = ""
    @State private var calories  = ""
    @State private var proteines = ""
    @State private var glucides  = ""
    @State private var lipides   = ""
    @State private var fibres    = ""
    @State private var sodium    = ""

    @State private var errorMsg: String? = nil
    @State private var isSaving = false
    @State private var confirmDiscard = false

    private var isDirty: Bool { pickedImage != nil || step == .review }

    @State private var mealType: String = {
        let h = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        switch h {
        case 5..<10:  return "matin"
        case 10..<14: return "midi"
        case 14..<20: return "soir"
        default:      return "collation"
        }
    }()

    private func p(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                switch step {
                case .capture:  captureView
                case .analyzing: analyzingView
                case .review:   reviewView
                }
            }
            .navigationTitle("Scan étiquette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }.foregroundColor(Color.forge)
                }
                if step == .review {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Confirmer") { confirmSave() }
                            .foregroundColor(Color.forge).fontWeight(.semibold)
                            .disabled(nom.isEmpty || calories.isEmpty || isSaving)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("Abandonner le scan ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Les valeurs scannées seront perdues.")
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Step 1 — Capture

    private var captureView: some View {
        VStack(spacing: 20) {
            Button { showCameraPicker = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.15),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        )
                    if let img = pickedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .padding(8)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 44))
                                .foregroundColor(Color.forge.opacity(0.7))
                            Text("Prendre une photo de l'étiquette")
                                .font(.system(size: 14))
                                .foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                    }
                }
                .frame(height: 180)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showCameraPicker) {
                ImagePickerView(image: $pickedImage, sourceType: .camera)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("QUANTITÉ")
                        .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(.appTextSecondary)
                    TextField("1", text: $quantity)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.appTextPrimary)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(10)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("UNITÉ")
                        .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(.appTextSecondary)
                    Picker("", selection: $unit) {
                        Text("Portion").tag("serving")
                        Text("g").tag("g")
                        Text("ml").tag("ml")
                    }
                    .pickerStyle(.segmented)
                }
            }

            if let err = errorMsg {
                Text(err)
                    .font(.appLabel).foregroundColor(Color.appDanger)
                    .multilineTextAlignment(.center)
            }

            Button {
                guard pickedImage != nil else { errorMsg = "Sélectionne une image d'abord"; return }
                Task { await analyze() }
            } label: {
                Text("Analyser")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(pickedImage == nil ? Color(white: 0.5) : Color.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(pickedImage == nil ? Color.forge.opacity(0.4) : Color.forge)
                    .cornerRadius(12)
            }
            .disabled(pickedImage == nil)

            Spacer()
        }
        .padding(20)
    }

    // MARK: Step 2 — Analyzing

    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.5).tint(Color.forge)
            Text("Analyse en cours…")
                .font(.appBody).foregroundColor(.appTextSecondary).padding(.top, 8)
            Spacer()
        }
    }

    // MARK: Step 3 — Review

    private var reviewView: some View {
        Form {
            Section("ALIMENT") {
                TextField("Nom", text: $nom).foregroundColor(.appTextPrimary)
                HStack {
                    TextField("Calories", text: $calories).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                    Text("kcal").foregroundColor(.appTextSecondary).font(.appLabel)
                }
            }.listRowBackground(Color.appCard)

            Section("MACROS") {
                HStack {
                    TextField("Protéines", text: $proteines).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                    Text("g").foregroundColor(.appTextSecondary).font(.appLabel)
                }
                HStack {
                    TextField("Glucides", text: $glucides).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                    Text("g").foregroundColor(.appTextSecondary).font(.appLabel)
                }
                HStack {
                    TextField("Lipides", text: $lipides).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                    Text("g").foregroundColor(.appTextSecondary).font(.appLabel)
                }
            }.listRowBackground(Color.appCard)

            if p(fibres) > 0 || p(sodium) > 0 {
                Section("INFORMATIF") {
                    HStack {
                        Text("Fibres").foregroundColor(.appTextSecondary)
                        Spacer()
                        Text("\(fibres)g").foregroundColor(.appTextPrimary)
                    }
                    HStack {
                        Text("Sodium").foregroundColor(.appTextSecondary)
                        Spacer()
                        Text("\(sodium)mg").foregroundColor(.appTextPrimary)
                    }
                }.listRowBackground(Color.appCard)
            }

            Section("REPAS") {
                Picker("", selection: $mealType) {
                    Text("Matin").tag("matin")
                    Text("Midi").tag("midi")
                    Text("Soir").tag("soir")
                    Text("Collation").tag("collation")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }.listRowBackground(Color.appCard)

            Section {
                Button("← Refaire le scan") {
                    withAnimation { step = .capture; errorMsg = nil }
                }.foregroundColor(.appTextSecondary)
            }.listRowBackground(Color.appCard)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Logic

    private func analyze() async {
        guard let img = pickedImage else { return }
        step = .analyzing
        errorMsg = nil
        guard let jpeg = img.jpegData(compressionQuality: 0.7) else {
            errorMsg = "Impossible de traiter l'image"
            step = .capture
            return
        }
        let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 1
        do {
            let result = try await APIService.shared.scanNutritionLabel(
                imageBase64: jpeg.base64EncodedString(),
                quantity: qty,
                unit: unit
            )
            nom       = result.nom
            calories  = "\(result.calories)"
            proteines = "\(result.proteines)"
            glucides  = "\(result.glucides)"
            lipides   = "\(result.lipides)"
            fibres    = "\(result.fibres)"
            sodium    = "\(result.sodiumMg)"
            step = .review
        } catch let e as ScanLabelError {
            errorMsg = e.message
            step = .capture
        } catch {
            errorMsg = "Connexion impossible — réessaie"
            step = .capture
        }
    }

    private func confirmSave() {
        Task {
            isSaving = true
            try? await APIService.shared.addNutritionEntry(
                name: nom,
                calories: p(calories),
                proteines: p(proteines),
                glucides: p(glucides),
                lipides: p(lipides),
                mealType: mealType,
                source: "scan"
            )
            await onSaved()
            onLogged?(nom)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - UIImagePickerController wrapper

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
