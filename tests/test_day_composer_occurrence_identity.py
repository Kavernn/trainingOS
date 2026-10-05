"""Occurrence contract through the real Flask route, no user DB."""
from unittest.mock import patch
from conftest import BaseRouteTest


class TestOccurrenceIdentity(BaseRouteTest):
    def test_legacy_and_occurrences_reach_upsert_unchanged(self):
        for key in [None, '', 'dc1:morning', 'dc1:evening']:
            with patch('db.upsert_exercise_log_direct', return_value=True) as save:
                body = {'exercise': 'Bench Press', 'weight': 80, 'reps': '8',
                        'sets': [{'weight': 80, 'reps': 8}], 'force': True,
                        'notes': 'exact\n', 'is_second': True}
                if key is not None:
                    body['occurrence_key'] = key
                response = self.post('/api/log', body)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(save.call_args.kwargs['occurrence_key'], key or '')
                self.assertEqual(save.call_args.kwargs['notes'], 'exact\n')

    def test_invalid_occurrence_rejected_before_write(self):
        for key in [None, 3, [], {}, 'a' * 161, 'é' * 81]:
            with patch('db.upsert_exercise_log_direct') as save:
                response = self.post('/api/log', {'exercise': 'Bench Press', 'weight': 80,
                    'reps': '8', 'occurrence_key': key})
                self.assertEqual(response.status_code, 400)
                save.assert_not_called()


class TestOccurrenceStorage:
    def test_real_helper_upsert_readback_and_pagination(self):
        import db_sessions
        from types import SimpleNamespace
        rows = {}

        class Query:
            def __init__(self):
                self.filters = {}; self.bounds = (0, 999); self.payload = None
            def upsert(self, payload, on_conflict):
                assert on_conflict == 'session_id,exercise_id,side,occurrence_key'
                self.payload = payload
                return self
            def select(self, fields):
                assert 'occurrence_key' in fields
                return self
            def eq(self, key, value):
                self.filters[key] = value; return self
            def in_(self, key, value):
                self.filters[key] = value; return self
            def order(self, key): return self
            def range(self, start, end):
                self.bounds = (start, end); return self
            def execute(self):
                if self.payload is not None:
                    p = self.payload
                    key = tuple(p.get(k, '') for k in ['session_id', 'exercise_id', 'side', 'occurrence_key'])
                    rows[key] = {**p, 'exercises': {'name': 'Curl'}}
                    return SimpleNamespace(data=[p])
                result = [r for r in rows.values() if all(
                    r[k] in v if isinstance(v, list) else r[k] == v for k, v in self.filters.items())]
                return SimpleNamespace(data=result[self.bounds[0]:self.bounds[1]+1])

        client = SimpleNamespace(table=lambda _: Query())
        with patch.object(db_sessions.db_core, '_client', client), \
             patch.object(db_sessions.db_core, 'MODE', 'ONLINE'), \
             patch.object(db_sessions, 'get_or_create_exercise_id', return_value='curl-id'):
            for key, weight in [('', 10), ('', 11), ('A', 20), ('B', 30), ('A', 21)]:
                assert db_sessions.upsert_exercise_log_direct('session-a', 'Curl', weight, '8', occurrence_key=key)
            assert len(rows) == 3
            assert rows[('session-a', 'curl-id', 'both', 'A')]['weight'] == 21
            assert rows[('session-a', 'curl-id', 'both', 'B')]['weight'] == 30
            assert db_sessions.upsert_exercise_log_direct('session-b', 'Curl', 40, '8', occurrence_key='A')
            result = db_sessions.get_exercise_logs_for_session_with_names('session-a', strict=True)
            assert {r['occurrence_key'] for r in result} == {'', 'A', 'B'}
            for i in range(1001):
                assert db_sessions.upsert_exercise_log_direct('page', 'Curl', i, '8', occurrence_key=str(i))
            assert len(db_sessions.get_exercise_logs_for_session_with_names('page', strict=True)) == 1001
            grouped = db_sessions.get_exercise_history_grouped_by_session(['page'])
            assert len(grouped['page']) == 1001
            assert len({r['occurrence_key'] for r in grouped['page']}) == 1001
