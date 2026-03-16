import SwiftUI

// MARK: - Data

private struct ChecklistItem {
    let id: String
    let label: String
    var subs: [ChecklistItem] = []
    var isGymBag: Bool { !subs.isEmpty }
}

private let kItems: [ChecklistItem] = [
    ChecklistItem(id: "telephone",    label: "Téléphone"),
    ChecklistItem(id: "portefeuille", label: "Portefeuille"),
    ChecklistItem(id: "cles",         label: "Clés"),
    ChecklistItem(id: "vape",         label: "Vape"),
    ChecklistItem(id: "montre",       label: "Montre"),
    ChecklistItem(id: "gym", label: "Sac de gym", subs: [
        ChecklistItem(id: "gym_bas",      label: "Bas"),
        ChecklistItem(id: "gym_chandail", label: "Chandail"),
        ChecklistItem(id: "gym_shorts",   label: "Shorts"),
        ChecklistItem(id: "gym_gourde",   label: "Gourde"),
        ChecklistItem(id: "gym_serv_d",   label: "Serviette douche"),
        ChecklistItem(id: "gym_serv_g",   label: "Serviette gym"),
        ChecklistItem(id: "gym_savon",    label: "Savon"),
        ChecklistItem(id: "gym_goug",     label: "Gougounes"),
    ]),
]

private let kAllIDs: [String] = kItems.flatMap { item in
    item.isGymBag ? item.subs.map(\.id) + [item.id] : [item.id]
}

// MARK: - Persistence

private enum ChecklistStore {
    static let statesKey     = "cl_states_v1"
    static let dateKey       = "cl_date_v1"
    static let hiddenDateKey = "cl_hidden_date_v1"
    static let gymExpandKey  = "cl_gym_expanded_v1"

    static var todayStr: String {
        ISO8601DateFormatter().string(from: Date()).prefix(10).description
    }

    static func load() -> [String: Bool] {
        let stored = UserDefaults.standard.string(forKey: dateKey) ?? ""
        if stored != todayStr {
            UserDefaults.standard.removeObject(forKey: statesKey)
            UserDefaults.standard.set(todayStr, forKey: dateKey)
        }
        return (UserDefaults.standard.dictionary(forKey: statesKey) as? [String: Bool]) ?? [:]
    }

    static func save(_ states: [String: Bool]) {
        UserDefaults.standard.set(states, forKey: statesKey)
    }

    static var isHiddenToday: Bool {
        UserDefaults.standard.string(forKey: hiddenDateKey) == todayStr
    }

    static func hideToday() {
        UserDefaults.standard.set(todayStr, forKey: hiddenDateKey)
    }

    static var gymExpanded: Bool {
        get { UserDefaults.standard.bool(forKey: gymExpandKey) }
        set { UserDefaults.standard.set(newValue, forKey: gymExpandKey) }
    }
}

// MARK: - Card View

struct ChecklistCardView: View {
    @State private var states: [String: Bool] = [:]
    @State private var gymExpanded = false
    @State private var isHidden = false
    @State private var showComplete = false

    var body: some View {
        if isHidden { EmptyView() } else {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("CHECK AVANT DE PARTIR")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider().background(Color.white.opacity(0.06))

                VStack(spacing: 0) {
                    ForEach(kItems, id: \.id) { item in
                        if item.isGymBag {
                            gymBagRow(item)
                        } else {
                            itemRow(id: item.id, label: item.label, isSub: false)
                        }
                    }
                }

                if showComplete {
                    Text("✅ Perfect. Good to go amigo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .glassCard()
            .cornerRadius(16)
            .onAppear {
                isHidden    = ChecklistStore.isHiddenToday
                states      = ChecklistStore.load()
                gymExpanded = ChecklistStore.gymExpanded
            }
        }
    }

    // MARK: – Rows

    private func itemRow(id: String, label: String, isSub: Bool) -> some View {
        let checked = states[id] == true
        return Button {
            toggle(id)
        } label: {
            HStack(spacing: 12) {
                if isSub { Spacer().frame(width: 16) }
                checkBox(checked: checked, small: isSub)
                Text(label)
                    .font(.system(size: isSub ? 14 : 15, weight: .medium))
                    .foregroundColor(checked ? .white.opacity(0.3) : .white.opacity(0.85))
                    .strikethrough(checked, color: .white.opacity(0.2))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isSub ? 9 : 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.05))
        }
    }

    private func gymBagRow(_ item: ChecklistItem) -> some View {
        let checked = states[item.id] == true
        return VStack(spacing: 0) {
            // Parent row
            HStack(spacing: 12) {
                Button { toggle(item.id) } label: {
                    checkBox(checked: checked, small: false)
                }
                .buttonStyle(.plain)

                Text(item.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(checked ? .white.opacity(0.3) : .white.opacity(0.85))
                    .strikethrough(checked, color: .white.opacity(0.2))
                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        gymExpanded.toggle()
                        ChecklistStore.gymExpanded = gymExpanded
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(gymExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.22), value: gymExpanded)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                Divider().background(Color.white.opacity(0.05))
            }

            // Sub-items (expandable)
            if gymExpanded {
                VStack(spacing: 0) {
                    ForEach(item.subs, id: \.id) { sub in
                        itemRow(id: sub.id, label: sub.label, isSub: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func checkBox(checked: Bool, small: Bool) -> some View {
        let size: CGFloat = small ? 18 : 22
        return ZStack {
            RoundedRectangle(cornerRadius: small ? 5 : 6)
                .fill(checked ? Color.orange : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: small ? 5 : 6)
                        .stroke(checked ? Color.orange : Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .frame(width: size, height: size)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: small ? 9 : 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: checked)
    }

    // MARK: – Logic

    private func toggle(_ id: String) {
        var s = states
        s[id] = !(s[id] ?? false)

        // If toggling a sub-item, auto-check/uncheck gym parent
        let gymSubs = kItems.first(where: \.isGymBag)?.subs.map(\.id) ?? []
        if gymSubs.contains(id) {
            s["gym"] = gymSubs.allSatisfy { s[$0] == true }
        }
        // If toggling gym parent, toggle all subs
        if id == "gym" {
            let newVal = s[id] ?? false
            for subID in gymSubs { s[subID] = newVal }
        }

        states = s
        ChecklistStore.save(s)
        checkCompletion(s)
    }

    private func checkCompletion(_ s: [String: Bool]) {
        let done = kAllIDs.allSatisfy { s[$0] == true }
        guard done else { return }
        withAnimation { showComplete = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.35)) { isHidden = true }
            ChecklistStore.hideToday()
        }
    }
}
