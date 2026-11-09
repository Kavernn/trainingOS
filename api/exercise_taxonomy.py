"""Pure catalogue taxonomy; no IO, persistence, prescriptions or load arithmetic."""
from exercise_taxonomy_data import TAXONOMY

GROUPS = TAXONOMY['groups']
MUSCLES = frozenset(m for values in GROUPS.values() for m in values)
PATTERNS = TAXONOMY['patterns']
EQUIPMENT = frozenset(TAXONOMY['equipment'])
LOAD_TYPES = frozenset(TAXONOMY['load_types'])
NON_STRENGTH = frozenset(('mobility','cardio','interval','protocol'))
REGIONS = frozenset(TAXONOMY['non_strength_regions'])

def _index(values, aliases):
    result={k.casefold():v for k,v in aliases.items()}
    result.update({v.casefold():v for v in values})
    return result

_MUSCLES=_index(MUSCLES,TAXONOMY['muscle_aliases'])
_GROUPS=_index(GROUPS,TAXONOMY['group_aliases'])
_EQUIPMENT=_index(EQUIPMENT,TAXONOMY['equipment_aliases'])

def _resolve(value, index):
    return index.get(value.strip().casefold()) if isinstance(value,str) else None

def canonical_muscle(value): return _resolve(value,_MUSCLES)
def canonical_group(value): return _resolve(value,_GROUPS)
def canonical_equipment(value): return _resolve(value,_EQUIPMENT)

def canonical_pattern(value, group=None):
    if value in PATTERNS:return value
    if value in TAXONOMY['pattern_aliases']:return TAXONOMY['pattern_aliases'][value]
    if isinstance(value,str) and value.lower()=='isolation':
        if group in ('Biceps','Triceps'):return 'isolation_arm'
        if group=='Avant-bras':return 'accessory_wrist'
        if group in ('Épaules','Trapèzes'):return 'isolation_shoulder'
        if group in ('Quadriceps','Ischio-jambiers','Fessiers','Mollets','Hanches'):return 'isolation_leg'
    return None

def detailed_target(value):
    """Preserve unknowns visibly rather than silently dropping analytics rows."""
    return canonical_muscle(value) or canonical_group(value) or (value.strip() if isinstance(value,str) else None)

def redundant_broad_secondary(primary, secondary):
    """Anatomical containment, not mere sharing of a reporting bucket.

    Brachial is in the Biceps reporting bucket but is a different muscle.
    Tibial antérieur likewise isn't part of the calf musculature.
    """
    primary = canonical_muscle(primary)
    if not primary or secondary not in GROUPS or primary == secondary:
        return False
    if secondary == 'Biceps':
        return primary.startswith('Biceps brachial —')
    if secondary == 'Triceps':
        return primary.startswith('Triceps —')
    if secondary == 'Mollets':
        return primary.startswith('Gastrocnémien') or primary == 'Soléaire'
    if secondary == 'Pectoraux':
        return primary.startswith('Pectoral')
    return primary in GROUPS[secondary]


def normalize_metadata(row):
    """Alias normalization only. No variant inference or load conversion."""
    out=dict(row)
    out['muscle_group']=canonical_group(row.get('muscle_group')) or row.get('muscle_group')
    out['muscle_specific']=canonical_muscle(row.get('muscle_specific')) or row.get('muscle_specific')
    out['secondary_muscles']=list(dict.fromkeys(detailed_target(x) for x in row.get('secondary_muscles') or []))
    out['equipment']=list(dict.fromkeys(canonical_equipment(x) or x for x in row.get('equipment') or []))
    out['movement_pattern']=canonical_pattern(row.get('movement_pattern'),out['muscle_group']) or row.get('movement_pattern')
    return out

def validate_catalogue(rows):
    findings=[];ids=set();names=set()
    for r in rows:
        archived=bool(r.get('deleted_at'));strength=r.get('tracking_type') not in NON_STRENGTH
        def err(code,field,value):
            findings.append(dict(id=r.get('id'),name=r.get('name'),archived=archived,code=code,field=field,value=value))
        if not r.get('id') or r['id'] in ids:err('identity','id',r.get('id'))
        ids.add(r.get('id'))
        name=r.get('name')
        if not isinstance(name,str) or not name.strip():err('identity','name',name)
        elif not archived:
            if name.casefold() in names:err('identity','name',name)
            names.add(name.casefold())
        group=r.get('muscle_group');primary=r.get('muscle_specific')
        if isinstance(primary,list):err('invalid_primary','muscle_specific',primary)
        if not archived and strength and not (primary or group):err('missing_primary','muscle_specific',primary)
        if group and group not in GROUPS:err('unknown_group','muscle_group',group)
        if not group and not archived and strength:err('missing_group','muscle_group',group)
        if isinstance(primary,str) and primary in MUSCLES:
            owners=[g for g,ms in GROUPS.items() if primary in ms]
            if group not in owners:err('incompatible_group','muscle_group',group)
        secondary=r.get('secondary_muscles') or []
        if not isinstance(secondary,list):err('invalid_secondary','secondary_muscles',secondary);secondary=[]
        targets=([primary] if primary else [])+secondary
        for m in targets:
            if not isinstance(m,str) or (m not in MUSCLES and not (not strength and m in REGIONS)):
                err('unknown_muscle','muscle_specific' if m==primary else 'secondary_muscles',m)
        normalized=[detailed_target(x) for x in secondary if isinstance(x,str)]
        if len(normalized)!=len(set(normalized)):err('duplicate_secondary','secondary_muscles',secondary)
        if detailed_target(primary or group) in normalized or any(redundant_broad_secondary(primary, m) for m in normalized):
            err('overlap','secondary_muscles',secondary)
        equipment=r.get('equipment')
        if equipment is not None and not isinstance(equipment,list):err('invalid_equipment','equipment',equipment)
        else:
            for e in equipment or []:
                if e not in EQUIPMENT:err('invalid_equipment','equipment',e)
        if not equipment and not archived and strength:err('missing_equipment','equipment',equipment)
        for f,values,code in [('movement_pattern',PATTERNS,'invalid_pattern'),('weight_type',LOAD_TYPES,'invalid_load')]:
            value=r.get(f)
            if value not in values and (value or (not archived and strength)):err(code,f,value)
    return findings
