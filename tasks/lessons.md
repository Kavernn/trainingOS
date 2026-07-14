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

### Dette technique post-palier-2 (split de séance, 2026-06)

Le palier 1 du split a fixé le dashboard sans toucher à `load_sessions()` (cible déjà couverte par `get_today_sessions_all` pour durée/exos et `get_daily_session_volumes` pour volume). L'écrasement de `load_sessions` reste latent pour d'autres consommateurs.

**Règle : ne PAS agréger `load_sessions()` tant que les deux chemins d'écriture suivants n'ont pas été neutralisés** — `save_sessions()` écrit via `update_workout_session` qui filtre `session_type='morning'`, donc un load agrégé propagerait l'agrégat (sum duration, max rpe, union exos) dans la session matin seulement → pollution.

**Chemins d'écriture dangereux à neutraliser d'abord :**
- `api/sessions.py:log_second_session` (~L100, legacy probable — `extra_sessions[]` jamais persisté en Supabase)
- `api/routes/workout_logging.py` endpoint update rpe/comment (~L208-221, `load+modifier+save` redondant avec l'`update_workout_session_by_type` qui suit)

**Bénéficiaires d'un éventuel `load_sessions_aggregated` (option C) en lecture, à faire APRÈS neutralisation :**
- `api/health_data.py:212` (training_duration_min, exos)
- `api/deload.py:290-336` (vol_7j sous-estimé si split)
- `api/routes/data_views.py:172` (`/api/sessions` passthrough)
- `api/routes/data_views.py:178` (`/api/notes_data` avg_rpe)

À déclencher si Vince commence à splitter régulièrement post-palier-2 (sinon dette dormante acceptable).

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

## iOS — "Reprendre la dernière séance" : redimensionner les sets avant de remplir

Le bouton boucle sur `evm.sets.indices` qui est initialisé depuis le `scheme` programme (ex: `"4x8-12"` → 4 sets). Si l'utilisateur n'a jamais fait 4 sets, le 4e set apparaît vide à chaque "Reprendre".

**Règle :** Toujours redimensionner `evm.sets` au compte réel de `lastRepsParts` **avant** de remplir :
```swift
let parts = evm.lastRepsParts
let targetCount = max(1, parts.count)
if evm.sets.count < targetCount {
    evm.sets.append(contentsOf: Array(repeating: SetInput(), count: targetCount - evm.sets.count))
} else if evm.sets.count > targetCount {
    evm.sets = Array(evm.sets.prefix(targetCount))
}
for i in evm.sets.indices {
    evm.sets[i].reps = parts.indices.contains(i) ? parts[i] : (parts.first ?? "")
}
```

---

## iOS — `SeanceSoirViewModel` et `BonusSeanceViewModel` : override `finish()` doit appeler `logExercise()` par exercice

Ces deux classes overridaient `finish()` en appelant seulement `logSession()`, sans boucle sur `logResults`. Résultat : les exercices n'étaient pas enregistrés dans `exercise_logs` (aucun appel `/api/log`).

**Règle :** Tout override de `finish()` dans une sous-classe de `SeanceViewModel` doit copier exactement le pattern de la classe parente :
1. Boucle `for result in logResults.values` → `APIService.shared.logExercise(...)`
2. Puis `APIService.shared.logSession(..., exerciseLogs: exerciseLogs)`
3. Puis `fetchDashboard()`

Ne jamais shortcutter en appelant seulement `logSession()`.

---

## iOS 26 beta — `async let` parallèle → crash LIFO Swift Concurrency

Sur iOS 26 beta, tout groupe `async let` / `await (a, b)` crash avec SIGABRT "freed pointer was not the last allocation" dans `libswift_Concurrency.dylib`.

**Cause :** `asyncLet_finish_after_task_completion` fait un check LIFO sur la mémoire des child tasks. Quand les tasks se terminent dans un ordre non-déterministe (réseau rapide vs lent), le check échoue → fatal error. Régression beta du runtime Swift.

**Signature stack trace :**
```
swift::_swift_task_dealloc_specific(.cold.2)
asyncLet_finish_after_task_completion(...)
Thread: View.task @ SomeView.swift:<line>
```

**Red herring :** "Requesting visual style in an implementation that has disabled it" (UIKit/Liquid Glass) apparaît systématiquement avant le crash — sans rapport avec la cause.

**Fix :** Remplacer **tous** les `async let` par des `await` séquentiels :
```swift
// ❌ Crash iOS 26 beta
async let a = try? APIService.shared.fetchA()
async let b = try? APIService.shared.fetchB()
let (x, y) = await (a, b)

// ✅ Correct
let x = try? await APIService.shared.fetchA()
let y = try? await APIService.shared.fetchB()
```
**Règle :** Grep `async let` dans tous les `.swift` après chaque mise à jour iOS 26 beta. 19 fichiers affectés dans TrainingOS (2026-05-05). Parallelisme récupérable quand Apple corrige le runtime.

---

## Backend — Supabase "Server disconnected" : reconnexion httpx

Le client Supabase est créé une fois au démarrage du module. Les connexions httpx keep-alive s'épuisent après une période d'inactivité → `httpx.RemoteProtocolError: Server disconnected without sending a response`.

**Fix — pattern `_do()` + `_reconnect()` :**
```python
def _reconnect() -> bool:
    global _client
    try:
        from supabase import create_client
        _client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        return True
    except Exception:
        return False

def some_func(...):
    def _do():
        return _client.table(...).select(...).execute()
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            return _do()   # retry une fois
        raise
```
**Règle :** Toute fonction db.py qui appelle Supabase doit avoir cette enveloppe. Ne jamais réutiliser le résultat d'un appel échoué sans `_reconnect()` d'abord.

---

## iOS — `fetchWithCache` peut servir un format de réponse obsolète

`fetchWithCache` retourne le cache immédiatement si valide (TTL) et refresh en arrière-plan. Si le format JSON a changé côté API, le cache périmé cassera le décodeur à chaque lancement jusqu'à expiration du TTL.

**Fix :** Écrire les décodeurs Codable de façon défensive — essayer le nouveau format, fallback sur l'ancien :
```swift
// stagnants : API peut retourner [String] (nouveau) ou [{exercise: String, ...}] (ancien)
if let strings = try? c.decodeIfPresent([String].self, forKey: .stagnants) {
    stagnants = strings ?? []
} else {
    struct StagnantDict: Decodable { let exercise: String }
    stagnants = (try? c.decodeIfPresent([StagnantDict].self, forKey: .stagnants))?.map(\.exercise) ?? []
}
```
**Règle :** Quand un champ API change de type, toujours écrire un décodeur tolérant au lieu de faire un breaking change brutal — le cache peut avoir des données dans l'ancien format pendant plusieurs heures.

---

## DB — Les migrations KV→relational peuvent créer des doublons

Lors de la migration d'une table KV (clé/valeur) vers des tables relationnelles, si le script de migration est relancé sans guard `ON CONFLICT`, il insère des doublons.

**Règle :** Toujours utiliser `ON CONFLICT DO NOTHING` ou vérifier l'existence avant insert dans les scripts de migration. Auditer les comptes après migration.

**Contexte :** 14 doublons dans `cardio_logs` découverts lors de l'audit (tous avec `logged_at` identique à la milliseconde).

---

## iOS 26 — AlarmKit est un vrai framework Apple (ne pas remplacer)

`AlarmKit` est un framework Apple réel introduit avec iOS 26. `Services/SmartAlarmService.swift:4`
importe `AlarmKit` et utilise les symboles officiels : `AlarmManager.shared`,
`AlarmAttributes<SmartAlarmMetadata>`, `AlarmPresentation.Alert`, `AlarmConfiguration`,
`.fixed(alarmTime)`. La clé Info.plist `NSAlarmKitUsageDescription` est requise et présente
(`TrainingOS/Info.plist:5`).

**Règle :** Ne pas "corriger" `SmartAlarmService.swift` en le remplaçant par
`UNUserNotificationCenter` — l'API utilisée est correcte et intentionnelle. `UNUserNotificationCenter`
est utilisé séparément dans `NotificationService.swift` et `AlertService.swift` pour les
notifications standard. Les deux coexistent.

---

## iOS 26 beta — withTaskGroup aussi problématique dans certains contextes

`async let` crash (LIFO, déjà documenté). `withTaskGroup` a aussi des problèmes sur iOS 26 beta
dans certains contextes : `Services/HealthKitService.swift:467` et
`Services/WatchSyncService.swift:141` ont tous deux été revertés à des awaits séquentiels avec
le commentaire "sequential — withTaskGroup hangs on iOS 26 beta".

D'autres fichiers utilisent toujours `withTaskGroup` (`Services/APIService+Workout.swift:182`,
`Views/Dashboard/DashboardViewModel.swift:209`, etc.) — résultats mixtes selon le contexte.

**Règle :** Les `await` séquentiels sont le seul pattern universellement safe sur iOS 26 beta.
`withTaskGroup` peut fonctionner mais a causé des hangs dans HealthKit et Watch. Préférer le
séquentiel jusqu'à ce qu'Apple corrige le runtime.

---

## iOS — HealthKit poids : conversion unique à la frontière

HealthKit retourne la masse corporelle en kg (`.gramUnit(with: .kilo)`).
La conversion vers lbs est faite **une seule fois**, à `Services/HealthKitService.swift:297` :
`return kg * 2.20462`.

À partir de là, tout est en lbs jusqu'au stockage DB. Aucune double conversion.

**Règle :** Si un poids semble "bizarre" dans un flux HealthKit → API → DB, vérifier d'abord
que la valeur n'est pas déjà en lbs avant d'appliquer une conversion. La seule frontière légale
est `HealthKitService.fetchLatestBodyWeight()`. Toute autre conversion dans ce chemin est un bug.

---

## iOS — Fenêtre de vestiges UserDefaults 2026-07-13 (drafts d'exercice)

**Contexte** : entre le fix Volet C (`d4d0634` — scoping draft par date+session_type)
et le fix Volet E (`ff545d6` — suppression du pré-remplissage automatique à l'expand),
le canal `.onChange(of: isExpanded)` de `ExerciseCard.swift` (bloc supprimé au fix E)
pouvait écrire des drafts pour la clé `exo_draft_<today>_evening_<name>` sans que
Vince ait tapé quoi que ce soit — via `perSetHint` + `lastRepsParts` + debounce
saveDraft L248-252 d'`ExerciseViewModel`.

Ces drafts sont **auto-résolus** par `purgeOldExerciseDrafts`
(`Views/Seance/ExerciseViewModel.swift:75-92`) qui purge quand
`firstSegment < currentDate` (strict). À minuit MTL, la purge supprime les drafts
d'aujourd'hui → problème disparaît sans code additionnel.

**Contournement immédiat** si un vestige gêne une séance en cours :
- "Reprendre la dernière séance" (canal explicite) écrase le draft avec les vraies valeurs.
- OU saisie manuelle des valeurs correctes.

**Règle** : si un symptôme "sets pré-remplis sans geste" réapparaît **APRÈS le 2026-07-14**,
ce n'est PAS un vestige de cette fenêtre. Rouvrir l'enquête : un autre canal écrit encore.

---

## Tests — 37 fixtures pytest dormantes (`MagicMock is not JSON serializable`)

**État constaté 2026-07-13** : 37 tests d'intégration route échouent sur tree pristine
(vérifié par `git stash` + rerun), tous avec la même stack trace :
```
TypeError: Object of type MagicMock is not JSON serializable
```
Fichiers concernés : `tests/test_read_api_routes.py`, `tests/test_main_routes.py`,
`tests/test_programme_inventory_sync.py` (2 cas seulement).

Note d'écart : mesuré à 21 lors du commit 9b23f82 sur un périmètre restreint
(`TestProgrammeData` seul du fichier `test_read_api_routes.py`). Réévalué à 37
au commit suivant sur le fichier COMPLET. Baseline de référence = **37**.

**Cause probable :** le fixture `BaseRouteTest` (`tests/conftest.py:646`) mocke
certaines valeurs Supabase avec `MagicMock()` non-sérialisable, qui remontent jusqu'au
`jsonify()` de Flask via un chemin non-encapsulé (probablement une clé récemment
ajoutée au payload d'un endpoint que le fixture n'a jamais mockée explicitement).

**Impact :** les gardiens de `inventory_schemes`, `inventory_types`, `already_logged`,
plusieurs invariants dashboard/historique/session-edit sont **dormants**. Modifier ces
endpoints ne casse pas les tests parce qu'ils échouent déjà avant d'atteindre l'assertion.
Un changement qui régresse la génération de `inventory_schemes` passerait pytest sans
alerte.

**Règle en attendant réparation :** test manuel obligatoire (Vince builde + valide UI)
pour toute modification des payloads `/api/seance_data`, `/api/seance_soir_data`,
`/api/programme_data`, `/api/dashboard`, `/api/historique_data`, `/api/session/edit`.
La fixture MagicMock doit être remise en état dans un chantier dédié (hors périmètre
d'un fix bug applicatif) — audit `conftest.py:646` + mocking correct des retours Supabase
(dict sérialisable au lieu de `MagicMock()`).

**Commande pour compter :**
```bash
pytest tests/test_read_api_routes.py tests/test_main_routes.py \
       tests/test_programme_inventory_sync.py 2>&1 | grep -c "MagicMock is not JSON"
```
Baseline attendue = 21. Si le nombre BAISSE (fix incidental d'un fixture), célébrer.
Si BOOST (nouveau endpoint ajouté sans fixture correspondante), ajouter le mock au
`BaseRouteTest`.
