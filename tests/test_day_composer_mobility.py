"""Mobility binary completion through the real route, with isolated fake DB."""
from unittest.mock import patch
from conftest import BaseRouteTest


class TestMobilityCompletion(BaseRouteTest):
    def test_binary_completion_never_inherits_effort_or_progresses_load(self):
        self.store['weights']['Bench Press']['history'][0]['rpe'] = 6
        with patch('db.get_exercise_by_name', return_value={'tracking_type': 'mobility'}), \
             patch('db.upsert_exercise_log_direct', return_value=True) as save, \
             patch('db.update_exercise_current_weight') as update, \
             patch('db.upsert_exercise_pr') as pr, \
             patch('db.recompute_exercise_pr') as recompute, \
             patch('progression.suggest_next_weight', return_value=(50, 'increase')) as suggest:
            response = self.post('/api/log', {
                'exercise': 'Bench Press',  # Type, never the name, defines the contract.
                'weight': 0, 'reps': '1', 'sets': [{'weight': 0}],
                'force': True, 'equipment_type': 'machine', 'notes': 'exact mobilité\n',
            })
            self.assertEqual(response.status_code, 200)
            self.assertTrue(save.called)
            self.assertIsNone(save.call_args.kwargs['rpe'])
            self.assertEqual(save.call_args.kwargs['notes'], 'exact mobilité\n')
            self.assertEqual(save.call_args.kwargs['sets_json'][0]['set_volume'], 0)
            suggest.assert_not_called()
            update.assert_not_called()
            pr.assert_not_called()
            recompute.assert_not_called()
            self.assertFalse(self.json(response)['is_pr'])
