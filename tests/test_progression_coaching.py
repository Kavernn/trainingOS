"""R11 coaching contracts. No app startup, credentials or network; isolated DB doubles."""
import sys, types, unittest, importlib, inspect, copy
from pathlib import Path
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'api'))
from flask import Flask
from routes.workout_schedule import workout_schedule_bp

class CoachingContracts(unittest.TestCase):
    def setUp(self):
        self.state = dict(current_weight=100, default_scheme='3x12')
        self.db = types.ModuleType('db')
        self.db.update_exercise_default_scheme = lambda n,s: self.state.update(default_scheme=s) or True
        self.db.update_exercise_current_weight = lambda n,w: self.state.update(current_weight=w) or True
        self.db.get_active_program_id = lambda **kw: '00000000-0000-0000-0000-000000000001'
        self.db.get_exercises_info_bulk = lambda names, **kw: {'X':dict(self.state, type='cable',load_profile='compound_hypertrophy')}
        self.db.apply_progression_atomic = self.atomic
        self.patch = patch.dict(sys.modules, {'db':self.db});self.patch.start();self.addCleanup(self.patch.stop)
        import smart_progression
        self.sp=smart_progression
        self.sp_patch=patch.object(self.sp,'db',self.db);self.sp_patch.start();self.addCleanup(self.sp_patch.stop)
        self.app=Flask('coaching');self.app.register_blueprint(workout_schedule_bp)
        self.client=self.app.test_client()
        self.payload=dict(exercise_name='X',suggested_weight=105,suggested_scheme='4x12',expected_current_weight=100,expected_current_scheme='3x12',session_date='2026-10-02',session_type='evening',session_name='A',program_id=self.db.get_active_program_id())
    def atomic(self, payload):
        if payload['expected_current_weight'] != self.state['current_weight'] or payload['expected_current_scheme'] != self.state['default_scheme']:
            return {'success':False,'status':409,'error':'stale'}
        after=self.state.copy()
        if payload.get('suggested_weight') is not None: after['current_weight']=payload['suggested_weight']
        if payload.get('suggested_scheme') is not None: after['default_scheme']=payload['suggested_scheme']
        self.state=after
        return dict(success=True,status=200,applied_weight=after['current_weight'],applied_scheme=after['default_scheme'],current_weight=after['current_weight'],current_scheme=after['default_scheme'])
    def apply_helper(self, **overrides):
        payload=dict(self.payload,**overrides)
        # Baseline adapter calls the existing helper; fixed helper accepts the full CAS contract.
        if 'context' in inspect.signature(self.sp.apply_suggestion).parameters:
            return self.sp.apply_suggestion('X',payload['suggested_weight'],payload['suggested_scheme'],context=payload)
        return self.sp.apply_suggestion('X',payload['suggested_weight'],payload['suggested_scheme'])
    def test_apply_route_exists(self):
        r=self.client.post('/api/apply_progression',json=self.payload)
        self.assertEqual(r.status_code,200);self.assertTrue(r.json['success'])
    def test_partial_write_cannot_leave_scheme_changed(self):
        self.db.update_exercise_current_weight=lambda *a:False
        self.db.apply_progression_atomic=lambda p:dict(success=False,status=500,error='fixture transaction failure')
        self.apply_helper();self.assertEqual(self.state,dict(current_weight=100,default_scheme='3x12'))
    def test_stale_weight_does_not_overwrite(self):
        self.state['current_weight']=110
        self.apply_helper();self.assertEqual(self.state['current_weight'],110)
    def test_stale_scheme(self):
        self.state['default_scheme']='5x12';r=self.client.post('/api/apply_progression',json=self.payload)
        self.assertEqual(r.status_code,409);self.assertEqual(self.state['default_scheme'],'5x12')
    def test_weight_only(self):
        r=self.client.post('/api/apply_progression',json=dict(self.payload,suggested_scheme=None))
        self.assertEqual(r.status_code,200);self.assertEqual(self.state,dict(current_weight=105,default_scheme='3x12'))
    def test_scheme_only(self):
        r=self.client.post('/api/apply_progression',json=dict(self.payload,suggested_weight=None))
        self.assertEqual(r.status_code,200);self.assertEqual(self.state,dict(current_weight=100,default_scheme='4x12'))
    def test_invalid_payloads(self):
        for change in [dict(suggested_weight=-1),dict(suggested_weight=True),dict(suggested_weight='100'),dict(suggested_scheme='bad'),dict(session_type='bad'),dict(session_date='2026-02-30'),dict(session_name=''),dict(suggested_weight=None,suggested_scheme=None)]:
            with self.subTest(change=change):self.assertEqual(self.client.post('/api/apply_progression',json=dict(self.payload,**change)).status_code,400)
    def test_retry_is_conflict_not_second_write(self):
        self.assertEqual(self.client.post('/api/apply_progression',json=self.payload).status_code,200)
        self.assertEqual(self.client.post('/api/apply_progression',json=self.payload).status_code,409)
    def test_missing_exercise_http_404(self):
        self.db.apply_progression_atomic=lambda p:dict(success=False,status=404,error='missing')
        self.assertEqual(self.client.post('/api/apply_progression',json=self.payload).status_code,404)
    def test_internal_failure_http_503(self):
        self.db.apply_progression_atomic=Mock(side_effect=RuntimeError('fixture rollback'))
        self.assertEqual(self.client.post('/api/apply_progression',json=self.payload).status_code,503)
    def test_undo_restores_both_and_is_cas(self):
        self.client.post('/api/apply_progression',json=self.payload)
        undo=dict(self.payload,suggested_weight=100,suggested_scheme='3x12',expected_current_weight=105,expected_current_scheme='4x12')
        self.assertEqual(self.client.post('/api/apply_progression',json=undo).status_code,200)
        self.assertEqual(self.state,dict(current_weight=100,default_scheme='3x12'))
        self.assertEqual(self.client.post('/api/apply_progression',json=undo).status_code,409)



class SuggestionContracts(unittest.TestCase):
    atomic = CoachingContracts.atomic
    def setUp(self):
        CoachingContracts.setUp(self)
        utils=types.ModuleType('utils');utils.get_mesocycle_info=lambda:{'phase':None};utils._today_mtl=lambda:'2026-10-02'
        planner=types.ModuleType('planner');planner.load_program=lambda:{};planner.get_day_plan=lambda *a:{'morning':{'X':'3x12'},'evening':{'X':'3x12'},'bonus':{'X':'3x12'}}
        extra=patch.dict(sys.modules,{'utils':utils,'planner':planner});extra.start();self.addCleanup(extra.stop)
        self.db.get_progression_session=lambda *a,**kw:dict(id='prev' if kw.get('previous') else 'now',date='2026-09-30' if kw.get('previous') else '2026-10-02')
        self.db.get_exercise_logs_for_session_with_names=lambda *a,**kw:[dict(exercise_name='X',weight=100,reps='12',sets_json=[dict(weight=100,reps=12)]*3)]
        self.db.get_exercise_history_bulk=lambda *a,**kw:{'X':[]}
    def suggestions(self,**overrides):
        return self.client.get('/api/progression_suggestions',query_string=dict(date='2026-10-02',session_type='evening',session_name='A',**overrides))
    def test_actionable_snapshot_and_equipment(self):
        r=self.suggestions();self.assertEqual(r.status_code,200)
        s=r.json['suggestions'][0];self.assertEqual(s['suggested_weight'],102.5);self.assertEqual(s['expected_current_weight'],100);self.assertEqual(s['expected_current_scheme'],'3x12');self.assertTrue(s['reference_available'])
    def test_maintain_only_valid(self):
        self.db.get_exercise_logs_for_session_with_names=lambda *a,**kw:[{'exercise_name':'X'}]
        r=self.suggestions();self.assertEqual(r.status_code,200);self.assertEqual(r.json['suggestions'][0]['suggestion_type'],'maintain')
    def test_empty_insufficient_history(self):
        self.db.get_progression_session=lambda *a,**kw:None
        self.assertEqual(self.suggestions().json,{'suggestions':[]})
    def test_missing_load_profile_is_valid_exclusion(self):
        self.db.get_exercises_info_bulk=lambda *a,**kw:{'X':dict(default_scheme='3x12')}
        self.assertEqual(self.suggestions().json,{'suggestions':[]})
    def test_invalid_context_is_400(self):
        for change in [dict(date='bad'),dict(session_type='bad'),dict(session_name='')]:
            params=dict(date='2026-10-02',session_type='morning',session_name='A');params.update(change)
            self.assertEqual(self.client.get('/api/progression_suggestions',query_string=params).status_code,400)
    def test_db_exception_is_not_empty(self):
        self.db.get_progression_session=Mock(side_effect=RuntimeError('fixture DB'))
        self.assertEqual(self.suggestions().status_code,503)
    def test_equipment_matrix_keeps_existing_rules(self):
        for equipment,increment in [('barbell',5),('dumbbell',5),('machine',5),('cable',2.5),('bodyweight',5)]:
            with self.subTest(equipment=equipment):
                self.db.get_exercises_info_bulk=lambda *a,equipment=equipment,**kw:{'X':dict(self.state,load_profile='compound_hypertrophy',type=equipment)}
                self.assertEqual(self.suggestions().json['suggestions'][0]['suggested_weight'],100+increment)

class Query:
    def __init__(self, rows):self.rows=copy.deepcopy(rows);self.projection=None;self.orders=[];self.bounds=None
    def select(self,value):self.projection=value;return self
    def eq(self,k,v):self.rows=[r for r in self.rows if r.get(k)==v];return self
    def lt(self,k,v):self.rows=[r for r in self.rows if r.get(k)<v];return self
    def in_(self,k,v):self.rows=[r for r in self.rows if r.get(k) in v];return self
    def is_(self,k,v):self.rows=[r for r in self.rows if r.get(k) is None];return self
    def order(self,k,desc=False):self.orders.append((k,desc));return self
    def range(self,a,b):self.bounds=(a,b);return self
    def execute(self):
        rows=self.rows
        for k,desc in reversed(self.orders):rows=sorted(rows,key=lambda r:r.get(k,''),reverse=desc)
        if self.bounds:rows=rows[self.bounds[0]:self.bounds[1]+1]
        return types.SimpleNamespace(data=rows)

class DatabaseContracts(unittest.TestCase):
    def setUp(self):
        self.rows=[];self.queries=[]
        self.core=types.ModuleType('db_core');self.core.MODE='ONLINE';self.core._client=types.SimpleNamespace(table=self.table)
        self.core._is_disconnect=lambda e:False;self.core.logger=Mock()
        util=types.ModuleType('utils');util._today_mtl=lambda:'2026-10-02'
        patcher=patch.dict(sys.modules,{'db_core':self.core,'utils':util});patcher.start();self.addCleanup(patcher.stop)
        # Load the actual DB helpers against a credential-free in-memory query boundary.
        self.ex=self.load('db_exercises');p=patch.dict(sys.modules,{'db_exercises':self.ex});p.start();self.addCleanup(p.stop)
        self.sessions=self.load('db_sessions')
    def load(self,name):
        m=types.ModuleType(name);exec(compile((Path(__file__).resolve().parents[1]/'api'/f'{name}.py').read_text(),name+'.py','exec'),m.__dict__);return m
    def table(self,name):
        q=Query(getattr(self,"tables",{}).get(name,self.rows));self.queries.append(q);return q
    def session(self,id,slot='morning',name='A',program=None):return dict(id=id,date='2026-09-30',session_type=slot,session_name=name,program_id=program)
    def lookup(self,slot='morning'):return self.sessions.get_progression_session('2026-10-02',slot,'A',['X'],previous=True,program_id='p1')
    def test_same_name_prefers_same_type(self):
        self.rows=[self.session('pm','evening'),self.session('am')];self.assertEqual(self.lookup()['id'],'am')
    def test_known_program_identity_is_filtered(self):
        self.rows=[self.session('other',program='p2'),self.session('own',program='p1')];self.assertEqual(self.lookup()['id'],'own')
    def test_legacy_null_name_with_overlap(self):
        self.rows=[self.session('legacy',name=None)];self.sessions.get_exercise_logs_for_session_with_names=lambda *a,**kw:[{'exercise_name':'X'}]
        self.assertEqual(self.lookup()['id'],'legacy')
    def test_moved_am_pm_requires_overlap(self):
        self.rows=[self.session('moved','evening')];self.sessions.get_exercise_logs_for_session_with_names=lambda *a,**kw:[{'exercise_name':'X'}]
        self.assertEqual(self.lookup()['id'],'moved')
        self.sessions.get_exercise_logs_for_session_with_names=lambda *a,**kw:[];self.assertIsNone(self.lookup())
    def test_bonus_prefers_bonus(self):
        self.rows=[self.session('am'),self.session('bonus','bonus')];self.assertEqual(self.lookup('bonus')['id'],'bonus')
    def test_current_wrong_name_rejected(self):
        self.rows=[dict(self.session('wrong',name='B'),date='2026-10-02')]
        self.assertIsNone(self.sessions.get_progression_session('2026-10-02','morning','A',['X']))
    def test_history_cutoff_precedes_limit(self):
        self.tables={'exercises':[{'id':'e','name':'X'}], 'exercise_logs':[
            {'exercise_id':'e','weight':200,'reps':'12','workout_sessions':{'date':'2026-10-03'}},
            {'exercise_id':'e','weight':100,'reps':'12','workout_sessions':{'date':'2026-10-01'}}]}
        history=self.sessions.get_exercise_history_bulk(['X'],limit_per=1,strict=True,cutoff='2026-10-02')
        self.assertEqual(history['X'][0]['weight'],100)
    def test_projection_includes_equipment_and_reference(self):
        self.rows=[dict(name='X',type='cable',current_weight=100)]
        self.sessions.get_exercises_info_bulk(['X'],strict=True)
        fields={s.strip() for s in self.queries[-1].projection.split(',')}
        self.assertTrue({'type','current_weight','default_scheme'}.issubset(fields))
    def test_strict_db_error_propagates(self):
        self.core._client.table=Mock(side_effect=RuntimeError('fixture'))
        with self.assertRaises(RuntimeError):self.sessions.get_exercises_info_bulk(['X'],strict=True)
        self.assertEqual(self.sessions.get_exercises_info_bulk(['X']),{})
    def test_apply_uses_one_rpc_and_no_split_table_writes(self):
        self.core.get_service_supabase=Mock(return_value=types.SimpleNamespace(rpc=Mock()))
        self.core.get_service_supabase.return_value.rpc=Mock(return_value=types.SimpleNamespace(execute=lambda:types.SimpleNamespace(data={'success':True})))
        self.core._client.table=Mock(side_effect=AssertionError('split write'))
        self.assertTrue(self.ex.apply_progression_atomic({'fixture':True})['success'])
        self.core.get_service_supabase.return_value.rpc.assert_called_once_with('apply_progression',{'p':{'fixture':True}})
    def test_rpc_failure_never_falls_back_to_partial_setters(self):
        self.core.get_service_supabase=Mock(return_value=types.SimpleNamespace(rpc=Mock()))
        self.core.get_service_supabase.return_value.rpc=Mock(side_effect=RuntimeError('transaction aborted'))
        self.core._client.table=Mock(side_effect=AssertionError('split write'))
        with self.assertRaises(RuntimeError):self.ex.apply_progression_atomic({})
        self.core._client.table.assert_not_called()

    def weights_module(self):
        db=types.ModuleType('db');volume=types.ModuleType('volume');volume.calc_exercise_volume=lambda *a,**kw:0
        with patch.dict(sys.modules,{'db':db,'volume':volume}):return self.load('weights')
    def test_confirmed_reference_owns_next_prefill_even_zero(self):
        weights_module=self.weights_module()
        self.rows=[dict(name='X',current_weight=0,default_scheme='3x12',progression_reference=True)]
        refs=weights_module.coaching_references(['X'])
        weights={'X':{'current_weight':110,'history':[{'weight':100}]}};suggestions=[dict(exercise='X',display='old')]
        weights_module.overlay_coaching_weights(weights,suggestions,refs)
        self.assertEqual(weights['X']['current_weight'],0);self.assertEqual(weights['X']['history'],[{'weight':100}]);self.assertIn('0 lbs',suggestions[0]['display'])
    def test_approved_scheme_uncapped_only_in_its_programme_and_without_override(self):
        w=self.weights_module();blocks=types.ModuleType('blocks');blocks.get_strength_exercises=lambda value:value
        sys.modules['utils'].cap_scheme_sets=lambda s:'3x12' if s=='4x12' else s
        refs={'X':{'progression_schemes':{'p1/A':'4x12'}}};full={'A':{'X':'4x12'}}
        with patch.dict(sys.modules,{'blocks':blocks}):
            flat={'A':{'X':'3x12'}};w.restore_coaching_schemes(flat,full,refs,'p1');self.assertEqual(flat['A']['X'],'4x12')
            flat={'A':{'X':'3x12'}};w.restore_coaching_schemes(flat,full,refs,'p2');self.assertEqual(flat['A']['X'],'3x12')
            flat={'A':{'X':'2x12'}};w.restore_coaching_schemes(flat,full,refs,'p1');self.assertEqual(flat['A']['X'],'2x12')

if __name__=='__main__': unittest.main()
