"""Tests sécurité boundary RPC privilégiée.

Phase 1 audit RLS (2026-11) : le client Supabase principal utilise désormais
SUPABASE_SERVICE_ROLE_KEY (plus de repli sur anon). La séparation anon/service
historique a disparu — il n'y a qu'un seul client service_role.

Invariants préservés dans ce fichier :
  - les RPC (apply_progression, save_full_program_atomic) ne fuitent jamais
    le secret dans les logs ou la réponse HTTP ;
  - un échec de factory / RPC renvoie 503 sans trace du secret ;
  - en mode OFFLINE, la RPC refuse sans initialiser de client.
"""
import os
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

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
        self.service = Mock(name='service_role')
        self.service.rpc.return_value.execute.return_value.data = dict(success=True, status=200)
        self.factory = Mock(return_value=self.service)
        sdk = types.ModuleType('supabase')
        sdk.Client = Mock
        sdk.create_client = self.factory
        env = patch.dict(os.environ, {
            'APP_DATA_MODE':             'ONLINE',
            'SUPABASE_URL':              'https://fixture.supabase.co',
            'SUPABASE_SERVICE_ROLE_KEY': 'fixture-service-secret',
        }, clear=True)
        env.start(); self.addCleanup(env.stop)
        with patch.dict(sys.modules, {'supabase': sdk}):
            self.core = load('db_core')
        p = patch.object(self.core, '_make_supabase_client', self.factory)
        p.start(); self.addCleanup(p.stop)
        p = patch.dict(sys.modules, {'db_core': self.core})
        p.start(); self.addCleanup(p.stop)
        self.ex = load('db_exercises')
        self.db.apply_progression_atomic = self.ex.apply_progression_atomic
        self.db.update_exercise_default_scheme = Mock()
        self.db.update_exercise_current_weight = Mock()

    def test_apply_progression_uses_service_client(self):
        response = self.client.post('/api/apply_progression', json=self.payload)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.service.rpc.call_count, 1)
        self.assertEqual(self.service.rpc.call_args.args[0], 'apply_progression')

    def test_missing_service_key_fails_closed(self):
        del os.environ['SUPABASE_SERVICE_ROLE_KEY']
        response = self.client.post('/api/apply_progression', json=self.payload)
        self.assertEqual(response.status_code, 503)
        self.db.update_exercise_default_scheme.assert_not_called()
        self.db.update_exercise_current_weight.assert_not_called()
        with self.assertRaisesRegex(RuntimeError, 'service-role client unavailable'):
            self.core.get_service_supabase()

    def test_factory_failure_does_not_leak_secret(self):
        self.factory.side_effect = RuntimeError('fixture-service-secret')
        with self.assertLogs(level='ERROR') as logs:
            response = self.client.post('/api/apply_progression', json=self.payload)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('fixture-service-secret',
                         response.get_data(as_text=True) + '\n'.join(logs.output))

    def test_rpc_failure_does_not_leak_secret(self):
        self.service.rpc.side_effect = RuntimeError('fixture-service-secret')
        with self.assertLogs(level='ERROR') as logs:
            response = self.client.post('/api/apply_progression', json=self.payload)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('fixture-service-secret',
                         response.get_data(as_text=True) + '\n'.join(logs.output))

    def test_offline_never_initializes_service(self):
        self.core.MODE = 'OFFLINE'
        with self.assertRaises(RuntimeError):
            self.ex.apply_progression_atomic(self.payload)

    def test_only_atomic_helpers_consume_privileged_factory(self):
        """get_service_supabase() reste réservé aux RPC atomiques privilégiées.
        Pour les autres accès DB, le _client principal (service_role depuis
        Phase 1) suffit — pas besoin d'instancier un 2e client."""
        consumers = []
        for path in (ROOT / 'api').rglob('*.py'):
            if path.name != 'db_core.py' and 'get_service_supabase(' in path.read_text():
                consumers.append(str(path.relative_to(ROOT)))
        self.assertEqual(sorted(consumers),
                         sorted(['api/db_exercises.py', 'api/db_programs.py']))


if __name__ == '__main__':
    unittest.main()
