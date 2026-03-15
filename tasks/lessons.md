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
| `remove` | supprimer | **NE PAS toucher** |
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

## Tests — Régression sur les bugs de sync

Après chaque correction de bug CRUD programme/inventaire, ajouter un test de régression dans `tests/test_programme_inventory_sync.py`. Les bugs fuzzy-match et value-type Swift reviennent facilement.
