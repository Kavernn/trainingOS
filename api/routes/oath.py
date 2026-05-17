from __future__ import annotations
from flask import Blueprint, jsonify, request
import db

oath_bp = Blueprint("oath", __name__)


@oath_bp.route("/api/oath/current", methods=["GET"])
def get_current():
    row = db.get_current_oath()
    if row is None:
        return jsonify({}), 200
    return jsonify(row), 200


@oath_bp.route("/api/oath/versions", methods=["GET"])
def get_versions():
    rows = db.get_oath_versions()
    return jsonify(rows), 200


@oath_bp.route("/api/oath", methods=["POST"])
def save():
    body = request.get_json(silent=True) or {}
    text = body.get("text", "").strip()
    if not text:
        return jsonify({"error": "text requis"}), 400
    word_count = body.get("word_count", len(text.split()))
    row = db.save_oath(text=text, word_count=int(word_count))
    if row is None:
        return jsonify({"error": "Erreur sauvegarde"}), 500
    return jsonify(row), 201


@oath_bp.route("/api/oath/recall", methods=["POST"])
def log_recall():
    body = request.get_json(silent=True) or {}
    oath_id = body.get("oath_id", "")
    trigger  = body.get("trigger", "manual")
    valid_triggers = {"streak_reset", "phoenix_decline", "emergency", "milestone", "manual"}
    if trigger not in valid_triggers:
        return jsonify({"error": "trigger invalide"}), 400
    db.log_oath_recall(oath_id=oath_id, trigger=trigger)
    return jsonify({"ok": True}), 200


@oath_bp.route("/api/oath/recalls", methods=["GET"])
def get_recalls():
    limit = int(request.args.get("limit", 20))
    rows  = db.get_oath_recalls(limit=limit)
    return jsonify(rows), 200
