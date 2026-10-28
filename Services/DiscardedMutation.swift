import Foundation

/// Mutation rejetée au cours du rejeu de la file hors-ligne.
/// Alimente SyncManager.recentDiscards (bannière persistante).
struct DiscardedMutation: Codable, Identifiable, Equatable {
    enum Reason: String, Codable {
        case rejected   // 4xx du serveur après enqueue
        case zombie     // 5xx réessayé jusqu'à maxRetries → abandon
    }

    let id: UUID
    let endpoint: String
    let method: String
    let label: String           // libellé humain par domaine (ex. "Édition de séance — 2026-10-20")
    let serverMessage: String?  // extrait du JSON (error ou message), nil si body non parseable
    let statusCode: Int         // 0 pour zombie
    let retryCount: Int         // nombre de tentatives écoulées
    let reason: Reason
    let timestamp: Date

    init(id: UUID = UUID(), endpoint: String, method: String, label: String,
         serverMessage: String?, statusCode: Int, retryCount: Int,
         reason: Reason, timestamp: Date = Date()) {
        self.id = id
        self.endpoint = endpoint
        self.method = method
        self.label = label
        self.serverMessage = serverMessage
        self.statusCode = statusCode
        self.retryCount = retryCount
        self.reason = reason
        self.timestamp = timestamp
    }
}

enum SyncDiscardLabel {

    /// Mapping endpoint → libellé par domaine (préfixe). Les endpoints non
    /// reconnus retombent sur le chemin brut (ex. "/api/unknown_route").
    /// Si le payload contient une `date`, la concatène ("— YYYY-MM-DD").
    static func label(for endpoint: String, method: String, payload: [String: Any]?) -> String {
        let base = domainLabel(for: endpoint, method: method)
        if let date = payload?["date"] as? String, !date.isEmpty {
            return "\(base) — \(date)"
        }
        return base
    }

    private static func domainLabel(for endpoint: String, method: String) -> String {
        // Séance / exercice
        if endpoint == "/api/log"                        { return "Séance — log exercice" }
        if endpoint == "/api/log_session"                { return "Séance — fin de séance" }
        if endpoint == "/api/session/edit"               { return "Séance — édition" }
        if endpoint == "/api/session/delete"             { return "Séance — suppression" }
        if endpoint == "/api/update_session"             { return "Séance — mise à jour" }
        if endpoint == "/api/apply_progression"          { return "Séance — progression" }
        if endpoint == "/api/save_exercise"              { return "Séance — enregistrement exercice" }
        if endpoint == "/api/delete_exercise"            { return "Séance — suppression exercice" }
        if endpoint == "/api/exercises/classify"         { return "Séance — classification exercice" }
        // HIIT
        if endpoint == "/api/log_hiit"                   { return "HIIT — log" }
        if endpoint == "/api/hiit/edit"                  { return "HIIT — édition" }
        if endpoint == "/api/delete_hiit"                { return "HIIT — suppression" }
        // Cardio
        if endpoint == "/api/log_cardio"                 { return "Cardio — log" }
        if endpoint == "/api/delete_cardio"              { return "Cardio — suppression" }
        // Récupération
        if endpoint == "/api/log_recovery"               { return "Récupération — log" }
        if endpoint == "/api/delete_recovery"            { return "Récupération — suppression" }
        if endpoint == "/api/pss/submit"                 { return "Récupération — PSS" }
        if endpoint == "/api/smart_alarm/bedtime"        { return "Récupération — smart alarm" }
        // Mental
        if endpoint == "/api/mood/log"                   { return "Mental — humeur" }
        if endpoint == "/api/journal/save"               { return "Mental — journal" }
        if endpoint == "/api/breathwork/log"             { return "Mental — breathwork" }
        if endpoint == "/api/self_care/log"              { return "Mental — self-care" }
        if endpoint == "/api/self_care/habits"           { return "Mental — habitudes self-care" }
        // War Room (préfixe)
        if endpoint == "/api/war_room/config"            { return "War Room — config" }
        if endpoint == "/api/war_room/battle"            { return "War Room — battle" }
        if endpoint == "/api/war_room/trigger"           { return "War Room — trigger" }
        if endpoint.hasPrefix("/api/war_room/arsenal") {
            if endpoint.hasSuffix("/deploy")             { return "War Room — arsenal (déploiement)" }
            if method == "DELETE"                        { return "War Room — arsenal (suppression)" }
            return "War Room — arsenal"
        }
        // Oath / Ritual
        if endpoint == "/api/oath"                       { return "Oath — serment" }
        if endpoint == "/api/oath/recall"                { return "Oath — rappel" }
        if endpoint == "/api/ritual/engagements"         { return "Oath — engagements rituels" }
        // Profil / corps
        if endpoint == "/api/body_weight"                { return "Profil / corps — poids" }
        if endpoint == "/api/body_weight/update"         { return "Profil / corps — mise à jour poids" }
        if endpoint == "/api/body_weight/delete"         { return "Profil / corps — suppression poids" }
        if endpoint == "/api/update_profile"             { return "Profil / corps — profil" }
        if endpoint == "/api/wearable/sync"              { return "Profil / corps — sync wearable" }
        // Nutrition
        if endpoint == "/api/nutrition/add"              { return "Nutrition — ajout entrée" }
        if endpoint == "/api/nutrition/delete"           { return "Nutrition — suppression entrée" }
        if endpoint == "/api/nutrition/settings"         { return "Nutrition — réglages" }
        if endpoint == "/api/food_catalog"               { return "Nutrition — catalogue aliments" }
        if endpoint == "/api/meal_templates"             { return "Nutrition — nouveau repas-template" }
        if endpoint.hasPrefix("/api/meal_templates/") {
            if endpoint.hasSuffix("/update")             { return "Nutrition — repas-template (update)" }
            if endpoint.hasSuffix("/delete")             { return "Nutrition — repas-template (suppression)" }
            if endpoint.hasSuffix("/log")                { return "Nutrition — repas-template (log)" }
            return "Nutrition — repas-template"
        }
        // Saisons
        if endpoint == "/api/seasons/start"              { return "Saisons — démarrage" }
        // Fallback : chemin brut
        return endpoint
    }
}
