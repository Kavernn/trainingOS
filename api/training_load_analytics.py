"""Pure typed training-load analytics for the future Stats cockpit.

This module intentionally defines no universal load score. It aggregates facts
from caller-provided DTOs and delegates tonnage semantics to ``metric_semantics``.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from enum import Enum
from typing import Iterable

from metric_semantics import (
    DateWindow,
    TrackingType,
    analytical_tonnage,
    tracking_capabilities,
)


class TonnageCoverage(str, Enum):
    COMPLETE = "complete"
    PARTIAL = "partial"
    UNAVAILABLE = "unavailable"


@dataclass(frozen=True)
class TrainingLoadSet:
    weight: object
    reps: object


@dataclass(frozen=True)
class TrainingLoadExposure:
    exposure_id: str
    session_id: str
    exercise_name: str
    date: date
    tracking_type: object
    sets: tuple[TrainingLoadSet, ...] | None

    def __post_init__(self) -> None:
        if not isinstance(self.exposure_id, str) or not self.exposure_id.strip():
            raise ValueError("exposure_id must be a non-empty string")
        if not isinstance(self.session_id, str) or not self.session_id.strip():
            raise ValueError("session_id must be a non-empty string")
        if not isinstance(self.exercise_name, str) or not self.exercise_name.strip():
            raise ValueError("exercise_name must be a non-empty string")
        if type(self.date) is not date:
            raise TypeError("exposure date must be a date")
        if self.sets is not None and not isinstance(self.sets, tuple):
            raise TypeError("sets must be a tuple or None")


@dataclass(frozen=True)
class TonnageAggregate:
    value: float | None
    applicable_exposure_count: int
    calculable_exposure_count: int
    coverage: TonnageCoverage

    @property
    def uncalculable_exposure_count(self) -> int:
        return self.applicable_exposure_count - self.calculable_exposure_count


@dataclass(frozen=True)
class TrainingLoadSummary:
    period: DateWindow
    exposure_count: int
    session_count: int
    active_day_count: int
    reps_exposure_count: int
    valid_reps_set_count: int
    tonnage: TonnageAggregate


@dataclass(frozen=True)
class WeeklyTrainingLoad:
    week_start: date
    week_end: date
    covered_window: DateWindow
    is_partial: bool
    exposure_count: int
    session_count: int
    active_day_count: int
    reps_exposure_count: int
    valid_reps_set_count: int
    tonnage: TonnageAggregate


def _validate_period(period: DateWindow) -> None:
    if period.start > period.end:
        raise ValueError("period start cannot follow period end")


def _deduplicate(exposures: Iterable[TrainingLoadExposure]) -> list[TrainingLoadExposure]:
    """Deduplicate exact clones and reject conflicting uses of one exposure ID."""
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


def _set_payload(exposure: TrainingLoadExposure) -> tuple[dict[str, object], ...] | None:
    if exposure.sets is None:
        return None
    return tuple({"weight": item.weight, "reps": item.reps} for item in exposure.sets)


def _is_reps(exposure: TrainingLoadExposure) -> bool:
    return tracking_capabilities(exposure.tracking_type).tracking_type is TrackingType.REPS


def _valid_reps_set_count(exposure: TrainingLoadExposure) -> int:
    if not _is_reps(exposure) or exposure.sets is None:
        return 0
    count = 0
    for item in exposure.sets:
        result = analytical_tonnage(
            tracking_type=exposure.tracking_type,
            sets=({"weight": item.weight, "reps": item.reps},),
        )
        if result.applicable and result.value is not None:
            count += 1
    return count


def _aggregate_tonnage(exposures: list[TrainingLoadExposure]) -> TonnageAggregate:
    applicable = 0
    calculable = 0
    known_total = 0.0

    for exposure in exposures:
        result = analytical_tonnage(
            tracking_type=exposure.tracking_type,
            sets=_set_payload(exposure),
        )
        if not result.applicable:
            continue
        applicable += 1
        if result.value is not None:
            calculable += 1
            known_total += result.value

    if calculable == 0:
        return TonnageAggregate(
            value=None,
            applicable_exposure_count=applicable,
            calculable_exposure_count=0,
            coverage=TonnageCoverage.UNAVAILABLE,
        )
    coverage = (
        TonnageCoverage.COMPLETE
        if calculable == applicable
        else TonnageCoverage.PARTIAL
    )
    return TonnageAggregate(
        value=known_total,
        applicable_exposure_count=applicable,
        calculable_exposure_count=calculable,
        coverage=coverage,
    )


def _summarize_unique(
    exposures: list[TrainingLoadExposure], period: DateWindow
) -> TrainingLoadSummary:
    reps_exposures = [exposure for exposure in exposures if _is_reps(exposure)]
    return TrainingLoadSummary(
        period=period,
        exposure_count=len(exposures),
        session_count=len({exposure.session_id for exposure in exposures}),
        active_day_count=len({exposure.date for exposure in exposures}),
        reps_exposure_count=len(reps_exposures),
        valid_reps_set_count=sum(
            _valid_reps_set_count(exposure) for exposure in reps_exposures
        ),
        tonnage=_aggregate_tonnage(exposures),
    )


def summarize_training_load(
    exposures: Iterable[TrainingLoadExposure], *, period: DateWindow
) -> TrainingLoadSummary:
    """Aggregate factual activity and typed tonnage over an explicit period."""
    _validate_period(period)
    in_period = [exposure for exposure in exposures if period.contains(exposure.date)]
    return _summarize_unique(_deduplicate(in_period), period)


def _monday(value: date) -> date:
    return value - timedelta(days=value.weekday())


def weekly_training_load(
    exposures: Iterable[TrainingLoadExposure],
    *,
    period: DateWindow,
    include_empty: bool = True,
) -> list[WeeklyTrainingLoad]:
    """Return deterministic Monday-Sunday buckets intersecting ``period``.

    ``week_start`` and ``week_end`` always describe the canonical full week.
    ``covered_window`` describes the possibly partial portion included by the
    caller's period. Empty weeks retain unavailable tonnage rather than zero.
    """
    _validate_period(period)
    in_period = [exposure for exposure in exposures if period.contains(exposure.date)]
    unique = _deduplicate(in_period)

    buckets: list[WeeklyTrainingLoad] = []
    week_start = _monday(period.start)
    while week_start <= period.end:
        week_end = week_start + timedelta(days=6)
        covered = DateWindow(
            start=max(week_start, period.start),
            end=min(week_end, period.end),
        )
        week_exposures = [
            exposure for exposure in unique if covered.contains(exposure.date)
        ]
        if include_empty or week_exposures:
            summary = _summarize_unique(week_exposures, covered)
            buckets.append(
                WeeklyTrainingLoad(
                    week_start=week_start,
                    week_end=week_end,
                    covered_window=covered,
                    is_partial=covered.start != week_start or covered.end != week_end,
                    exposure_count=summary.exposure_count,
                    session_count=summary.session_count,
                    active_day_count=summary.active_day_count,
                    reps_exposure_count=summary.reps_exposure_count,
                    valid_reps_set_count=summary.valid_reps_set_count,
                    tonnage=summary.tonnage,
                )
            )
        week_start += timedelta(days=7)
    return buckets
