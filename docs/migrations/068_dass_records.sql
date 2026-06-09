-- Migration 068 — DASS-21 records
-- Depression Anxiety Stress Scales (Lovibond & Lovibond 1995)
-- Fréquence : mensuelle. Sous-scores séparés × 2.

create table if not exists dass_records (
  id                   text        primary key default gen_random_uuid()::text,
  date                 date        not null unique,
  responses            jsonb       not null,           -- array[21] of int 0-3
  depression_raw       int         not null,            -- sum items D (0-21)
  anxiety_raw          int         not null,            -- sum items A (0-21)
  stress_raw           int         not null,            -- sum items S (0-21)
  depression_score     int         not null,            -- raw × 2 (0-42)
  anxiety_score        int         not null,            -- raw × 2 (0-42)
  stress_score         int         not null,            -- raw × 2 (0-42)
  depression_category  text        not null,
  anxiety_category     text        not null,
  stress_category      text        not null,
  pro_referral         boolean     not null default false,
  notes                text,
  created_at           timestamptz not null default now()
);
