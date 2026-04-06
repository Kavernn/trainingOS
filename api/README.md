# TrainingOS API — Documentation

Base URL: `https://training-os-rho.vercel.app`

All endpoints are unauthenticated (see #A1 in audit). JSON responses unless noted.

---

## Dashboard

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/dashboard` | Full dashboard payload: profile, today's session, insights, deload, LSS, mood due |

---

## Profile

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/profil_data` | — | User profile row |
| POST | `/api/update_profile` | `{name, age, weight, height, goal, level, sex}` | Upsert user_profile |
| POST | `/api/update_profile_photo` | `{photo_b64}` | Update profile photo (base64, max 500 KB) |

---

## Workout — Session Logging

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | `/api/log` | `{exercise, weight, reps, session_date, session_type, session_name, rpe, rir, pain_zone, sets_json}` | Log one exercise set |
| POST | `/api/log_session` | `{date, rpe, comment, duration_min, energy_pre, session_name}` | Commit a finished session |
| POST | `/api/log_hiit` | `{date, type, duration_min, rounds, work_sec, rest_sec, rpe}` | Log a HIIT session |
| POST | `/api/delete_hiit` | `{id}` | Delete a HIIT session |
| POST | `/api/hiit/edit` | `{id, type, duration_min, rounds, rpe}` | Edit a HIIT session |
| POST | `/api/session/edit` | `{session_id, rpe, comment, duration_min, sets}` | Edit a logged muscu session |
| POST | `/api/session/delete` | `{session_id}` | Delete a session + its logs |
| POST | `/api/delete_exercise_log` | `{log_id}` | Delete one exercise log |
| POST | `/api/update_session` | `{session_id, rpe, comment, duration_min}` | Update session metadata |

---

## Workout — Data Views

| Method | Path | Params | Description |
|--------|------|--------|-------------|
| GET | `/api/seance_data` | `?date=YYYY-MM-DD&session_type=morning` | Today's session prescription + status |
| GET | `/api/seance_soir_data` | `?date=YYYY-MM-DD` | Evening session data |
| GET | `/api/hiit_data` | — | All HIIT logs |
| GET | `/api/progression_suggestions` | `?date=YYYY-MM-DD&session_name=Push+A` | Smart progression suggestions |
| POST | `/api/apply_progression` | `{exercise, action, new_weight, new_scheme}` | Apply a suggestion |

---

## Programme (Planning)

| Method | Path | Body/Params | Description |
|--------|------|-------------|-------------|
| GET | `/api/programs` | — | List all programs |
| POST | `/api/programs` | `{name}` | Create a program |
| POST | `/api/programme` | `{action, ...}` | Manage program sessions and exercises |
| GET/POST | `/api/evening_schedule` | — | Get/set evening workout schedule |
| POST | `/api/morning_schedule` | `{session_name}` | Set morning session |
| POST | `/api/save_exercise` | `{name, default_scheme, increment, category, ...}` | Create/update exercise in inventory |
| POST | `/api/delete_exercise` | `{name}` | Delete exercise |

---

## Goals & Body Composition

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | `/api/set_goal` | `{exercise, goal_weight, deadline, note}` | Set strength goal |
| GET | `/api/objectifs_data` | — | All goals + progress |
| POST | `/api/archive_objectif` | `{exercise}` | Archive a goal |
| GET | `/api/smart_goals` | — | Smart goals with computed current values |
| POST | `/api/smart_goals/save` | `{type, target_value, target_date, id?}` | Create/update smart goal |
| POST | `/api/smart_goals/delete` | `{id}` | Delete smart goal |
| POST | `/api/body_weight` | `{poids, note, body_fat, waist_cm, ...}` | Log body weight entry |
| POST | `/api/body_weight/update` | `{date, poids, body_fat, ...}` | Edit body weight entry |
| POST | `/api/body_weight/delete` | `{date}` | Delete body weight entry |

**Smart goal types:** `body_fat`, `lean_mass`, `waist_cm`, `weekly_volume`, `training_frequency`, `protein_daily`, `nutrition_streak`, `estimated_1rm`, `monthly_distance`, `resting_hr`, `pss_avg`, `sleep_streak`

---

## Nutrition

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/nutrition_data` | — | Entries, totals, settings, history |
| POST | `/api/nutrition/add` | `{name, calories, proteines, glucides, lipides, meal_type, heure}` | Add nutrition entry |
| POST | `/api/nutrition/edit` | `{entry_id, name, calories, proteines, glucides, lipides, meal_type}` | Edit entry |
| POST | `/api/nutrition/delete` | `{entry_id}` | Delete entry |
| POST | `/api/nutrition/settings` | `{limite_calories, objectif_proteines, glucides, lipides}` | Update daily targets |

---

## Recovery & Cardio

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/recovery_data` | — | All recovery logs |
| POST | `/api/log_recovery` | `{date, hrv, hr_rest, sleep_hours, energy, soreness, comment}` | Log recovery |
| POST | `/api/delete_recovery` | `{date}` | Delete recovery entry |
| GET | `/api/cardio_data` | — | All cardio logs |
| POST | `/api/log_cardio` | `{date, type, duration_min, distance_km, calories, hr_avg, hr_max, notes}` | Log cardio |
| POST | `/api/delete_cardio` | `{id}` | Delete cardio entry |
| POST | `/api/healthkit_sync` | `{workouts: [...], snapshots: [...]}` | Sync Apple Watch data |

---

## Wellness — Sleep, Mood, PSS

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/sleep/log` | Log sleep record `{date, duration_hours, quality, deep_pct, rem_pct, source}` |
| GET | `/api/sleep/history` | Sleep history |
| GET | `/api/sleep/today` | Today's sleep entry |
| GET | `/api/sleep/stats` | Sleep averages |
| POST | `/api/sleep/delete` | `{id}` Delete sleep record |
| GET | `/api/mood/emotions` | Emotion catalog |
| POST | `/api/mood/log` | Log mood `{score, emotions, note}` |
| GET | `/api/mood/history` | Mood history |
| GET | `/api/mood/check_due` | Whether mood check is due today |
| GET | `/api/pss/questions` | PSS-10 questions |
| POST | `/api/pss/submit` | Submit PSS `{answers: [0..4 × 10]}` |
| GET | `/api/pss/history` | PSS records |
| GET | `/api/pss/check_due` | Whether PSS is due (monthly) |

---

## Mental Health

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/mental_health/summary` | Full mental health dashboard |
| GET | `/api/life_stress/score` | Latest life stress score |
| GET | `/api/life_stress/trend` | Life stress trend (last 30 days) |
| GET | `/api/journal/today_prompt` | Today's journal prompt |
| POST | `/api/journal/save` | Save journal entry `{content, mood_score, prompt}` |
| GET | `/api/journal/entries` | Journal history |
| GET | `/api/breathwork/techniques` | Available breathwork techniques |
| POST | `/api/breathwork/log` | Log breathwork session |
| GET | `/api/breathwork/stats` | Breathwork stats |
| GET | `/api/self_care/habits` | Self-care habits list |
| POST | `/api/self_care/habits` | Create habit |
| DELETE | `/api/self_care/habits/<id>` | Delete habit |
| POST | `/api/self_care/log` | Log habit completion today |
| GET | `/api/self_care/today` | Today's habit completion status |

---

## Analytics & AI

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/insights` | AI-generated insights for dashboard |
| GET | `/api/deload_status` | Deload recommendation |
| POST | `/api/apply_deload` | Apply deload (–15% weights) |
| GET | `/api/acwr` | Acute:Chronic Workload Ratio |
| GET | `/api/coach/morning_brief` | Morning brief data |
| GET | `/api/peak_prediction` | Peak performance prediction |
| GET | `/api/insights/correlations` | Training–wellness correlations |
| GET | `/api/stats_data` | Full stats payload (weights, sessions, muscle stats) |
| POST | `/api/ai/propose` | AI progression proposal `{exercise, history}` |
| POST | `/api/ai/narrative` | AI post-session narrative `{session_data}` |
| POST | `/api/ai/coach` | Chat with AI coach `{message, history}` |
| GET | `/api/ai/coach/history` | Chat history |

**Rate limit:** 10 AI calls/hour (shared across workers via Supabase `ai_rate_limit` table).

---

## Export

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/export_data` | Full data export as JSON file |

---

## Notes

- All dates: `YYYY-MM-DD` (Montreal timezone)
- Weights: stored in **lbs** (not kg)
- No authentication on any route (see audit item #A1)
- Vercel serverless deployment — cold starts possible on first request
