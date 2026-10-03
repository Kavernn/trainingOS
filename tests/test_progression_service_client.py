"""Dedicated privileged RPC boundary; fake credentials and no network."""
import os
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'api'))
import test_progression_coaching as coaching

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    module = types.ModuleType(name)
    module.__file__ = str(ROOT / 'api' / (name + '.py'))
    exec(compile(Path(module.__file__).read_text(), module.__file__, 'exec'), module.__dict__)
    return module


class ServiceClientContracts(unittest.TestCase):
    atomic = coaching.CoachingContracts.atomic

    def setUp(self):
        coaching.CoachingContracts.setUp(self)
        self.anon = Mock(name='anon')
        self.anon.rpc.side_effect = PermissionError('permission denied for function apply_progression')
        self.service = Mock(name='service_role')
        self.service.rpc.return_value.execute.return_value.data = dict(success=True, status=200)
        self.factory = Mock(side_effect=lambda url, key: self.anon if key == 'fixture-anon' else self.service)
        sdk = types.ModuleType('supabase')
        sdk.Client = Mock
        sdk.create_client = self.factory
        env = patch.dict(os.environ, {'APP_DATA_MODE':'ONLINE', 'SUPABASE_URL':'https://fixture.supabase.co', 'SUPABASE_ANON_KEY':'fixture-anon'}, clear=True)
        env.start(); self.addCleanup(env.stop)
        with patch.dict(sys.modules, {'supabase':sdk}):
            self.core = load('db_core')
        p = patch.object(self.core, '_make_supabase_client', self.factory)
        p.start(); self.addCleanup(p.stop)
        p = patch.dict(sys.modules, {'db_core':self.core})
        p.start(); self.addCleanup(p.stop)
        self.ex = load('db_exercises')
        self.db.apply_progression_atomic = self.ex.apply_progression_atomic
        self.db.update_exercise_default_scheme = Mock()
        self.db.update_exercise_current_weight = Mock()

    def test_missing_secret_fails_closed_without_anon_or_legacy(self):
        response = self.client.post('/api/apply_progression', json=self.payload)
        self.assertEqual(response.status_code, 503)
        self.anon.rpc.assert_not_called()
        self.db.update_exercise_default_scheme.assert_not_called()
        self.db.update_exercise_current_weight.assert_not_called()
        with self.assertRaisesRegex(RuntimeError, 'service-role client unavailable'):
            self.core.get_service_supabase()

    def test_apply_and_undo_use_only_dedicated_client(self):
        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'fixture-service-secret'
        for payload in [self.payload, dict(self.payload, restore=True, suggested_weight=100, suggested_scheme='3x12', expected_current_weight=105, expected_current_scheme='4x12')]:
            self.assertEqual(self.client.post('/api/apply_progression', json=payload).status_code, 200)
        self.assertEqual(self.service.rpc.call_count, 2)
        self.assertEqual(self.service.rpc.call_args.args, ('apply_progression', {'p':dict(self.payload, restore=True, suggested_weight=100, suggested_scheme='3x12', expected_current_weight=105, expected_current_scheme='4x12')}))
        self.anon.rpc.assert_not_called()
        self.assertIs(self.core.client(), self.anon)

    def test_factory_is_lazy_and_singleton_under_concurrency(self):
        self.factory.assert_called_once_with('https://fixture.supabase.co', 'fixture-anon')
        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'fixture-service-secret'
        with ThreadPoolExecutor(max_workers=8) as pool:
            clients = list(pool.map(lambda _:self.core.get_service_supabase(), range(20)))
        self.assertTrue(all(c is self.service for c in clients))
        self.assertEqual(self.factory.call_count, 2)
        self.assertIs(self.core._client, self.anon)

    def test_factory_failure_does_not_leak_secret_in_logs_or_http(self):
        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'fixture-service-secret'
        self.factory.side_effect = RuntimeError('fixture-service-secret')
        with self.assertLogs(level='ERROR') as logs:
            response = self.client.post('/api/apply_progression', json=self.payload)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('fixture-service-secret', response.get_data(as_text=True) + '\n'.join(logs.output))
        self.anon.rpc.assert_not_called()

    def test_rpc_failure_does_not_leak_secret_or_fallback(self):
        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'fixture-service-secret'
        self.service.rpc.side_effect = RuntimeError('fixture-service-secret')
        with self.assertLogs(level='ERROR') as logs:
            response = self.client.post('/api/apply_progression', json=self.payload)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('fixture-service-secret', response.get_data(as_text=True) + '\n'.join(logs.output))
        self.anon.rpc.assert_not_called()

    def test_offline_never_initializes_service(self):
        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'fixture-service-secret'
        self.core.MODE = 'OFFLINE'
        with self.assertRaises(RuntimeError): self.ex.apply_progression_atomic(self.payload)
        self.factory.assert_called_once()

    def test_normal_reads_stay_anon(self):
        os.environ['SUPABASE_SERVICE_ROLE_KEY'] = 'fixture-service-secret'
        self.anon.table.return_value.select.return_value.eq.return_value.is_.return_value.single.return_value.execute.return_value.data = {'id':'fixture'}
        self.ex.get_exercise_by_name('X')
        self.anon.table.assert_called_once_with('exercises')
        self.service.assert_not_called()
        self.factory.assert_called_once()

    def test_only_atomic_helper_consumes_privileged_factory(self):
        consumers = []
        for path in (ROOT / 'api').rglob('*.py'):
            if path.name != 'db_core.py' and 'get_service_supabase(' in path.read_text():
                consumers.append(str(path.relative_to(ROOT)))
        self.assertEqual(consumers, ['api/db_exercises.py'])


if __name__ == '__main__':
    unittest.main()
