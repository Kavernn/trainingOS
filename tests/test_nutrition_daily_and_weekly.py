"""
Tests nutrition : isolation journalière et bilan hebdomadaire.

1. Chaque jour est logué séparément (les entrées d'un jour ne contaminent
   pas un autre jour).
2. get_recent_days() retourne un bilan correct sur la semaine.
"""
import copy
import sys
import os
import unittest
from unittest.mock import patch, MagicMock
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))


# ── Store in-memory ──────────────────────────────────────────────────────────

def make_db_store(initial_log=None, initial_settings=None):
    store = {
        "nutrition_log": copy.deepcopy(initial_log or {}),
        "nutrition_settings": copy.deepcopy(initial_settings or {
            "limite_calories": 2200,
            "objectif_proteines": 160,
        }),
    }

    def get_nutrition_entries(date):
        log = store.get("nutrition_log", {})
        return copy.deepcopy((log.get(date) or {}).get("entries", []))

    def get_nutrition_entries_recent(n=7):
        log = store.get("nutrition_log", {})
        days = sorted(log.keys(), reverse=True)[:n]
        return [
            {
                "date":     d,
                "calories": round(sum(e.get("calories", 0) for e in (log.get(d) or {}).get("entries", []))),
                "nb":       len((log.get(d) or {}).get("entries", [])),
            }
            for d in days
        ]

    def insert_nutrition_entry(data):
        log = store.get("nutrition_log", {})
        d = data.get("date", "")
        if d not in log:
            log[d] = {"entries": []}
        log[d]["entries"].append(copy.deepcopy(data))
        store["nutrition_log"] = log
        return copy.deepcopy(data)

    def delete_nutrition_entry(entry_id):
        log = store.get("nutrition_log", {})
        for day_data in log.values():
            before = len(day_data.get("entries", []))
            day_data["entries"] = [e for e in day_data.get("entries", []) if e.get("id") != entry_id]
            if len(day_data["entries"]) < before:
                store["nutrition_log"] = log
                return True
        return False

    def get_nutrition_settings():
        return copy.deepcopy(store.get("nutrition_settings", {}))

    def update_nutrition_settings(patch):
        settings = store.get("nutrition_settings", {})
        settings.update(patch)
        store["nutrition_settings"] = settings
        return True

    return store, MagicMock(
        get_nutrition_entries=get_nutrition_entries,
        get_nutrition_entries_recent=get_nutrition_entries_recent,
        insert_nutrition_entry=insert_nutrition_entry,
        delete_nutrition_entry=delete_nutrition_entry,
        get_nutrition_settings=get_nutrition_settings,
        update_nutrition_settings=update_nutrition_settings,
    )


def load_nutrition_module(db_mock):
    """Importe nutrition.py avec un db mocké (méthodes relationnelles)."""
    original_db = sys.modules.get("db", None)
    sys.modules["db"] = db_mock

    if "nutrition" in sys.modules:
        del sys.modules["nutrition"]
    import nutrition

    if original_db is None:
        sys.modules.pop("db", None)
    else:
        sys.modules["db"] = original_db

    return nutrition


# ── Fixtures ─────────────────────────────────────────────────────────────────

LOG_MULTI_DAY = {
    "2026-03-01": {"entries": [
        {"id": "aaa00001", "nom": "Riz",     "calories": 350, "proteines": 7.0,
         "glucides": 75.0, "lipides": 1.0, "heure": "12:00"},
        {"id": "aaa00002", "nom": "Poulet",  "calories": 300, "proteines": 40.0,
         "glucides": 0.0,  "lipides": 5.0, "heure": "12:05"},
    ]},
    "2026-03-02": {"entries": [
        {"id": "bbb00001", "nom": "Avoine",  "calories": 400, "proteines": 12.0,
         "glucides": 68.0, "lipides": 7.0, "heure": "08:00"},
    ]},
    "2026-03-03": {"entries": [
        {"id": "ccc00001", "nom": "Oeufs",   "calories": 220, "proteines": 18.0,
         "glucides": 1.0,  "lipides": 14.0, "heure": "09:00"},
        {"id": "ccc00002", "nom": "Fromage", "calories": 180, "proteines": 12.0,
         "glucides": 0.5,  "lipides": 14.0, "heure": "13:00"},
        {"id": "ccc00003", "nom": "Pâtes",   "calories": 500, "proteines": 15.0,
         "glucides": 90.0, "lipides": 2.0,  "heure": "19:30"},
    ]},
    "2026-03-04": {"entries": []},          # jour vide (zéro calorie)
    "2026-03-05": {"entries": [
        {"id": "eee00001", "nom": "Steak",   "calories": 600, "proteines": 55.0,
         "glucides": 0.0,  "lipides": 40.0, "heure": "20:00"},
    ]},
    "2026-03-06": {"entries": [
        {"id": "fff00001", "nom": "Salade",  "calories": 150, "proteines": 5.0,
         "glucides": 10.0, "lipides": 8.0,  "heure": "12:30"},
        {"id": "fff00002", "nom": "Saumon",  "calories": 400, "proteines": 38.0,
         "glucides": 0.0,  "lipides": 22.0, "heure": "19:00"},
    ]},
    "2026-03-07": {"entries": [
        {"id": "ggg00001", "nom": "Yaourt",  "calories": 100, "proteines": 8.0,
         "glucides": 12.0, "lipides": 3.0,  "heure": "07:30"},
    ]},
}


# ── Helpers ───────────────────────────────────────────────────────────────────

def fake_now(date_str):
    """Retourne un objet datetime fixé à date_str (YYYY-MM-DD)."""
    return datetime.strptime(date_str, "%Y-%m-%d")


# ═════════════════════════════════════════════════════════════════════════════
# 1. Isolation journalière
# ═════════════════════════════════════════════════════════════════════════════

class TestDailyIsolation(unittest.TestCase):

    def _module(self, initial_log=None):
        store, db_mock = make_db_store(initial_log)
        self.store = store
        return load_nutrition_module(db_mock), store

    def test_add_entry_creates_day_key(self):
        """add_entry crée la clé YYYY-MM-DD si elle n'existe pas."""
        nut, store = self._module()
        with patch("nutrition.datetime") as mock_dt:
            mock_dt.now.return_value = fake_now("2026-03-07")
            nut.add_entry("Banane", 100, proteines=1.5)

        self.assertIn("2026-03-07", store["nutrition_log"])

    def test_add_entries_on_different_days_are_isolated(self):
        """Des entrées ajoutées des jours différents ne se mélangent pas."""
        nut, store = self._module()

        for date_str, food, cal in [
            ("2026-03-05", "Pain",   200),
            ("2026-03-06", "Beurre", 150),
            ("2026-03-07", "Café",    10),
        ]:
            with patch("nutrition.datetime") as mock_dt:
                dt = fake_now(date_str)
                mock_dt.now.return_value = dt
                nut.add_entry(food, cal)

        log = store["nutrition_log"]
        self.assertEqual(len(log["2026-03-05"]["entries"]), 1)
        self.assertEqual(log["2026-03-05"]["entries"][0]["nom"], "Pain")

        self.assertEqual(len(log["2026-03-06"]["entries"]), 1)
        self.assertEqual(log["2026-03-06"]["entries"][0]["nom"], "Beurre")

        self.assertEqual(len(log["2026-03-07"]["entries"]), 1)
        self.assertEqual(log["2026-03-07"]["entries"][0]["nom"], "Café")

    def test_multiple_entries_same_day_accumulate(self):
        """Plusieurs appels à add_entry le même jour s'empilent sur ce jour."""
        nut, store = self._module()

        for food, cal in [("Riz", 350), ("Poulet", 300), ("Légumes", 80)]:
            with patch("nutrition.datetime") as mock_dt:
                mock_dt.now.return_value = fake_now("2026-03-07")
                nut.add_entry(food, cal)

        entries = store["nutrition_log"]["2026-03-07"]["entries"]
        self.assertEqual(len(entries), 3)
        noms = [e["nom"] for e in entries]
        self.assertIn("Riz", noms)
        self.assertIn("Poulet", noms)
        self.assertIn("Légumes", noms)

    def test_get_today_entries_returns_only_today(self):
        """get_today_entries() ne renvoie QUE les entrées du jour courant."""
        nut, _ = self._module(copy.deepcopy(LOG_MULTI_DAY))

        with patch("nutrition.datetime") as mock_dt:
            mock_dt.now.return_value = fake_now("2026-03-07")
            entries = nut.get_today_entries()

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["nom"], "Yaourt")

    def test_get_today_entries_empty_for_unknown_day(self):
        """get_today_entries() renvoie [] si aucune entrée n'existe pour ce jour."""
        nut, _ = self._module(copy.deepcopy(LOG_MULTI_DAY))

        with patch("nutrition.datetime") as mock_dt:
            mock_dt.now.return_value = fake_now("2026-03-10")
            entries = nut.get_today_entries()

        self.assertEqual(entries, [])

    def test_get_today_totals_correct(self):
        """get_today_totals() additionne correctement les macros du jour."""
        nut, _ = self._module(copy.deepcopy(LOG_MULTI_DAY))

        # Le 2026-03-03 : oeufs(220) + fromage(180) + pâtes(500) = 900 kcal
        with patch("nutrition.datetime") as mock_dt:
            mock_dt.now.return_value = fake_now("2026-03-03")
            totals = nut.get_today_totals()

        self.assertEqual(totals["calories"], 900)
        self.assertAlmostEqual(totals["proteines"], 45.0, places=1)
        self.assertAlmostEqual(totals["glucides"],  91.5, places=1)
        self.assertAlmostEqual(totals["lipides"],   30.0, places=1)

    def test_delete_entry_does_not_affect_other_days(self):
        """Supprimer une entrée d'aujourd'hui ne modifie pas les autres jours."""
        nut, store = self._module(copy.deepcopy(LOG_MULTI_DAY))

        snapshot_before = {
            day: copy.deepcopy(data)
            for day, data in store["nutrition_log"].items()
            if day != "2026-03-07"
        }

        with patch("nutrition.datetime") as mock_dt:
            mock_dt.now.return_value = fake_now("2026-03-07")
            result = nut.delete_entry("ggg00001")

        self.assertTrue(result)

        for day, data in snapshot_before.items():
            self.assertEqual(
                store["nutrition_log"][day],
                data,
                f"Le jour {day} a été modifié après suppression sur 2026-03-07",
            )

    def test_delete_entry_by_id_regardless_of_day(self):
        """delete_entry() supprime par ID sans restriction de date."""
        nut, store = self._module(copy.deepcopy(LOG_MULTI_DAY))

        # bbb00001 est du 2026-03-02 ; doit être supprimable depuis n'importe quel jour
        result = nut.delete_entry("bbb00001")

        self.assertTrue(result)
        entries_march2 = store["nutrition_log"].get("2026-03-02", {}).get("entries", [])
        self.assertFalse(any(e["id"] == "bbb00001" for e in entries_march2))

    def test_each_entry_has_unique_id(self):
        """Deux entrées ajoutées le même jour ont des IDs distincts."""
        nut, store = self._module()

        with patch("nutrition.datetime") as mock_dt:
            mock_dt.now.return_value = fake_now("2026-03-07")
            nut.add_entry("Repas A", 400)
            nut.add_entry("Repas B", 300)

        entries = store["nutrition_log"]["2026-03-07"]["entries"]
        ids = [e["id"] for e in entries]
        self.assertEqual(len(ids), len(set(ids)), "Des IDs dupliqués ont été générés")


# ═════════════════════════════════════════════════════════════════════════════
# 2. Bilan hebdomadaire
# ═════════════════════════════════════════════════════════════════════════════

class TestWeeklySummary(unittest.TestCase):

    def _module(self, initial_log=None):
        store, db_mock = make_db_store(initial_log)
        self.store = store
        return load_nutrition_module(db_mock)

    def test_get_recent_days_returns_7_days(self):
        """get_recent_days() retourne au plus 7 jours quand le log en contient 7."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        result = nut.get_recent_days(7)
        self.assertEqual(len(result), 7)

    def test_get_recent_days_sorted_descending(self):
        """Les jours sont renvoyés du plus récent au plus ancien."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        result = nut.get_recent_days(7)
        dates = [r["date"] for r in result]
        self.assertEqual(dates, sorted(dates, reverse=True))

    def test_get_recent_days_calories_correct(self):
        """Les calories de chaque jour sont correctement agrégées."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        result = nut.get_recent_days(7)

        by_date = {r["date"]: r for r in result}

        # 2026-03-01 : 350 + 300 = 650
        self.assertEqual(by_date["2026-03-01"]["calories"], 650)
        # 2026-03-02 : 400
        self.assertEqual(by_date["2026-03-02"]["calories"], 400)
        # 2026-03-03 : 220 + 180 + 500 = 900
        self.assertEqual(by_date["2026-03-03"]["calories"], 900)
        # 2026-03-04 : 0 (jour vide)
        self.assertEqual(by_date["2026-03-04"]["calories"], 0)
        # 2026-03-05 : 600
        self.assertEqual(by_date["2026-03-05"]["calories"], 600)
        # 2026-03-06 : 150 + 400 = 550
        self.assertEqual(by_date["2026-03-06"]["calories"], 550)
        # 2026-03-07 : 100
        self.assertEqual(by_date["2026-03-07"]["calories"], 100)

    def test_get_recent_days_nb_entries_correct(self):
        """Le champ 'nb' reflète le nombre exact d'entrées par jour."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        result = nut.get_recent_days(7)

        by_date = {r["date"]: r for r in result}
        self.assertEqual(by_date["2026-03-01"]["nb"], 2)
        self.assertEqual(by_date["2026-03-02"]["nb"], 1)
        self.assertEqual(by_date["2026-03-03"]["nb"], 3)
        self.assertEqual(by_date["2026-03-04"]["nb"], 0)
        self.assertEqual(by_date["2026-03-07"]["nb"], 1)

    def test_get_recent_days_n_param_respected(self):
        """get_recent_days(n) retourne exactement n jours si disponibles."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        for n in [1, 3, 5, 7]:
            with self.subTest(n=n):
                result = nut.get_recent_days(n)
                self.assertEqual(len(result), n)

    def test_get_recent_days_only_most_recent(self):
        """Avec n=3, seuls les 3 jours les plus récents sont renvoyés."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        result = nut.get_recent_days(3)
        dates = {r["date"] for r in result}
        self.assertIn("2026-03-07", dates)
        self.assertIn("2026-03-06", dates)
        self.assertIn("2026-03-05", dates)
        self.assertNotIn("2026-03-01", dates)

    def test_get_recent_days_empty_log(self):
        """get_recent_days() retourne [] si aucune entrée n'existe."""
        nut = self._module({})
        result = nut.get_recent_days(7)
        self.assertEqual(result, [])

    def test_get_recent_days_fewer_than_n_available(self):
        """Quand il y a moins de n jours dans le log, on retourne ce qui existe."""
        partial_log = {
            "2026-03-06": {"entries": [
                {"id": "x1", "nom": "A", "calories": 500, "proteines": 30.0,
                 "glucides": 50.0, "lipides": 10.0, "heure": "12:00"}
            ]},
            "2026-03-07": {"entries": [
                {"id": "x2", "nom": "B", "calories": 300, "proteines": 20.0,
                 "glucides": 30.0, "lipides": 5.0, "heure": "08:00"}
            ]},
        }
        nut = self._module(partial_log)
        result = nut.get_recent_days(7)
        self.assertEqual(len(result), 2)

    def test_weekly_total_calories(self):
        """La somme des calories de la semaine est correcte."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        result = nut.get_recent_days(7)
        total = sum(r["calories"] for r in result)
        # 650 + 400 + 900 + 0 + 600 + 550 + 100 = 3200
        self.assertEqual(total, 3200)

    def test_each_day_in_summary_has_required_fields(self):
        """Chaque entrée du bilan hebdo possède les champs date, calories, nb."""
        nut = self._module(copy.deepcopy(LOG_MULTI_DAY))
        result = nut.get_recent_days(7)
        for day in result:
            with self.subTest(date=day.get("date")):
                self.assertIn("date",     day)
                self.assertIn("calories", day)
                self.assertIn("nb",       day)


if __name__ == "__main__":
    unittest.main(verbosity=2)
