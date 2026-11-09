import copy
import json
from pathlib import Path
import subprocess
import sys
import pytest
from exercise_taxonomy import (GROUPS,MUSCLES,PATTERNS,canonical_muscle,canonical_pattern,
                               detailed_target,normalize_metadata,validate_catalogue)
from analytics_adapter import _muscle_assignment
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'docs/audits/catalogue-2026-11-07/pass2'
def read(name):return json.loads((DATA/name).read_text())

def row():
    return dict(id='test',name='Test',muscle_group='Biceps',muscle_specific='Brachial',secondary_muscles=[],
                equipment=['Haltères'],movement_pattern='isolation_arm',weight_type='dumbbell',tracking_type='reps')

def test_complete_catalogue_except_explicit_untouched_ambiguities():
    rows=read('candidate.json');assert len(rows)==161
    ambiguous={a['id'] for a in read('ambiguous.json')}
    findings=validate_catalogue(rows)
    assert all(f['id'] in ambiguous for f in findings),json.dumps(findings,ensure_ascii=False,indent=2)
    # Every remaining ambiguous row is byte-for-data unchanged, not made clean by guesswork.
    before={r['id']:r for r in read('before.json')}
    assert all(r==before[r['id']] for r in rows if r['id'] in ambiguous)
    assert sum(not r['deleted_at'] for r in rows)==142
    assert not [f for f in findings if f['code']=='missing_primary']

def test_canonical_vocabulary_is_closed_and_aliases_resolve():
    from exercise_taxonomy_data import TAXONOMY
    for m in MUSCLES:assert canonical_muscle(m)==m,m
    for alias,target in TAXONOMY['muscle_aliases'].items():assert canonical_muscle(alias)==target,(alias,target)
    assert set(TAXONOMY['pattern_aliases'].values()) <= set(PATTERNS)
    assert len(PATTERNS)==17
    assert 'legs' not in GROUPS and 'arms' not in GROUPS
    assert 'Hanches' in GROUPS # existing editor group, not a new adductors group

@pytest.mark.parametrize('mutation,code',[
    ({'id':None},'identity'),({'name':''},'identity'),
    ({'muscle_group':None,'muscle_specific':None},'missing_primary'),
    ({'muscle_specific':['Brachial','Brachial']},'invalid_primary'),
    ({'muscle_specific':'Imaginary'},'unknown_muscle'),
    ({'muscle_group':'legs'},'unknown_group'),
    ({'muscle_group':'Pectoraux'},'incompatible_group'),
    ({'secondary_muscles':['Brachial']},'overlap'),
    ({'secondary_muscles':['Brachialis','Brachial']},'duplicate_secondary'),
    ({'equipment':['spaceship']},'invalid_equipment'),
    ({'weight_type':'strength'},'invalid_load'),
    ({'movement_pattern':'new_enum'},'invalid_pattern')])
def test_quality_failures_identify_row(mutation,code):
    r=row();r.update(mutation);fs=validate_catalogue([r])
    assert any(f['code']==code for f in fs)
    assert all(f['id']==r['id'] and f['name']==r['name'] for f in fs)

def test_archived_invalid_taxonomy_is_checked_but_missing_legacy_data_tolerated():
    r=dict(id='archived',name='Old',deleted_at='date',tracking_type='reps')
    assert validate_catalogue([r])==[]
    r.update(muscle_specific='Imaginary',weight_type='bad')
    assert {'unknown_muscle','invalid_load'} <= {f['code'] for f in validate_catalogue([r])}

def test_non_strength_regions_are_intentional_exceptions_only():
    for modality in ['cardio','interval','protocol','mobility']:
        r=dict(id=modality,name=modality,tracking_type=modality,muscle_group='Autre',muscle_specific='Thoracique')
        assert validate_catalogue([r])==[]
    r['tracking_type']='reps'
    assert any(f['code']=='unknown_muscle' for f in validate_catalogue([r]))

def test_every_canonical_target_survives_workload_analytics():
    for target in MUSCLES:
        result=_muscle_assignment(dict(name='Test',muscle_specific=target))
        assert result.direct_muscles==(target,),target
    assert detailed_target('Deltoïde antérieur')!=detailed_target('Deltoïde postérieur')
    assert detailed_target('Droit abdominal')!=detailed_target('Obliques')
    assert detailed_target('Grand dorsal')!=detailed_target('Haut du dos')

def test_alias_normalization_idempotent_and_load_immutable():
    for r in read('before.json'):
        n=normalize_metadata(r)
        assert normalize_metadata(n)==n
        for k in ['id','name','type','weight_type','bar_weight','increment','default_scheme','tracking_type','is_unilateral']:
            assert n.get(k)==r.get(k),(r['name'],k)

def test_all_corrections_preserve_ids_history_contract_and_landmine():
    before=read('before.json');candidate=read('candidate.json')
    protected=['id','name','type','bar_weight','increment','default_scheme','tracking_type','rest_seconds','load_profile','deleted_at','tips','alternate_name','muscles']
    for b,a in zip(before,candidate):
        assert all(b[k]==a[k] for k in protected),(b['name'],{k for k in protected if b[k]!=a[k]})
    meadows=next(r for r in candidate if r['name']=='Meadows Row')
    assert (meadows['type'],meadows['weight_type'],meadows['bar_weight'])==('landmine','landmine',45)

def test_client_taxonomy_matches_backend():
    subprocess.run([sys.executable,str(ROOT/'scripts/generate_catalogue_taxonomy_swift.py'),'--check'],check=True)

def test_pattern_aliases_feed_existing_dna_ratios():
    assert canonical_pattern('Hip Hinge')=='hinge'
    assert canonical_pattern('Horizontal Push')=='push_horizontal'
    assert canonical_pattern('Isolation','Quadriceps')=='isolation_leg'
    assert canonical_pattern('Plyometric') is None # requires exercise context, never guessed globally

def test_volume_aliases_merge_without_losing_training_distinctions(monkeypatch):
    import muscle_volume
    logs=[dict(muscle_group='Core',muscle_specific=s,sets_json=[dict(reps=8)])
          for s in ['Droit abdominal',"Droit de l'abdomen",'Obliques']]
    monkeypatch.setattr(muscle_volume.db,'get_exercise_logs_since',lambda cutoff: copy.deepcopy(logs))
    result=muscle_volume.compute_weekly_hard_sets()
    assert result['Droit abdominal']['sets']==2
    assert result['Obliques']['sets']==1
    assert len(result)==2


def test_duplicate_ids_and_names_rejected():
    assert {'id','name'} <= {f['field'] for f in validate_catalogue([row(),row()])}

def test_verified_production_matches_only_safe_plan_and_preserves_archived_rows():
    before=read('before.json');after=read('after.json')
    expected={r['id']:copy.deepcopy(r) for r in before}
    for change in read('corrections.json'):
        r=expected[change['id']]
        assert not r['deleted_at']
        assert {k:r[k] for k in change['before']}==change['before']
        r.update(change['after'])
    assert after==[expected[r['id']] for r in before]
    ambiguous={a['id'] for a in read('ambiguous.json')}
    assert all(a==b for a,b in zip(after,before) if b['deleted_at'] or b['id'] in ambiguous)
    # Pending deltas are a reviewable local projection, not silently applied data.
    projected={r['id']:copy.deepcopy(r) for r in after}
    for change in read('pending.json'):
        r=projected[change['id']]
        assert {k:r[k] for k in change['before']}==change['before']
        r.update(change['after'])
    assert list(projected.values())==read('candidate.json')

def test_reporting_bucket_is_not_an_anatomical_alias_for_every_member():
    from exercise_taxonomy import redundant_broad_secondary
    assert not redundant_broad_secondary('Brachial','Biceps')
    assert not redundant_broad_secondary('Tibial antérieur','Mollets')
    assert redundant_broad_secondary('Pectoral supérieur','Pectoraux')
    assignment=_muscle_assignment(dict(name='Hammer curl',muscle_specific='Brachial',secondary_muscles=['Biceps']))
    assert assignment.indirect_muscles==('Biceps',)


@pytest.mark.parametrize("label,expected", [
    ("Hanches", "Hanches"), ("Autre", "Autre"),
    ("Brachialis", "Brachial"), ("Brachial", "Brachial"),
    ("rotator_cuff", "Coiffe des rotateurs"), ("Coiffe des rotateurs", "Coiffe des rotateurs"),
    ("hip_flexors", "Fléchisseurs de hanche"), ("Fléchisseurs de hanche", "Fléchisseurs de hanche"),
])
def test_release_transition_keeps_targets_and_original_history(label, expected):
    original = dict(name="Transition", muscle_group=label, muscle_specific=label,
                    secondary_muscles=[], equipment=["dip_bars", "medicine ball"],
                    default_scheme="3x8", bar_weight=45, type="landmine", tracking_type="reps")
    snapshot = copy.deepcopy(original)
    normalized = normalize_metadata(original)
    assignment = _muscle_assignment(normalized)
    assert assignment.direct_muscles == (expected,)
    assert normalized["equipment"] == ["dip_bars", "medicine ball"]
    assert original == snapshot
    assert {k: normalized[k] for k in ("default_scheme", "bar_weight", "type", "tracking_type")} == {
        k: original[k] for k in ("default_scheme", "bar_weight", "type", "tracking_type")}
