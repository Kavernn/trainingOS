# api/index.py — app factory
from __future__ import annotations
import os, sys, socket, logging
from pathlib import Path

# ── Logging setup ────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("trainingos")

# Charge le .env pour le dev local (no-op sur Vercel)
try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / '.env')
except ImportError:
    pass

# ✅ Ajoute /api au path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from flask import Flask, jsonify
import wearable

# ── App config ──────────────────────────────────────────────
_API_DIR  = os.path.dirname(os.path.abspath(__file__))
BASE_DIR  = os.path.dirname(_API_DIR)  # remonte à la racine

app = Flask(__name__)
_secret_key = os.getenv("SECRET_KEY", "")
if not _secret_key:
    if os.getenv("VERCEL"):
        raise RuntimeError("SECRET_KEY env var must be set in Vercel dashboard")
    _secret_key = "trainingos-dev-only-not-for-production"
    logger.warning("SECRET_KEY not set — using insecure default (dev only)")
elif _secret_key == "trainingos-secret-change-in-prod" and os.getenv("VERCEL"):
    raise RuntimeError("SECRET_KEY must not use the placeholder value in production")
app.secret_key = _secret_key

# ── Global error handler ─────────────────────────────────────
from werkzeug.exceptions import HTTPException

@app.errorhandler(Exception)
def _handle_exception(e):
    if isinstance(e, HTTPException):
        return jsonify({"error": e.description}), e.code
    logger.exception("Unhandled exception in route")
    return jsonify({"error": "Erreur interne — réessaie"}), 500

# ── API Key auth middleware ───────────────────────────────────
_API_KEY = os.getenv("TRAININGOS_API_KEY", "")

@app.before_request
def _require_api_key():
    from flask import request
    # Explicit local/test bypass to keep unit tests independent from env secrets.
    if app.config.get("TESTING"):
        return
    # Skip auth when key not configured (local dev without env var)
    if not _API_KEY:
        return
    if request.path in ("/favicon.ico", "/favicon.png"):
        return
    auth = request.headers.get("Authorization", "")
    if auth != f"Bearer {_API_KEY}":
        return jsonify({"error": "Unauthorized"}), 401

# ── Wearable / Apple Watch routes ───────────────────────────
wearable.register_routes(app)

# ── Schema health-check at startup ──────────────────────────
import db as _db_startup
_db_startup.ensure_schema_migrations()

# ── Register blueprints ──────────────────────────────────────
from routes.profile      import profile_bp
from routes.nutrition_entries   import nutrition_bp
from routes.nutrition_scan      import nutrition_scan_bp
from routes.nutrition_food      import nutrition_food_bp
from routes.nutrition_templates import nutrition_templates_bp
from routes.nutrition_analytics import nutrition_analytics_bp
from routes.nutrition_hydration import nutrition_hydration_bp
from routes.ai_coach_tools   import ai_coach_tools_bp
from routes.ai_coach_program import ai_coach_program_bp
from routes.ai_coach_memory  import ai_coach_memory_bp
from routes.goals        import goals_bp
from routes.analytics_load  import analytics_load_bp
from routes.analytics_coach import analytics_coach_bp
from routes.analytics_stats import analytics_stats_bp
from routes.analytics_body  import analytics_body_bp
from routes.workout_logging   import workout_bp
from routes.workout_hiit      import workout_hiit_bp
from routes.workout_exercises import workout_exercises_bp
from routes.workout_programs  import workout_programs_bp
from routes.workout_schedule  import workout_schedule_bp
from routes.data_views   import data_views_bp
from routes.wellness          import wellness_bp
from routes.wellness_recovery import wellness_recovery_bp
from routes.wellness_stress   import wellness_stress_bp
from routes.wellness_mood     import wellness_mood_bp
from routes.wellness_spirit   import wellness_spirit_bp
from routes.coach_tip    import coach_tip_bp
from routes.patterns     import patterns_bp
from routes.readiness    import readiness_bp
from routes.time_capsule import time_capsule_bp
from routes.workout_dna  import workout_dna_bp
from routes.plateau      import plateau_bp
from routes.ritual       import ritual_bp
from routes.war_room     import war_room_bp
from routes.spirit       import spirit_bp
from routes.oath         import oath_bp
from routes.seasons      import seasons_bp
from routes.gym_finder   import gym_finder_bp
from routes.cardio_metrics import cardio_metrics_bp
from routes.energy_daily  import energy_daily_bp
from routes.coach_insights       import coach_insights_bp
from routes.proactive_insights   import proactive_insights_bp
from routes.daily_brief          import daily_brief_bp
from routes.velocity             import velocity_bp
from routes.compound             import compound_bp
from routes.temporal             import temporal_bp
from routes.portrait             import portrait_bp
from routes.behavioral_prs       import behavioral_prs_bp
from routes.rupture              import rupture_bp
from routes.performance_conditions import performance_conditions_bp
from routes.sleep_debt           import sleep_debt_bp
from routes.training_load        import training_load_bp
from routes.ideal_week           import ideal_week_bp
from routes.nutrition_performance import nutrition_performance_bp
from routes.comeback_arc         import comeback_arc_bp
from routes.weekly_momentum      import weekly_momentum_bp
from routes.weekly_tonnage       import weekly_tonnage_bp
from routes.optimal_day          import optimal_day_bp
from routes.muscle_balance       import muscle_balance_bp
from routes.muscle_imbalance     import muscle_imbalance_bp
from routes.muscle_volume        import muscle_volume_bp
from routes.consistency          import consistency_bp
from routes.volume_progression   import volume_progression_bp
from routes.sleep_hrv            import sleep_hrv_bp
from routes.stress_load          import stress_load_bp
from routes.progressive_overload import progressive_overload_bp
from routes.session_quality      import session_quality_bp
from routes.training_heatmap     import training_heatmap_bp
from routes.body_weight_trend    import body_weight_trend_bp
from routes.energy_performance   import energy_performance_bp
from routes.pr_tracker           import pr_tracker_bp
from routes.soreness_fatigue     import soreness_fatigue_bp
from routes.sleep_quality        import sleep_quality_bp
from routes.workout_duration     import workout_duration_bp
from routes.smart_alarm          import smart_alarm_bp
from routes.session_progression  import session_progression_bp

app.register_blueprint(profile_bp)
app.register_blueprint(nutrition_bp)
app.register_blueprint(nutrition_scan_bp)
app.register_blueprint(nutrition_food_bp)
app.register_blueprint(nutrition_templates_bp)
app.register_blueprint(nutrition_analytics_bp)
app.register_blueprint(nutrition_hydration_bp)
app.register_blueprint(ai_coach_tools_bp)
app.register_blueprint(ai_coach_program_bp)
app.register_blueprint(ai_coach_memory_bp)
app.register_blueprint(goals_bp)
app.register_blueprint(analytics_load_bp)
app.register_blueprint(analytics_coach_bp)
app.register_blueprint(analytics_stats_bp)
app.register_blueprint(analytics_body_bp)
app.register_blueprint(workout_bp)
app.register_blueprint(workout_hiit_bp)
app.register_blueprint(workout_exercises_bp)
app.register_blueprint(workout_programs_bp)
app.register_blueprint(workout_schedule_bp)
app.register_blueprint(data_views_bp)
app.register_blueprint(wellness_bp)
app.register_blueprint(wellness_recovery_bp)
app.register_blueprint(wellness_stress_bp)
app.register_blueprint(wellness_mood_bp)
app.register_blueprint(wellness_spirit_bp)
app.register_blueprint(coach_tip_bp)
app.register_blueprint(patterns_bp)
app.register_blueprint(readiness_bp)
app.register_blueprint(time_capsule_bp)
app.register_blueprint(workout_dna_bp)
app.register_blueprint(plateau_bp)
app.register_blueprint(ritual_bp)
app.register_blueprint(war_room_bp)
app.register_blueprint(spirit_bp)
app.register_blueprint(oath_bp)
app.register_blueprint(seasons_bp)
app.register_blueprint(gym_finder_bp)
app.register_blueprint(cardio_metrics_bp)
app.register_blueprint(energy_daily_bp)
app.register_blueprint(coach_insights_bp)
app.register_blueprint(proactive_insights_bp)
app.register_blueprint(daily_brief_bp)
app.register_blueprint(velocity_bp)
app.register_blueprint(compound_bp)
app.register_blueprint(temporal_bp)
app.register_blueprint(portrait_bp)
app.register_blueprint(behavioral_prs_bp)
app.register_blueprint(rupture_bp)
app.register_blueprint(performance_conditions_bp)
app.register_blueprint(sleep_debt_bp)
app.register_blueprint(training_load_bp)
app.register_blueprint(ideal_week_bp)
app.register_blueprint(nutrition_performance_bp)
app.register_blueprint(comeback_arc_bp)
app.register_blueprint(weekly_momentum_bp)
app.register_blueprint(weekly_tonnage_bp)
app.register_blueprint(optimal_day_bp)
app.register_blueprint(muscle_balance_bp)
app.register_blueprint(muscle_imbalance_bp)
app.register_blueprint(muscle_volume_bp)
app.register_blueprint(consistency_bp)
app.register_blueprint(volume_progression_bp)
app.register_blueprint(sleep_hrv_bp)
app.register_blueprint(stress_load_bp)
app.register_blueprint(progressive_overload_bp)
app.register_blueprint(session_quality_bp)
app.register_blueprint(training_heatmap_bp)
app.register_blueprint(body_weight_trend_bp)
app.register_blueprint(energy_performance_bp)
app.register_blueprint(pr_tracker_bp)
app.register_blueprint(soreness_fatigue_bp)
app.register_blueprint(sleep_quality_bp)
app.register_blueprint(workout_duration_bp)
app.register_blueprint(smart_alarm_bp)
app.register_blueprint(session_progression_bp)


# ── Dev server ───────────────────────────────────────────────
def find_free_port(start=5000, end=5100):
    for port in range(start, end):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("0.0.0.0", port))
                return port
            except OSError:
                continue
    raise RuntimeError("Aucun port libre")


if __name__ == "__main__":
    port = int(os.environ.setdefault("PORT", str(find_free_port())))
    logger.info("TrainingOS API → http://localhost:%d", port)
    app.run(debug=True, use_reloader=True, host="0.0.0.0", port=port)
