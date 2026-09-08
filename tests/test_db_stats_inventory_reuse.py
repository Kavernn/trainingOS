import db_stats


def test_pattern_volume_reuses_supplied_inventory(monkeypatch):
    weights = {
        "Bench Press": {
            "history": [{"date": "2026-09-01", "weight": 100, "reps": "5"}]
        }
    }
    inventory = {"Bench Press": {"movement_pattern": "push_horizontal"}}

    def fail_load_inventory():
        raise AssertionError("inventory should be reused")

    monkeypatch.setattr("inventory.load_inventory", fail_load_inventory)
    assert db_stats.get_pattern_volume(28, weights=weights, inventory=inventory) == {"push": 500}


def test_pattern_volume_without_inventory_keeps_fallback(monkeypatch):
    weights = {
        "Bench Press": {
            "history": [{"date": "2026-09-01", "weight": 100, "reps": "5"}]
        }
    }
    inventory = {"Bench Press": {"movement_pattern": "push_horizontal"}}
    monkeypatch.setattr("inventory.load_inventory", lambda: inventory)
    assert db_stats.get_pattern_volume(28, weights=weights) == {"push": 500}


def test_one_rm_trend_reuses_supplied_inventory(monkeypatch):
    weights = {
        "Bench Press": {
            "history": [
                {"date": "2026-08-20", "1rm": 100},
                {"date": "2026-09-01", "1rm": 105},
            ]
        }
    }
    inventory = {"Bench Press": {"movement_pattern": "push_horizontal"}}

    def fail_load_inventory():
        raise AssertionError("inventory should be reused")

    monkeypatch.setattr("inventory.load_inventory", fail_load_inventory)
    assert db_stats.get_one_rm_trend(84, weights=weights, inventory=inventory) == {
        "Bench Press": [
            {"date": "2026-08-20", "one_rm": 100.0},
            {"date": "2026-09-01", "one_rm": 105.0},
        ]
    }


def test_one_rm_trend_without_inventory_keeps_fallback(monkeypatch):
    weights = {
        "Bench Press": {
            "history": [
                {"date": "2026-08-20", "1rm": 100},
                {"date": "2026-09-01", "1rm": 105},
            ]
        }
    }
    inventory = {"Bench Press": {"movement_pattern": "push_horizontal"}}
    monkeypatch.setattr("inventory.load_inventory", lambda: inventory)
    assert db_stats.get_one_rm_trend(84, weights=weights) == {
        "Bench Press": [
            {"date": "2026-08-20", "one_rm": 100.0},
            {"date": "2026-09-01", "one_rm": 105.0},
        ]
    }
