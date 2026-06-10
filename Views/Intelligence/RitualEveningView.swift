import SwiftUI

// Écran C — Création des engagements pour le lendemain
struct EngagementCreationView: View {
    let ritual: RitualToday
    let onSaved: (RitualToday) -> Void

    @State private var texts: [String] = ["", "", ""]
    @State private var isSaving    = false
    @State private var confirmed   = false
    @FocusState private var focusedIndex: Int?

    private let amber = Color.appWarning

    private var validTexts: [String] {
        texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var canConfirm: Bool { !validTexts.isEmpty && !isSaving }

    var body: some View {
        ZStack {
            Color(hex: "0D0906").ignoresSafeArea()

            if confirmed {
                confirmedView
                    .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: confirmed)
        .onTapGesture { focusedIndex = nil }
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock
                    .padding(.top, 40)
                    .padding(.horizontal, 24)

                fieldsBlock
                    .padding(.top, 28)
                    .padding(.horizontal, 24)

                addFieldButton
                    .padding(.top, 12)
                    .padding(.horizontal, 24)

                confirmBlock
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ce soir")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.28))
                .tracking(0.5)

            Text("Tes engagements pour demain")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Text(tomorrowDateLabel)
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.35))
        }
    }

    // MARK: - Fields

    private var fieldsBlock: some View {
        VStack(spacing: 10) {
            ForEach(texts.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(white: 0.22))
                        .frame(width: 16)

                    TextField("Engagement \(i + 1)\u{2026}", text: $texts[i])
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .tint(amber)
                        .focused($focusedIndex, equals: i)
                        .submitLabel(i < texts.count - 1 ? .next : .done)
                        .onSubmit {
                            if i < texts.count - 1 { focusedIndex = i + 1 }
                            else { focusedIndex = nil }
                        }

                    if texts.count > 1 {
                        Button(action: { removeField(at: i) }) {
                            Image(systemName: "xmark")
                                .font(.appCaption)
                                .foregroundColor(Color(white: 0.22))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(white: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            focusedIndex == i ? amber.opacity(0.4) : Color(white: 0.1),
                            lineWidth: 1
                        )
                )
                .cornerRadius(10)
                .animation(.easeInOut(duration: 0.15), value: focusedIndex == i)
            }
        }
    }

    // MARK: - Add / Remove

    @ViewBuilder
    private var addFieldButton: some View {
        if texts.count < 5 {
            Button(action: addField) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12))
                    Text("Ajouter un engagement").font(.appLabel)
                }
                .foregroundColor(Color(white: 0.38))
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private func addField() {
        guard texts.count < 5 else { return }
        texts.append("")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedIndex = texts.count - 1 }
    }

    private func removeField(at index: Int) {
        guard texts.count > 1 else { return }
        texts.remove(at: index)
    }

    // MARK: - Confirm

    private var confirmBlock: some View {
        VStack(spacing: 10) {
            Button(action: confirm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canConfirm ? amber : amber.opacity(0.25))
                        .frame(height: 52)
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Text("Confirmer pour demain")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(canConfirm ? .black : Color(white: 0.4))
                    }
                }
            }
            .disabled(!canConfirm)
            .buttonStyle(.plain)

            Text("Verrouillés jusqu'au \(tomorrowDateShort)")
                .font(.appCaption)
                .foregroundColor(Color(white: 0.2))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Confirmed state

    private var confirmedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(amber)
            Text(confirmedCountLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text("Verrouillés pour \(tomorrowDateShort)")
                .font(.appLabel)
                .foregroundColor(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var confirmedCountLabel: String {
        let n = validTexts.count
        return "\(n) engagement\(n > 1 ? "s" : "") créé\(n > 1 ? "s" : "")"
    }

    // MARK: - Helpers

    private var tomorrowDateLabel: String {
        let tmrw = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let fmt  = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "EEEE d MMMM"
        return fmt.string(from: tmrw).capitalized
    }

    private var tomorrowDateShort: String {
        let tmrw = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let fmt  = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "d MMMM"
        return fmt.string(from: tmrw)
    }

    private var tomorrowISODate: String {
        let tmrw = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let fmt  = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: tmrw)
    }

    private func confirm() {
        let valid = validTexts
        guard !valid.isEmpty, !isSaving else { return }
        isSaving     = true
        focusedIndex = nil
        Task {
            do {
                try await APIService.shared.createEngagements(date: tomorrowISODate, texts: valid)
                await MainActor.run {
                    withAnimation { confirmed = true }
                    isSaving = false
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                CacheService.shared.clear(for: "ritual_today")
                if let updated = try? await APIService.shared.fetchRitualToday() {
                    await MainActor.run { onSaved(updated) }
                }
            } catch {
                await MainActor.run { isSaving = false }
            }
        }
    }
}
