# api/index.py — app factory (~150 lignes)
from __future__ import annotations
import os, sys, socket, logging
from threading import Timer
import webbrowser
from datetime import datetime
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

# Sur Vercel, templates/static sont à la racine
TEMPLATES = os.path.join(BASE_DIR, "templates")
STATIC    = os.path.join(BASE_DIR, "static")

app = Flask(
    __name__,
    template_folder = TEMPLATES,
    static_folder   = STATIC,
)
_SECRET_KEY_DEFAULT = "trainingos-secret-change-in-prod"
_secret_key = os.getenv("SECRET_KEY", _SECRET_KEY_DEFAULT)
if os.getenv("VERCEL") and _secret_key == _SECRET_KEY_DEFAULT:
    raise RuntimeError("SECRET_KEY must be set to a secure value in production (Vercel env vars)")
app.secret_key = _secret_key

UPLOAD_FOLDER      = os.path.join(BASE_DIR, "static", "uploads")
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# ── Global error handler ─────────────────────────────────────
import traceback as _tb

@app.errorhandler(Exception)
def _handle_exception(e):
    _tb.print_exc()  # log serveur uniquement, jamais envoyé au client
    code = getattr(e, "code", 500)
    if isinstance(code, int) and 400 <= code < 500:
        return jsonify({"error": str(e)}), code
    return jsonify({"error": "Erreur interne — réessaie"}), 500

# ── API Key auth middleware ───────────────────────────────────
_API_KEY = os.getenv("TRAININGOS_API_KEY", "")

@app.before_request
def _require_api_key():
    from flask import request
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
from routes.profile   import profile_bp
from routes.nutrition import nutrition_bp
from routes.ai_coach  import ai_coach_bp
from routes.goals     import goals_bp
from routes.analytics import analytics_bp
from routes.workout   import workout_bp
from routes.data_views import data_views_bp
from routes.wellness  import wellness_bp

app.register_blueprint(profile_bp)
app.register_blueprint(nutrition_bp)
app.register_blueprint(ai_coach_bp)
app.register_blueprint(goals_bp)
app.register_blueprint(analytics_bp)
app.register_blueprint(workout_bp)
app.register_blueprint(data_views_bp)
app.register_blueprint(wellness_bp)


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
    # PORT stocké dans l'env pour que le child du reloader utilise le même
    port = int(os.environ.setdefault("PORT", str(find_free_port())))
    url  = f"http://localhost:{port}"
    logger.info("TrainingOS → %s", url)
    # N'ouvre le navigateur que dans le processus principal (pas le child du reloader)
    if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
        Timer(1.0, lambda: webbrowser.open(url)).start()
    app.run(debug=True, use_reloader=True, host="0.0.0.0", port=port)
