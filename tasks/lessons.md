# Lessons apprises

## Swift — Value semantics sur les dictionnaires imbriqués

**Pattern piégeux :**
```swift
fullProgram[key]?[newName] = fullProgram[key]?.removeValue(forKey: oldName)
```
`removeValue` opère sur une **copie** temporaire — l'ancienne clé n'est jamais supprimée de l'original.

**Correct :**
```swift
if let oldScheme = fullProgram[key]?[oldName] {
    fullProgram[key]?[newName] = oldScheme
    fullProgram[key]?.removeValue(forKey: oldName)
}
```

---

## Swift — JSONSerialization + cast de type

`JSONSerialization` retourne `[String: Any]`. Le cast direct `as? [String: [String: String]]` **échoue silencieusement**.

**Correct :**
```swift
fullProgram = raw.mapValues { $0.compactMapValues { $0 as? String } }
```
Et typer `@State` dès le départ en `[String: [String: String]]`, pas `[String: [String: Any]]`.

---

## Python — Fuzzy matching dans l'inventaire

Utiliser `exercise.lower() in k.lower()` pour chercher dans l'inventaire est dangereux : "Bench Press" match "Incline Bench Press".

**Toujours utiliser la clé exacte :**
```python
if exercise in inv:
    inv[exercise]["default_scheme"] = new_scheme
```

---

## Python — Sync programme ↔ inventaire (règles métier)

| Action | Programme | Inventaire |
|--------|-----------|------------|
| `add` | insert | créer si absent (ne pas écraser) |
| `remove` | supprimer | supprimer de l'inventaire **si plus dans aucune autre séance** |
| `scheme` | update | update `default_scheme` (clé exacte) |
| `replace` | swap | créer/update entrée new_ex |
| `rename` | rename partout | renommer clé exacte (`pop` + réinsert) |

---

## Architecture — Bridge process orphelin

Le `bridge.mjs` de VinceSeven doit tourner avec `npm run dev` (vite + miniverse + bridge ensemble). Lancé seul, il échoue en boucle sur `localhost:4321` (Miniverse non démarré).

---

## Performance — KV reads Supabase (Vercel 15s timeout)

Pour les endpoints analytiques (`/api/insights/correlations`), charger toutes les données en **4 KV reads** groupés, pas en N×4. Évite le timeout Vercel.

---

## Workflow — Ne jamais déclarer un bug "réglé" sans test réel

Les tests unitaires (pytest) passent ≠ le bug est corrigé en production.

**Règle :** Après un fix de comportement observable côté app (exercice manquant dans inventaire, etc.), toujours demander à l'utilisateur de **retester sur l'app** avant de conclure. Ne jamais écrire "reteste, ça devrait marcher" comme conclusion finale — attendre la confirmation.

---

## iOS — Timezone : utiliser `today` serveur, jamais recalculer côté device

`localToday` recalculait le jour de séance depuis le calendar local de l'iPhone. En PST à 23h = MTL lendemain → séance incorrecte + programme CRUD envoyé au mauvais `jour`.

**Règle :** Toujours utiliser `data.today` (fourni par le serveur en heure MTL). Supprimer tout recalcul de date côté iOS sauf pour la UI pure (ex: afficher "Aujourd'hui").

---

## iOS — Invalider le cache après chaque mutation

Toute mutation backend (`logExercise`, `logSession`, etc.) doit invalider les caches concernés **immédiatement** (y compris sur le path offline). Sinon, après force-quit + relance, l'app affiche l'état pré-mutation.

**Pattern :**
```swift
let data = try await offlinePost(endpoint: "/api/log", payload: body)
CacheService.shared.clear(for: "seance_data")
CacheService.shared.clear(for: "dashboard")
```

---

## Backend — DELETE ALL + reinsert = opération dangereuse sans guard

`save_full_program` fait DELETE ALL + reinsert sur `program_block_exercises`. Si `exercises = {}` est passé (block vide, reorder incomplet, ou race condition), **tous les exercices du programme sont silencieusement supprimés**.

**Règle :** Avant tout DELETE ALL suivi de reinsert, vérifier que la liste à réinsérer est ≥ à ce qui existe déjà en DB quand une réduction à 0 n'est pas intentionnelle.

```python
# Guard dans save_full_program
if not exercises:
    existing_count = _client.table("program_block_exercises")
        .select("id", count="exact").eq("block_id", block_id).execute().count or 0
    if existing_count > 0:
        logger.warning("refusing to save 0 exercises over %d existing", existing_count)
        continue
```

---

## Backend — Reorder action doit toujours appender les exercices manquants

Si iOS envoie un ordre partiel (`ordre = ["ex1", "ex2"]`) mais la DB en a 5, l'ancien code sauvegardait seulement 2 → 3 exercices définitivement perdus.

**Règle :** L'action `reorder` doit toujours appender les exercices absents de `ordre` :
```python
reordered = {ex: exercises[ex] for ex in ordre if ex in exercises}
for ex, scheme in exercises.items():
    if ex not in reordered:
        reordered[ex] = scheme  # jamais supprimer
exercises = reordered
```
**Côté iOS :** guard `order.count >= localProgram.count` avant d'envoyer le reorder.

---

## iOS — isLoading=true détruit les @State de WorkoutSeanceView

`isLoading = true` dans `SeanceViewModel.load()` fait disparaître `WorkoutSeanceView` de la hiérarchie → tous ses `@State` (dont `exerciseOrder`) sont réinitialisés à `[]` → ordre repart alphabétique.

**Règle :** Ne passer `isLoading = true` que si `seanceData == nil`. Si des données en cache existent déjà, rafraîchir silencieusement en arrière-plan sans spinner (évite la destruction de la vue et le reset des @State).

```swift
if seanceData == nil { isLoading = true }
```

---

## Tests — Régression sur les bugs de sync

Après chaque correction de bug CRUD programme/inventaire, ajouter un test de régression dans `tests/test_programme_inventory_sync.py`. Les bugs fuzzy-match et value-type Swift reviennent facilement.

---

## Swift — Condition composée `if let` avec bool indépendant

`if isLoggedToday, let session = todaySession` **échoue si `isLoggedToday=true` mais `session=nil`** — la condition tombe dans le `else` même si le bool est vrai.

**Règle :** Séparer les conditions booléennes des optional bindings quand ils sont indépendants :
```swift
if isLoggedToday {
    if let session = todaySession {
        // récap seulement si données disponibles
    }
    // CTA "bonus" affiché dans tous les cas de isLoggedToday
}
```
Le bug typique : `alreadyLoggedToday=true` (flag API) mais `sessions[todayDate]=nil` (désync cache) → "Commencer la séance" affiché après une séance déjà loggée.

---

## Swift — Division entière dans les labels de durée

`90 / 60 = 1` en Swift (division entière) → deux chips identiques "1min" pour 60s et 90s.

**Règle :** Toujours utiliser une fonction `formatDur` qui gère les secondes résiduelles :
```swift
private func formatDur(_ s: Int) -> String {
    s >= 60 ? "\(s / 60)min\(s % 60 > 0 ? "\(s % 60)s" : "")" : "\(s)s"
}
// 60 → "1min", 90 → "1min30s", 120 → "2min"
```
Ne jamais écrire `s < 60 ? "\(s)s" : "\(s / 60)min"` pour des durées potentiellement non multiples de 60.
