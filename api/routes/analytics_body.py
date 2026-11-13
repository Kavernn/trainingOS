from flask import Blueprint, jsonify, request
from datetime import timedelta
import logging
from utils import _today_mtl

logger = logging.getLogger("trainingos")

analytics_body_bp = Blueprint("analytics_body", __name__)


@analytics_body_bp.route("/api/pain_journal")
def api_pain_journal():
    """Return exercise pain zones history for the injury journal."""
    import db as _db
    entries = _db.get_pain_journal(limit=200)
    by_exercise: dict = {}
    for e in entries:
        ex = e.get("exercise") or "Inconnu"
        by_exercise.setdefault(ex, {"exercise": ex, "count": 0, "zones": [], "last_date": None, "entries": []})
        by_exercise[ex]["count"] += 1
        zone = e.get("pain_zone")
        if zone and zone not in by_exercise[ex]["zones"]:
            by_exercise[ex]["zones"].append(zone)
        if e.get("date") and (by_exercise[ex]["last_date"] is None or str(e["date"]) > str(by_exercise[ex]["last_date"])):
            by_exercise[ex]["last_date"] = e.get("date")
        by_exercise[ex]["entries"].append(e)
    result = sorted(by_exercise.values(), key=lambda x: (x["last_date"] or ""), reverse=True)
    return jsonify({"entries": entries, "by_exercise": result})

@analytics_body_bp.route("/api/body/backfill_navy_bf")
def api_backfill_navy_bf():
    """Backfill body_fat via Navy formula for historical entries missing it.

    ?dry_run=true  → preview only, no writes.
    ?apply=true    → writes body_fat (and only body_fat) on recoverable entries.
    Re-running after a full backfill is safe: all entries have body_fat,
    skip logic + .is_(null) guard ensure zero rows are touched again.
    """
    import db as _db
    from body_weight import compute_navy_bf

    dry_run = request.args.get("dry_run", "").lower() in ("1", "true")
    apply   = request.args.get("apply",   "").lower() in ("1", "true")
    if not dry_run and not apply:
        return jsonify({"error": "Paramètre requis : ?dry_run=true ou ?apply=true"}), 400

    profile   = _db.get_profile() or {}
    height_cm = float(profile.get("height") or 0) or None
    sex       = str(profile.get("sex") or "m")
    if not height_cm:
        return jsonify({"error": "height absent du profil — Navy impossible"}), 422

    logs = _db.get_body_weight_logs(limit=500) or []
    recoverable = []
    skipped     = 0

    for row in logs:
        if row.get("body_fat") is not None:
            skipped += 1
            continue
        waist = row.get("waist_cm")
        neck  = row.get("neck_cm")
        hips  = row.get("hips_cm")
        date  = str(row.get("date") or "")
        if not waist or not neck:
            skipped += 1
            continue
        bf = compute_navy_bf(float(waist), float(neck), height_cm, sex,
                             float(hips) if hips else None)
        if bf is None:
            skipped += 1
            continue
        recoverable.append({"date": date, "waist_cm": waist, "neck_cm": neck, "body_fat": bf})

    if dry_run:
        return jsonify({"preview": recoverable, "skipped": skipped, "total": len(logs)})

    # apply=true — écrit UNIQUEMENT body_fat, jamais les mesures saisies
    applied = 0
    errors  = []
    for entry in recoverable:
        try:
            _db._client.table("body_weight_logs") \
                .update({"body_fat": entry["body_fat"]}) \
                .eq("date", entry["date"]) \
                .is_("body_fat", "null") \
                .execute()
            applied += 1
        except Exception as e:
            errors.append(f"{entry['date']}: {e}")

    return jsonify({"applied": applied, "skipped": skipped, "errors": errors})
