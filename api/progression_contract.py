"""Transport/reference contract, independent of recommendation rules."""
from datetime import date
import math
import re
from uuid import UUID


def validate_context(payload):
    day = payload.get('session_date')
    try:
        if not isinstance(day, str) or date.fromisoformat(day).isoformat() != day:
            raise ValueError()
    except (ValueError, TypeError):
        raise ValueError('session_date must be YYYY-MM-DD')
    if payload.get('session_type') not in ('morning', 'evening', 'bonus'):
        raise ValueError('invalid session_type')
    if not isinstance(payload.get('session_name'), str) or not payload['session_name'].strip():
        raise ValueError('session_name required')


def validate_apply(payload):
    if not isinstance(payload, dict):
        raise ValueError('JSON object required')
    validate_context(payload)
    if not isinstance(payload.get('exercise_name'), str) or not payload['exercise_name'].strip():
        raise ValueError('exercise_name required')
    try:
        UUID(payload['program_id'])
    except (KeyError, ValueError, TypeError, AttributeError):
        raise ValueError('program_id required')
    for key in ('expected_current_weight', 'expected_current_scheme'):
        if key not in payload:
            raise ValueError(key + ' required')
    for key in ('suggested_weight', 'expected_current_weight'):
        value = payload.get(key)
        if value is not None and (isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0):
            raise ValueError('invalid ' + key)
    # Expected scheme is the raw DB snapshot, nullable for legacy rows; never infer it.
    if payload.get('expected_current_scheme') is not None and not isinstance(payload['expected_current_scheme'], str):
        raise ValueError('invalid expected_current_scheme')
    if 'restore' in payload and not isinstance(payload['restore'], bool):
        raise ValueError('invalid restore')
    scheme = payload.get('suggested_scheme')
    if scheme is not None:
        if not isinstance(scheme, str) or not re.fullmatch(r'[1-9]\d*x[1-9]\d*(?:-[1-9]\d*)?s?', scheme):
            raise ValueError('invalid suggested_scheme')
        parts = re.findall(r'\d+', scheme)
        if len(parts) == 3 and int(parts[1]) > int(parts[2]):
            raise ValueError('invalid scheme range')
    weight = payload.get('suggested_weight')
    if payload.get('restore'):
        if 'suggested_weight' not in payload or 'suggested_scheme' not in payload:
            raise ValueError('complete restoration required')
        unchanged = weight == payload['expected_current_weight'] and scheme == payload['expected_current_scheme']
    else:
        unchanged = (weight is None or weight == payload['expected_current_weight']) and (scheme is None or scheme == payload['expected_current_scheme'])
    if unchanged:
        raise ValueError('no change requested')
