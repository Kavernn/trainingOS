import SwiftUI
import AVFoundation

// MARK: - Barcode Scanner

struct BarcodeScannerSheet: View {
    var onDetected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasPermission: Bool? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let permitted = hasPermission {
                    if permitted {
                        BarcodeCameraView { code in
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                            dismiss()
                            onDetected(code)
                        }
                        .ignoresSafeArea()
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.75), lineWidth: 2)
                                .frame(width: 280, height: 110)
                                .shadow(color: .white.opacity(0.15), radius: 8)
                            Text("Pointe vers le code-barres")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 12)
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.slash.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("Accès caméra refusé")
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                            Text("Active l'accès dans Réglages > Confidentialité > Caméra.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.white)
                }
            }
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { hasPermission = granted }
            }
        }
    }
}

struct BarcodeCameraView: UIViewRepresentable {
    var onDetected: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.onDetected = onDetected
        context.coordinator.setupSession(in: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onDetected: ((String) -> Void)?
        var previewLayer: AVCaptureVideoPreviewLayer?
        private let session = AVCaptureSession()
        private var hasDetected = false

        func setupSession(in view: UIView) {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input  = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !hasDetected,
                  let meta = objects.first as? AVMetadataMachineReadableCodeObject,
                  let code = meta.stringValue else { return }
            hasDetected = true
            session.stopRunning()
            onDetected?(code)
        }
    }
}

