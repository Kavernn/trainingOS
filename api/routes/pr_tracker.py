from flask import Blueprint, jsonify
import pr_tracker_engine

pr_tracker_bp = Blueprint("pr_tracker", __name__)


@pr_tracker_bp.route("/api/pr-tracker")
def get_pr_tracker():
    return jsonify(pr_tracker_engine.compute())
