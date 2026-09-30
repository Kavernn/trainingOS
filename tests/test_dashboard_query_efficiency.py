"""Dashboard metrics: real route/adapters/db_sessions, isolated transport.

Reference JSON and traces were captured on f30c3c3 before the production edit.
Planning and Nutrition are fixed collaborators, outside the measured D reads.
No network, SQL server, account data, or wall-clock benchmark is involved.
"""
import copy
import json
import socket
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from conftest import BaseRouteTest
import db_core
import db_sessions

DATE = '2026-09-28'
REFERENCE = Path(__file__).parent / 'fixtures/dashboard_metrics_reference.json'
SCENARIOS = ('empty', 'no_logs', 'morning_evening', 'pagination', 'partial',
             'read_error', 'corrected', 'other_user', 'history_error')


def fixture_rows(scenario):
    def session(sid, slot, **extra):
        return dict(id=sid, date=DATE, session_type=slot, is_second=slot == 'evening',
                    session_name='Same name', completed=False, rpe=None,
                    duration_min=None, energy_pre=None, comment=None,
                    logged_at=DATE + 'T12:00:00Z', user_id='owner', **extra)

    am, pm = session('am', 'morning'), session('pm', 'evening')
    am.update(duration_min=30, rpe=7, energy_pre=4, completed=True, comment='First')
    pm.update(duration_min=20, rpe=5, completed=True, comment='Second')
    sessions = [pm, am]  # Real helper must restore canonical AM/PM ordering.
    if scenario == 'empty':
        sessions = []
    if scenario == 'partial':
        am.update(completed=False, rpe=None, duration_min=None, comment=None)
        pm.update(completed=False, rpe=None, duration_min=0, comment=None)
        sessions.append(session('bonus', 'bonus'))
    if scenario == 'pagination':
        sessions.append(session('bonus', 'bonus'))

    def log(sid, name, weight=100, date=DATE, user='owner', number=0):
        slot = next((s['session_type'] for s in sessions if s['id'] == sid), 'morning')
        return dict(id=f'{sid}-{number}', session_id=sid, user_id=user,
                    weight=weight, reps='10', sets_json=[{'weight': weight, 'reps': 10}],
                    exercises={'name': name}, workout_sessions={'date': date, 'session_type': slot})

    logs = [] if scenario in ('empty', 'no_logs') else [
        log('am', 'Bench Press'), log('pm', 'Evening only'),
        log('pm', 'Bench Press', 80, number=1),
    ]
    if scenario == 'partial':
        logs = [log('am', 'Bench Press', 0), log('am', None, number=1)]
        logs[0].update(reps=None, sets_json=None)
        logs[1]['exercises'] = None
    if scenario == 'pagination':
        logs = [log(sid, f'Exercise {i:03}', number=i)
                for sid in ('am', 'pm', 'bonus') for i in range(400)]
        logs[-1]['exercises']['name'] = 'Tail after page 1000'
    if scenario == 'corrected':
        logs[0].update(weight=125, sets_json=[{'weight': 125, 'reps': 10}])
        logs[1]['exercises']['name'] = 'Corrected evening'
    # Historical execution is deliberately not scoped to the active programme.
    history = session('past', 'morning')
    history.update(date='2026-09-20', completed=True, duration_min=40, rpe=6)
    if scenario != 'empty':
        sessions.append(history)
        logs.append(log('past', 'Historical only', date=history['date']))
    # Hidden data and a different date must never enter today's names.
    foreign = session('foreign', 'morning')
    foreign.update(user_id='other', completed=True, duration_min=999)
    sessions.append(foreign)
    logs.append(log('foreign', 'Private exercise', user='other'))
    if scenario == 'other_user':
        foreign.update(duration_min=9999)
        logs[-1]['exercises']['name'] = 'Changed private exercise'
    volumes = [dict(date=s['date'], total_volume=(None if scenario == 'partial' else 1000),
                    user_id=s['user_id']) for s in sessions]
    return {'workout_sessions': sessions, 'exercise_logs': logs, 'v_session_volume': volumes}


class MetricsTransport:
    """One execute = one simulated PostgREST response, not a SQL query count."""
    def __init__(self, scenario, cap=1000):
        self.rows = fixture_rows(scenario)
        self.scenario, self.cap = scenario, cap
        self.calls, self.writes = [], []
        self.fail_group_page = False
        self.omit_count = False

    def table(self, name):
        assert name in self.rows, name
        return MetricsQuery(self, name)


class MetricsQuery:
    def __init__(self, transport, name):
        self.transport, self.name = transport, name
        self.columns, self.count = '*', None
        self.filters, self.bounds, self.sort, self.one = [], None, None, False

    def select(self, columns, count=None): self.columns, self.count = columns, count; return self
    def eq(self, key, value): self.filters.append(('eq', key, value)); return self
    def in_(self, key, values): self.filters.append(('in', key, list(values))); return self
    def gte(self, key, value): self.filters.append(('gte', key, value)); return self
    def order(self, key, desc=False): self.sort = (key, desc); return self
    def range(self, start, end): self.bounds = (start, end + 1); return self
    def limit(self, count): self.bounds = (0, count); return self
    def single(self): self.one = True; return self
    def insert(self, *a, **kw): return self.write()
    def update(self, *a, **kw): return self.write()
    def upsert(self, *a, **kw): return self.write()
    def delete(self, *a, **kw): return self.write()

    def write(self):
        self.transport.writes.append(self.name)
        raise AssertionError('Unexpected storage write')

    def execute(self):
        t = self.transport
        call = dict(table=self.name, select=self.columns, filters=self.filters,
                    bounds=self.bounds, count=self.count, rows=0, error=False)
        t.calls.append(call)
        history = self.name == 'exercise_logs' and 'workout_sessions' in self.columns
        selected_ids = [value for op, key, value in self.filters if key == 'session_id']
        fails = t.scenario == 'read_error' and any(
            v == 'pm' or isinstance(v, list) and 'pm' in v for v in selected_ids)
        fails |= t.scenario == 'history_error' and history
        fails |= t.fail_group_page and self.columns.startswith('session_id,') and self.bounds is not None
        if fails:
            call['error'] = True
            raise RuntimeError('Isolated read failure')
        rows = copy.deepcopy([r for r in t.rows[self.name] if r['user_id'] == 'owner'])
        for op, key, value in self.filters:
            def matches(row):
                actual = row
                for part in key.split('.'):
                    actual = (actual or {}).get(part)
                if op == 'eq': return actual == value
                if op == 'in': return actual in value
                return actual is not None and actual >= value
            rows = [r for r in rows if matches(r)]
        if self.sort:
            key, desc = self.sort
            rows.sort(key=lambda r: r.get(key) or '', reverse=desc)
        total = len(rows)
        if self.bounds:
            rows = rows[slice(*self.bounds)]
        rows = rows[:t.cap]
        if self.columns != '*':
            # The two embedded projections used by the production metrics helpers.
            if self.columns in ('exercises(name)', 'session_id,exercises(name)'):
                rows = [dict(exercises=r.get('exercises'), **(
                    {'session_id': r['session_id']} if 'session_id' in self.columns else {})) for r in rows]
            elif history:
                rows = [{k: r.get(k) for k in ('weight', 'reps', 'sets_json', 'exercises', 'workout_sessions')} for r in rows]
            else:
                fields = [f.strip() for f in self.columns.split(',')]
                rows = [{k: r[k] for k in fields if k in r} for r in rows]
        call['rows'] = len(rows)
        if self.one:
            if len(rows) != 1:
                call['error'] = True
                raise RuntimeError('Expected one row')
            rows = rows[0]
        return SimpleNamespace(data=rows, count=total if self.count and not t.omit_count else None)


class TestDashboardQueryEfficiency(BaseRouteTest):
    def setUp(self):
        super().setUp()
        self.addCleanup(patch.stopall)
        self.network = patch.object(socket.socket, 'connect', side_effect=AssertionError('Network forbidden')).start()
        self.facade = sys.modules['db']
        self.helper_spies = {}
        for name in ('get_all_exercise_history', 'get_workout_sessions', 'get_today_sessions_all',
                     'get_daily_session_volumes', 'get_workout_session_second', 'get_workout_session_bonus'):
            self.helper_spies[name] = patch.object(self.facade, name, wraps=getattr(db_sessions, name)).start()
        patch.object(db_core, 'MODE', 'ONLINE').start()
        patch.object(db_core, '_is_disconnect', return_value=False).start()
        patch.object(db_sessions, '_today_mtl', return_value=DATE).start()
        patch('utils._today_mtl', return_value=DATE).start()
        patch('planner.get_today_date', return_value=DATE).start()
        patch('planner._montreal_now').start()
        # Keep unrelated collaborators fixed; actual metrics route/weights/sessions run.
        patch('planner.sessions_for_date', return_value=('Upper A', 'Evening plan')).start()
        patch('planner.get_day_plan', return_value={'morning': {'Bench Press': '4x5-7'},
              'evening': {}, 'bonus': {}, 'pushed_to_evening': [], 'pushed_to_bonus': []}).start()
        patch('tdee.compute_target_calories', return_value=2345).start()
        patch.object(self.facade, 'get_smart_goals', return_value=[]).start()
        self.store['hiit_log'] = []
        self.store['goals'] = {'Bench Press': {'goal_weight': 150, 'achieved': False}}

    def measure(self, scenario, cap=1000):
        transport = MetricsTransport(scenario, cap)
        for spy in self.helper_spies.values(): spy.reset_mock()
        with patch.object(db_core, '_client', transport), patch.object(self.facade, '_client', transport):
            response = self.get('/api/dashboard?date=' + DATE)
        self.assertEqual(response.status_code, 200)
        self.assertFalse(transport.writes)
        self.network.assert_not_called()
        return dict(status=response.status_code, json=self.json(response), calls=transport.calls,
                    helpers={k: [dict(args=list(c.args), kwargs=c.kwargs) for c in spy.call_args_list]
                             for k, spy in self.helper_spies.items()})

    def test_reference_parity_and_read_counts(self):
        references = json.loads(REFERENCE.read_text())
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                before = references['scenarios'][scenario]
                after = self.measure(scenario)
                self.assertEqual(after['status'], before['status'])
                self.assertEqual(after['json'], before['json'])
                self.assertEqual(after['helpers'], before['helpers'])
                expected_delta = {'empty': 0, 'no_logs': -1, 'morning_evening': -1,
                                  'pagination': -1, 'partial': -2, 'read_error': 1,
                                  'corrected': -1, 'other_user': -1, 'history_error': -1}
                self.assertEqual(len(after['calls']), len(before['calls']) + expected_delta[scenario])
                self.assertEqual(sum(c['rows'] for c in after['calls']),
                                 sum(c['rows'] for c in before['calls']))
                print('DASHBOARD_METRICS ' + json.dumps(dict(scenario=scenario,
                    before_reads=len(before['calls']), after_reads=len(after['calls']),
                    before_rows=sum(c['rows'] for c in before['calls']),
                    after_rows=sum(c['rows'] for c in after['calls']),
                    history_pages=sum('workout_sessions' in c['select'] for c in after['calls']),
                    parity=True), sort_keys=True))

    def test_business_values_and_source_isolation(self):
        result = self.measure('morning_evening')['json']
        day = result['sessions'][DATE]
        self.assertEqual(day['duration_min'], 50)
        self.assertEqual(day['session_volume'], 2000)
        self.assertEqual(day['session_count'], 2)
        self.assertEqual([s['type'] for s in day['slots']], ['morning', 'evening'])
        self.assertEqual(day['exos'], ['Bench Press', 'Evening only'])
        self.assertEqual(day['comment'], 'AM: First | PM: Second')
        self.assertEqual(day['rpe'], 7)
        self.assertTrue(result['already_logged_today'])
        self.assertTrue(result['second_session_completed'])
        self.assertFalse(result['has_bonus_session'])
        self.assertEqual(result['goals']['Bench Press']['current'], 100)
        self.assertEqual(result['target_calories'], 2345)
        self.assertEqual(self.measure('other_user')['json'], result)
        changed = self.measure('corrected')['json']
        self.assertEqual(changed['goals']['Bench Press']['current'], 125)
        self.assertEqual(changed['sessions'][DATE]['exos'], ['Bench Press', 'Corrected evening'])

    def test_empty_partial_pagination_and_read_failure(self):
        empty = self.measure('empty')['json']
        self.assertFalse(empty['already_logged_today'])
        self.assertIsNone(empty['total_workout_min_today'])
        self.assertEqual(empty['sessions'], {})
        partial = self.measure('partial')['json']
        self.assertTrue(partial['already_logged_today'])
        self.assertFalse(partial['sessions'][DATE]['completed'])
        self.assertIsNone(partial['sessions'][DATE]['session_volume'])
        self.assertEqual(partial['sessions'][DATE]['exos'], ['Bench Press'])
        paged = self.measure('pagination')
        self.assertIn('Tail after page 1000', paged['json']['sessions'][DATE]['exos'])
        self.assertEqual(len(paged['json']['sessions'][DATE]['exos']), 401)
        history = [c for c in paged['calls'] if 'workout_sessions' in c['select']]
        self.assertEqual([c['bounds'] for c in history], [(0, 1000), (1000, 2000)])
        failed = self.measure('read_error')['json']
        self.assertEqual(failed['sessions'][DATE]['exos'], ['Bench Press'])
        self.assertEqual(failed['sessions'][DATE]['session_volume'], 2000)

    def names(self, transport, sessions=None):
        from routes.data_views import _dashboard_logged_names
        if sessions is None:
            sessions = [{'id': 'am'}, {'id': 'pm'}]
        return _dashboard_logged_names(SimpleNamespace(_client=transport), sessions)

    def test_names_paginate_at_actual_transport_cap(self):
        transport = MetricsTransport('morning_evening', cap=2)
        self.assertEqual(self.names(transport), {'Bench Press', 'Evening only'})
        self.assertEqual([c['rows'] for c in transport.calls], [2, 1])
        self.assertEqual(transport.calls[1]['bounds'], (2, 4))
        for call in transport.calls:
            self.assertEqual(call['filters'], [('in', 'session_id', ['am', 'pm'])])
        self.assertFalse(transport.writes)

    def test_names_preserve_single_session_and_empty_paths(self):
        transport = MetricsTransport('morning_evening')
        self.assertEqual(self.names(transport, [{}, {'id': None}]), set())
        self.assertEqual(transport.calls, [])
        self.assertEqual(self.names(transport, [{'id': 'am'}]), {'Bench Press'})
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(transport.calls[0]['filters'], [('eq', 'session_id', 'am')])

    def test_names_fallback_preserves_partial_errors_and_unknown_count(self):
        for missing_count, page_failure in [(True, False), (False, True)]:
            with self.subTest(missing_count=missing_count, page_failure=page_failure):
                transport = MetricsTransport('morning_evening', cap=2)
                transport.omit_count = missing_count
                transport.fail_group_page = page_failure
                self.assertEqual(self.names(transport), {'Bench Press', 'Evening only'})
                self.assertEqual([c['filters'] for c in transport.calls[-2:]],
                                 [[('eq', 'session_id', 'am')], [('eq', 'session_id', 'pm')]])
                self.assertFalse(transport.writes)

    def test_names_do_not_expand_legacy_per_session_cap(self):
        transport = MetricsTransport('morning_evening', cap=1)
        transport.rows['exercise_logs'][2]['exercises']['name'] = 'Beyond legacy cap'
        self.assertEqual(self.names(transport), {'Bench Press', 'Evening only'})
        self.assertEqual([c['filters'] for c in transport.calls[-2:]],
                         [[('eq', 'session_id', 'am')], [('eq', 'session_id', 'pm')]])

    def test_unauthorized_request_never_reads_metrics(self):
        with patch.object(self.idx, '_API_KEY', 'fixture-key'), patch.dict(self.app.config, TESTING=False):
            response = self.get('/api/dashboard?date=' + DATE)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(self.json(response), {'error': 'Unauthorized'})
        for spy in self.helper_spies.values(): spy.assert_not_called()
