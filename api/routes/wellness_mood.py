from flask import Blueprint, jsonify, request

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
