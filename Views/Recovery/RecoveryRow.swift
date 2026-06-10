import SwiftUI

struct RecoveryRow: View {
    let entry: RecoveryEntry
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void

    @State private var expanded      = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Always-visible header ─────────────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(entry.date ?? "")
                            .font(.appLabel.weight(.semibold)).foregroundColor(.white)
                        if entry.isFromWatch {
                            Label("Watch", systemImage: "applewatch")
                                .font(.appMicro.weight(.medium))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                    // 3 primary KPIs
                    HStack(spacing: 10) {
                        kpiPill("moon.fill",
                                entry.sleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                                sleepColor(entry.sleepHours))
                        kpiPill("bolt.fill",
                                entry.energyPre.map { String(format: "%.0f/10", $0) } ?? "—",
                                energyColor(entry.energyPre))
                        kpiPill("flame.fill",
                                entry.soreness.map { String(format: "%.0f/10", $0) } ?? "—",
                                sorenessColor(entry.soreness))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        if let onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .font(.appCaption)
                                    .frame(width: 26, height: 26)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange.opacity(0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { confirmDelete = true } label: {
                            Image(systemName: "trash")
                                .font(.appCaption)
                                .frame(width: 26, height: 26)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.appMicro.weight(.medium))
                            .foregroundColor(.gray.opacity(0.45))
                            .frame(width: 26, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            // ── Expanded secondary section ────────────────────────────────
            if expanded {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let q = entry.sleepQuality {
                            secChip("star.fill", String(format: "%.0f/10", q), "qualité", .purple)
                        }
                        if let f = entry.fatigue {
                            secChip("bolt.slash.fill", String(format: "%.0f/10", f), "fatigue", .orange)
                        }
                        if let hr = entry.restingHr {
                            secChip("heart.fill", String(format: "%.0f bpm", hr), "FC repos", .red)
                        }
                        if let hrv = entry.hrv {
                            secChip("waveform.path.ecg", String(format: "%.0f ms", hrv), "HRV", .cyan)
                        }
                        if let s = entry.steps {
                            let sLabel = s >= 1_000 ? String(format: "%.1fk", Double(s) / 1_000) : "\(s)"
                            secChip("figure.walk", sLabel, "pas", .green)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 10)

                if let n = entry.notes, !n.isEmpty {
                    Text(n)
                        .font(.appCaption).foregroundColor(.gray.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
        }
        .background(Color.appCard).cornerRadius(12)
        .animation(.easeInOut(duration: 0.2), value: expanded)
        .confirmationDialog("Supprimer cette entrée ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func kpiPill(_ icon: String, _ value: String, _ color: Color) -> some View {
        let isNil = value == "—"
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.appMicro)
                .foregroundColor(isNil ? .gray.opacity(0.3) : color)
            Text(value)
                .font(.appCaption.weight(.medium))
                .foregroundColor(isNil ? .gray.opacity(0.35) : .white.opacity(0.9))
        }
    }

    private func secChip(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.appMicro).foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.appCaption.weight(.semibold)).foregroundColor(.white.opacity(0.9))
                Text(label).font(.system(size: 8)).foregroundColor(.gray.opacity(0.55))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    private func sorenessColor(_ v: Double?) -> Color {
        guard let v else { return .gray }
        return v >= 7 ? .red : (v >= 4 ? .orange : .green)
    }
    private func energyColor(_ v: Double?) -> Color {
        guard let v else { return .gray }
        return v >= 7 ? .green : (v >= 4 ? .orange : .red)
    }
    private func sleepColor(_ v: Double?) -> Color {
        guard let v else { return .gray }
        return v >= 7 ? .green : (v >= 6 ? .orange : .red)
    }
}
