"""Pure progression comparisons for the future Stats cockpit.

Callers are responsible for adapting persistence records into ``StrengthExposure``
instances, including stable identities and deload classification. This module has
no database, endpoint, presentation, or existing analytics-engine dependencies.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from enum import Enum
from typing import Iterable

from metric_semantics import (
    DateWindow,
    TrackingType,
    best_e1rm_for_exposure,
    comparison_windows,
    tracking_capabilities,
)


DEFAULT_COMPARISON_DAYS = 30
DEFAULT_MIN_EXPOSURES_PER_WINDOW = 2
DEFAULT_ATTENTION_MIN_EXPOSURES = 3
DEFAULT_ATTENTION_MIN_COVERED_DAYS = 21
DEFAULT_NEW_BEST_RESOLUTION_LBS = 0.1


class ProgressionStatus(str, Enum):
    IMPROVING = "improving"
    STABLE = "stable"
    DECLINING = "declining"
    INSUFFICIENT_DATA = "insufficientData"


class InsufficiencyReason(str, Enum):
    NON_COMPARABLE_TRACKING_TYPE = "nonComparableTrackingType"
    NO_VALID_EXPOSURE = "noValidExposure"
    INSUFFICIENT_BASELINE_EXPOSURES = "insufficientBaselineExposures"
    INSUFFICIENT_RECENT_EXPOSURES = "insufficientRecentExposures"
    INSUFFICIENT_BOTH_WINDOWS = "insufficientBothWindows"
    INVALID_BASELINE = "invalidBaseline"


class AttentionKind(str, Enum):
    NO_RECENT_IMPROVEMENT = "noRecentImprovement"


@dataclass(frozen=True)
class StrengthSet:
    weight: object
    reps: object


@dataclass(frozen=True)
class StrengthExposure:
    exposure_id: str
    exercise_name: str
    date: date
    tracking_type: object
    sets: tuple[StrengthSet, ...] | None
    weight: object = None
    reps: object = None
    is_deload: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.exposure_id, str) or not self.exposure_id.strip():
            raise ValueError("exposure_id must be a non-empty string")
        if not isinstance(self.exercise_name, str) or not self.exercise_name.strip():
            raise ValueError("exercise_name must be a non-empty string")
        if type(self.date) is not date:
            raise TypeError("exposure date must be a date")
        if self.sets is not None and not isinstance(self.sets, tuple):
            raise TypeError("sets must be a tuple or None")


@dataclass(frozen=True)
class ProgressionComparison:
    exercise_name: str
    tracking_type: TrackingType | None
    status: ProgressionStatus
    baseline_window: DateWindow
    recent_window: DateWindow
    baseline_best_e1rm: float | None
    recent_best_e1rm: float | None
    absolute_delta: float | None
    relative_delta: float | None
    baseline_exposure_count: int
    recent_exposure_count: int
    baseline_used_legacy_fallback: bool
    recent_used_legacy_fallback: bool
    insufficiency_reason: InsufficiencyReason | None


@dataclass(frozen=True)
class AttentionObservation:
    kind: AttentionKind
    exercise_name: str
    observation_window: DateWindow
    last_exposure_date: date
    days_since_last_exposure: int
    valid_exposure_count: int
    covered_days: int
    latest_best_e1rm: float


@dataclass(frozen=True)
class _EvaluatedExposure:
    exposure: StrengthExposure
    best_e1rm: float
    used_legacy_fallback: bool


def _deduplicate(exposures: Iterable[StrengthExposure]) -> list[StrengthExposure]:
    """Deduplicate exact clones by ID and reject contradictory duplicate IDs."""
    by_id: dict[str, StrengthExposure] = {}
    for exposure in exposures:
        existing = by_id.get(exposure.exposure_id)
        if existing is not None and existing != exposure:
            raise ValueError(
                f"conflicting exposures share exposure_id={exposure.exposure_id!r}"
            )
        by_id[exposure.exposure_id] = exposure
    return sorted(
        by_id.values(),
        key=lambda item: (item.exercise_name.casefold(), item.exercise_name, item.date, item.exposure_id),
    )


def _resolved_tracking_type(exposures: list[StrengthExposure]) -> TrackingType | None:
    resolved = {
        tracking_capabilities(exposure.tracking_type).tracking_type
        for exposure in exposures
    }
    if len(resolved) != 1:
        return None
    return next(iter(resolved))


def _evaluate(exposure: StrengthExposure) -> _EvaluatedExposure | None:
    if exposure.is_deload:
        return None
    result = best_e1rm_for_exposure(
        tracking_type=exposure.tracking_type,
        sets=(
            tuple({"weight": item.weight, "reps": item.reps} for item in exposure.sets)
            if exposure.sets is not None
            else None
        ),
        weight=exposure.weight,
        reps=exposure.reps,
    )
    if result.best_e1rm is None:
        return None
    return _EvaluatedExposure(
        exposure=exposure,
        best_e1rm=result.best_e1rm,
        used_legacy_fallback=result.used_legacy_fallback,
    )


def _insufficient_comparison(
    *,
    exercise_name: str,
    tracking_type: TrackingType | None,
    baseline_window: DateWindow,
    recent_window: DateWindow,
    baseline: list[_EvaluatedExposure],
    recent: list[_EvaluatedExposure],
    reason: InsufficiencyReason,
) -> ProgressionComparison:
    return ProgressionComparison(
        exercise_name=exercise_name,
        tracking_type=tracking_type,
        status=ProgressionStatus.INSUFFICIENT_DATA,
        baseline_window=baseline_window,
        recent_window=recent_window,
        baseline_best_e1rm=max((item.best_e1rm for item in baseline), default=None),
        recent_best_e1rm=max((item.best_e1rm for item in recent), default=None),
        absolute_delta=None,
        relative_delta=None,
        baseline_exposure_count=len(baseline),
        recent_exposure_count=len(recent),
        baseline_used_legacy_fallback=any(item.used_legacy_fallback for item in baseline),
        recent_used_legacy_fallback=any(item.used_legacy_fallback for item in recent),
        insufficiency_reason=reason,
    )


def compare_progression(
    exposures: Iterable[StrengthExposure],
    *,
    today: date,
    days: int = DEFAULT_COMPARISON_DAYS,
    min_exposures_per_window: int = DEFAULT_MIN_EXPOSURES_PER_WINDOW,
) -> list[ProgressionComparison]:
    """Compare each represented exercise across canonical adjacent windows."""
    if isinstance(min_exposures_per_window, bool) or not isinstance(min_exposures_per_window, int):
        raise ValueError("min_exposures_per_window must be a positive integer")
    if min_exposures_per_window <= 0:
        raise ValueError("min_exposures_per_window must be a positive integer")

    windows = comparison_windows(today=today, days=days)
    unique = _deduplicate(exposures)
    grouped: dict[str, list[StrengthExposure]] = {}
    for exposure in unique:
        grouped.setdefault(exposure.exercise_name, []).append(exposure)

    comparisons: list[ProgressionComparison] = []
    for exercise_name in sorted(grouped, key=lambda value: (value.casefold(), value)):
        exercise_exposures = grouped[exercise_name]
        tracking_type = _resolved_tracking_type(exercise_exposures)
        if tracking_type is not TrackingType.REPS:
            comparisons.append(
                _insufficient_comparison(
                    exercise_name=exercise_name,
                    tracking_type=tracking_type,
                    baseline_window=windows.baseline,
                    recent_window=windows.recent,
                    baseline=[],
                    recent=[],
                    reason=InsufficiencyReason.NON_COMPARABLE_TRACKING_TYPE,
                )
            )
            continue

        evaluated = [item for exposure in exercise_exposures if (item := _evaluate(exposure))]
        if not evaluated:
            comparisons.append(
                _insufficient_comparison(
                    exercise_name=exercise_name,
                    tracking_type=tracking_type,
                    baseline_window=windows.baseline,
                    recent_window=windows.recent,
                    baseline=[],
                    recent=[],
                    reason=InsufficiencyReason.NO_VALID_EXPOSURE,
                )
            )
            continue

        baseline = [item for item in evaluated if windows.baseline.contains(item.exposure.date)]
        recent = [item for item in evaluated if windows.recent.contains(item.exposure.date)]
        baseline_short = len(baseline) < min_exposures_per_window
        recent_short = len(recent) < min_exposures_per_window
        if baseline_short or recent_short:
            if baseline_short and recent_short:
                reason = InsufficiencyReason.INSUFFICIENT_BOTH_WINDOWS
            elif baseline_short:
                reason = InsufficiencyReason.INSUFFICIENT_BASELINE_EXPOSURES
            else:
                reason = InsufficiencyReason.INSUFFICIENT_RECENT_EXPOSURES
            comparisons.append(
                _insufficient_comparison(
                    exercise_name=exercise_name,
                    tracking_type=tracking_type,
                    baseline_window=windows.baseline,
                    recent_window=windows.recent,
                    baseline=baseline,
                    recent=recent,
                    reason=reason,
                )
            )
            continue

        baseline_best = max(item.best_e1rm for item in baseline)
        recent_best = max(item.best_e1rm for item in recent)
        if baseline_best <= 0:
            comparisons.append(
                _insufficient_comparison(
                    exercise_name=exercise_name,
                    tracking_type=tracking_type,
                    baseline_window=windows.baseline,
                    recent_window=windows.recent,
                    baseline=baseline,
                    recent=recent,
                    reason=InsufficiencyReason.INVALID_BASELINE,
                )
            )
            continue

        absolute_delta = recent_best - baseline_best
        relative_delta = absolute_delta / baseline_best
        if relative_delta >= 0.05:
            status = ProgressionStatus.IMPROVING
        elif relative_delta <= -0.05:
            status = ProgressionStatus.DECLINING
        else:
            status = ProgressionStatus.STABLE

        comparisons.append(
            ProgressionComparison(
                exercise_name=exercise_name,
                tracking_type=tracking_type,
                status=status,
                baseline_window=windows.baseline,
                recent_window=windows.recent,
                baseline_best_e1rm=baseline_best,
                recent_best_e1rm=recent_best,
                absolute_delta=absolute_delta,
                relative_delta=relative_delta,
                baseline_exposure_count=len(baseline),
                recent_exposure_count=len(recent),
                baseline_used_legacy_fallback=any(
                    item.used_legacy_fallback for item in baseline
                ),
                recent_used_legacy_fallback=any(
                    item.used_legacy_fallback for item in recent
                ),
                insufficiency_reason=None,
            )
        )

    return comparisons


def top_movers(
    comparisons: Iterable[ProgressionComparison],
) -> list[ProgressionComparison]:
    """Return sufficient improving comparisons in deterministic rank order."""
    eligible = [
        comparison
        for comparison in comparisons
        if comparison.status is ProgressionStatus.IMPROVING
        and comparison.insufficiency_reason is None
        and comparison.relative_delta is not None
        and comparison.absolute_delta is not None
    ]
    return sorted(
        eligible,
        key=lambda item: (
            -item.relative_delta,
            -item.absolute_delta,
            item.exercise_name.casefold(),
            item.exercise_name,
        ),
    )


def _is_new_best(current: float, previous: float, resolution_lbs: float) -> bool:
    """A new best must exceed the previous best by more than one resolution unit."""
    return Decimal(str(current)) > Decimal(str(previous)) + Decimal(str(resolution_lbs))


def no_recent_improvement(
    exposures: Iterable[StrengthExposure],
    *,
    observation_window: DateWindow,
    as_of: date,
    min_exposures: int = DEFAULT_ATTENTION_MIN_EXPOSURES,
    min_covered_days: int = DEFAULT_ATTENTION_MIN_COVERED_DAYS,
    new_best_resolution_lbs: float = DEFAULT_NEW_BEST_RESOLUTION_LBS,
) -> list[AttentionObservation]:
    """Return factual no-new-best observations within an explicit caller window.

    ``covered_days`` is elapsed time between first and last valid exposure, not
    an inclusive count of calendar labels. Any qualifying new best after the
    first exposure suppresses the observation for that entire supplied window.
    """
    if type(as_of) is not date:
        raise TypeError("as_of must be a date")
    if as_of < observation_window.end:
        raise ValueError("as_of cannot precede observation_window.end")
    if isinstance(min_exposures, bool) or not isinstance(min_exposures, int) or min_exposures <= 0:
        raise ValueError("min_exposures must be a positive integer")
    if isinstance(min_covered_days, bool) or not isinstance(min_covered_days, int) or min_covered_days < 0:
        raise ValueError("min_covered_days must be a non-negative integer")
    if new_best_resolution_lbs <= 0:
        raise ValueError("new_best_resolution_lbs must be positive")

    unique = _deduplicate(exposures)
    grouped: dict[str, list[StrengthExposure]] = {}
    for exposure in unique:
        if observation_window.contains(exposure.date):
            grouped.setdefault(exposure.exercise_name, []).append(exposure)

    observations: list[AttentionObservation] = []
    for exercise_name in sorted(grouped, key=lambda value: (value.casefold(), value)):
        exercise_exposures = grouped[exercise_name]
        if _resolved_tracking_type(exercise_exposures) is not TrackingType.REPS:
            continue
        evaluated = [item for exposure in exercise_exposures if (item := _evaluate(exposure))]
        evaluated.sort(key=lambda item: (item.exposure.date, item.exposure.exposure_id))
        if len(evaluated) < min_exposures:
            continue

        first_date = evaluated[0].exposure.date
        last_date = evaluated[-1].exposure.date
        covered_days = (last_date - first_date).days
        if covered_days < min_covered_days:
            continue

        previous_best = evaluated[0].best_e1rm
        observed_new_best = False
        for item in evaluated[1:]:
            if _is_new_best(item.best_e1rm, previous_best, new_best_resolution_lbs):
                observed_new_best = True
                previous_best = item.best_e1rm
            elif item.best_e1rm > previous_best:
                previous_best = item.best_e1rm
        if observed_new_best:
            continue

        observations.append(
            AttentionObservation(
                kind=AttentionKind.NO_RECENT_IMPROVEMENT,
                exercise_name=exercise_name,
                observation_window=observation_window,
                last_exposure_date=last_date,
                days_since_last_exposure=(as_of - last_date).days,
                valid_exposure_count=len(evaluated),
                covered_days=covered_days,
                latest_best_e1rm=max(item.best_e1rm for item in evaluated),
            )
        )

    return observations
