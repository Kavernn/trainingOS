# CLAUDE.md — TrainingOS

> AI assistant reference for the TrainingOS codebase. Keep this file up-to-date when adding features or changing conventions.

---

## Project Overview

**TrainingOS** is a personal fitness tracking web app built with Flask (Python) and Jinja2 templates. It tracks weight training sessions, HIIT workouts, body composition, goals, and deload cycles. It is deployed on **Vercel** as a serverless Python function, and is also packaged as an **iOS native app** via Capacitor.

- **Backend**: Flask (Python 3), served from `api/index.py`
- **Frontend**: Server-rendered Jinja2 HTML with embedded vanilla JS — no bundler/framework
- **Database**: Supabase (PostgreSQL key-value table) with a local SQLite fallback
- **Mobile**: Capacitor 6 wrapping the production web URL (`https://trainingos.app`)
- **PWA**: Service worker + Web App Manifest for installability and offline support
- **Language**: Codebase is primarily in **French** (variable names, routes, UI strings, comments)

---

## Repository Structure

```
trainingOS/
├── api/                     # All Python backend code
│   ├── index.py             # ← PRIMARY ENTRY POINT (Vercel + local dev)
│   ├── flask_app.py         # Legacy/duplicate Flask app (superseded by index.py)
│   ├── db.py                # Supabase + SQLite KV store abstraction
│   ├── planner.py           # Weekly schedule, program loading, weight suggestions
│   ├── progression.py       # Rep rules, weight increments, 1RM estimation (Epley)
│   ├── log_workout.py       # Exercise history read/write
│   ├── sessions.py          # Workout session logging
│   ├── inventory.py         # Exercise library (type, muscles, plates)
│   ├── deload.py            # Stagnation detection, fatigue analysis, deload logic
│   ├── goals.py             # Strength goal tracking
│   ├── body_weight.py       # Body weight log + trend detection
│   ├── hiit.py              # HIIT phases and log
│   ├── user_profile.py      # User profile persistence
│   ├── warmup.py            # (stub)
│   ├── timer.py             # (stub)
│   ├── stats.py             # (stub)
│   ├── menu_select.py       # CLI menu helper (terminal mode only)
│   ├── import_exercises.py  # One-off data import script
│   ├── migrate_to_supabase.py # One-off migration script
│   └── main.py              # CLI entrypoint (terminal mode, unused in web)
│
├── templates/               # Jinja2 HTML templates
│   ├── base.html            # ← Master layout (nav, CSS vars, toast, SW registration)
│   ├── index.html           # Dashboard / home
│   ├── seance.html          # Active workout session
│   ├── seance_speciale.html # HIIT / Yoga / Recovery days
│   ├── inventaire.html      # Exercise library manager
│   ├── programme.html       # Weekly program editor
│   ├── historique.html      # Lift history browser
│   ├── stats.html           # Statistics dashboard (charts, KPIs, PRs)
│   ├── objectifs.html       # Strength goals tracker
│   ├── profil.html          # User profile + body weight
│   ├── bodycomp.html        # Body composition page
│   ├── timer.html           # Rest timer
│   ├── hiit.html            # HIIT session history
│   ├── notes.html           # Session notes browser
│   ├── planificateur.html   # Training planner
│   ├── intelligence.html    # AI coach interface
│   └── xp.html              # XP / gamification page
│
├── static/
│   ├── sw.js                # Service worker (network-first HTML, cache-first assets)
│   ├── manifest.json        # PWA manifest (name, icons, theme #0f0f17 bg / #f97316 orange)
│   ├── icons/               # icon-192.png, icon-512.png
│   └── uploads/             # User-uploaded profile photos
│
├── data/                    # Local JSON fallback data (NOT used in production)
│   ├── weights.json
│   ├── sessions.json
│   ├── inventory.json
│   ├── program.json
│   ├── hiit_log.json
│   ├── body_weight.json
│   └── user.json
│
├── mobile/ios/              # Capacitor-generated Xcode project
├── www/                     # Capacitor web dir (points to production URL, not local files)
├── capacitor.config.ts      # Capacitor config (appId: com.trainingos.app)
├── package.json             # Node deps: @capacitor/core, @capacitor/ios, etc.
├── vercel.json              # Vercel deployment: routes all traffic → api/index.py
└── requirements.txt         # Python deps: Flask, Werkzeug, Jinja2, supabase
```

---

## Data Layer (`api/db.py`)

All data is stored in a **key-value store** via `get_json(key, default)` / `set_json(key, value)`.

### Modes (set via `APP_DATA_MODE` env var)
| Mode | Behaviour |
|------|-----------|
| `ONLINE` (default) | Write to Supabase; mirror to local SQLite. Falls back to `HYBRID` if no credentials. |
| `HYBRID` | Try Supabase; if it fails, write to SQLite with `dirty=1` for later sync. |
| `OFFLINE` | SQLite only. Use `sync_now()` to push dirty records when back online. |

### Supabase table: `kv`
Columns: `key TEXT PK`, `value JSONB`, `updated_at TIMESTAMPTZ`

### KV keys used in production
| Key | Type | Description |
|-----|------|-------------|
| `weights` | `dict` | Per-exercise weight history and current weight |
| `sessions` | `dict` | Keyed by `YYYY-MM-DD`, contains RPE, comment, exercises |
| `inventory` | `dict` | Exercise library (type, increment, muscles, tips, gif_url) |
| `program` | `dict` | Weekly training program (`{day: {exercise: scheme}}`) |
| `hiit_log` | `list` | HIIT session entries |
| `body_weight` | `list` | Body weight entries (`{date, poids, note}`) |
| `goals` | `dict` | Strength goals per exercise |
| `user_profile` | `dict` | Name, age, photo_b64, etc. |
| `deload_state` | `dict` | `{active, since, reason}` |

### Important constraints
- **Vercel filesystem is read-only** — `_ON_VERCEL` flag disables all SQLite writes in production.
- The SQLite local DB lives at `.local_kv.db` in the repo root (gitignored).
- Never write directly to the `data/` JSON files in new code — use `get_json`/`set_json`.

---

## Backend Conventions

### Entry Point
**Always use `api/index.py`** as the single Flask entry point. `api/flask_app.py` is a legacy duplicate and should not be modified or used for new code.

### Adding a new page
1. Add a route in `api/index.py`
2. Create `templates/<page>.html` extending `base.html`
3. Add a nav link to `base.html` if it should appear in the bottom nav

### Adding a new API endpoint
- All API routes are prefixed `/api/` and return `jsonify({...})`
- Return `{"success": True}` on success, `{"error": "..."}` with appropriate HTTP status on failure
- Always use `request.get_json()` (not `request.json`) when reading POST bodies to handle edge cases

### Progression logic (`api/progression.py`)
- `REPS_RULES`: defines target rep ranges per exercise (for auto-progression detection)
- `INCREMENT_RULES`: per-exercise or per-type weight increment in lbs
- `should_increase(reps_str, exercise)`: returns `True` if all sets hit the minimum reps
- `next_weight(exercise, current)`: adds the configured increment
- `estimate_1rm(weight, reps_str)`: Epley formula — `weight × (1 + avg_reps / 30)`
- To add a new exercise to auto-progression: add it to `REPS_RULES` and optionally `INCREMENT_RULES`

### Inventory exercise types
| Type | Behaviour |
|------|-----------|
| `barbell` | Weight shown as "X lbs per side"; plate calculator enabled |
| `dumbbell` | Weight shown as "X lbs per dumbbell" (÷2) |
| `machine` | Weight shown as total lbs |

### Week numbering
The training program started on **March 3, 2026**. Week number is computed from that date in `get_current_week()`. Week 1 = March 3–9, 2026.

### Weekly schedule (hardcoded in `planner.py`)
```
Mon → Upper A   Tue → HIIT 1   Wed → Upper B
Thu → HIIT 2   Fri → Lower    Sat → Yoga   Sun → Recovery
```
Special days (`HIIT 1`, `HIIT 2`, `Yoga`, `Recovery`) redirect to `/seance_speciale/<type>`.

### HIIT progression phases
| Weeks | Sprint | Rest | Rounds | Speed |
|-------|--------|------|--------|-------|
| 1–3 | 30s | 90s | 8 | 12–14 km/h |
| 4–6 | 40s | 80s | 9 | 13–15 km/h |
| 7+ | 45s | 75s | 10 | 14–16 km/h |

---

## Frontend Conventions

### Design system (defined in `base.html` CSS variables)
```css
--orange:  #f97316   /* primary accent */
--orange2: #ea580c   /* darker orange */
--orange3: #fbbf24   /* amber highlight */
--green:   #22c55e
--blue:    #3b82f6
--purple:  #a855f7
--rose:    #f43f5e
--bg:      #080810   /* page background */
--bg2:     #11111c
--bg3:     #191926
--glass:   rgba(17,17,28,0.75)  /* glassmorphism card bg */
--border:  rgba(255,255,255,0.07)
--radius:  14px
```

### Fonts
- **Barlow Condensed** (weights 400/600/700/800) — headings, buttons, nav labels
- **Inter** (weights 400/500/600) — body text, forms

### Reusable CSS classes
- `.card` — glassmorphism card with blur + border
- `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-success`, `.btn-block`
- `.badge`, `.badge-orange`, `.badge-green`, `.badge-blue`, `.badge-red`
- `.progress-wrap` + `.progress-fill` — animated shimmer progress bar
- `.alert`, `.alert-warning`, `.alert-success`, `.alert-info`
- `.grid-2` — 2-column grid (collapses to 1 on ≤600px)
- `.flex-between`, `.flex`, `.gap-8`, `.gap-16`, `.mt-8/16/24`, `.mb-8/14/16`

### Toast notifications
```js
showToast('Message', 'success')  // or 'error'
// Displayed for 3s, positioned above bottom nav
```

### AJAX pattern
```js
fetch('/api/some_endpoint', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({...})
})
.then(r => r.json())
.then(data => {
  if (data.success) showToast('OK');
  else showToast(data.error || 'Erreur', 'error');
});
```

### Responsive breakpoints
- `≤600px` — mobile (Android/iOS): grid collapses, smaller fonts and buttons
- `≤520px` — small mobile: timer ring scales with `vw`
- `≤360px` — very small screens: further font/button reductions

### Template structure
All templates extend `base.html`:
```html
{% extends "base.html" %}
{% block title %}Page Title{% endblock %}
{% block extra_css %}<style>/* page-specific CSS */</style>{% endblock %}
{% block content %}
  <!-- page HTML -->
{% endblock %}
{% block extra_js %}<script>/* page-specific JS */</script>{% endblock %}
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | Yes (prod) | Supabase project URL |
| `SUPABASE_ANON_KEY` | Yes (prod) | Supabase anonymous key |
| `SECRET_KEY` | Yes (prod) | Flask session secret key |
| `APP_DATA_MODE` | No | `ONLINE` / `HYBRID` / `OFFLINE` (default: `ONLINE`) |
| `APP_LOCAL_DB` | No | Path to local SQLite file (default: `.local_kv.db`) |
| `OPENROUTER_API_KEY` | No | For `/api/ai/coach` (Mistral 7B via OpenRouter) |
| `X_RAPIDAPI_KEY` | No | For ExerciseDB GIF auto-fetch on exercise save |

On **Vercel**, `VERCEL` or `VERCEL_ENV` env vars are auto-set; SQLite is disabled automatically.

---

## Deployment

### Vercel (production)
- Entry point: `api/index.py` (see `vercel.json`)
- All routes → `api/index.py`; static files served directly from `/static/**`
- Max lambda size: 50MB
- Deploy: push to `master` branch (auto-deploy if Vercel integration is configured)

### Local development
```bash
# Install Python deps
pip install -r requirements.txt

# Set env vars (create a .env file or export manually)
export SUPABASE_URL=...
export SUPABASE_ANON_KEY=...
export APP_DATA_MODE=HYBRID  # allows local fallback during dev

# Run
python api/index.py
# or
python main.py
# App auto-finds a free port starting at 5000 and opens browser
```

### iOS (Capacitor)
```bash
npm install
npx cap sync          # sync web assets to native project
npx cap run ios       # build and run on simulator
npx cap open ios      # open in Xcode
```
The Capacitor app loads `https://trainingos.app` — it does **not** bundle local HTML files. The `www/` directory is the Capacitor `webDir` but points to the live server.

### PWA
- Service worker registered in `base.html` from `/static/sw.js`
- **Update CACHE_NAME version** in `sw.js` on every deployment to force cache refresh on mobile
- Strategy: Network-first for HTML pages, cache-first for images/icons, always-network for `/api/*`

---

## Key Patterns & Gotchas

1. **`flask_app.py` vs `index.py`**: `index.py` is the canonical file. If you see divergence between the two, trust `index.py`. Do not add new features to `flask_app.py`.

2. **Session blocking**: A session can only be logged once per day (`already_logged` check in `/seance`). The UI shows a warning but does not hard-block re-logging.

3. **Exercise renaming propagates**: When an exercise is renamed via `api/save_exercise`, the code automatically updates all program day entries to use the new name.

4. **Weight display depends on exercise type**: Always look up `inventory.get(ex, {}).get("type")` before rendering weights to apply the correct barbell/dumbbell/machine display format.

5. **History capped at 20 entries** per exercise in `weights`. Displayed history on the session page is the most recent 3; on historique page, most recent 10.

6. **1RM calculation**: Epley formula, computed fresh on each log. Stored in history entries as `"1rm"`.

7. **Deload detection**: `analyser_deload()` flags stagnation when the same weight appears in 3 consecutive history entries for an exercise. RPE fatigue is flagged when the average RPE of the last 3 sessions ≥ 8.5.

8. **Profile photos**: Stored as base64 data URLs in the `user_profile` KV entry (key: `photo_b64`). Max ~600KB after client-side compression. The old file-upload approach (`photo` filename) is deprecated.

9. **HIIT log**: Stored under KV key `hiit_log` (a JSON list). In legacy code, it was stored in a local file `api/data/hiit_log.json` — production always uses the KV store.

10. **AI coach**: `/api/ai/coach` proxies to OpenRouter (Mistral 7B). System prompt is hardcoded in the route. Responds in French, max 6 sentences.

---

## Git & Branching

- Main branch: `master`
- Feature branches: `claude/<description>-<session-id>` (required format for AI-generated branches)
- Never force-push to `master`
- Commit messages should be in English or French, using conventional commits where possible (`feat:`, `fix:`, `refactor:`, `chore:`)
