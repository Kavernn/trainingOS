#!/usr/bin/env python3
"""Read-only catalogue quality audit. No credentials or network access.

Pass a full JSON export of exercises. Exit 1 means unresolved data/taxonomy
findings, including incompatibilities between current consumers; not all
findings are safe to auto-fix. Vocabulary is extracted from existing sources.
"""
import argparse
import ast
import json
from pathlib import Path
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
NON_STRENGTH = {'mobility', 'cardio', 'interval', 'protocol'}


def key(value):
    return unicodedata.normalize('NFKC', value).strip().casefold()


def literal_assignment(path, name):
    for node in ast.parse(path.read_text()).body:
        if isinstance(node, ast.AnnAssign) and getattr(node.target, 'id', None) == name:
            return ast.literal_eval(node.value)
        if isinstance(node, ast.Assign) and any(getattr(t, 'id', None) == name for t in node.targets):
            return ast.literal_eval(node.value)
    raise ValueError(f'Missing source taxonomy: {name}')


def vocabulary():
    # Frozen first-pass evidence; the live quality gate uses exercise_taxonomy.
    v=json.loads((ROOT/'docs/audits/catalogue-2026-11-07/taxonomy-observed.json').read_text())
    return (v['editor_groups_and_specifics'],set(v['doctrine_accepted_groups']),
            set(v['known_muscle_labels_union_not_canonical']),
            set(v['editor_movement_patterns']),set(v['editor_weight_types']))


def audit(rows):
    groups, doctrine, known, patterns, loads = vocabulary()
    findings = []
    ids = set()
    names = {}
    synonyms = {'droit abdominal': "droit de l'abdomen", 'brachialis': 'brachial',
                'trapèze supérieur': 'trapèze — chef supérieur', 'trapèze moyen': 'trapèze — chef moyen',
                'trapèze inférieur': 'trapèze — chef inférieur'}
    def muscle_key(s):
        k = key(s)
        return synonyms.get(k, k)
    for row in rows:
        def issue(category, field, detail):
            findings.append(dict(id=row.get('id'), name=row.get('name'), category=category, field=field, detail=detail))
        ident = row.get('id')
        if not ident or ident in ids: issue('INCONSISTENT', 'id', 'Missing or duplicate id')
        ids.add(ident)
        if not isinstance(row.get('name'), str) or not row['name'].strip(): issue('MISSING DATA', 'name', 'Empty name')
        if row.get('deleted_at'): continue  # inventory retained, no archived anatomy migration
        name = key(row.get('name') or '')
        if name in names: issue('INCONSISTENT', 'name', 'Active homonym: '+str(names[name]))
        names[name] = ident
        strength = row.get('tracking_type') not in NON_STRENGTH
        primary = row.get('muscle_specific')
        group = row.get('muscle_group')
        if isinstance(primary, list): issue('INCONSISTENT', 'muscle_specific', 'Primary must be scalar; array/duplicate primaries unsupported')
        if strength and not (primary or group): issue('MISSING DATA', 'muscle_specific', 'Strength has no primary (specific or group fallback)')
        if strength and not primary: issue('MISSING DATA', 'muscle_specific', 'Specific missing; group fallback still available')
        if group and group not in groups and group not in doctrine: issue('INVALID TAXONOMY', 'muscle_group', 'Not in editor or doctrine')
        if group and group not in doctrine: issue('INVALID TAXONOMY', 'muscle_group', 'unknown muscle_group in TrainingDoctrine')
        if strength and not group: issue('MISSING DATA', 'muscle_group', 'Missing strength group')
        secondary = row.get('secondary_muscles')
        if secondary is not None and not isinstance(secondary, list):
            issue('INCONSISTENT', 'secondary_muscles', 'Expected array'); secondary = []
        secondary = secondary or []
        if secondary and not (primary or group): issue('INCONSISTENT', 'secondary_muscles', 'Secondary without primary')
        seen = set()
        for muscle in ([primary] if primary else []) + secondary:
            if not isinstance(muscle, str) or key(muscle) not in known:
                issue('INVALID TAXONOMY', 'muscles', f'Unknown muscle: {muscle!r}')
        for muscle in secondary:
            if not isinstance(muscle, str): continue
            k = muscle_key(muscle)
            if k in seen: issue('INCONSISTENT', 'secondary_muscles', f'Duplicate secondary: {muscle}')
            seen.add(k)
            if isinstance(primary or group, str) and k == muscle_key(primary or group):
                issue('INCONSISTENT', 'secondary_muscles', f'Primary also secondary: {muscle}')
        equivalent_group = {'Biceps':'Biceps+Avant-bras', 'Avant-bras':'Biceps+Avant-bras', 'Trapèzes':'Dos', 'Abdominaux':'Core'}.get(group, group)
        owners = [g for g, ms in groups.items() if primary in ms]
        if owners and equivalent_group not in owners:
            issue('INCONSISTENT', 'muscle_group', f'Editor places {primary} in {owners}, not {group}')
        if isinstance(primary, str) and primary not in {m for ms in groups.values() for m in ms}:
            issue('INVALID TAXONOMY', 'muscle_specific', 'Not selectable in editor; may be a supported broad backend label')
        if row.get('weight_type') not in loads: issue('INVALID TAXONOMY', 'weight_type', f'Unsupported load type: {row.get("weight_type")}')
        if row.get('movement_pattern') not in patterns: issue('INVALID TAXONOMY', 'movement_pattern', f'Not an editor pattern: {row.get("movement_pattern")}')
        if strength:
            for f in ('equipment', 'type', 'category', 'pattern', 'load_profile'):
                if not row.get(f): issue('MISSING DATA', f, 'Missing (not automatically inferable)')
            if row.get('secondary_muscles') is None: issue('MISSING DATA', 'secondary_muscles', 'Unknown; null is not an explicit empty selection')
        if not isinstance(row.get('is_unilateral'), bool): issue('MISSING DATA', 'is_unilateral', 'Expected explicit boolean')
        legacy = {'barbell':'barbell','ez-bar':'barbell','ez_bar':'barbell','dumbbell':'dumbbell','cable':'cable_single','cable_double':'cable_double','machine':'machine','landmine':'landmine','press':'press'}
        if row.get('tracking_type') == 'reps' and row.get('type') in legacy and row.get('weight_type') != legacy[row['type']]:
            issue('INCONSISTENT', 'weight_type', 'Legacy type and weight_type disagree; verify convention before changing load')
    return findings


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('snapshot', type=Path)
    p.add_argument('--output', type=Path)
    args=p.parse_args()
    findings=audit(json.loads(args.snapshot.read_text()))
    result=json.dumps(findings,ensure_ascii=False,indent=2)+'\n'
    if args.output: args.output.write_text(result)
    else: print(result,end='')
    return bool(findings)

if __name__ == '__main__':
    raise SystemExit(main())
