import os
import uuid
from datetime import date

import pytest


def _must_env(name: str) -> str:
    v = os.getenv(name, "").strip()
    if not v:
        pytest.skip(f"Missing env var {name} (required for integration DB tests)")
    return v


@pytest.fixture(scope="session")
def supabase_env():
    # We require Service Role to bypass RLS and to ensure cleanup works.
    return {
        "SUPABASE_URL": _must_env("SUPABASE_URL"),
        "SUPABASE_SERVICE_ROLE_KEY": _must_env("SUPABASE_SERVICE_ROLE_KEY"),
    }


@pytest.fixture(scope="session")
def sb(supabase_env):
    from supabase import create_client

    return create_client(supabase_env["SUPABASE_URL"], supabase_env["SUPABASE_SERVICE_ROLE_KEY"])


@pytest.fixture(scope="session")
def flask_app():
    # Import the real app and force TESTING mode to bypass API key auth.
    import sys
    from pathlib import Path

    api_dir = Path(__file__).resolve().parents[2] / "api"
    sys.path.insert(0, str(api_dir))

    import index as api_index

    api_index.app.config["TESTING"] = True
    return api_index.app


@pytest.fixture()
def client(flask_app):
    return flask_app.test_client()


@pytest.fixture()
def test_date():
    # Far future to avoid collisions with real data.
    return date(2099, 1, 6).isoformat()


@pytest.fixture()
def cleanup_ids(sb):
    created = {"workout_session_ids": set(), "exercise_log_ids": set()}
    yield created

    # Cleanup logs first, then sessions.
    for log_id in list(created["exercise_log_ids"]):
        sb.table("exercise_logs").delete().eq("id", log_id).execute()
    for sid in list(created["workout_session_ids"]):
        sb.table("workout_sessions").delete().eq("id", sid).execute()


def _get_or_create_exercise_id(sb, name: str) -> str:
    r = sb.table("exercises").select("id,name").eq("name", name).limit(1).execute()
    if r.data:
        return r.data[0]["id"]
    # Create minimal exercise row (schema allows nullable fields besides name)
    ins = sb.table("exercises").insert({"name": name}).execute()
    return ins.data[0]["id"]


def _fetch_session(sb, date_str: str, session_type: str):
    r = (
        sb.table("workout_sessions")
        .select("id,date,session_type,session_name,completed,rpe,comment,duration_min,energy_pre,logged_at")
        .eq("date", date_str)
        .eq("session_type", session_type)
        .limit(1)
        .execute()
    )
    return r.data[0] if r.data else None


def _fetch_exercise_log(sb, session_id: str, exercise_id: str):
    r = (
        sb.table("exercise_logs")
        .select("id,session_id,exercise_id,weight,reps,sets_json")
        .eq("session_id", session_id)
        .eq("exercise_id", exercise_id)
        .limit(1)
        .execute()
    )
    return r.data[0] if r.data else None


def test_api_log_writes_exercise_logs_and_session(sb, client, test_date, cleanup_ids):
    ex_name = f"IT Pause Bench Press {uuid.uuid4().hex[:8]}"
    ex_id = _get_or_create_exercise_id(sb, ex_name)

    payload = {
        "exercise": ex_name,
        "weight": 65,
        "reps": "5,5,5,5",
        "session_date": test_date,
        "session_type": "morning",
        "session_name": "IT Push A",
        "rpe": 7,
        "rir": 2,
        "pain_zone": "",
        "sets_json": [
            {"weight": 65, "reps": 5},
            {"weight": 65, "reps": 5},
            {"weight": 65, "reps": 5},
            {"weight": 65, "reps": 5},
        ],
    }

    res = client.post("/api/log", json=payload)
    assert res.status_code == 200, res.data

    ws = _fetch_session(sb, test_date, "morning")
    assert ws is not None
    cleanup_ids["workout_session_ids"].add(ws["id"])
    assert ws.get("session_name") in (None, "IT Push A", "Push A", "IT Push A ")

    log = _fetch_exercise_log(sb, ws["id"], ex_id)
    assert log is not None
    cleanup_ids["exercise_log_ids"].add(log["id"])
    assert float(log["weight"]) == 65.0
    assert log["reps"] == "5,5,5,5"


def test_api_log_session_marks_completed(sb, client, test_date, cleanup_ids):
    # Ensure session exists by logging an exercise first
    ex_name = f"IT Incline Bench {uuid.uuid4().hex[:8]}"
    ex_id = _get_or_create_exercise_id(sb, ex_name)
    res = client.post(
        "/api/log",
        json={
            "exercise": ex_name,
            "weight": 100,
            "reps": "8,8,8",
            "session_date": test_date,
            "session_type": "morning",
            "session_name": "IT Push A",
            "sets_json": [{"weight": 100, "reps": 8}] * 3,
        },
    )
    assert res.status_code == 200, res.data

    ws = _fetch_session(sb, test_date, "morning")
    assert ws is not None
    cleanup_ids["workout_session_ids"].add(ws["id"])
    log = _fetch_exercise_log(sb, ws["id"], ex_id)
    assert log is not None
    cleanup_ids["exercise_log_ids"].add(log["id"])

    res2 = client.post(
        "/api/log_session",
        json={
            "date": test_date,
            "rpe": 7,
            "comment": "integration test",
            "duration_min": 55,
            "energy_pre": 7,
            "session_name": "IT Push A",
            "session_type": "morning",
        },
    )
    assert res2.status_code == 200, res2.data

    ws2 = _fetch_session(sb, test_date, "morning")
    assert ws2 is not None
    assert bool(ws2.get("completed")) is True
    assert ws2.get("duration_min") in (55, "55")

