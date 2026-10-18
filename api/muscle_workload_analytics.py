"""Pure muscle exposure facts for the future Stats cockpit.

Catalog records are deliberately adapted to ``ExerciseMuscleAssignment`` by a
caller. This module does not infer muscles from names or interpret raw catalog
fields, and it contains no hypertrophy or coaching rules.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Callable, Iterable

from metric_semantics import DateWindow, TrackingType, analytical_tonnage, tracking_capabilities
from training_load_analytics import TrainingLoadExposure

# Pondération unique des séries indirectes pour l'exposition musculaire effective.
# Source doctrine : Schoenfeld & al. — une série où le muscle n'est pas moteur
# principal contribue environ 50 % à l'adaptation hypertrophique vs. une série
# directe. UN SEUL point d'ajustement. Modifie ici si la doctrine évolue.
INDIRECT_SET_COEFFICIENT = 0.5
_DAYS_PER_WEEK = 7


def weekly_effective_sets(direct_sets: int, indirect_sets: int, period_days: int) -> float:
    """Volume effectif en séries / semaine pour une fenêtre de N jours.

    (direct + INDIRECT_SET_COEFFICIENT * indirect) / (period_days / 7).
    period_days doit être > 0. Comparable à MEV/MAV/MRV (séries hebdo).
    """
    if period_days <= 0:
        raise ValueError("period_days must be positive")
    return (direct_sets + INDIRECT_SET_COEFFICIENT * indirect_sets) / (period_days / _DAYS_PER_WEEK)


@dataclass(frozen=True)
class ExerciseMuscleAssignment:
    exercise_name: str
    direct_muscles: tuple[str, ...]
    indirect_muscles: tuple[str, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.exercise_name, str) or not self.exercise_name.strip():
            raise ValueError("exercise_name must be a non-empty string")
        if not isinstance(self.direct_muscles, tuple) or not isinstance(self.indirect_muscles, tuple):
            raise TypeError("muscle assignments must be tuples")

        direct = _canonical_muscles(self.direct_muscles)
        indirect = tuple(muscle for muscle in _canonical_muscles(self.indirect_muscles) if muscle not in direct)
        object.__setattr__(self, "direct_muscles", direct)
        object.__setattr__(self, "indirect_muscles", indirect)


@dataclass(frozen=True)
class MuscleMappingCoverage:
    total_exposure_count: int
    mapped_exposure_count: int
    unmapped_exposure_count: int
    reps_exposure_count: int
    mapped_reps_exposure_count: int


@dataclass(frozen=True)
class MuscleWorkload:
    muscle: str
    direct_set_count: int
    indirect_set_count: int
    direct_exposure_count: int
    indirect_exposure_count: int
    session_count: int
    active_day_count: int
    last_exposure_date: date
    # Volume comparable aux plages MEV/MAV/MRV (séries hebdo), calculé sur les
    # jours HORS décharge uniquement : (direct_hors_décharge + 0,5 ×
    # indirect_hors_décharge) / (jours_hors_décharge / 7). None si la fenêtre
    # est 100 % décharge — iOS affiche badge "Décharge" sans verdict.
    weekly_effective_sets: float | None


@dataclass(frozen=True)
class MuscleWorkloadSummary:
    period: DateWindow
    coverage: MuscleMappingCoverage
    muscles: tuple[MuscleWorkload, ...]
    # Nombre de jours de la fenêtre détectés comme décharge et retirés du
    # calcul de weekly_effective_sets. 0 si pas de callable `is_deload`
    # fourni ou si aucun jour n'est en décharge.
    deload_days_excluded: int = 0


@dataclass
class _MuscleAccumulator:
    direct_sets: int = 0
    indirect_sets: int = 0
    direct_sets_non_deload: int = 0
    indirect_sets_non_deload: int = 0
    direct_exposures: int = 0
    indirect_exposures: int = 0
    sessions: set[str] = None  # type: ignore[assignment]
    active_days: set[date] = None  # type: ignore[assignment]
    last_date: date | None = None

    def __post_init__(self) -> None:
        self.sessions = set()
        self.active_days = set()


def _canonical_muscles(values: tuple[str, ...]) -> tuple[str, ...]:
    cleaned: set[str] = set()
    for value in values:
        if not isinstance(value, str) or not value.strip():
            raise ValueError("muscle names must be non-empty strings")
        cleaned.add(value.strip())
    return tuple(sorted(cleaned, key=lambda value: (value.casefold(), value)))


def _deduplicate_assignments(
    assignments: Iterable[ExerciseMuscleAssignment],
) -> dict[str, ExerciseMuscleAssignment]:
    by_name: dict[str, ExerciseMuscleAssignment] = {}
    for assignment in assignments:
        existing = by_name.get(assignment.exercise_name)
        if existing is not None and existing != assignment:
            raise ValueError(
                f"conflicting assignments share exercise_name={assignment.exercise_name!r}"
            )
        by_name[assignment.exercise_name] = assignment
    return by_name


def _deduplicate_exposures(
    exposures: Iterable[TrainingLoadExposure],
) -> list[TrainingLoadExposure]:
    by_id: dict[str, TrainingLoadExposure] = {}
    for exposure in exposures:
        existing = by_id.get(exposure.exposure_id)
        if existing is not None and existing != exposure:
            raise ValueError(
                f"conflicting exposures share exposure_id={exposure.exposure_id!r}"
            )
        by_id[exposure.exposure_id] = exposure
    return sorted(
        by_id.values(),
        key=lambda item: (
            item.date,
            item.session_id,
            item.exercise_name.casefold(),
            item.exercise_name,
            item.exposure_id,
        ),
    )


def _is_reps(exposure: TrainingLoadExposure) -> bool:
    return tracking_capabilities(exposure.tracking_type).tracking_type is TrackingType.REPS


def _valid_set_count(exposure: TrainingLoadExposure) -> int:
    if not _is_reps(exposure) or exposure.sets is None:
        return 0
    return sum(
        1
        for item in exposure.sets
        if analytical_tonnage(
            tracking_type=exposure.tracking_type,
            sets=({"weight": item.weight, "reps": item.reps},),
        ).value
        is not None
    )


def summarize_muscle_workload(
    exposures: Iterable[TrainingLoadExposure],
    assignments: Iterable[ExerciseMuscleAssignment],
    *,
    period: DateWindow,
    is_deload: Callable[[date], bool] | None = None,
) -> MuscleWorkloadSummary:
    """Aggregate mapped muscle facts over the caller-provided date window.

    `is_deload` : callable optionnel qui retourne True si un jour donné
    appartient à une semaine de décharge. Les séries des jours de décharge
    sont encore comptées dans direct_set_count / indirect_set_count (ce qui
    a été réellement fait), mais weekly_effective_sets normalise sur les
    jours hors décharge uniquement (volume comparable aux plages Israetel).
    """
    if period.start > period.end:
        raise ValueError("period start cannot follow period end")

    assignment_by_name = _deduplicate_assignments(assignments)
    unique = _deduplicate_exposures(exposures)
    in_period = [exposure for exposure in unique if period.contains(exposure.date)]

    mapped = [
        exposure
        for exposure in in_period
        if (assignment := assignment_by_name.get(exposure.exercise_name)) is not None
        and (assignment.direct_muscles or assignment.indirect_muscles)
    ]
    reps_exposures = [exposure for exposure in in_period if _is_reps(exposure)]
    mapped_reps = [exposure for exposure in mapped if _is_reps(exposure)]
    coverage = MuscleMappingCoverage(
        total_exposure_count=len(in_period),
        mapped_exposure_count=len(mapped),
        unmapped_exposure_count=len(in_period) - len(mapped),
        reps_exposure_count=len(reps_exposures),
        mapped_reps_exposure_count=len(mapped_reps),
    )

    accumulators: dict[str, _MuscleAccumulator] = {}
    for exposure in mapped:
        assignment = assignment_by_name[exposure.exercise_name]
        set_count = _valid_set_count(exposure)
        exposure_is_deload = bool(is_deload and is_deload(exposure.date))
        direct = set(assignment.direct_muscles)
        indirect = set(assignment.indirect_muscles) - direct
        for muscle in sorted(direct | indirect, key=lambda value: (value.casefold(), value)):
            accumulator = accumulators.setdefault(muscle, _MuscleAccumulator())
            is_direct = muscle in direct
            if is_direct:
                accumulator.direct_exposures += 1
                accumulator.direct_sets += set_count
                if not exposure_is_deload:
                    accumulator.direct_sets_non_deload += set_count
            else:
                accumulator.indirect_exposures += 1
                accumulator.indirect_sets += set_count
                if not exposure_is_deload:
                    accumulator.indirect_sets_non_deload += set_count
            accumulator.sessions.add(exposure.session_id)
            accumulator.active_days.add(exposure.date)
            if accumulator.last_date is None or exposure.date > accumulator.last_date:
                accumulator.last_date = exposure.date

    deload_days_excluded = 0
    if is_deload is not None:
        for i in range(period.day_count):
            if is_deload(period.start + timedelta(days=i)):
                deload_days_excluded += 1
    non_deload_days = period.day_count - deload_days_excluded
    muscles = tuple(
        MuscleWorkload(
            muscle=muscle,
            direct_set_count=accumulator.direct_sets,
            indirect_set_count=accumulator.indirect_sets,
            direct_exposure_count=accumulator.direct_exposures,
            indirect_exposure_count=accumulator.indirect_exposures,
            session_count=len(accumulator.sessions),
            active_day_count=len(accumulator.active_days),
            last_exposure_date=accumulator.last_date,  # type: ignore[arg-type]
            weekly_effective_sets=(
                None if non_deload_days <= 0
                else weekly_effective_sets(
                    accumulator.direct_sets_non_deload,
                    accumulator.indirect_sets_non_deload,
                    non_deload_days,
                )
            ),
        )
        for muscle, accumulator in sorted(
            accumulators.items(), key=lambda item: (item[0].casefold(), item[0])
        )
    )
    return MuscleWorkloadSummary(
        period=period, coverage=coverage, muscles=muscles,
        deload_days_excluded=deload_days_excluded,
    )
