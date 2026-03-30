import SwiftUI

// MARK: - Data (unchanged)

private struct ChecklistItem {
    let id: String
    let label: String
    var subs: [ChecklistItem] = []
    var isGymBag: Bool { !subs.isEmpty }
}

private let kItems: [ChecklistItem] = [
    ChecklistItem(id: "medocs",    label: "Médocs Vyvance"),
    ChecklistItem(id: "telephone",    label: "Téléphone"),
    ChecklistItem(id: "portefeuille", label: "Portefeuille"),
    ChecklistItem(id: "cles",         label: "Clés"),
    ChecklistItem(id: "vape",         label: "Vape/Liquide"),
    ChecklistItem(id: "montre",       label: "Montre"),
    ChecklistItem(id: "ecouteurs",    label: "Écouteurs"),
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

// MARK: - Persistence (unchanged + minimized key)

private enum ChecklistStore {
    static let statesKey      = "cl_states_v2"
    static let dateKey        = "cl_date_v2"
    static let hiddenDateKey  = "cl_hidden_date_v2"
    static let gymExpandKey   = "cl_gym_expanded_v2"
    static let minimizedKey   = "cl_minimized_v2"

    static var todayStr: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func load() -> [String: Bool] {
        let stored = UserDefaults.standard.string(forKey: dateKey) ?? ""
        if stored != todayStr {
            // New day: reset all state including hidden flag
            UserDefaults.standard.removeObject(forKey: statesKey)
            UserDefaults.standard.removeObject(forKey: hiddenDateKey)
            UserDefaults.standard.set(true, forKey: minimizedKey)
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

    static var isMinimized: Bool {
        get {
            // Default to true if key was never set
            if UserDefaults.standard.object(forKey: minimizedKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: minimizedKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: minimizedKey) }
    }
}

// MARK: - Card View

struct ChecklistCardView: View {
    @State private var states: [String: Bool] = [:]
    @State private var gymExpanded = false
    @State private var isHidden = false
    @State private var showComplete = false
    @State private var minimized = true

    var body: some View {
        if isHidden { EmptyView() } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !minimized {
                    Divider().background(Color.white.opacity(0.06))
                    itemList
                    if showComplete {
                        completionMessage
                    }
                }
            }
            .glassCard()
            .cornerRadius(16)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: minimized)
            .onAppear {
                states    = ChecklistStore.load()   // resets hidden flag si nouveau jour
                isHidden  = ChecklistStore.isHiddenToday
                gymExpanded = ChecklistStore.gymExpanded
                // Auto-expand if any items are already checked
                let anyChecked = kAllIDs.contains { states[$0] == true }
                minimized = anyChecked ? false : ChecklistStore.isMinimized
            }
        }
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AVANT DE PARTIR")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundColor(.orange)
                if minimized {
                    Text(progressSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .transition(.opacity)
                }
            }

            Spacer()

            // "I'm leaving" button — visible only when minimized
            if minimized {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        minimized = false
                        ChecklistStore.isMinimized = false
                    }
                } label: {
                    Text("Je pars")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.orange)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // Collapse/expand chevron
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    minimized.toggle()
                    ChecklistStore.isMinimized = minimized
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(minimized ? 0 : 180))
                    .animation(.easeInOut(duration: 0.25), value: minimized)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var progressSummary: String {
        let checked = kAllIDs.filter { states[$0] == true }.count
        let total   = kAllIDs.count
        if checked == 0 { return "\(total) items à vérifier" }
        return "\(checked) / \(total) cochés"
    }

    // MARK: – Item list

    private var itemList: some View {
        VStack(spacing: 0) {
            ForEach(kItems, id: \.id) { item in
                if item.isGymBag {
                    gymBagRow(item)
                } else {
                    itemRow(id: item.id, label: item.label, isSub: false)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var completionMessage: some View {
        Text("✅ Perfect. Good to go amigo")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: – Rows (unchanged)

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

    // MARK: – Logic (unchanged)

    private func toggle(_ id: String) {
        var s = states
        s[id] = !(s[id] ?? false)

        let gymSubs = kItems.first(where: \.isGymBag)?.subs.map(\.id) ?? []
        if gymSubs.contains(id) {
            s["gym"] = gymSubs.allSatisfy { s[$0] == true }
        }
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
