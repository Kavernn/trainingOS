import SwiftUI
import UserNotifications

struct NotificationCenterView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var authorizationStatus: UNAuthorizationStatus?

    // MARK: - Global
    @AppStorage("notif_all_disabled") private var allDisabled = false

    // MARK: - Rituel
    @AppStorage("notif_on_ritual_morning") private var ritualMorning = true
    @AppStorage("ritual_morning_hour")     private var morningHour   = 7
    @AppStorage("notif_on_ritual_evening") private var ritualEvening = true
    @AppStorage("ritual_evening_hour")     private var eveningHour   = 20
    @AppStorage("ritual_evening_minute")   private var eveningMinute = 30

    // MARK: - Séance
    @AppStorage("notif_on_seance_friday")    private var seanceFriday    = true
    @AppStorage("notif_on_inactivity")       private var inactivity      = true
    @AppStorage("notif_on_streak_milestone") private var streakMilestone = true

    // MARK: - Récupération & Suivi
    @AppStorage("notif_on_selfcare")    private var selfCare    = true
    @AppStorage("notif_on_pss")         private var pss         = true
    @AppStorage("notif_on_nutrition")   private var nutrition   = true
    @AppStorage("notif_on_recap")       private var recap       = true
    @AppStorage("notif_on_hrv_morning") private var hrvMorning  = true
    @AppStorage("hrv_morning_hour")     private var hrvHour     = 7
    @AppStorage("hrv_morning_minute")   private var hrvMinute   = 0

    // MARK: - Intelligence
    @AppStorage("notif_on_capsule")   private var capsule   = true
    @AppStorage("notif_on_phoenix")   private var phoenix   = true
@AppStorage("notif_on_dna")       private var dna       = true
    @AppStorage("notif_on_proactive") private var proactive = true

    // MARK: - War Room
    @AppStorage("warRoomEnabled") private var warRoomFunctionalEnabled = false
    @AppStorage("notif_on_war_room_checkin") private var warRoomCheckinEnabled = true

    // MARK: - Time pickers

    // Calendar.current VOLONTAIRE (pickers d'heure de notif) — les heures suivent
    // le device, pas MTL. L'utilisateur veut ses rappels à l'heure locale.
    // Ne pas migrer vers Calendar.mtl.
    private var morningDate: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: morningHour, minute: 0, second: 0, of: Date()) ?? Date() },
            set: {
                morningHour = Calendar.current.component(.hour, from: $0)
                NotificationService.scheduleAll()
            }
        )
    }

    private var eveningDate: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: eveningHour, minute: eveningMinute, second: 0, of: Date()) ?? Date() },
            set: {
                eveningHour   = Calendar.current.component(.hour,   from: $0)
                eveningMinute = Calendar.current.component(.minute, from: $0)
                NotificationService.scheduleAll()
            }
        )
    }

    private var hrvDate: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hrvHour, minute: hrvMinute, second: 0, of: Date()) ?? Date() },
            set: {
                hrvHour   = Calendar.current.component(.hour,   from: $0)
                hrvMinute = Calendar.current.component(.minute, from: $0)
                NotificationService.scheduleAll()
            }
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackground(color: .statusPurple)

            List {
                authorizationSection
                globalSection
                if !allDisabled {
                    seanceSection
                    rituelSection
                    recoverySection
                    intelligenceSection
                    warRoomSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { refreshAuthorizationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshAuthorizationStatus()
            }
        }
    }

    // MARK: - Sections

    private var authorizationSection: some View {
        Section("Autorisation système") {
            HStack(spacing: 12) {
                Image(systemName: authorizationDetails.icon)
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(authorizationDetails.color)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(authorizationDetails.title)
                        .font(.appBody.weight(.medium))
                        .foregroundColor(.appTextPrimary)
                    Text(authorizationDetails.message)
                        .font(.appCaption)
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Autorisation système")
            .accessibilityValue("\(authorizationDetails.title). \(authorizationDetails.message)")

            if authorizationStatus == .notDetermined {
                authorizationButton(
                    title: "Autoriser les notifications",
                    icon: "bell.badge.fill",
                    action: requestAuthorization
                )
            } else if authorizationStatus == .denied {
                authorizationButton(
                    title: "Ouvrir Réglages",
                    icon: "arrow.up.right.square",
                    action: openAppSettings
                )
            }
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    private var globalSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { !allDisabled },
                set: { enabled in
                    allDisabled = !enabled
                    if !enabled {
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    } else {
                        NotificationService.scheduleAll()
                        NotificationService.scheduleWarRoomDailyCheckin(
                            isEnabled: warRoomFunctionalEnabled && warRoomCheckinEnabled
                        )
                    }
                }
            )) {
                notifLabel(
                    icon: allDisabled ? "bell.slash.fill" : "bell.fill",
                    color: allDisabled ? .gray : .statusPurple,
                    title: allDisabled ? "Notifications coupées" : "Notifications actives",
                    subtitle: allDisabled ? "Appuie pour réactiver" : "Un tap pour tout couper"
                )
            }
            .tint(.statusPurple)
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    private var seanceSection: some View {
        Section("Séance") {
            notifToggle(icon: "dumbbell.fill", color: .statusBlue,
                        title: "Vendredi Full Body",
                        subtitle: "Rappel hebdomadaire — heure adaptée",
                        isOn: $seanceFriday,
                        ids: ["weekly.friday.fullbody"])
            notifToggle(icon: "figure.run", color: .teal,
                        title: "Inactivité",
                        subtitle: "Après 3+ jours sans séance",
                        isOn: $inactivity,
                        ids: ["inactivity.reminder"])
            notifToggle(icon: "flame.fill", color: .statusOrange,
                        title: "Streak milestone",
                        subtitle: "7, 14, 30, 60, 100 jours consécutifs",
                        isOn: $streakMilestone,
                        ids: ["streak.milestone"])
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    private var rituelSection: some View {
        Section("Engagements") {
            notifToggle(icon: "sunrise.fill", color: Color.appDanger,
                        title: "Rappel matin",
                        subtitle: "Déclare ta guerre",
                        isOn: $ritualMorning,
                        ids: ["ritual.morning.reminder"])
            if ritualMorning {
                HStack {
                    Spacer().frame(width: 42)
                    DatePicker("", selection: morningDate, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "fr_CA"))
                        .labelsHidden()
                }
            }
            notifToggle(icon: "moon.stars.fill", color: Color.appDanger.opacity(0.85),
                        title: "Rappel soir",
                        subtitle: "Crée tes engagements pour demain",
                        isOn: $ritualEvening,
                        ids: ["ritual.evening.reminder"])
            if ritualEvening {
                HStack {
                    Spacer().frame(width: 42)
                    DatePicker("", selection: eveningDate, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "fr_CA"))
                        .labelsHidden()
                }
            }
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    private var recoverySection: some View {
        Section("Récupération & Suivi") {
            notifToggle(icon: "waveform.path.ecg", color: .statusCyan,
                        title: "HRV du matin",
                        subtitle: "Rappel quotidien — reste allongé pour mesurer",
                        isOn: $hrvMorning,
                        ids: ["hrv.morning.reminder"])
            if hrvMorning {
                HStack {
                    Spacer().frame(width: 42)
                    DatePicker("", selection: hrvDate, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "fr_CA"))
                        .labelsHidden()
                }
            }
            notifToggle(icon: "moon.zzz.fill", color: .indigo,
                        title: "Self-care du soir",
                        subtitle: "Rappel quotidien — heure adaptée",
                        isOn: $selfCare,
                        ids: ["selfcare.daily.reminder"])
            notifToggle(icon: "brain.head.profile", color: .statusPurple,
                        title: "Test PSS hebdo",
                        subtitle: "Chaque lundi — mesure ton stress",
                        isOn: $pss,
                        ids: ["pss.weekly.test"])
            notifToggle(icon: "fork.knife", color: .statusOrange,
                        title: "Nutrition",
                        subtitle: "Rappel de log — actif si tu logs régulièrement",
                        isOn: $nutrition,
                        ids: ["nutrition.daily.reminder"])
            notifToggle(icon: "chart.bar.fill", color: .statusBlue,
                        title: "Recap hebdomadaire",
                        subtitle: "Chaque dimanche — résultats de la semaine",
                        isOn: $recap,
                        ids: ["weekly.recap.sunday"])
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    private var intelligenceSection: some View {
        Section("Intelligence") {
            notifToggle(icon: "clock.badge.fill", color: .statusYellow,
                        title: "Capsule temporelle",
                        subtitle: "7 jours avant l'ouverture",
                        isOn: $capsule,
                        ids: [],
                        onToggle: { enabled in
                            if !enabled { removeCapsuleNotifications() }
                            NotificationService.scheduleAll()
                        })
            notifToggle(icon: "bird.fill", color: Color(hex: "FF6B00"),
                        title: "Évolutions Phoenix",
                        subtitle: "Quand ton score change de catégorie",
                        isOn: $phoenix,
                        ids: ["event.phoenix.state"])
notifToggle(icon: "staroflife.fill", color: .indigo,
                        title: "ADN Workout",
                        subtitle: "Quand ton archétype change",
                        isOn: $dna,
                        ids: ["event.dna.archetype"])
            notifToggle(icon: "sparkle", color: .mint,
                        title: "Coach proactif",
                        subtitle: "Message contextuel à 19h30",
                        isOn: $proactive,
                        ids: ["proactive.daily"])
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    private var warRoomSection: some View {
        Section("War Room") {
            notifToggle(icon: "shield.fill", color: Color.forge,
                        title: "Check-in War Room",
                        subtitle: warRoomFunctionalEnabled
                            ? "À 22h — victoire ou défaite"
                            : "Disponible lorsque War Room est actif",
                        isOn: $warRoomCheckinEnabled,
                        ids: ["war_room.daily.checkin"],
                        onToggle: { enabled in
                            NotificationService.scheduleWarRoomDailyCheckin(
                                isEnabled: warRoomFunctionalEnabled && enabled
                            )
                        })
                .disabled(!warRoomFunctionalEnabled)
                .accessibilityHint(
                    warRoomFunctionalEnabled
                        ? "Active ou désactive le rappel quotidien War Room"
                        : "Disponible lorsque War Room est actif"
                )
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.appSeparator)
    }

    // MARK: - Helpers

    private var authorizationDetails: (title: String, message: String, icon: String, color: Color) {
        guard let authorizationStatus else {
            return (
                "Vérification…",
                "Lecture de l’autorisation iOS en cours.",
                "hourglass",
                .statusBlue
            )
        }

        switch authorizationStatus {
        case .notDetermined:
            return (
                "À autoriser",
                "Autorise les notifications pour que les rappels puissent fonctionner.",
                "bell.badge.fill",
                .statusBlue
            )
        case .denied:
            return (
                "Désactivé dans iOS",
                "Tes préférences sont enregistrées, mais iOS bloque actuellement leur livraison.",
                "bell.slash.fill",
                .statusRed
            )
        case .authorized:
            return (
                "Autorisé",
                "Les notifications peuvent être livrées par iOS.",
                "checkmark.circle.fill",
                .statusGreen
            )
        case .provisional:
            return (
                "Autorisation limitée",
                "iOS autorise provisoirement la livraison des notifications.",
                "bell.badge.fill",
                .statusYellow
            )
        case .ephemeral:
            return (
                "Autorisation temporaire",
                "iOS autorise temporairement la livraison des notifications.",
                "clock.fill",
                .statusYellow
            )
        @unknown default:
            return (
                "État système inconnu",
                "L’autorisation iOS n’a pas pu être identifiée.",
                "questionmark.circle.fill",
                .statusYellow
            )
        }
    }

    private func authorizationButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(Color.forge)
                Spacer()
                Image(systemName: icon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(Color.forge)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                authorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                NotificationService.scheduleAll()
            }
            refreshAuthorizationStatus()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private func notifToggle(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        ids: [String],
        onToggle: ((Bool) -> Void)? = nil
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                if let custom = onToggle {
                    custom(newValue)
                } else {
                    if !newValue && !ids.isEmpty {
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
                    }
                    NotificationService.scheduleAll()
                }
            }
        )) {
            notifLabel(icon: icon, color: color, title: title, subtitle: subtitle)
        }
        .tint(color)
    }

    @ViewBuilder
    private func notifLabel(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appBody.weight(.medium))
                    .foregroundColor(.appTextPrimary)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func removeCapsuleNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix("event.capsule.soon.") }
                .map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
