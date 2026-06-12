-- 071_exercise_prs.sql
-- PR all-time maintenu au write — une row par exercice, en lbs (convention interne du projet)
-- Pas d'index secondaire (table mono-user ~200 rows, PK suffice)

CREATE TABLE IF NOT EXISTS exercise_prs (
    exercise_id     UUID         NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    pr_weight_lbs   DECIMAL(7,2) NOT NULL,
    pr_e1rm_lbs     DECIMAL(7,2) NOT NULL,
    pr_date         DATE         NOT NULL,
    pr_reps         INTEGER      NOT NULL,
    baseline_count  INTEGER      NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    PRIMARY KEY (exercise_id)
);

ALTER TABLE exercise_prs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_all_exercise_prs" ON exercise_prs FOR ALL USING (true) WITH CHECK (true);
