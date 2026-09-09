"""Database-to-analytics adapter for the future Stats cockpit.

This module preserves raw log identity and adapts rows to the canonical pure
analytics DTOs. It intentionally does not expose an HTTP route or serialize a
cockpit response.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any, Iterable

from metric_semantics import DateWindow, TrackingType, best_e1rm_for_exposure
from muscle_workload_analytics import ExerciseMuscleAssignment
from progression_comparison import StrengthExposure
from training_load_analytics import TrainingLoadExposure, TrainingLoadSet


@dataclass(frozen=True)
class UnmappedExerciseDiagnostic:
    exercise_id: str
    exercise_name: str
    reason: str
    unmapped_exposure_count: int


@dataclass(frozen=True)
class AnalyticsAdapterDiagnostics:
    queried_exposure_count: int
    analytics_exposure_count: int
    invalid_row_count: int
    missing_tracking_type_count: int
    missing_muscle_mapping_count: int
    legacy_strength_fallback_count: int
    known_deload_exposure_count: int
    unmapped_exercises: tuple[UnmappedExerciseDiagnostic, ...]


@dataclass(frozen=True)
class AnalyticsAdapterResult:
    period: DateWindow
    strength_exposures: tuple[StrengthExposure, ...]
    training_load_exposures: tuple[TrainingLoadExposure, ...]
    assignments: tuple[ExerciseMuscleAssignment, ...]
    diagnostics: AnalyticsAdapterDiagnostics


def _unmapped_diagnostics_from_unique(unique) -> tuple[UnmappedExerciseDiagnostic, ...]:
    by_identity: dict[tuple[str, str], int] = {}
    for _, load_exposure, assignment, exercise_id in unique:
        if assignment is None:
            key = (exercise_id, load_exposure.exercise_name)
            by_identity[key] = by_identity.get(key, 0) + 1
    return tuple(
        UnmappedExerciseDiagnostic(
            exercise_id=exercise_id,
            exercise_name=exercise_name,
            reason="missing_structured_muscle_metadata",
            unmapped_exposure_count=count,
        )
        for (exercise_id, exercise_name), count in sorted(
            by_identity.items(), key=lambda item: (-item[1], item[0][1].casefold(), item[0][0])
        )
    )


def unmapped_exercise_diagnostics(
    rows: Iterable[dict[str, Any]],
    *,
    period: DateWindow,
    cycle_start_date: date | None = None,
) -> tuple[UnmappedExerciseDiagnostic, ...]:
    """Return catalogue metadata gaps for exactly the requested exposure window."""
    adapted = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        item = _adapt_row(row, cycle_start_date)
        if item is not None and period.contains(item[0].date):
            adapted.append(item)
    return _unmapped_diagnostics_from_unique(_dedupe_adapted(adapted))


def _parse_date(value: object) -> date | None:
    if type(value) is date:
        return value
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _nested(row: dict[str, Any], key: str) -> dict[str, Any]:
    value = row.get(key)
    return value if isinstance(value, dict) else {}


def _sets(raw: object) -> tuple[TrainingLoadSet, ...] | None:
    if raw is None:
        return None
    if not isinstance(raw, (list, tuple)):
        return tuple()
    return tuple(
        TrainingLoadSet(
            item.get("weight") if isinstance(item, dict) else None,
            item.get("reps") if isinstance(item, dict) else None,
        )
        for item in raw
    )


def _canonical_muscle_value(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    # This is the only exact V1 catalogue correction established by the audit.
    if cleaned == "glutes":
        return "Fessiers"
    return cleaned


def _muscle_assignment(exercise: dict[str, Any]) -> ExerciseMuscleAssignment | None:
    name = exercise.get("name")
    if not isinstance(name, str) or not name.strip():
        return None
    specific = _canonical_muscle_value(exercise.get("muscle_specific"))
    group = _canonical_muscle_value(exercise.get("muscle_group"))
    direct = (specific or group,)
    direct = tuple(value for value in direct if value is not None)

    secondary_raw = exercise.get("secondary_muscles")
    if not isinstance(secondary_raw, (list, tuple)):
        secondary_raw = ()
    indirect = tuple(
        value
        for value in (_canonical_muscle_value(item) for item in secondary_raw)
        if value is not None
    )
    if not direct and not indirect:
        return None
    return ExerciseMuscleAssignment(
        exercise_name=name,
        direct_muscles=direct,
        indirect_muscles=indirect,
    )


def _is_deload(day: date, cycle_start_date: date | None) -> bool:
    if cycle_start_date is None:
        return False
    # Existing programme doctrine: 11th week of an 11-week / 77-day cycle.
    return ((day - cycle_start_date).days % 77) // 7 + 1 == 11


def _adapt_row(row: dict[str, Any], cycle_start_date: date | None):
    exercise = _nested(row, "exercises")
    session = _nested(row, "workout_sessions")
    exposure_id = row.get("id")
    session_id = row.get("session_id")
    exercise_id = row.get("exercise_id")
    name = exercise.get("name")
    day = _parse_date(session.get("date"))
    if not all(isinstance(value, str) and value.strip() for value in (exposure_id, session_id, exercise_id, name)):
        return None
    if day is None:
        return None

    sets = _sets(row.get("sets_json"))
    tracking_type = exercise.get("tracking_type")
    deload = _is_deload(day, cycle_start_date)
    strength = StrengthExposure(
        exposure_id=exposure_id,
        exercise_name=name,
        date=day,
        tracking_type=tracking_type,
        sets=sets,
        weight=row.get("weight"),
        reps=row.get("reps"),
        is_deload=deload,
    )
    load = TrainingLoadExposure(
        exposure_id=exposure_id,
        session_id=session_id,
        exercise_name=name,
        date=day,
        tracking_type=tracking_type,
        sets=sets,
    )
    assignment = _muscle_assignment(exercise)
    return strength, load, assignment, exercise_id


def _dedupe_adapted(rows: Iterable[tuple[Any, Any, Any, str]]):
    by_id: dict[str, tuple[Any, Any, Any, str]] = {}
    for item in rows:
        exposure_id = item[0].exposure_id
        existing = by_id.get(exposure_id)
        if existing is not None and existing != item:
            raise ValueError(f"conflicting rows share exercise_logs.id={exposure_id!r}")
        by_id[exposure_id] = item
    return sorted(
        by_id.values(),
        key=lambda item: (
            item[0].date,
            item[0].session_id if hasattr(item[0], "session_id") else item[1].session_id,
            item[0].exercise_name.casefold(),
            item[0].exercise_name,
            item[0].exposure_id,
        ),
    )


def adapt_analytics_rows(
    rows: Iterable[dict[str, Any]],
    *,
    period: DateWindow,
    cycle_start_date: date | None = None,
) -> AnalyticsAdapterResult:
    """Adapt raw joined rows while preserving IDs and explicit data gaps."""
    if period.start > period.end:
        raise ValueError("period start cannot follow period end")
    raw_rows = list(rows)
    adapted = []
    invalid = 0
    for row in raw_rows:
        if not isinstance(row, dict):
            invalid += 1
            continue
        item = _adapt_row(row, cycle_start_date)
        if item is None:
            invalid += 1
            continue
        if period.contains(item[0].date):
            adapted.append(item)

    unique = _dedupe_adapted(adapted)
    strength = tuple(item[0] for item in unique)
    load = tuple(item[1] for item in unique)

    assignments_by_name: dict[str, ExerciseMuscleAssignment] = {}
    for _, _, assignment, _ in unique:
        if assignment is None:
            continue
        existing = assignments_by_name.get(assignment.exercise_name)
        if existing is not None and existing != assignment:
            raise ValueError(
                f"conflicting assignments share exercise_name={assignment.exercise_name!r}"
            )
        assignments_by_name[assignment.exercise_name] = assignment

    missing_mapping = sum(
        1
        for item in unique
        if item[2] is None
    )
    unmapped_exercises = _unmapped_diagnostics_from_unique(unique)
    missing_tracking = sum(
        1
        for item in unique
        if not isinstance(item[0].tracking_type, str) or not item[0].tracking_type.strip()
    )
    legacy_fallbacks = 0
    known_deload_exposures = 0
    for item in unique:
        exposure = item[0]
        if exposure.is_deload:
            known_deload_exposures += 1
        result = best_e1rm_for_exposure(
            tracking_type=exposure.tracking_type,
            sets=(
                tuple({"weight": value.weight, "reps": value.reps} for value in exposure.sets)
                if exposure.sets is not None
                else None
            ),
            weight=exposure.weight,
            reps=exposure.reps,
        )
        if result.used_legacy_fallback and result.best_e1rm is not None:
            legacy_fallbacks += 1

    return AnalyticsAdapterResult(
        period=period,
        strength_exposures=strength,
        training_load_exposures=load,
        assignments=tuple(
            assignment
            for _, assignment in sorted(
                assignments_by_name.items(), key=lambda item: (item[0].casefold(), item[0])
            )
        ),
        diagnostics=AnalyticsAdapterDiagnostics(
            queried_exposure_count=len(raw_rows),
            analytics_exposure_count=len(unique),
            invalid_row_count=invalid,
            missing_tracking_type_count=missing_tracking,
            missing_muscle_mapping_count=missing_mapping,
            legacy_strength_fallback_count=legacy_fallbacks,
            known_deload_exposure_count=known_deload_exposures,
            unmapped_exercises=unmapped_exercises,
        ),
    )


def fetch_raw_analytics_rows(client: Any, *, period: DateWindow) -> list[dict[str, Any]]:
    """Fetch identity-preserving rows; callers choose auth and error policy."""
    if period.start > period.end:
        raise ValueError("period start cannot follow period end")
    response = (
        client.table("exercise_logs")
        .select(
            "id,session_id,exercise_id,weight,reps,sets_json,"
            "workout_sessions!inner(date),"
            "exercises!inner(name,tracking_type,muscle_group,muscle_specific,secondary_muscles)"
        )
        .gte("workout_sessions.date", period.start.isoformat())
        .lte("workout_sessions.date", period.end.isoformat())
        .execute()
    )
    return list(response.data or [])
