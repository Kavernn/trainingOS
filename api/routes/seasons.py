from __future__ import annotations
from flask import Blueprint, jsonify, request
import db
import season_engine

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
