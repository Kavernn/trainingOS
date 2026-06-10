import SwiftUI
import UserNotifications

struct NotificationCenterView: View {

    // MARK: - Global
    @AppStorage("notif_all_disabled") private var allDisabled = false

    // MARK: - Rituel
    @AppStorage("notif_on_ritual_morning") private var ritualMorning = true
    @AppStorage("ritual_morning_hour")     private var morningHour   = 7
    @AppStorage("notif_on_ritual_evening") private var ritualEvening = true
    @AppStorage("ritual_evening_hour")     private var eveningHour   = 20
    @AppStorage("ritual_evening_minute")   private var eveningMinute = 30
    @AppStorage("notif_on_ritual_streak")  private var ritualStreak  = true
    @AppStorage("notif_on_ritual_demon")   private var ritualDemon   = true

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
    @AppStorage("notif_on_graveyard") private var graveyard = true
    @AppStorage("notif_on_dna")       private var dna       = true
    @AppStorage("notif_on_proactive") private var proactive = true

    // MARK: - War Room
    @AppStorage("warRoomEnabled") private var warRoom = false

    // MARK: - Time pickers

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
            AmbientBackground(color: .purple)

            List {
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
    }

    // MARK: - Sections

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
                        NotificationService.scheduleWarRoomDailyCheckin(isEnabled: warRoom)
                    }
                }
            )) {
                notifLabel(
                    icon: allDisabled ? "bell.slash.fill" : "bell.fill",
                    color: allDisabled ? .gray : .purple,
                    title: allDisabled ? "Notifications coupées" : "Notifications actives",
                    subtitle: allDisabled ? "Appuie pour réactiver" : "Un tap pour tout couper"
                )
            }
            .tint(.purple)
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }

    private var seanceSection: some View {
        Section("Séance") {
            notifToggle(icon: "dumbbell.fill", color: .blue,
                        title: "Vendredi Full Body",
                        subtitle: "Rappel hebdomadaire — heure adaptée",
                        isOn: $seanceFriday,
                        ids: ["weekly.friday.fullbody"])
            notifToggle(icon: "figure.run", color: .teal,
                        title: "Inactivité",
                        subtitle: "Après 3+ jours sans séance",
                        isOn: $inactivity,
                        ids: ["inactivity.reminder"])
            notifToggle(icon: "flame.fill", color: .orange,
                        title: "Streak milestone",
                        subtitle: "7, 14, 30, 60, 100 jours consécutifs",
                        isOn: $streakMilestone,
                        ids: ["streak.milestone"])
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }

    private var rituelSection: some View {
        Section("Rituel Quotidien") {
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
                        subtitle: "Est-ce que tu l'as tué ?",
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
            notifToggle(icon: "exclamationmark.triangle.fill", color: .yellow,
                        title: "Streak à risque",
                        subtitle: "À 13h si le matin n'est pas fait",
                        isOn: $ritualStreak,
                        ids: ["ritual.streak.risk"])
            notifToggle(icon: "flame.fill", color: .red,
                        title: "Démon persistant",
                        subtitle: "Quand une intention traîne 3+ nuits",
                        isOn: $ritualDemon,
                        ids: ["ritual.demon.haunting"])
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }

    private var recoverySection: some View {
        Section("Récupération & Suivi") {
            notifToggle(icon: "waveform.path.ecg", color: .cyan,
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
            notifToggle(icon: "brain.head.profile", color: .purple,
                        title: "Test PSS hebdo",
                        subtitle: "Chaque lundi — mesure ton stress",
                        isOn: $pss,
                        ids: ["pss.weekly.test"])
            notifToggle(icon: "fork.knife", color: .orange,
                        title: "Nutrition",
                        subtitle: "Rappel de log — actif si tu logs régulièrement",
                        isOn: $nutrition,
                        ids: ["nutrition.daily.reminder"])
            notifToggle(icon: "chart.bar.fill", color: .blue,
                        title: "Recap hebdomadaire",
                        subtitle: "Chaque dimanche — résultats de la semaine",
                        isOn: $recap,
                        ids: ["weekly.recap.sunday"])
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }

    private var intelligenceSection: some View {
        Section("Intelligence") {
            notifToggle(icon: "clock.badge.fill", color: .yellow,
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
            notifToggle(icon: "cross.case.fill", color: Color(hex: "FF6600"),
                        title: "Graveyard",
                        subtitle: "Quand un exercice est archivé",
                        isOn: $graveyard,
                        ids: ["event.graveyard.tombstone"])
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
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }

    private var warRoomSection: some View {
        Section("War Room") {
            notifToggle(icon: "shield.fill", color: Color.forge,
                        title: "Check-in quotidien",
                        subtitle: "À 22h — victoire ou défaite",
                        isOn: $warRoom,
                        ids: ["war_room.daily.checkin"],
                        onToggle: { enabled in
                            NotificationService.scheduleWarRoomDailyCheckin(isEnabled: enabled)
                        })
        }
        .listRowBackground(Color.appCard)
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }

    // MARK: - Helpers

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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
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
