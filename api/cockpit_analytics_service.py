"""Typed orchestration for the future Stats cockpit.

This layer only joins the existing adapter and pure analytics engines. HTTP,
authentication, serialization, caching, and production consumers belong to
later layers.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from analytics_adapter import AnalyticsAdapterDiagnostics, UnmappedExerciseDiagnostic, adapt_analytics_rows, fetch_raw_analytics_rows, unmapped_exercise_diagnostics
from metric_semantics import ComparisonWindows, DateWindow, comparison_windows
from muscle_workload_analytics import MuscleMappingCoverage, MuscleWorkload, summarize_muscle_workload
from progression_comparison import AttentionObservation, ProgressionComparison, ProgressionStatus, compare_progression, no_recent_improvement, top_movers
from training_load_analytics import TrainingLoadSummary, WeeklyTrainingLoad, summarize_training_load, weekly_training_load


SUPPORTED_PROGRESSION_DAYS = frozenset({30, 90})


def _validate_window(window: DateWindow, name: str) -> None:
    if type(window.start) is not date or type(window.end) is not date:
        raise TypeError(f"{name} must contain date values")
    if window.start > window.end:
        raise ValueError(f"{name} start cannot follow end")


@dataclass(frozen=True)
class CockpitAnalyticsConfig:
    as_of: date
    progression_days: int
    weekly_period: DateWindow
    muscle_period: DateWindow

    def __post_init__(self) -> None:
        if type(self.as_of) is not date:
            raise TypeError("as_of must be a date")
        if isinstance(self.progression_days, bool) or self.progression_days not in SUPPORTED_PROGRESSION_DAYS:
            raise ValueError("progression_days must be 30 or 90")
        _validate_window(self.weekly_period, "weekly_period")
        _validate_window(self.muscle_period, "muscle_period")
        if self.weekly_period.end > self.as_of:
            raise ValueError("weekly_period cannot end after as_of")
        if self.muscle_period.end > self.as_of:
            raise ValueError("muscle_period cannot end after as_of")

    @property
    def progression_windows(self) -> ComparisonWindows:
        return comparison_windows(today=self.as_of, days=self.progression_days)

    @property
    def raw_period(self) -> DateWindow:
        windows = self.progression_windows
        periods = (windows.baseline, windows.recent, self.weekly_period, self.muscle_period)
        return DateWindow(start=min(period.start for period in periods), end=max(period.end for period in periods))


@dataclass(frozen=True)
class ProgressionStatusCounts:
    improving: int
    stable: int
    declining: int
    insufficient_data: int


@dataclass(frozen=True)
class CockpitProgression:
    comparison_window_days: int
    baseline_window: DateWindow
    recent_window: DateWindow
    status_counts: ProgressionStatusCounts
    comparisons: tuple[ProgressionComparison, ...]
    top_movers: tuple[ProgressionComparison, ...]
    attention: tuple[AttentionObservation, ...]


@dataclass(frozen=True)
class CockpitTrainingLoad:
    period: DateWindow
    summary: TrainingLoadSummary
    weekly: tuple[WeeklyTrainingLoad, ...]


@dataclass(frozen=True)
class CockpitMuscles:
    period: DateWindow
    coverage: MuscleMappingCoverage
    workloads: tuple[MuscleWorkload, ...]
    unmapped_exercises: tuple[UnmappedExerciseDiagnostic, ...]


@dataclass(frozen=True)
class CockpitDataQuality:
    requested_raw_period: DateWindow
    adapter: AnalyticsAdapterDiagnostics


@dataclass(frozen=True)
class CockpitAnalyticsResponse:
    as_of: date
    progression: CockpitProgression
    training_load: CockpitTrainingLoad
    muscles: CockpitMuscles
    data_quality: CockpitDataQuality


def _status_counts(comparisons: tuple[ProgressionComparison, ...]) -> ProgressionStatusCounts:
    return ProgressionStatusCounts(
        improving=sum(item.status is ProgressionStatus.IMPROVING for item in comparisons),
        stable=sum(item.status is ProgressionStatus.STABLE for item in comparisons),
        declining=sum(item.status is ProgressionStatus.DECLINING for item in comparisons),
        insufficient_data=sum(item.status is ProgressionStatus.INSUFFICIENT_DATA for item in comparisons),
    )


def build_cockpit_analytics(client: object, config: CockpitAnalyticsConfig, *, cycle_start_date: date | None = None) -> CockpitAnalyticsResponse:
    """Fetch once, adapt once, and assemble all canonical cockpit facts."""
    if cycle_start_date is not None and type(cycle_start_date) is not date:
        raise TypeError("cycle_start_date must be a date")
    raw_rows = fetch_raw_analytics_rows(client, period=config.raw_period)
    adapted = adapt_analytics_rows(raw_rows, period=config.raw_period, cycle_start_date=cycle_start_date)
    windows = config.progression_windows
    comparisons = tuple(compare_progression(adapted.strength_exposures, today=config.as_of, days=config.progression_days))
    attention = tuple(no_recent_improvement(adapted.strength_exposures, observation_window=windows.recent, as_of=config.as_of))
    load_summary = summarize_training_load(adapted.training_load_exposures, period=config.weekly_period)
    muscle_summary = summarize_muscle_workload(adapted.training_load_exposures, adapted.assignments, period=config.muscle_period)
    return CockpitAnalyticsResponse(
        as_of=config.as_of,
        progression=CockpitProgression(
            comparison_window_days=config.progression_days,
            baseline_window=windows.baseline,
            recent_window=windows.recent,
            status_counts=_status_counts(comparisons),
            comparisons=comparisons,
            top_movers=tuple(top_movers(comparisons)),
            attention=attention,
        ),
        training_load=CockpitTrainingLoad(
            period=config.weekly_period,
            summary=load_summary,
            weekly=tuple(weekly_training_load(adapted.training_load_exposures, period=config.weekly_period, include_empty=True)),
        ),
        muscles=CockpitMuscles(
            period=config.muscle_period,
            coverage=muscle_summary.coverage,
            workloads=muscle_summary.muscles,
            unmapped_exercises=unmapped_exercise_diagnostics(
                raw_rows, period=config.muscle_period, cycle_start_date=cycle_start_date
            ),
        ),
        data_quality=CockpitDataQuality(requested_raw_period=config.raw_period, adapter=adapted.diagnostics),
    )
