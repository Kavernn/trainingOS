# TrainingOS — État réel du schéma DB

## Source de vérité

`docs/schema.sql` est la **source de vérité unique**.

Il incorpore l'état complet post-migrations 001 à 047.
Pour restaurer la base sur une DB vide : exécuter `schema.sql` suffit.

> **Note (2026-06-17) :** 25 migrations supplémentaires ont été appliquées (048 → 072).
> `schema.sql` doit être mis à jour pour les intégrer. En attendant, appliquer les fichiers
> `docs/migrations/048_*.sql` … `072_*.sql` dans l'ordre après `schema.sql`.

## Historique des changements

Les fichiers `docs/migrations/` sont conservés à titre d'historique et pour le tracker `schema_migrations`.
Ils ne doivent **pas** être ré-exécutés sur une DB créée depuis `schema.sql`.

## Ajouter une table ou une colonne

1. Créer `docs/migrations/0NN_nom.sql` avec le DDL incremental
2. Mettre à jour `docs/schema.sql` pour intégrer le changement directement dans la définition de table
3. Ajouter `INSERT INTO schema_migrations (version) VALUES ('0NN_nom') ON CONFLICT DO NOTHING;` à la fin de la migration
4. Respecter les règles Supabase :
   - RLS + policy `anon_all` sur chaque nouvelle table
   - Pas de dollar-quoting (`$$`) dans les fonctions
   - Pas d'index partiel (`CREATE INDEX ... WHERE ...`)

## Tables (50 au 2026-05-20 + 4 confirmées en 048-072 = ≥54 — référer à schema.sql pour le compte exact)

| # | Nom | Migration d'origine |
|---|-----|---------------------|
| 1 | programs | 002 |
| 2 | exercises | schema initial |
| 3 | program_sessions | schema initial + 002 |
| 4 | program_blocks | schema initial |
| 5 | program_block_exercises | schema initial |
| 6 | weekly_schedule | schema initial + 002 |
| 7 | workout_sessions | schema initial |
| 8 | exercise_logs | schema initial + 024 |
| 9 | hiit_logs | schema initial |
| 10 | goals | schema initial |
| 11 | goals_archived | 011 |
| 12 | generated_programs | 014 |
| 13 | plateau_alerts | 028 |
| 14 | body_weight_logs | schema initial + 029 |
| 15 | cardio_logs | schema initial + 001 |
| 16 | recovery_logs | schema initial + 001 + 017 |
| 17 | hydration_logs | 039 |
| 18 | nutrition_settings | schema initial |
| 19 | nutrition_logs | schema initial |
| 20 | meal_templates | 018 |
| 21 | food_catalog | 004_food_catalog |
| 22 | nutrition_entries | nutrition_entries |
| 23 | pss_records | schema initial + 025 + 046 |
| 24 | mood_logs | schema initial + 044 |
| 25 | journal_entries | schema initial |
| 26 | life_stress_scores | schema initial |
| 27 | daily_ritual | 004 |
| 28 | self_care_habits | schema initial |
| 29 | self_care_logs | schema initial |
| 30 | sleep_records | schema initial |
| 31 | breathwork_sessions | schema initial + 033 (réconcilié 042) |
| 32 | meditation_sessions | 033 |
| 33 | spirit_journal | 033 |
| 34 | spirit_config | 033 |
| 35 | coach_history | schema initial |
| 36 | user_profile | schema initial + 023 + 036 + 047 |
| 37 | deload_state | schema initial |
| 38 | oaths | 034 |
| 39 | oath_recalls | 034 (CASCADE corrigé par 043) |
| 40 | seasons | 035 |
| 41 | season_snapshots | 035 (CASCADE corrigé par 043) |
| 42 | war_room_config | 032 |
| 43 | war_room_battles | 032 |
| 44 | war_room_triggers | 032 |
| 45 | war_room_arsenal | 032 |
| 46 | time_capsules | 027 |
| 47 | gym_contributions | 037 |
| 48 | user_gym_history | 037 |
| 49 | schema_migrations | 026 |
| 50 | ai_rate_limit | schema initial |

## Nouvelles tables confirmées (migrations 048-072)

| Migration | Table / Objet | Notes |
|---|---|---|
| 055 | `body_budget_log` | Feature BodyBudget supprimée — table peut subsister en DB |
| 068 | `dass_records` | DASS-21 dépression/anxiété/stress |
| 069 | `smart_alarm_sessions` | AlarmKit iOS 26 |
| 071 | `exercise_prs` | PRs par exercice (`pr_weight_lbs`, `pr_e1rm_lbs`) |
| 072 | table daily_brief | Cache briefing coach quotidien |

Autres migrations 048-070 : ajouts de colonnes sur tables existantes (voir fichiers individuels).

## Corrections d'intégrité appliquées (migrations 042-047)

| Migration | Problème corrigé |
|-----------|-----------------|
| 042 | breathwork_sessions : colonnes Spirit Pillar absentes si schema.sql avait tourné avant 033 |
| 043 | oath_recalls + season_snapshots : FK sans ON DELETE → ajout CASCADE |
| 044 | mood_logs : lien PSS sans FK formelle → ajout colonne pss_record_id UUID |
| 045 | program_sessions : FK program_id sans index → ajout idx_program_sessions_program_id |
| 046 | workout_sessions.session_name + pss_records.type : NOT NULL manquants |
| 047 | user_profile.active_program_id : TEXT → UUID + FK vers programs |
