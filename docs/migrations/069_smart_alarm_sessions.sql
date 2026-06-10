-- Migration 069 — Table smart_alarm_sessions
-- Stocke les paires (bedtime_tap, hk_sleep_start) pour calibrer la latence adaptative.
-- bedtime_tap   : horodatage "Je me couche" envoyé par iOS (HH:mm).
-- hk_sleep_start: premier sample asleepX HealthKit (HH:mm), arrive lors de la sync du matin.
-- latency_min   : hk_sleep_start − bedtime_tap en minutes, calculé côté backend.
-- date           : date calendaire locale du tap (clé primaire).

CREATE TABLE IF NOT EXISTS smart_alarm_sessions (
    date            DATE        PRIMARY KEY,
    bedtime_tap     TEXT,
    hk_sleep_start  TEXT,
    latency_min     NUMERIC,
    created_at      TIMESTAMPTZ DEFAULT now()
);
