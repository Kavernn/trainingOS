import SwiftUI

struct HealthDataSettingsView: View {
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showExportShare = false
    @State private var exportError: String?

    var body: some View {
        ZStack {
            AmbientBackground(color: .pink)

            List {
                Section("HealthKit") {
                    Button(action: openHealthSettings) {
                        HStack(spacing: 12) {
                            settingsIcon("heart.text.square.fill", color: .pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Permissions HealthKit").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                                Text("Gérer depuis les Réglages iOS > Santé > Accès aux apps").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                Section("Données") {
                    Button { Task { await exportData() } } label: {
                        HStack(spacing: 12) {
                            settingsIcon("square.and.arrow.up.fill", color: .statusBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exporter mes données").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                                Text("Créer une copie de mes données").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                            }
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .tint(Color.statusBlue)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.appCaption)
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .accessibilityValue(isExporting ? "Export en cours" : "")
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Données & Santé")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showExportShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .alert("Export impossible", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func openHealthSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func exportData() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            exportURL = try await UserDataExporter.export()
            showExportShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func settingsIcon(_ icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
        }
    }
}
