"""
GET /api/energy/daily    — Bilan énergétique du jour (BMR + EAT + NEAT)
GET /api/energy/history  — Historique N jours (?days=7, max 30)
"""
from __future__ import annotations

import time
import logging
from flask import Blueprint, jsonify, request
import energy as _energy

logger = logging.getLogger("trainingos.routes.energy_daily")

energy_daily_bp = Blueprint("energy_daily", __name__)

_CACHE:   dict = {}
_TTL_DAY  = 5  * 60   # 5 min — données du jour (fréquemment mises à jour)
_TTL_HIST = 10 * 60   # 10 min — historique (moins volatile)


@energy_daily_bp.route("/api/energy/daily", methods=["GET"])
def api_energy_daily():
    date      = request.args.get("date")
    cache_key = f"energy_daily_{date or 'today'}"

    now    = time.time()
    cached = _CACHE.get(cache_key)
    if cached and (now - cached["ts"]) < _TTL_DAY:
        return jsonify(cached["data"])

    data = _energy.compute_energy_daily(date)
    _CACHE[cache_key] = {"data": data, "ts": now}
    return jsonify(data)


@energy_daily_bp.route("/api/energy/history", methods=["GET"])
def api_energy_history():
    try:
        days = min(int(request.args.get("days", 7)), 30)
    except ValueError:
        days = 7
    cache_key = f"energy_history_{days}"

    now    = time.time()
    cached = _CACHE.get(cache_key)
    if cached and (now - cached["ts"]) < _TTL_HIST:
        return jsonify(cached["data"])

    data = _energy.compute_energy_history(days)
    _CACHE[cache_key] = {"data": data, "ts": now}
    return jsonify(data)
