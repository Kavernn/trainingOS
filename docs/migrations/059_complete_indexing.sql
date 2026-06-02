-- Migration 059 : Index complets — FK manquants + colonnes temporelles
-- Audit : 49 tables, 6 FK sans index (critiques), 39 colonnes temporelles sans index

-- ── FK CRITIQUES ────────────────────────────────────────────────────────────────
-- Sans ces index, chaque JOIN fait un seq scan complet

CREATE INDEX IF NOT EXISTS idx_mood_logs_pss_record_id      ON mood_logs (pss_record_id);
CREATE INDEX IF NOT EXISTS idx_oath_recalls_oath_id          ON oath_recalls (oath_id);
CREATE INDEX IF NOT EXISTS idx_season_snapshots_season_id    ON season_snapshots (season_id);
CREATE INDEX IF NOT EXISTS idx_self_care_logs_habit_id       ON self_care_logs (habit_id);
CREATE INDEX IF NOT EXISTS idx_user_profile_active_program   ON user_profile (active_program_id);
CREATE INDEX IF NOT EXISTS idx_weekly_schedule_session_id    ON weekly_schedule (session_id);

-- ── TEMPORELS — WAR ROOM ────────────────────────────────────────────────────────
-- war_room_config est single-row (id=1) : pas d'index
CREATE INDEX IF NOT EXISTS idx_war_room_battles_created_at   ON war_room_battles (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_war_room_battles_updated_at   ON war_room_battles (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_war_room_triggers_logged_at   ON war_room_triggers (logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_war_room_triggers_created_at  ON war_room_triggers (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_war_room_arsenal_created_at   ON war_room_arsenal (created_at DESC);

-- ── TEMPORELS — NUTRITION ────────────────────────────────────────────────────────
-- nutrition_settings est single-row (id=1) : pas d'index
CREATE INDEX IF NOT EXISTS idx_nutrition_entries_created_at  ON nutrition_entries (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nutrition_logs_logged_at      ON nutrition_logs (logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_meal_templates_created_at     ON meal_templates (created_at DESC);

-- ── TEMPORELS — SANTÉ MENTALE ────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_pss_records_recorded_at       ON pss_records (recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_journal_entries_created_at    ON journal_entries (created_at DESC);

-- ── TEMPORELS — BIEN-ÊTRE ────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_spirit_journal_created_at     ON spirit_journal (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_spirit_journal_updated_at     ON spirit_journal (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sleep_records_logged_at       ON sleep_records (logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_breathwork_sessions_logged_at ON breathwork_sessions (logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_meditation_sessions_started   ON meditation_sessions (started_at DESC);

-- ── TEMPORELS — COACHING & PROFIL ───────────────────────────────────────────────
-- user_profile et deload_state sont des tables single-row (id=1) : aucun index utile

-- ── TEMPORELS — CARACTÈRE & IDENTITÉ ────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_oaths_written_at              ON oaths (written_at DESC);
CREATE INDEX IF NOT EXISTS idx_oath_recalls_shown_at         ON oath_recalls (shown_at DESC);
CREATE INDEX IF NOT EXISTS idx_seasons_created_at            ON seasons (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_seasons_started_at            ON seasons (started_at DESC);

-- ── TEMPORELS — ENTRAÎNEMENT ────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_goals_created_at              ON goals (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_goals_target_date             ON goals (target_date DESC);
CREATE INDEX IF NOT EXISTS idx_cardio_logs_logged_at         ON cardio_logs (logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_hiit_logs_logged_at           ON hiit_logs (logged_at DESC);

-- ── TEMPORELS — RÉFÉRENTIEL ──────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_programs_created_at           ON programs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_created_at          ON exercises (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_daily_ritual_created_at       ON daily_ritual (created_at DESC);

-- ── TEMPORELS — SYSTÈME ──────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_gym_contributions_created_at  ON gym_contributions (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_time_capsules_created_at      ON time_capsules (created_at DESC);
