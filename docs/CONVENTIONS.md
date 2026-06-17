# TrainingOS — Conventions de développement

> Règles non-triviales qui ne se déduisent pas à la lecture du code.
> Chaque règle est ancrée dans le code réel (fichier:ligne).
> Mise à jour : 2026-06-16.

---

## 1. Sources de vérité uniques

### 1.1 Streak d'entraînement

**Source :** `api/routes/analytics_stats.py:87-168` — `GET /api/stats/streaks`

Docstring ligne 90 : "Source de vérité unique pour le streak". iOS consomme le résultat via
`StreakResponse` (`Views/Dashboard/DashboardViewModel.swift:24, 139, 315, 356`) — aucun calcul
local côté Swift.

Comptage : une session compte si `completed=true` OR `rpe is not None` ; today est inclus si des
`exercise_logs` existent pour ce jour. Sources agrégées : `get_workout_sessions(limit=730)` +
`load_hiit_log()` + `get_cardio_logs(limit=730)` + `get_session_exercise_logs(today_str)`.

Streak at risk : `streak_at_risk = True` après 18h MTL si rien n'est loggé aujourd'hui (ligne 159).

---

### 1.2 Readiness

**Source :** `api/readiness.py:741` — `def compute()` appelé par `GET /api/readiness`
(`api/routes/readiness.py:8-9`).

Cache 30 min (`readiness.py:735-736`). Inputs : `recovery_logs` (HRV, RHR, durée/qualité sommeil,
active_energy). 9 modules pondérés : hrv, rhr, acwr, sleep_quality, sleep_duration, subjective,
muscle_rec, nutrition, pattern.

**Violation connue — fallback silencieux :** `readiness.py:834-843` — sur exception, retourne
`{"score": 65, "verdict": "moderate"}` (HTTP 200) au lieu de propager l'erreur. Masque les
pannes DB en données fictives. Ne pas supprimer sans remplacer par un HTTP 500.

---

### 1.3 Date du jour — MTL obligatoire

**Source API :** `api/utils.py:33-38` — `_today_mtl()` et `_today_mtl_date()`, basées sur
`_now_mtl()` (`utils.py:8-31`, `ZoneInfo("America/Montreal")` ligne 12).

Importées dans ~70 fichiers Python. Ne jamais utiliser `datetime.date.today()` côté serveur (UTC).

**Écart connu :** `api/planner.py:78-83` réimplémente `_now_mtl` au lieu d'importer depuis `utils`.

**Côté iOS :** `Utilities/Extensions.swift:155, 242` — seuls sites avec `TimeZone(identifier:
"America/Montreal")` explicite. La plupart des vues utilisent `TimeZone.current` / `Calendar.current`.
Règle absolue : toujours consommer `data.today` fourni par le serveur pour toute décision de date
liée au workout. Ne jamais recalculer la date du jour côté iOS (cf. lesson iOS timezone).

---

### 1.4 Sommeil

**Source :** Table `recovery_logs` (colonnes `sleep_duration`, `sleep_quality`, `hrv`, `rhr`).

La table `sleep_records` est **dépréciée**. `api/sleep.py:121` : "Source de vérité :
recovery_logs — sleep_records est archivée."

Endpoints sleep (`/api/sleep-quality`, `/api/sleep-debt`, `/api/sleep-hrv`) lisent tous depuis
`recovery_logs` via engines (`routes/sleep_quality.py:7-9`, `routes/sleep_debt.py:10-16`).

---

### 1.5 Nutrition

**Sources :** `nutrition_entries` (repas individuels) et `nutrition_daily` (agrégats journaliers).
Endpoints dans `routes/nutrition_entries.py`, `routes/nutrition_food.py`,
`routes/nutrition_analytics.py`. Cache iOS 30 min (`Services/CacheService.swift:49-50`),
pas de calcul local.

---

### 1.6 Manuel > HealthKit

Une valeur saisie manuellement n'est jamais écrasée par une valeur HealthKit.

**Deux sites d'application :**
- `api/db_body.py:299-310` — upsert depuis wearable : si `existing["source"] == "manual"`, les
  champs manuels sont conservés.
- `api/routes/wellness_recovery.py:119-126` — `_hk(field)` : si `is_manual` et valeur existante
  non-null, retourner la valeur manuelle.

**Marquage :** `api/sleep.py:122, 130` — log sommeil manuel → `source="manual"`. Colonne `source`
sur `recovery_logs` avec `DEFAULT 'manual'` (`docs/schema.sql:322, 356`).

---

## 2. Unités — lbs canonique

Le stockage est toujours en **livres (lbs)**, jamais en kg.

**Preuves :**
- `Services/UnitSettings.swift:17-19` — "Storage is always lbs internally. display() converts from
  lbs → display unit. toStorage() converts from user input → lbs for storage."
- `api/db_body.py:10` — "weight field is in lbs (not kg)."
- `api/db_stats.py:289-290` — "weight is always stored in lbs — the iOS app hardcodes the input
  label as 'POIDS (LBS)' and converts HealthKit kg values via / 0.453592 before sending."
- `api/plateau.py:3` — "All weights are in lbs."
- `api/README.md:278` — "Weights: stored in **lbs** (not kg)"

**Colonnes PR :** `pr_weight_lbs` et `pr_e1rm_lbs` dans `exercise_prs`
(`docs/migrations/071_exercise_prs.sql:2` : "en lbs (convention interne du projet)").
Ces colonnes ont toujours été en lbs — pas de migration depuis pr_kg.

**Frontière HealthKit :** HealthKit retourne la masse en kg (`.gramUnit(with: .kilo)`).
Conversion unique à `Services/HealthKitService.swift:297` : `kg * 2.20462` → lbs.
Aucune double conversion.

**Conversion display :** `UnitSettings.swift:20-21` —
`display(_ lbs: Double) -> Double { isKg ? lbs * 0.453592 : lbs }` /
`toStorage(_ value: Double) -> Double { isKg ? value / 0.453592 : value }`.

---

## 3. e1RM — formule canonique

**Source :** `api/progression.py:362-381` — `def estimate_1rm(weight, reps_str)`.

| Plage reps | Formule |
|---|---|
| ≤ 10 | Epley : `weight × (1 + reps/30)` |
| 11 – 15 | Brzycki : `weight × (36 / (37 - reps))` |
| > 15 | `None` — trop imprécis, non estimé |

**Important :** le cap est à **15 reps** (>15 → None). Le commentaire dans `api/weights.py:23`
dit ">20 reps" — il est faux. Se fier uniquement à `progression.py:374-375`.

**Best set :** L'e1RM retenu est le MAX sur tous les sets de la session
(`api/pr_tracker_engine.py:59`, `api/progressive_overload_engine.py:60`,
`api/db_sessions.py:1855-1868`). Jamais la moyenne.

**Imports :** Toujours importer depuis `progression.py`. Ne pas réimplémenter.
Quatre duplications existent déjà (`api/plateau.py:43`, `api/volume.py:72`,
`api/routes/data_views.py:299`, migration `040_1rm_brzycki.sql:26`) — dette technique, pas un
pattern à reproduire.

---

## 4. Suppression — hard vs soft delete

### exercises (catalogue)

Soft-delete via `deleted_at` uniquement. Migration `020_soft_delete_exercises.sql` — remplace les
hard DELETE (qui cascadaient sur exercise_logs) par un marqueur timestamp.

Toutes les lectures filtrent `.is_("deleted_at", "null")` (`api/db_exercises.py:22, 49`).

Fonction : `api/db_exercises.py:241-257` — `delete_exercise_by_name` → `update({"deleted_at": "now()"})`.

### exercise_logs

**Hard-delete.** Les logs sont physiquement supprimés. Sites : `api/db_sessions.py:475, 1448, 1480,
1674`. Endpoint public : `api/routes/workout_exercises.py:104-114` — `POST /api/delete_exercise_log`.

### Note générale

Il n'existe **pas** de colonne `is_deleted` dans la codebase. La convention soft-delete utilise
`deleted_at` (timestamp).

---

## 5. No-silent-fallback

Un échec de DB ou de validation doit remonter en erreur explicite (exception ou HTTP 5xx),
pas être masqué par une valeur par défaut.

**Exemples corrects :**
- `api/pss.py:190` — `raise RuntimeError("pss: DB write failed — upsert returned None")`
- `api/progression.py:159, 170` — `raise ValueError` si reps invalides
- `api/time_capsule.py:182` — `raise RuntimeError("Supabase not connected")`
- `api/db_profile.py:119` — `raise RuntimeError("Supabase client not available")`

**Violations connues (documentées, pas à reproduire) :**
- `api/readiness.py:834-843` — exception catchée → `{"score": 65, "verdict": "moderate"}` (HTTP 200).
  Masque les pannes DB en données fictives "modérées".
- `api/routes/sleep_debt.py:14-16` — exception catchée → `{"has_data": False, "debt_7d": None}`
  (HTTP 200). Le client iOS interprète ça comme "pas de données" au lieu d'une erreur réseau.

Ne pas ajouter de nouvelles violations sans discussion. Le pattern `dict.get(key) or default`
est légitime pour les valeurs nullable ; le problème est de masquer des exceptions d'infrastructure.
