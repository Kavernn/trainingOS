"""GET /api/budget/status, POST /api/budget/log."""
from flask import Blueprint, jsonify, request
import budget as _b
import db_budget
from utils import require_fields

budget_bp = Blueprint("budget", __name__)


@budget_bp.route("/api/budget/status", methods=["GET"])
def api_budget_status():
    return jsonify(_b.compute_status())


@budget_bp.route("/api/budget/log", methods=["POST"])
def api_budget_log():
    data = request.get_json(silent=True) or {}
    data, err = require_fields(data, "date", "type", "amount_cents")
    if err: return err

    type_ = data["type"]
    if type_ not in ("expense", "debt_payment", "fund_transfer"):
        return jsonify({"error": "type invalide (expense|debt_payment|fund_transfer)"}), 400

    try:
        amount = int(data["amount_cents"])
    except (TypeError, ValueError):
        return jsonify({"error": "amount_cents doit être un integer"}), 400

    env  = data.get("envelope_key")
    debt = data.get("debt_key")
    if type_ == "expense":
        if not env or debt:
            return jsonify({"error": "expense exige envelope_key et interdit debt_key"}), 400
    else:  # debt_payment | fund_transfer
        if not debt or env:
            return jsonify({"error": f"{type_} exige debt_key et interdit envelope_key"}), 400

    note = (data.get("note") or "").strip()
    if amount < 0 and not note:
        return jsonify({"error": "note obligatoire pour contre-écriture (amount négatif)"}), 400

    entry = {
        "date":         data["date"],
        "type":         type_,
        "amount_cents": amount,
        "envelope_key": env,
        "debt_key":     debt,
        "note":         note or None,
    }
    if not db_budget.insert_log(entry):
        return jsonify({"error": "insert failed"}), 500
    return jsonify({"ok": True}), 201
