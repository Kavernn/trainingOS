"""Single-end loading contracts; no production database calls."""
from unittest.mock import patch
from conftest import BaseRouteTest


class TestLandmine(BaseRouteTest):
    def test_catalog_create_and_edit_preserve_load_configuration(self):
        for bar in (45, 35, 0):
            r = self.post('/api/save_exercise', dict(name='Meadows Row', type='landmine',
                weight_type='landmine', bar_weight=bar, default_scheme='3x8', load_profile='compound_hypertrophy'))
            self.assertEqual(r.status_code, 200)
            entry = self.store['inventory']['Meadows Row']
            self.assertEqual(entry['type'], 'landmine')
            self.assertEqual(entry['weight_type'], 'landmine')
            self.assertEqual(entry['bar_weight'], bar)

    def test_metadata_and_suggestion_do_not_use_stale_barbell_input_type(self):
        from inventory import attach_load_metadata
        from planner import get_suggested_weights_for_today
        weights = {'Meadows Row': {'current_weight': 115, 'input_type': 'barbell'}}
        inv = {'Meadows Row': {'type': 'landmine', 'bar_weight': 35}}
        attach_load_metadata(weights, inv)
        self.assertEqual(weights['Meadows Row']['bar_weight'], 35)
        self.assertEqual(weights['Meadows Row']['current_weight'], 115)
        with patch('inventory.load_inventory', return_value=inv), patch('planner.suggest_next_weight', return_value=(120, 'increase')):
            values = get_suggested_weights_for_today(weights, {}, exercise_plan={'Meadows Row': '3x8'})
        self.assertEqual(values[0]['display'], '85.0 charge (total 120.0 lbs)')

    def test_weight_endpoint_carries_custom_bar_without_history(self):
        self.store['inventory']['Meadows Row'] = dict(type='landmine', bar_weight=35)
        response = self.get('/api/weights?exercise=Meadows%20Row')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.json(response)['Meadows Row']['bar_weight'], 35)

    def test_real_logging_volume_and_pr_receive_total(self):
        with patch('db.get_exercise_by_name', return_value={'tracking_type': 'reps'}), \
             patch('db.upsert_exercise_log_direct', return_value=True) as save, \
             patch('db.update_exercise_current_weight'), \
             patch('db.upsert_exercise_pr') as pr, \
             patch('db.recompute_exercise_pr'), \
             patch('progression.suggest_next_weight', return_value=(120, 'increase')) as suggest:
            response = self.post('/api/log', dict(exercise='Bench Press', weight=115, reps='8',
                sets=[dict(weight=115, reps='8')], force=True, equipment_type='landmine'))
            self.assertEqual(response.status_code, 200)
            self.assertEqual(save.call_args.args[2], 115)
            self.assertEqual(save.call_args.kwargs['sets_json'][0]['set_volume'], 920)
            self.assertEqual(suggest.call_args.args[1], 115)
            self.assertTrue(pr.called)
            self.assertEqual(pr.call_args.args[2], 115)

    def test_pr_compares_90_to_100_as_totals(self):
        from progression import estimate_1rm
        prior = dict(exercise_name='Bench Press', pr_e1rm_lbs=estimate_1rm(90, '8'), baseline_count=4)
        with patch('db.get_exercise_prs', return_value=[prior]), \
             patch('db.get_exercise_by_name', return_value={'tracking_type': 'reps'}), \
             patch('db.upsert_exercise_log_direct', return_value=True), \
             patch('db.update_exercise_current_weight'), \
             patch('db.upsert_exercise_pr') as pr, patch('db.recompute_exercise_pr'):
            response = self.post('/api/log', dict(exercise='Bench Press', weight=100, reps='8',
                sets=[dict(weight=100, reps='8')], force=True, equipment_type='landmine'))
            self.assertEqual(response.status_code, 200)
            self.assertTrue(self.json(response)['is_pr'])
            self.assertEqual(pr.call_args.args[2], 100)
            self.assertAlmostEqual(pr.call_args.args[1], estimate_1rm(100, '8'))
