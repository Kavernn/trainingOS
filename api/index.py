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
    auth = request.headers.get("Authorization", "")
    if auth != f"Bearer {_API_KEY}":
        return jsonify({"error": "Unauthorized"}), 401

# ── Wearable / Apple Watch routes ───────────────────────────
wearable.register_routes(app)

# ── Schema health-check at startup ──────────────────────────
import db as _db_startup
_db_startup.ensure_schema_migrations()

# ── Register blueprints ──────────────────────────────────────
from routes.profile    import profile_bp
from routes.nutrition  import nutrition_bp
from routes.ai_coach   import ai_coach_bp
from routes.goals      import goals_bp
from routes.analytics  import analytics_bp
from routes.workout    import workout_bp
from routes.data_views import data_views_bp
from routes.wellness   import wellness_bp
from routes.coach_tip  import coach_tip_bp

app.register_blueprint(profile_bp)
app.register_blueprint(nutrition_bp)
app.register_blueprint(ai_coach_bp)
app.register_blueprint(goals_bp)
app.register_blueprint(analytics_bp)
app.register_blueprint(workout_bp)
app.register_blueprint(data_views_bp)
app.register_blueprint(wellness_bp)
app.register_blueprint(coach_tip_bp)


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
