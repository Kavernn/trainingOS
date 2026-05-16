"""GET /api/body_budget — Daily Body Budget score."""
from __future__ import annotations
import time
import logging
from flask import Blueprint, jsonify
import body_budget as _bb

logger = logging.getLogger("trainingos.routes.body_budget")

body_budget_bp = Blueprint("body_budget", __name__)

_CACHE: dict = {}
_TTL = 30 * 60  # 30 minutes


@body_budget_bp.route("/api/body_budget", methods=["GET"])
def api_body_budget():
    now = time.time()
    cached = _CACHE.get("result")
    if cached and (now - cached["ts"]) < _TTL:
        return jsonify(cached["data"])

    data = _bb.compute()
    _CACHE["result"] = {"data": data, "ts": now}
    return jsonify(data)
