from flask import Blueprint, jsonify, request
from datetime import date, timedelta

from utils import _today_mtl

wellness_mood_bp = Blueprint("wellness_mood", __name__)


@wellness_mood_bp.route("/api/mood/emotions")
def api_mood_emotions():
    from mood import EMOTIONS
    return jsonify(EMOTIONS)


@wellness_mood_bp.route("/api/mood/log", methods=["POST"])
def api_mood_log():
    from mood import save_mood_entry
    data = request.get_json(silent=True) or {}
    score = data.get("score")
    if score is None:
        return jsonify({"error": "score requis (1-10)"}), 400
    try:
        entry = save_mood_entry(
            score    = int(score),
            emotions = data.get("emotions", []),
            notes    = data.get("notes"),
            triggers = data.get("triggers"),
        )
        from routes.daily_brief import invalidate_cache as _brief_invalidate
        _brief_invalidate()
        return jsonify(entry), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@wellness_mood_bp.route("/api/mood/history")
def api_mood_history():
    from mood import get_history as mood_get_history
    try:
        days   = int(request.args.get("days", 90))
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        days, limit, offset = 90, 20, 0
    return jsonify(mood_get_history(days, limit, offset))


@wellness_mood_bp.route("/api/mood/rpe")
def api_mood_rpe():
    """Return mean daily session RPE for the requested recent window."""
    try:
        days = int(request.args.get("days", 90))
    except (TypeError, ValueError):
        return jsonify({"error": "days must be an integer between 1 and 365"}), 400
    if not 1 <= days <= 365:
        return jsonify({"error": "days must be an integer between 1 and 365"}), 400

    import db as _db

    cutoff = (date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
    rows: list[dict] = []
    page_size = 500
    offset = 0
    while True:
        page = _db.get_workout_sessions(limit=page_size, offset=offset, since=cutoff) or []
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size

    totals: dict[str, tuple[float, int]] = {}
    for row in rows:
        day = str(row.get("date") or "")[:10]
        raw_rpe = row.get("rpe")
        if not day or raw_rpe is None:
            continue
        total, count = totals.get(day, (0.0, 0))
        totals[day] = (total + float(raw_rpe), count + 1)

    return jsonify({
        "rpe_by_date": {
            day: round(total / count, 1)
            for day, (total, count) in sorted(totals.items())
        }
    })


@wellness_mood_bp.route("/api/mood/today")
def api_mood_today():
    from mood import get_today_entry as mood_today_entry
    entry = mood_today_entry()
    return jsonify(entry) if entry else jsonify(None)


@wellness_mood_bp.route("/api/mood/check_due")
def api_mood_check_due():
    from mood import check_due as mood_check_due
    return jsonify(mood_check_due())


@wellness_mood_bp.route("/api/mood/insights")
def api_mood_insights():
    from mood import generate_insights as mood_insights
    try:
        days = int(request.args.get("days", 30))
    except ValueError:
        days = 30
    return jsonify(mood_insights(days))


@wellness_mood_bp.route("/api/journal/today_prompt")
def api_journal_today_prompt():
    from journal import get_today_prompt
    return jsonify({"prompt": get_today_prompt()})


@wellness_mood_bp.route("/api/journal/save", methods=["POST"])
def api_journal_save():
    from journal import save_entry as journal_save
    data = request.get_json(silent=True) or {}
    prompt     = data.get("prompt", "")
    content    = data.get("content", "")
    mood_score = data.get("mood_score")
    try:
        entry = journal_save(prompt, content, mood_score=mood_score)
        return jsonify(entry), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@wellness_mood_bp.route("/api/journal/entries")
def api_journal_entries():
    from journal import get_entries
    try:
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        limit, offset = 20, 0
    return jsonify(get_entries(limit, offset))


@wellness_mood_bp.route("/api/journal/search")
def api_journal_search():
    from journal import search_entries
    q = request.args.get("q", "")
    return jsonify(search_entries(q))
