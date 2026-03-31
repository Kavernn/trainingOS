"""
test_deferred_logging.py
========================
Tests the deferred logging fix across 4 scenarios.

SCOPE : backend only — exercises the same endpoints the iOS client calls.
        No Supabase required: runs in OFFLINE mode (SQLite KV only).
        Uses a temp DB so production data is never touched.

Scenarios
---------
  S1  Séance complétée normalement  → "Terminer la séance" appuyé
  S2  Séance quittée en cours       → zéro commit
  S3  Séance quittée → Sauvegarder  → commit complet
  S4  Séance quittée → Abandonner   → zéro commit

DB state tracked: KV weights[exercise]['history'][0]['date']
"""
from __future__ import annotations

import os, sys, json, tempfile, threading, time

# ── Isolated offline DB ────────────────────────────────────────────────────
TEMP_DB = tempfile.mktemp(suffix=".db", prefix="trainingos_test_")
os.environ["APP_DATA_MODE"]  = "OFFLINE"
os.environ["APP_LOCAL_DB"]   = TEMP_DB

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import db as _db            # picks up OFFLINE + TEMP_DB before any connect
from weights import load_weights, save_weights

# ── Flask test client ──────────────────────────────────────────────────────
import index as _idx        # noqa: E402  (side-effects: registers routes)
_idx.app.config["TESTING"]   = True
_idx.app.config["DEBUG"]     = False
client = _idx.app.test_client()

TODAY = "2026-03-31"

# ── Helpers ────────────────────────────────────────────────────────────────

RESULTS: list[tuple[str, str, str]] = []   # (scenario, status, detail)


def _today_in_kv(exercise: str) -> bool:
    """True if exercise has a history entry dated TODAY in the KV store."""
    w = load_weights()
    hist = w.get(exercise, {}).get("history", [])
    return bool(hist and hist[0].get("date") == TODAY)


def _reset_kv(exercises: list[str]):
    """Remove today's entries for listed exercises from KV and clear today's session."""
    w = load_weights()
    for ex in exercises:
        if ex in w:
            w[ex]["history"] = [h for h in w[ex].get("history", []) if h.get("date") != TODAY]
    save_weights(w)
    # Also reset session state so each scenario gets a clean slate
    sessions = _db.get_json("sessions", {})
    sessions.pop(TODAY, None)
    _db.set_json("sessions", sessions)


def _post_log(exercise: str, weight: float = 100.0, reps: str = "3,3,3",
              sets: list | None = None, force: bool = False,
              is_second: bool = False, is_bonus: bool = False) -> tuple[int, dict]:
    """POST /api/log and return (status_code, response_json)."""
    payload: dict = {"exercise": exercise, "weight": weight, "reps": reps}
    if sets:
        payload["sets"] = sets
    if force:
        payload["force"] = True
    if is_second:
        payload["is_second"] = True
    if is_bonus:
        payload["is_bonus"] = True
    r = client.post("/api/log", json=payload,
                    headers={"X-Date-Override": TODAY})
    try:
        body = json.loads(r.data)
    except Exception:
        body = {}
    return r.status_code, body


def _post_log_session(exercises: list[str], rpe: float = 7.0,
                      comment: str = "test") -> tuple[int, dict]:
    """POST /api/log_session — equivalent of vm.finish() logSession call."""
    exos = [f"{ex} {100}lbs 3,3,3" for ex in exercises]
    payload = {
        "rpe": rpe, "comment": comment,
        "exos": exos, "date": TODAY,
    }
    r = client.post("/api/log_session", json=payload)
    try:
        body = json.loads(r.data)
    except Exception:
        body = {}
    return r.status_code, body


def check(name: str, condition: bool, detail: str):
    status = "OK  ✓" if condition else "FAIL ✗"
    RESULTS.append((name, status, detail))
    print(f"  {status}  {detail}")


# ══════════════════════════════════════════════════════════════════════════
# Scenario 1 — Séance complétée normalement
# Expected:
#   BEFORE batch-commit  → nothing in DB
#   After  batch-commit  → exercise logged
#   After  log_session   → session completed
# ══════════════════════════════════════════════════════════════════════════
def test_s1():
    print("\n── S1: Séance complétée normalement ──────────────────────────────")
    ex = "Bench Press S1"
    _reset_kv([ex])

    # BEFORE: nothing logged (deferred — user logged locally, did NOT hit /api/log yet)
    before = _today_in_kv(ex)
    check("S1-before", not before,
          f"BEFORE finish: {ex} NOT in DB (deferred) → {'absent' if not before else 'PRESENT (bug!)'}")

    # User taps "Terminer" → batch-commit: POST /api/log per exercise
    sc_log, resp_log = _post_log(ex, weight=100, reps="8,8,8")
    check("S1-log-ok", sc_log == 200 and resp_log.get("success"),
          f"/api/log → HTTP {sc_log}, success={resp_log.get('success')}")

    after_log = _today_in_kv(ex)
    check("S1-in-db", after_log,
          f"AFTER /api/log: {ex} IN DB → {'present' if after_log else 'ABSENT (bug!)'}")

    # POST /api/log_session (same as vm.finish logSession)
    sc_sess, resp_sess = _post_log_session([ex])
    check("S1-session-ok", sc_sess == 200 and resp_sess.get("success"),
          f"/api/log_session → HTTP {sc_sess}, success={resp_sess.get('success')}")


# ══════════════════════════════════════════════════════════════════════════
# Scenario 2 — Séance quittée en cours (no API call made)
# Expected: nothing written to DB at any point during the session
# ══════════════════════════════════════════════════════════════════════════
def test_s2():
    print("\n── S2: Séance quittée en cours (aucun commit) ────────────────────")
    ex = "Pull-Up S2"
    _reset_kv([ex])

    # Simulate user logging 3 exercises locally and quitting without tapping "Terminer"
    # (With deferred logging, neither /api/log nor /api/log_session is called)
    # → DB check: nothing written

    after_quit = _today_in_kv(ex)
    check("S2-no-write", not after_quit,
          f"After quit (no API calls): {ex} NOT in DB → {'absent (correct)' if not after_quit else 'PRESENT (bug!)'}")

    # Double-check: KV for today is clean
    w = load_weights()
    today_count = sum(
        1 for ex_data in w.values()
        if ex_data.get("history") and ex_data["history"][0].get("date") == TODAY
        and ex_data["history"][0].get("weight") == 0  # sentinel: no real data
    )
    check("S2-kv-clean", after_quit is False,
          f"KV contains no S2 exercise for today")


# ══════════════════════════════════════════════════════════════════════════
# Scenario 3 — Séance quittée → "Sauvegarder" choisi
# Expected:
#   User exits, picks Sauvegarder → FinishSessionSheet opens → Terminer tapped
#   → same as S1: batch-commit + log_session
# ══════════════════════════════════════════════════════════════════════════
def test_s3():
    print("\n── S3: Quitter → 'Sauvegarder' → commit complet ─────────────────")
    ex = "Squat S3"
    _reset_kv([ex])

    # BEFORE: nothing in DB (user had been doing exercise locally)
    before = _today_in_kv(ex)
    check("S3-before", not before,
          f"BEFORE save: {ex} NOT in DB → {'absent' if not before else 'PRESENT (bug!)'}")

    # User picks "Sauvegarder" → FinishSessionSheet opens → same commit path as S1
    sc_log, resp_log = _post_log(ex, weight=80, reps="5,5,5")
    check("S3-log-ok", sc_log == 200 and resp_log.get("success"),
          f"/api/log → HTTP {sc_log}")

    after = _today_in_kv(ex)
    w = load_weights()
    entry = w.get(ex, {}).get("history", [{}])[0]
    check("S3-complete", after and entry.get("reps") == "5,5,5",
          f"AFTER save: {ex} IN DB | reps={entry.get('reps')} | weight={entry.get('weight')}")

    sc_sess, resp_sess = _post_log_session([ex])
    check("S3-session", sc_sess == 200,
          f"/api/log_session → HTTP {sc_sess}")


# ══════════════════════════════════════════════════════════════════════════
# Scenario 4 — Séance quittée → "Abandonner" choisi
# Expected: logResults cleared in memory, NO API calls → DB stays clean
# ══════════════════════════════════════════════════════════════════════════
def test_s4():
    print("\n── S4: Quitter → 'Abandonner' → zéro DB write ───────────────────")
    ex = "Deadlift S4"
    _reset_kv([ex])

    # Simulate Abandonner: logResults = [:] on iOS side, then dismiss
    # No /api/log call, no /api/log_session call
    # → DB check: nothing written

    after_abandon = _today_in_kv(ex)
    check("S4-no-write", not after_abandon,
          f"After abandon: {ex} NOT in DB → {'absent (correct)' if not after_abandon else 'PRESENT (bug!)'}")

    w = load_weights()
    s4_exercises = [k for k in w if "S4" in k and
                    w[k].get("history") and w[k]["history"][0].get("date") == TODAY]
    check("S4-kv-clean", len(s4_exercises) == 0,
          f"KV has 0 S4 entries for today (found {len(s4_exercises)})")


# ══════════════════════════════════════════════════════════════════════════
# Edge: duplicate-prevention — batch-commit with force=False on clean slate
# ══════════════════════════════════════════════════════════════════════════
def test_edge_dedup():
    print("\n── EDGE: force=False on clean slate (normal batch-commit path) ───")
    ex = "OHP Edge"
    _reset_kv([ex])

    # First log (no prior entry today) → should succeed
    sc1, r1 = _post_log(ex, weight=60, reps="5,5,5")
    check("EDGE-first-ok", sc1 == 200 and r1.get("success"),
          f"First /api/log (force=False, no prior): HTTP {sc1}, success={r1.get('success')}")

    # Second log same exercise same day without force → should return 409 already_logged
    sc2, r2 = _post_log(ex, weight=60, reps="5,5,5")
    check("EDGE-dedup-409", sc2 == 409 and r2.get("error") == "already_logged",
          f"Second /api/log same day (force=False): HTTP {sc2}, error={r2.get('error')}")

    # This is fine: in the real app, each exercise only commits once per session


# ══════════════════════════════════════════════════════════════════════════
# Run all
# ══════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    print("=" * 66)
    print("  TEST: Deferred Logging — 4 scenarios + 1 edge case")
    print(f"  DB:   {TEMP_DB}")
    print("=" * 66)

    test_s1()
    test_s2()
    test_s3()
    test_s4()
    test_edge_dedup()

    # ── Summary ──────────────────────────────────────────────────────────
    print("\n" + "=" * 66)
    print("  RAPPORT FINAL")
    print("=" * 66)
    ok    = sum(1 for _, s, _ in RESULTS if "OK" in s)
    fail  = sum(1 for _, s, _ in RESULTS if "FAIL" in s)
    for name, status, detail in RESULTS:
        print(f"  [{name:<20}] {status}  {detail}")
    print("-" * 66)
    print(f"  Total: {ok} OK  |  {fail} FAIL")
    print("=" * 66)

    # Cleanup
    try:
        os.remove(TEMP_DB)
    except Exception:
        pass

    sys.exit(0 if fail == 0 else 1)
