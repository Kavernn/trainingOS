-- 018_meal_templates.sql
-- Reusable meal templates for batch food logging (log a whole meal in one tap)

CREATE TABLE IF NOT EXISTS meal_templates (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT         NOT NULL,
    items      JSONB        NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
