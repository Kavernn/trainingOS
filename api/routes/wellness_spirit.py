from flask import Blueprint, jsonify, request

wellness_spirit_bp = Blueprint("wellness_spirit", __name__)


# Wellness breathwork: writes technique_id (str key e.g. "coherence"), technique (display name),
# duration_min, logged_at. Distinct from Spirit breathwork (protocol: calm_storm/ignite/stillness).
# Both share breathwork_sessions table; reads are partitioned by technique_id IS NOT NULL (wellness)
# vs protocol IS NOT NULL (spirit) — do not remove those filters.
@wellness_spirit_bp.route("/api/breathwork/techniques")
def api_breathwork_techniques():
    from breathwork import TECHNIQUES
    return jsonify(TECHNIQUES)


@wellness_spirit_bp.route("/api/breathwork/log", methods=["POST"])
def api_breathwork_log():
    from breathwork import log_session as bw_log
    data = request.get_json(silent=True) or {}
    technique_id = data.get("technique_id")
    if not technique_id:
        return jsonify({"error": "technique_id requis"}), 400
    try:
        session = bw_log(
            technique_id = technique_id,
            duration_sec = int(data.get("duration_sec", 0)),
            cycles       = int(data.get("cycles", 0)),
        )
        return jsonify(session), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@wellness_spirit_bp.route("/api/breathwork/history")
def api_breathwork_history():
    from breathwork import get_history as bw_history
    try:
        days = int(request.args.get("days", 30))
    except ValueError:
        days = 30
    return jsonify(bw_history(days))


@wellness_spirit_bp.route("/api/breathwork/stats")
def api_breathwork_stats():
    from breathwork import get_stats as bw_stats_fn
    try:
        days = int(request.args.get("days", 7))
    except ValueError:
        days = 7
    return jsonify(bw_stats_fn(days))


@wellness_spirit_bp.route("/api/self_care/habits")
def api_self_care_habits():
    from self_care import get_habits
    return jsonify(get_habits())


@wellness_spirit_bp.route("/api/self_care/habits", methods=["POST"])
def api_self_care_habits_add():
    from self_care import add_habit
    data = request.get_json(silent=True) or {}
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"error": "name requis"}), 400
    habit = add_habit(
        name     = name,
        icon     = data.get("icon", "star.fill"),
        category = data.get("category", "mental"),
    )
    return jsonify(habit), 201


@wellness_spirit_bp.route("/api/self_care/habits/<habit_id>", methods=["DELETE"])
def api_self_care_habits_delete(habit_id: str):
    from self_care import delete_habit
    deleted = delete_habit(habit_id)
    if not deleted:
        return jsonify({"error": "Habitude introuvable"}), 404
    return jsonify({"deleted": habit_id})


@wellness_spirit_bp.route("/api/self_care/log", methods=["POST"])
def api_self_care_log():
    from self_care import log_today as sc_log
    data = request.get_json(silent=True) or {}
    habit_ids = data.get("habit_ids", [])
    return jsonify(sc_log(habit_ids))


@wellness_spirit_bp.route("/api/self_care/today")
def api_self_care_today():
    from self_care import get_today_status
    return jsonify(get_today_status())


@wellness_spirit_bp.route("/api/self_care/streaks")
def api_self_care_streaks():
    from self_care import get_streaks
    return jsonify(get_streaks())


@wellness_spirit_bp.route("/api/mental_health/summary")
def api_mental_health_summary():
    from mental_health_dashboard import get_summary as mh_summary
    try:
        days = int(request.args.get("days", 7))
    except ValueError:
        days = 7
    return jsonify(mh_summary(days))
