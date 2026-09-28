"""Real Flask routes and planning helpers; only Supabase transport is isolated."""
import copy
import json
import sys
from collections import Counter
from types import SimpleNamespace
from unittest.mock import patch
from conftest import BaseRouteTest
import db_core
import db_programs
import db_exercises
import db_features


class ReadFixture:
    def __init__(self):
        def session(name, order, names):
            return {'id': name, 'name': name, 'program_id': 'active', 'order_index': order,
                    'program_blocks': [{'type': 'strength', 'order_index': 0,
                        'program_block_exercises': [
                            {'order_index': i, 'scheme': '3x10', 'exercises': {'id': n, 'name': n}}
                            for i, n in enumerate(names)]}]}
        self.rows = {
            'user_profile': [{'id': 1, 'active_program_id': 'active', 'selected_program_id': 'selected',
                              'session_override': {'session': 'Wrong override'}}],
            'programs': [{'id': 'active', 'name': 'Active', 'created_at': '1'},
                         {'id': 'selected', 'name': 'Selected', 'created_at': '2'}],
            'program_sessions': [session('AM', 0, ['Squat', 'Row']), session('PM', 1, ['Stretch'])],
            'weekly_schedule': [
                {'day_name': 'Lun', 'slot': 'morning', 'session_id': 'AM', 'program_sessions': {'name': 'AM', 'program_id': 'active'}},
                {'day_name': 'Lun', 'slot': 'evening', 'session_id': 'PM', 'program_sessions': {'name': 'PM', 'program_id': 'active'}},
                {'day_name': 'Dim', 'slot': 'morning', 'session_id': None, 'program_sessions': None}],
            'exercises': [{'id': str(i), 'name': n, 'type': 'machine', 'default_scheme': '3x10',
                           'tracking_type': 'reps', 'muscles': ['back']} for i, n in enumerate(
                               ['Squat', 'Row', 'Stretch'] + [f'Catalogue {i}' for i in range(97)])],
            'v_exercise_current': [],
        }
        self.calls = []
        self.writes = []
        self.failure = None

    def table(self, name):
        return Query(self, name)


class Query:
    def __init__(self, fixture, table):
        self.fixture, self.name = fixture, table
        self.columns = '*'
        self.filters = []
        self.bounds = None
        self.sort = None
        self.negated = False
    def select(self, columns): self.columns = columns; return self
    def eq(self, key, value): self.filters.append((key, value)); return self
    def order(self, key): self.sort = key; return self
    def limit(self, count): self.bounds = (0, count); return self
    def range(self, start, end): self.bounds = (start, end + 1); return self
    @property
    def not_(self): self.negated = True; return self
    def is_(self, key, value):
        if self.negated: self.filters.append((key, 'NOT_NULL'))
        self.negated = False
        return self
    def insert(self, *args): return self.write()
    def update(self, *args): return self.write()
    def upsert(self, *args, **kwargs): return self.write()
    def delete(self, *args): return self.write()
    def write(self):
        self.fixture.writes.append(self.name)
        raise AssertionError('Unexpected write')
    def execute(self):
        self.fixture.calls.append((self.name, self.columns))
        if self.fixture.failure == self.name: raise RuntimeError('isolated failure')
        rows = copy.deepcopy(self.fixture.rows[self.name])
        for key, value in self.filters:
            rows = [r for r in rows if (r.get(key) is not None if value == 'NOT_NULL' else r.get(key) == value)]
        if self.sort: rows.sort(key=lambda r: r.get(self.sort, ''))
        if self.bounds: rows = rows[slice(*self.bounds)]
        if self.columns != '*' and '(' not in self.columns:
            fields = [f.strip() for f in self.columns.split(',')]
            rows = [{k: r[k] for k in fields if k in r} for r in rows]
        return SimpleNamespace(data=rows)


class TestDashboardContext(BaseRouteTest):
    def setUp(self):
        super().setUp()
        self.fixture = ReadFixture()
        self.addCleanup(patch.stopall)
        patch.object(db_core, '_client', self.fixture).start()
        patch.object(db_core, 'MODE', 'ONLINE').start()
        patch.object(db_core, '_is_disconnect', return_value=False).start()
        # Legacy route uses the facade; wire it to the SAME real production helpers.
        facade = sys.modules['db']
        for name in ['get_active_program_id', 'get_full_program', 'get_relational_week_schedule',
                     'get_all_programs', 'get_all_session_names', 'get_cycle_start_date']:
            patch.object(facade, name, getattr(db_programs, name)).start()
        patch.object(facade, 'get_exercises', db_exercises.get_exercises).start()
        patch.object(facade, 'get_current_1rm_estimates', db_features.get_current_1rm_estimates).start()
        self.write_spy = patch.object(facade, 'upsert_exercise', side_effect=AssertionError('inventory write')).start()

    def context(self, date='2026-09-28'):
        return self.get('/api/dashboard_context?date=' + date + '&program_id=selected')

    def test_parity_encoded_bytes_and_actual_read_counts(self):
        old = self.get('/api/programme_data')
        self.assertEqual(old.status_code, 200)
        before = list(self.fixture.calls)
        self.fixture.calls.clear()
        new = self.context()
        self.assertEqual(new.status_code, 200)
        old_json, new_json = self.json(old), self.json(new)
        for key in ['active_program_id', 'current_program_id', 'schedule', 'full_program', 'exercise_order', 'session_order']:
            self.assertEqual(old_json[key], new_json[key], key)
        self.assertEqual(new_json['active_program_id'], 'active')
        self.assertEqual(new_json['schedule'], {'Lun': 'AM', 'Dim': 'Repos'})
        self.assertEqual(new_json['evening_schedule'], {'Lun': 'PM'})
        self.assertEqual(new.headers['Cache-Control'], 'no-store')
        self.assertEqual(len(self.fixture.calls), 4)
        self.assertLess(len(new.data), len(old.data))
        self.assertFalse(self.fixture.writes)
        self.write_spy.assert_not_called()
        self.assertNotIn('exercises', [t for t, _ in self.fixture.calls])
        result = {'fixture': '2 sessions / 3 planned exercises / 100 inventory exercises',
                  'legacy_bytes': len(old.data), 'context_bytes': len(new.data),
                  'legacy_reads': len(before), 'context_reads': len(self.fixture.calls),
                  'legacy_categories': dict(Counter(t for t, _ in before)),
                  'context_categories': dict(Counter(t for t, _ in self.fixture.calls)), 'writes': 0}
        print('CONTEXT_MEASUREMENT ' + json.dumps(result, sort_keys=True))

    def test_same_program_schedule_content_order_and_evening_changes(self):
        before = self.json(self.context())
        self.fixture.rows['weekly_schedule'][0]['program_sessions']['name'] = 'PM'
        after = self.json(self.context())
        self.assertNotEqual(before['schedule'], after['schedule'])
        rows = self.fixture.rows['program_sessions'][0]['program_blocks'][0]['program_block_exercises']
        rows[0]['order_index'], rows[1]['order_index'] = 1, 0
        reordered = self.json(self.context())
        self.assertEqual(reordered['exercise_order']['AM'], ['Row', 'Squat'])
        rows[0]['scheme'] = '2x8'
        self.assertNotEqual(reordered['full_program'], self.json(self.context())['full_program'])
        self.fixture.rows['weekly_schedule'][1]['program_sessions']['name'] = 'AM'
        self.assertEqual(self.json(self.context())['evening_schedule'], {'Lun': 'AM'})
        self.assertFalse(self.fixture.writes)

    def test_empty_program_is_valid_but_missing_program_is_not(self):
        self.fixture.rows['program_sessions'] = []
        self.fixture.rows['weekly_schedule'] = []
        result = self.context()
        self.assertEqual(result.status_code, 200)
        self.assertEqual(self.json(result)['full_program'], {})
        self.fixture.rows['programs'] = []
        result = self.context()
        self.assertEqual(result.status_code, 404)
        self.assertEqual(self.json(result)['error'], 'active_program_not_found')

    def test_active_resolution_fallbacks_reuse_existing_priority_without_writes(self):
        self.fixture.rows['user_profile'] = []
        self.assertEqual(self.json(self.context())['active_program_id'], 'active')
        self.fixture.rows['weekly_schedule'] = []
        self.assertEqual(self.json(self.context())['active_program_id'], 'active')
        self.fixture.rows['programs'] = []
        self.assertEqual(self.context().status_code, 409)
        self.assertFalse(self.fixture.writes)

    def test_invalid_date_and_read_failures_fail_closed(self):
        for date in ['', '2026-02-30', '2026-9-28']:
            self.assertEqual(self.context(date).status_code, 400)
        for table in ['user_profile', 'program_sessions', 'weekly_schedule']:
            self.fixture.failure = table
            result = self.context()
            self.assertEqual(result.status_code, 503)
            self.assertEqual(self.json(result)['error'], 'dashboard_context_unavailable')
        self.assertFalse(self.fixture.writes)

    def test_route_retains_existing_authentication(self):
        with patch.object(self.idx, '_API_KEY', 'fixture-key'):
            self.app.config['TESTING'] = False
            try:
                self.assertEqual(self.context().status_code, 401)
                self.assertFalse(self.fixture.calls)
                response = self.client.get('/api/dashboard_context?date=2026-09-28',
                                           headers={'Authorization': 'Bearer fixture-key'})
                self.assertEqual(response.status_code, 200)
            finally:
                self.app.config['TESTING'] = True
