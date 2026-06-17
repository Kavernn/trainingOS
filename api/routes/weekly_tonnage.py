from flask import Blueprint, jsonify
import db
from utils import _today_mtl
from datetime import date, timedelta

weekly_tonnage_bp = Blueprint("weekly_tonnage", __name__)


@weekly_tonnage_bp.route("/api/weekly-tonnage")
def get_weekly_tonnage():
    today = date.fromisoformat(_today_mtl())
    monday = (today - timedelta(days=today.weekday())).isoformat()
    rows = db.get_weekly_tonnage(weeks=2) or []
    current = next((r for r in reversed(rows) if r.get("week_start", "") >= monday), None)
    volume = int(current["total_volume"]) if current else 0
    return jsonify({"volume": volume})
