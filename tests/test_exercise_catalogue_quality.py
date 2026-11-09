"""Full-catalogue regression coverage; strict quality gate is the audit CLI.

Unresolved taxonomy findings are explicit, not accepted as clean exercises.
A new finding (or a resolved one) changes the reviewed ledger and fails here.
"""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT/'docs/audits/catalogue-2026-11-07'
spec = importlib.util.spec_from_file_location('catalogue_audit', ROOT/'scripts/audit_exercise_catalogue_legacy.py')
audit_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_module)
audit = audit_module.audit


def fixture():
    return dict(id='test-id', name='Test curl', muscle_group='Biceps+Avant-bras',
                muscle_specific='Brachial', secondary_muscles=[], equipment=['Haltères'],
                type='dumbbell', weight_type='dumbbell', movement_pattern='isolation_arm',
                category='pull', pattern='isolation', load_profile='isolation',
                tracking_type='reps', is_unilateral=False, deleted_at=None)


def test_valid_existing_contract():
    assert audit([fixture()]) == []


def test_identity_name_and_strength_primary_errors_include_exercise():
    row=fixture()
    row.update(id=None, name='', muscle_group=None, muscle_specific=None, secondary_muscles=['Brachial'])
    findings=audit([row])
    assert {'id','name','muscle_specific','muscle_group','secondary_muscles'} <= {f['field'] for f in findings}
    assert all(f['id'] is None and f['name']=='' for f in findings)


def test_duplicate_ids_and_homonyms():
    assert {'id','name'} <= {f['field'] for f in audit([fixture(),fixture()])}


def test_unknown_muscles_group_load_and_incompatible_group():
    row=fixture(); row.update(muscle_specific='Invented muscle', muscle_group='Invented group', weight_type='strength')
    assert {'muscles','muscle_group','weight_type'} <= {f['field'] for f in audit([row])}
    row=fixture(); row['muscle_group']='Pectoraux'
    assert any('Editor places' in f['detail'] for f in audit([row]))


def test_duplicate_secondary_and_primary_overlap_through_synonym():
    row=fixture(); row['secondary_muscles']=['Brachialis','Brachial']
    findings=audit([row])
    assert any('Duplicate secondary' in f['detail'] for f in findings)
    assert any('Primary also secondary' in f['detail'] for f in findings)
    row['muscle_specific']=['Brachial','Brachial']
    assert any('Primary must be scalar' in f['detail'] for f in audit([row]))


def test_optional_non_strength_metadata():
    for modality in ('cardio','interval','mobility','protocol'):
        row=fixture(); row.update(tracking_type=modality, muscle_group=None, muscle_specific=None,
                                 secondary_muscles=None, equipment=None, type=None, load_profile=None)
        assert audit([row]) == []


def test_all_catalogue_rows_match_explicit_unresolved_ledger():
    rows=json.loads((DATA/'after.json').read_text())
    expected=json.loads((DATA/'unresolved.json').read_text())
    assert len(rows)==161
    assert len([r for r in rows if not r['deleted_at']])==142
    actual=audit(rows)
    assert actual==expected, json.dumps(actual,ensure_ascii=False,indent=2)


def test_only_reviewed_metadata_changed_and_ambiguous_archived_rows_untouched():
    before=json.loads((DATA/'before.json').read_text())
    after=json.loads((DATA/'after.json').read_text())
    plan=json.loads((DATA/'corrections.json').read_text())
    ambiguous={x['id'] for x in json.loads((DATA/'ambiguous.json').read_text())}
    expected={x['id']:copy.deepcopy(x) for x in before}
    allowed={'muscle_specific','muscle_group','equipment','is_unilateral','pattern','movement_pattern'}
    for p in plan:
        assert set(p['after'])<=allowed
        assert p['id'] not in ambiguous
        assert not expected[p['id']]['deleted_at']
        assert {k:expected[p['id']][k] for k in p['before']}==p['before']
        expected[p['id']].update(p['after'])
    assert after==[expected[x['id']] for x in before]
    meadows=next(x for x in after if x['name']=='Meadows Row' and not x['deleted_at'])
    assert (meadows['type'],meadows['weight_type'],meadows['bar_weight'])==('landmine','landmine',45.0)


def test_normalized_anatomical_synonyms_keep_backend_workload_attribution():
    from utils import canonical_muscle_display
    for old,new in [('Droit abdominal',"Droit de l'abdomen"),('Brachialis','Brachial'),
                    ('Trapèze supérieur','Trapèze — chef supérieur'),
                    ('Trapèze inférieur','Trapèze — chef inférieur')]:
        assert canonical_muscle_display(old) is not None
        assert canonical_muscle_display(old)==canonical_muscle_display(new)
    assert canonical_muscle_display('Trapèze — chef moyen')==canonical_muscle_display('Trapèzes')
