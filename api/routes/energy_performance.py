from flask import Blueprint, jsonify
import energy_performance_engine

energy_performance_bp = Blueprint("energy_performance", __name__)


@energy_performance_bp.route("/api/energy-performance")
def get_energy_performance():
    return jsonify(energy_performance_engine.compute())
