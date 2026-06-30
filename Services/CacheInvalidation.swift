import Foundation

// Single source of truth for cache invalidation rules.
// When a POST mutates data, call the matching case — never clear cache keys manually.
enum CacheInvalidation {

    // MARK: - Workout
    case exerciseLogged(isSecond: Bool, isBonus: Bool)
    case sessionLogged(isSecond: Bool, isBonus: Bool)
    case sessionMutated           // delete / update / edit
    case hiitLogged
    case programmeApproved
    case deloadApplied

    // MARK: - Wellness
    case recoveryLogged
    case pssSubmitted

    // MARK: - Mental
    case moodLogged
    case journalLogged
    case breathworkLogged
    case selfCareLogged
    case selfCareHabitsUpdated

    // MARK: - Profile
    case bodyWeightMutated
    case exerciseSaved
    case wearableSynced

    // MARK: - Ritual
    case ritualActioned           // morning / evening (today + streak)
    case ritualUpdated            // kill-demon / evening-full (today + streak + stats)
    case ritualItemActioned       // checklist item (today only)

    // MARK: - Sleep
    case sleepMutated

    // MARK: - Seasons
    case seasonMutated            // start / end (active + list)
    case seasonUpdated            // patch (list only)

    // MARK: - War Room
    case warRoomConfigUpdated
    case warRoomBattleLogged
    case warRoomTriggerLogged
    case warRoomArsenalMutated

    // MARK: - Spirit
    case spiritConfigUpdated
    case spiritBreathworkLogged
    case spiritMeditationLogged
    case spiritJournalLogged

    // MARK: - Other domains
    case timeCapsuleCreated       // capsules + snapshot
    case timeCapsuleOpened        // capsules only
    case oathUpdated
    case patternsPinMutated
    case plateauDismissed
    case nutritionLogged       // add / delete / edit (entries + dashboard + score)
    case cardioLogged
    case energyLogged
    case foodCatalogUpdated
    case dashboardInvalidated
    case profileUpdated        // name / age / height / goal / level / sex

    // MARK: - Keys

    // Brief contract: toute mutation qui modifie un signal lu par api/morning_brief.py
    // (LSS = HRV/sleep/RHR + PSS + RPE + nutrition, engagement_streak, profil, session du jour)
    // DOIT inclure "morning_brief" dans ses keys, sinon le verdict du brief reste stale.
    // Cases couvertes au 2026-06-30 : exerciseLogged, sessionLogged, sessionMutated,
    // programmeApproved, deloadApplied, recoveryLogged, wearableSynced, pssSubmitted,
    // moodLogged, ritualActioned, ritualUpdated, nutritionLogged, profileUpdated.
    // (hiitLogged: log isolé hors sessions → ne nourrit pas le brief, ne pas ajouter.)
    var keys: [String] {
        switch self {
        case .exerciseLogged(let isSecond, let isBonus):
            var k = ["dashboard", "stats_data", "streak_data", "morning_brief"]
            if !isBonus { k.append(isSecond ? "seance_soir_data" : "seance_data") }
            return k
        case .sessionLogged(let isSecond, let isBonus):
            var k = ["dashboard", "historique_data", "stats_data", "streak_data", "morning_brief"]
            if !isBonus { k.append(isSecond ? "seance_soir_data" : "seance_data") }
            return k
        case .sessionMutated:
            return ["historique_data", "dashboard", "morning_brief"]
        case .hiitLogged:
            return ["dashboard", "hiit_data"]
        case .programmeApproved:
            return ["programme_data", "stats_data", "morning_brief"]
        case .deloadApplied:
            return ["seance_data", "dashboard", "morning_brief"]
        case .recoveryLogged:
            return ["recovery_data", "hrv_analysis", "readiness", "morning_brief"]
        case .pssSubmitted:
            return ["pss_history", "pss_check_due_full", "morning_brief"]
        case .moodLogged:
            return ["mood_history", "mood_check_due", "dashboard", "morning_brief"]
        case .journalLogged:
            return ["journal_entries"]
        case .breathworkLogged:
            return ["breathwork_stats"]
        case .selfCareLogged:
            return ["self_care_today", "self_care_streaks"]
        case .selfCareHabitsUpdated:
            return ["self_care_habits", "self_care_today"]
        case .bodyWeightMutated:
            return ["profil_data"]
        case .exerciseSaved:
            return ["seance_data", "seance_soir_data"]
        case .wearableSynced:
            return ["recovery_data", "cardio_data", "hrv_analysis",
                    "sleep_history", "sleep_today", "sleep_stats", "readiness", "morning_brief"]
        case .ritualActioned:
            return ["ritual_today", "ritual_streak", "morning_brief"]
        case .ritualUpdated:
            return ["ritual_today", "ritual_streak", "ritual_stats", "morning_brief"]
        case .ritualItemActioned:
            return ["ritual_today"]
        case .sleepMutated:
            return ["sleep_history", "sleep_today", "sleep_stats"]
        case .seasonMutated:
            return ["season_active", "seasons_list"]
        case .seasonUpdated:
            return ["seasons_list"]
        case .warRoomConfigUpdated:
            return ["war_room_config"]
        case .warRoomBattleLogged:
            return ["war_room_summary", "war_room_battles", "war_room_today_status"]
        case .warRoomTriggerLogged:
            return ["war_room_triggers", "war_room_today_status"]
        case .warRoomArsenalMutated:
            return ["war_room_arsenal"]
        case .spiritConfigUpdated:
            return ["spirit_config"]
        case .spiritBreathworkLogged:
            return ["spirit_breathwork"]
        case .spiritMeditationLogged:
            return ["spirit_meditation"]
        case .spiritJournalLogged:
            return ["spirit_journal_list"]
        case .timeCapsuleCreated:
            return ["time_capsules", "capsule_snapshot"]
        case .timeCapsuleOpened:
            return ["time_capsules"]
        case .oathUpdated:
            return ["oath_current", "oath_versions"]
        case .patternsPinMutated:
            return ["patterns_daily"]
        case .plateauDismissed:
            return ["plateau_alerts"]
        case .nutritionLogged:
            return ["nutrition_data", "dashboard", "readiness", "morning_brief"]
        case .cardioLogged:
            return ["cardio_history", "stats_cardio"]
        case .energyLogged:
            return ["energy_daily_today", "energy_history_7"]
        case .foodCatalogUpdated:
            return ["food_catalog"]
        case .dashboardInvalidated:
            return ["dashboard"]
        case .profileUpdated:
            return ["profil_data", "dashboard", "readiness", "morning_brief"]
        }
    }

    var prefixesToClear: [String] {
        switch self {
        case .pssSubmitted:   return ["life_stress_trend"]
        case .nutritionLogged: return ["life_stress_trend"]
        default: return []
        }
    }

    func invalidate() {
        keys.forEach { CacheService.shared.clear(for: $0) }
        prefixesToClear.forEach { CacheService.shared.clear(prefix: $0) }
    }

    /// Deduplicates keys across N cases before clearing — use when calling invalidate() in a loop.
    static func invalidateBatch(_ cases: [CacheInvalidation]) {
        var uniqueKeys = Set<String>()
        var uniquePrefixes = Set<String>()
        for c in cases {
            c.keys.forEach { uniqueKeys.insert($0) }
            c.prefixesToClear.forEach { uniquePrefixes.insert($0) }
        }
        uniqueKeys.forEach { CacheService.shared.clear(for: $0) }
        uniquePrefixes.forEach { CacheService.shared.clear(prefix: $0) }
    }
}
