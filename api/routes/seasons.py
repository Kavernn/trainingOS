from __future__ import annotations
from flask import Blueprint, jsonify, request
import db
import season_engine
from utils import _today_mtl

seasons_bp = Blueprint("seasons", __name__)


@seasons_bp.route("/api/seasons", methods=["GET"])
def list_seasons():
    rows = db.get_all_seasons()
    return jsonify(rows), 200


@seasons_bp.route("/api/seasons/active", methods=["GET"])
def get_active():
    row = db.get_active_season()
    if row is None:
        return jsonify({}), 200
    return jsonify(row), 200


@seasons_bp.route("/api/seasons/<season_id>", methods=["GET"])
def get_season(season_id: str):
    row = db.get_season_by_id(season_id)
    if row is None:
        return jsonify({"error": "Not found"}), 404
    snaps = db.get_season_snapshots(season_id)
    return jsonify({**row, "snapshots": snaps}), 200


@seasons_bp.route("/api/seasons/start", methods=["POST"])
def start_season():
    existing = db.get_active_season()
    if existing:
        return jsonify({"error": "Une saison est déjà active"}), 409
    number  = db.get_next_season_number()
    today   = str(season_engine._today())
    season  = db.create_season(number=number, started_at=today)
    if not season:
        return jsonify({"error": "Erreur création saison"}), 500
    snap = season_engine.compute_snapshot(as_of_date=today)
    db.save_season_snapshot(season["id"], "start", snap)
    return jsonify(season), 201


@seasons_bp.route("/api/seasons/<season_id>/close", methods=["POST"])
def close_season(season_id: str):
    report = season_engine.close_season(season_id)
    if report is None:
        return jsonify({"error": "Saison introuvable"}), 404
    return jsonify(report), 200


@seasons_bp.route("/api/seasons/comparison", methods=["GET"])
def get_seasons_comparison():
    """Current season live stats vs previous season end snapshot for StatsView."""
    from datetime import date, timedelta
    import db as _db

    active = _db.get_active_season()
    if active is None:
        return jsonify({"current": None, "previous": None}), 200

    season_start = (active.get("started_at") or "")[:10]

    # ── Current season — live stats ───────────────────────────────────────
    # Avg weekly volume
    if season_start:
        weeks_active = max(1, (date.fromisoformat(_today_mtl()) - date.fromisoformat(season_start)).days / 7)
    else:
        weeks_active = 1
    tonnage_rows = _db.get_weekly_tonnage(min(int(weeks_active) + 2, 52))
    vols = [r.get("total_volume", 0) for r in (tonnage_rows or [])
            if (r.get("week_start") or "") >= season_start and r.get("total_volume")]
    avg_vol_week = round(sum(vols) / len(vols)) if vols else None

    # PSS avg since season start
    all_pss = _db.get_pss_records(limit=200)
    pss_in_season = [r["score"] for r in (all_pss or [])
                     if (r.get("date") or r.get("recorded_at") or "")[:10] >= season_start
                     and r.get("score") is not None]
    pss_avg = round(sum(pss_in_season) / len(pss_in_season)) if pss_in_season else None

    # Weight delta: start snapshot weight vs latest body weight
    start_snaps = _db.get_season_snapshots(active["id"])
    start_snap  = next((s for s in start_snaps if s.get("type") == "start"), None)
    # limit=30 : latest weight reste bw_logs[0] (ordre date DESC), mais permet
    # de retrouver la dernière mesure body_fat non-null quand elle n'est pas
    # dans l'entrée la plus récente (body_fat est optionnel par ligne).
    bw_logs     = _db.get_body_weight_logs(limit=30)
    latest_weight = bw_logs[0].get("weight") if bw_logs else None
    weight_delta = None
    if start_snap and start_snap.get("weight_lbs") and latest_weight:
        weight_delta = round(float(latest_weight) - float(start_snap["weight_lbs"]), 1)

    # Start/end values exposed for the "avant → après" UI (commit 4). Pour
    # body_fat, la série de snapshots ne populate pas encore body_fat_pct
    # (compute_snapshot ne l'écrit pas), donc body_fat_start sera souvent
    # None jusqu'à ce que ce soit ajouté — à faire dans un commit séparé.
    weight_start_lbs = (
        round(float(start_snap["weight_lbs"]), 1)
        if start_snap and start_snap.get("weight_lbs") else None
    )
    weight_end_lbs = round(float(latest_weight), 1) if latest_weight else None
    body_fat_start = (
        float(start_snap["body_fat_pct"])
        if start_snap and start_snap.get("body_fat_pct") is not None else None
    )
    # body_fat_end : dernière mesure non-null, uniquement si ≤ 14 jours (sinon
    # on ne présente pas une valeur périmée comme "actuelle"). Symétrique du
    # garde-fou appliqué à body_fat_pct dans season_engine.compute_snapshot.
    try:
        today_date = date.fromisoformat(_today_mtl())
        bf_cutoff = today_date - timedelta(days=14)
    except ValueError:
        bf_cutoff = None
    def _recent_body_fat(logs):
        for r in logs:
            if r.get("body_fat") is None:
                continue
            try:
                d = date.fromisoformat((r.get("date") or "")[:10])
            except ValueError:
                continue
            if bf_cutoff is None or d >= bf_cutoff:
                return float(r["body_fat"])
        return None
    body_fat_end = _recent_body_fat(bw_logs)

    # Phoenix: not easily computed live here — skip unless snapshot available
    phoenix_avg = start_snap.get("phoenix_avg") if start_snap else None

    # Sessions count since start
    all_sessions = _db.get_workout_sessions(limit=500)
    sessions_count = sum(
        1 for s in (all_sessions or [])
        if (s.get("date") or "") >= season_start and s.get("completed")
    )

    current = {
        "title":            active.get("custom_title") or active.get("generated_title") or f"Saison {active.get('number', '')}",
        "volume_avg_week":  avg_vol_week,
        "sessions_count":   sessions_count,
        "pss_avg":          pss_avg,
        "weight_delta":     weight_delta,
        "weight_start_lbs": weight_start_lbs,
        "weight_end_lbs":   weight_end_lbs,
        "body_fat_start":   body_fat_start,
        "body_fat_end":     body_fat_end,
        "phoenix_avg":      phoenix_avg,
    }

    # ── Previous season — end snapshot ───────────────────────────────────
    all_seasons = _db.get_all_seasons()
    completed   = [s for s in (all_seasons or []) if s.get("status") == "completed"]
    previous_data = None
    if completed:
        prev      = max(completed, key=lambda s: s.get("number") or 0)
        prev_snaps = _db.get_season_snapshots(prev["id"])
        end_snap       = next((s for s in prev_snaps if s.get("type") == "end"),   None)
        start_snap_prev = next((s for s in prev_snaps if s.get("type") == "start"), None)
        if end_snap:
            prev_weight_delta = None
            prev_weight_start = None
            prev_weight_end   = None
            if start_snap_prev and start_snap_prev.get("weight_lbs") and end_snap.get("weight_lbs"):
                prev_weight_start = round(float(start_snap_prev["weight_lbs"]), 1)
                prev_weight_end   = round(float(end_snap["weight_lbs"]), 1)
                prev_weight_delta = round(prev_weight_end - prev_weight_start, 1)
            prev_bf_start = (
                float(start_snap_prev["body_fat_pct"])
                if start_snap_prev and start_snap_prev.get("body_fat_pct") is not None else None
            )
            prev_bf_end = (
                float(end_snap["body_fat_pct"])
                if end_snap.get("body_fat_pct") is not None else None
            )
            previous_data = {
                "title":            prev.get("custom_title") or prev.get("generated_title") or f"Saison {prev.get('number', '')}",
                "volume_avg_week":  None,
                "sessions_count":   None,
                "pss_avg":          end_snap.get("pss_score"),
                "weight_delta":     prev_weight_delta,
                "weight_start_lbs": prev_weight_start,
                "weight_end_lbs":   prev_weight_end,
                "body_fat_start":   prev_bf_start,
                "body_fat_end":     prev_bf_end,
                "phoenix_avg":      end_snap.get("phoenix_avg"),
            }

    return jsonify({"current": current, "previous": previous_data}), 200


@seasons_bp.route("/api/seasons/<season_id>", methods=["PATCH"])
def update_season(season_id: str):
    body = request.get_json(silent=True) or {}
    allowed = {"custom_title", "personal_note"}
    fields  = {k: v for k, v in body.items() if k in allowed}
    if not fields:
        return jsonify({"error": "Aucun champ valide"}), 400
    updated = db.update_season(season_id, fields)
    if updated is None:
        return jsonify({"error": "Erreur mise à jour"}), 500
    return jsonify(updated), 200
