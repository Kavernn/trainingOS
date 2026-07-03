-- Store daily readiness score prospectively (never backfilled).
-- Written by api/readiness.py:compute() at the end of each day's score computation.
-- Read by api/routes/readiness.py:api_readiness_history for the Recovery14dChart.

CREATE TABLE readiness_daily (
    date DATE PRIMARY KEY,
    score INTEGER NOT NULL CHECK (score >= 0 AND score <= 100),
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
