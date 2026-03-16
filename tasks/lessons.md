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

## Tests — Régression sur les bugs de sync

Après chaque correction de bug CRUD programme/inventaire, ajouter un test de régression dans `tests/test_programme_inventory_sync.py`. Les bugs fuzzy-match et value-type Swift reviennent facilement.
