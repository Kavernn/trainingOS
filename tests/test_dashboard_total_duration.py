"""Build 4 — durée multi-créneaux : un créneau à durée inconnue rend le total inconnu."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from routes.data_views import _known_duration, _total_duration


class TotalDurationTests(unittest.TestCase):
    def test_all_known_slots_are_summed(self):
        self.assertEqual(_total_duration([{"duration_min": 41}, {"duration_min": 35.5}]), 76.5)

    def test_one_unknown_slot_makes_total_unknown(self):
        for unknown in (None, 0, -5, "40"):
            self.assertIsNone(_total_duration([{"duration_min": 60}, {"duration_min": unknown}]), unknown)
        self.assertIsNone(_total_duration([{"duration_min": 60}, {}]))

    def test_no_slot_is_unknown(self):
        self.assertIsNone(_total_duration([]))

    def test_known_duration(self):
        self.assertEqual(_known_duration(41.0), 41.0)
        for unknown in (None, 0, -1, "41"):
            self.assertIsNone(_known_duration(unknown))


if __name__ == "__main__":
    unittest.main()
