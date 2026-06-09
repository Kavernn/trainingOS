from flask import Blueprint, jsonify
import training_heatmap_engine

training_heatmap_bp = Blueprint("training_heatmap", __name__)


@training_heatmap_bp.route("/api/training-heatmap")
def get_training_heatmap():
    return jsonify(training_heatmap_engine.compute())
