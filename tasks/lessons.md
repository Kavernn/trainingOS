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

## iOS — Ordre d'appel dans `onAppear` : reset avant lecture de flags

**Bug :** `ChecklistCardView` invisible chaque matin malgré un nouveau jour.

**Cause :** `isHiddenToday` était lu **avant** `load()`. `load()` efface `cl_hidden_date_v2` pour un nouveau jour — mais si l'app est gardée en mémoire à cheval sur minuit, `cl_date_v2` peut déjà valoir aujourd'hui et `cl_hidden_date_v2` aussi → `isHiddenToday = true` même si rien n'a été coché aujourd'hui.

**Règle :** Toujours appeler la **mutation de reset** (`load()`, etc.) **avant** de lire les flags dérivés dans `onAppear`.

```swift
// ❌ Mauvais
isHidden = ChecklistStore.isHiddenToday
states   = ChecklistStore.load()  // efface hiddenDate, mais trop tard

// ✅ Correct
states   = ChecklistStore.load()  // efface hiddenDate pour nouveau jour d'abord
isHidden = ChecklistStore.isHiddenToday
```

**Généralisation :** Tout `UserDefaults` flag lu dans `onAppear` qui dépend d'un reset de date → toujours reset avant lecture.

---

## Python — int(rpe) tronque les valeurs décimales RPE

`int(7.5) = 7` — la précision est silencieusement perdue.

**Règle :** Dans `db.create_workout_session` (et toute fonction qui stocke RPE), toujours utiliser `round(float(rpe), 1)` :
```python
# ❌ Mauvais
payload["rpe"] = int(rpe)

# ✅ Correct
payload["rpe"] = round(float(rpe), 1)
```

---

## iOS — Xcode : les nouveaux fichiers Swift doivent être ajoutés manuellement au pbxproj

Créer un fichier `.swift` avec Write ne l'ajoute **pas** automatiquement au target Xcode. L'erreur "Cannot find 'TypeName' in scope" dans un autre fichier est le symptôme classique.

**Règle :** Après chaque nouveau fichier Swift, ajouter manuellement les 4 entrées dans `project.pbxproj` :
1. `PBXBuildFile` (avec fileRef UUID)
2. `PBXFileReference` (avec path et sourceTree)
3. Children du group parent (par dossier)
4. `PBXSourcesBuildPhase files`

---

## iOS — ObservableObject / @Published requiert import Combine

`@Published` est défini dans `Combine`. Sans `import Combine`, Swift ne peut pas synthétiser la conformité à `ObservableObject` même si `Foundation` est importé.

**Règle :** Tout `class` qui utilise `@Published` doit avoir `import Combine` :
```swift
import Foundation
import Combine  // ← obligatoire

final class MyService: ObservableObject {
    @Published var items: [Item] = []
}
```

---

## Backend — session_type insuffisant pour comparer des séances du même type

`session_type = "morning"` ne suffit pas : Push A et Pull B sont tous deux `morning`. Comparer Push A vs Pull B = 0 suggestions pertinentes.

**Règle :** Pour le coaching de progression, toujours matcher par `session_name` (ex: "Push A") stocké dans `workout_sessions.session_name`. Fallback vers `session_type` uniquement pour les anciennes sessions qui n'ont pas de `session_name`.

```python
if session_name:
    prev_session = db.get_previous_session_by_name(session_date, session_name)
else:
    prev_session = db.get_previous_session_of_type(session_date, session_type)
```

**Côté iOS :** passer `data.today` (ex: "Push A") comme `sessionName` dans `logSession()` et `fetchProgressionSuggestions()`.

---

## Python — Bug de parité de plateau (parity off-by-one)

`plateau % 2 == 0 → increase_sets` était **inversé** : plateau=3 (impair) déclenchait deload au lieu de add_set.

**Cause :** La logique de cycle doit commencer par add_set à la session 3, donc compter *depuis 3*, pas depuis 0.

**Correct :**
```python
cycle_pos = (plateau - 3) % 4
if cycle_pos < 2 and can_add_set:  # sessions 3-4 → add set
    ...
else:                               # sessions 5-6 → deload
    ...
```

**Règle générale :** Pour tout cycle qui commence à N≠0, utiliser `(count - N) % cycle_length` plutôt que `count % 2`.

---

## Backend — PostgREST rejette silencieusement un UPDATE si une colonne est absente du schéma

Si on inclut une colonne qui n'existe pas encore en DB dans un `.update({...})` via PostgREST/Supabase, **l'UPDATE entier échoue sans erreur visible** (pas d'exception levée).

**Règle :** Avant de passer un patch avec de nouvelles colonnes, s'assurer que la migration SQL est appliquée. Ne jamais ajouter une colonne au code Python avant d'avoir la colonne en DB.

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

---

## Python — `dict.get(key, default)` ne protège pas contre les valeurs null explicites

`info.get("type", "machine")` retourne **`None`** si la clé existe avec la valeur `None` en DB. Le default n'est utilisé que si la clé est **absente**.

**Règle :** Pour les champs qui peuvent être `None` en DB, toujours utiliser `or` :
```python
# ❌ Mauvais — retourne None si type=NULL en DB
info.get("type", "machine")

# ✅ Correct — retourne "machine" si type est None ou absent
info.get("type") or "machine"
```
**Contexte :** Causait un crash silencieux dans Swift `[String: String]` quand `inventory_types` contenait des nulls.

---

## PostgreSQL — `smallint` rejette les floats Python

`round(float(5), 1)` = `5.0` (float Python) est rejeté par une colonne PostgreSQL `smallint`. Supabase / PostgREST retourne une erreur 400 qui peut être silencieusement catchée.

**Règle :** Pour toute colonne `smallint` (RPE, rating, etc.), toujours caster en `int` :
```python
# ❌ Mauvais
payload["rpe"] = round(float(rpe), 1)  # → 5.0, rejeté par smallint

# ✅ Correct
payload["rpe"] = int(round(float(rpe)))  # → 5, accepté
```
**Contexte :** Causait l'échec silencieux de **toutes** les créations de séances (exception catchée, `{}` retourné).

---

## iOS — `@AppStorage` ne doit pas être source de vérité pour l'état serveur

`@AppStorage` persiste localement. Si le serveur n'a pas reçu la mutation (erreur réseau, bug silencieux), l'état local et l'état serveur divergent.

**Règle :** Pour les flags qui reflètent un état serveur (ex: `alreadyLoggedToday`), toujours cross-checker avec la réponse API :
```swift
// ❌ Mauvais — si create_workout_session a échoué silencieusement
private var alreadyLoggedToday: Bool {
    loggedDate == DateFormatter.isoDate.string(from: Date())
}

// ✅ Correct — serveur est source de vérité
private var alreadyLoggedToday: Bool {
    let localSaysLogged = loggedDate == DateFormatter.isoDate.string(from: Date())
    let serverSaysLogged = vm.seanceData?.alreadyLogged ?? false
    return localSaysLogged && serverSaysLogged
}
```

---

## Backend — Vercel tourne en UTC, pas en heure locale

`datetime.date.today()` sur Vercel retourne la date UTC. Si l'utilisateur est à Montréal (UTC-4/UTC-5), la "date du jour" côté serveur peut différer de celle du device après 20h-21h.

**Règle :** Pour toute logique de "aujourd'hui" côté serveur, utiliser `ZoneInfo("America/Montreal")` :
```python
from zoneinfo import ZoneInfo
from datetime import datetime
today = datetime.now(ZoneInfo("America/Montreal")).date().isoformat()
```
Ne jamais utiliser `datetime.date.today()` pour des comparaisons de date liées au comportement utilisateur.

---

## Backend — CHECK constraint violation cause un upsert silencieux (données non sauvegardées)

La table `recovery_logs` a `soreness SMALLINT CHECK (soreness BETWEEN 1 AND 10)`. Le slider iOS va de 0 à 10. Quand `soreness=0` était envoyé, PostgreSQL rejetait l'upsert entier — **toutes** les colonnes, y compris `steps`, n'étaient pas sauvegardées. Le serveur Python catchait l'exception et retournait `{"ok": true}` quand même.

**Règle :** Pour tout champ avec CHECK constraint qui peut être 0 (falsy), convertir 0 → NULL côté serveur :
```python
"soreness": data.get("soreness") or None,  # 0 → NULL (contrainte 1-10)
```
Et toujours propager les erreurs d'upsert au client (HTTP 500 si False) plutôt que de masquer l'échec avec `{"ok": true}`.

---

## iOS — Champ texte vide doit envoyer nil, pas une valeur par défaut

`Int(stepsStr) ?? Int(Double(stepsStr) ?? 0)` — quand `stepsStr=""`, retourne `0`, pas `nil`. Comme `steps: Int?`, `0` est non-nil → `body["steps"] = 0` envoyé → écrase les pas existants en DB.

**Règle :** Pour tout champ optionnel qui ne doit pas écraser les données existantes :
```swift
steps: stepsStr.isEmpty ? nil : (Int(stepsStr) ?? Int(Double(stepsStr) ?? 0))
```
Nil n'est pas ajouté au body (`if let v = steps { body["steps"] = v }`), donc les données existantes en DB sont préservées.

---

## Backend — Session bonus ≠ second workout : fusionner dans l'historique

Une session `session_type="bonus"` est généralement un complement (RPE ajouté après coup), pas un deuxième workout distinct. Afficher morning + bonus séparément crée une double entrée déroutante pour l'utilisateur.

**Règle :** Dans `api_historique_data`, fusionner les sessions bonus dans la morning du même jour :
- RPE/comment bonus → morning si morning n'en a pas
- Exercices bonus → morning si morning est vide
- Supprimer la clé bonus de `best_by_key`

Si aucune session morning n'existe pour ce jour, conserver le bonus tel quel.

---

## iOS — Session loggée offline → dashboard stale sans refresh SyncManager

Quand `offlinePost()` retourne `nil` (mutation en queue), `CacheService.clear("dashboard")` n'est **pas** appelé (guard `if data != nil`). Résultat : `fetchDashboard()` sert le cache périmé qui ne reflète pas la séance. Quand le réseau revient, `SyncManager.flushQueue()` envoie les mutations mais **ne rafraîchit jamais le dashboard**.

**Double fix requis :**
1. Flag optimiste `@Published var sessionLoggedToday = false` dans `APIService` — mis à `true` dès `logSession()` (online ou offline). Vues qui montrent l'état de la séance peuvent l'observer immédiatement.
2. `SyncManager.flushQueue()` clear cache dashboard + appelle `fetchDashboard()` dès qu'une mutation `/api/log` ou `/api/log_session` a été rejouée avec succès.

```swift
// APIService.logSession()
await MainActor.run { sessionLoggedToday = true }  // avant l'await offlinePost

// SyncManager.flushQueue()
if syncedSessionMutation {
    CacheService.shared.clear(for: "dashboard")
    await APIService.shared.fetchDashboard()
}
```

**Règle :** Toute action "je viens de faire X" qui doit se refléter instantanément dans l'UI doit avoir un flag optimiste local, pas seulement un cache invalidé.

---

## iOS — Picker caméra vs bibliothèque : ouvrir la caméra directement

Pour un flux scan (étiquette, document, repas), l'utilisateur veut toujours la caméra. Ne pas afficher de `confirmationDialog` "Caméra / Bibliothèque" — lier le bouton directement à `showCameraPicker = true`.

```swift
// ❌ Mauvais — dialog inutile
Button { showSourceChoice = true }
.confirmationDialog("Source", isPresented: $showSourceChoice) {
    Button("Caméra")      { showCameraPicker  = true }
    Button("Bibliothèque") { showLibraryPicker = true }
}

// ✅ Correct — caméra directe
Button { showCameraPicker = true }
.sheet(isPresented: $showCameraPicker) {
    ImagePickerView(image: $pickedImage, sourceType: .camera)
}
```

---

## iOS — `try?` sur logSession swallows all server errors → fake success

`try? await APIService.shared.logSession(...)` swallowe silencieusement **tous** les échecs (erreur réseau, 409, 500). Le succès est affiché même si la séance n'a pas été sauvegardée.

**Règle :** Pour toute action de log critique, toujours utiliser `try/catch` + vérifier que `fresh.alreadyLogged == true` avant d'afficher la confirmation :

```swift
// ❌ Mauvais — faux succès garanti
try? await APIService.shared.logSession(...)
vm.showSuccess = true

// ✅ Correct — vérification côté serveur
do {
    try await APIService.shared.logSession(...)
} catch {
    vm.submitError = "Erreur : \(error.localizedDescription)"
    return
}
let fresh = try? await APIService.shared.fetchSeanceData()
if fresh?.alreadyLogged == true {
    vm.showSuccess = true
} else {
    vm.submitError = "Séance non confirmée — vérifie ta connexion."
}
```

Copier le pattern de `SeanceViewModel.finish()` qui fait déjà cette vérification.

---

## Backend — `load_sessions()` dict keyed by date perd les sessions quand plusieurs rows existent pour le même jour

`load_sessions()` → `get_workout_sessions()` retourne toutes les sessions (morning + evening + bonus). Pour la même date, le dernier row traité écrase les précédents. Si evening (completed=False) est retourné après morning yoga (completed=True), `already_logged` devient False.

**Règle :** Pour vérifier `already_logged` d'une session morning, toujours utiliser `_db.get_workout_session(today_date)` (requête directe avec `session_type='morning'`) — jamais `load_sessions().get(date)`.

```python
# ❌ Mauvais — peut retourner la mauvaise session si plusieurs rows
_s = sessions.get(today_date, {})

# ✅ Correct — cible explicitement la session morning
_s = _db.get_workout_session(today_date) or {}
already_logged = bool(_s.get("completed") or _s.get("rpe") is not None)
```

---

## iOS — `Calendar.date(byAdding:)` cause un crash 0x8BADF00D sur iOS 26

Sur iOS 26, `Calendar.current.date(byAdding: .day, value: -i, to: date)` et `Calendar.current.startOfDay(for:)` routent via `_CalendarGregorian.dateComponents` qui recurse infiniment → watchdog tue le process (0x8BADF00D).

**Règle :** Ne jamais utiliser `Calendar.date(byAdding:)` pour de l'arithmétique de dates quotidienne. Utiliser l'arithmétique timestamp pure :
```swift
// ❌ Mauvais — crash 0x8BADF00D sur iOS 26
let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

// ✅ Correct — arithmétique pure, pas de Calendar
let todayStr = DateFormatter.isoDate.string(from: Date())
let todayMidnight = DateFormatter.isoDate.date(from: todayStr)!  // parse propre
let yesterday = Date(timeIntervalSince1970: todayMidnight.timeIntervalSince1970 - 86400)
```
**Contexte :** Calcul du streak dans `GreetingHeaderView` — passage en timestamp pure pour éviter le crash.

---

## DB — Les migrations KV→relational peuvent créer des doublons

Lors de la migration d'une table KV (clé/valeur) vers des tables relationnelles, si le script de migration est relancé sans guard `ON CONFLICT`, il insère des doublons.

**Règle :** Toujours utiliser `ON CONFLICT DO NOTHING` ou vérifier l'existence avant insert dans les scripts de migration. Auditer les comptes après migration.

**Contexte :** 14 doublons dans `cardio_logs` découverts lors de l'audit (tous avec `logged_at` identique à la milliseconde).
