-- Migration 054 : Ajout champs GPS et timestamps dans cardio_logs
-- Tracking actif Strava-like : start/end time, distance précise, pace en secondes, points GPS, polyline
-- Tous les champs nullable — zéro impact sur les logs historiques existants

ALTER TABLE cardio_logs
  ADD COLUMN IF NOT EXISTS start_time       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS end_time         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS distance_km      NUMERIC(6,3),
  ADD COLUMN IF NOT EXISTS pace_avg_seconds INTEGER,
  ADD COLUMN IF NOT EXISTS gps_points       JSONB,
  ADD COLUMN IF NOT EXISTS route_encoded    TEXT;
