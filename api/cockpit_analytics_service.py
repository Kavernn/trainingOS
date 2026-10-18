"""Typed orchestration for the future Stats cockpit.

This layer only joins the existing adapter and pure analytics engines. HTTP,
authentication, serialization, caching, and production consumers belong to
later layers.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from datetime import timedelta
from analytics_adapter import AnalyticsAdapterDiagnostics, UnmappedExerciseDiagnostic, adapt_analytics_rows, fetch_raw_analytics_rows, is_deload_day, unmapped_exercise_diagnostics
from metric_semantics import ComparisonWindows, DateWindow, comparison_windows
from muscle_workload_analytics import MuscleMappingCoverage, MuscleWorkload, summarize_muscle_workload
from progression_comparison import AttentionObservation, MoverE1RMPoint, ProgressionComparison, ProgressionStatus, compare_progression, movers_e1rm_series, no_recent_improvement, top_movers
from training_load_analytics import DailyTrainingLoad, TrainingLoadSummary, WeeklyTrainingLoad, daily_training_load, summarize_training_load, weekly_training_load


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
    # Fenêtre précédente de même longueur que `muscle_period`, pour afficher
    # "courant vs précédent" dans "Détail musculaire". None → l'endpoint
    # n'expose pas de previous_workloads (backward-compat).
    muscle_previous_period: DateWindow | None = None

    def __post_init__(self) -> None:
        if type(self.as_of) is not date:
            raise TypeError("as_of must be a date")
        if isinstance(self.progression_days, bool) or self.progression_days not in SUPPORTED_PROGRESSION_DAYS:
            raise ValueError("progression_days must be 30 or 90")
        _validate_window(self.weekly_period, "weekly_period")
        _validate_window(self.muscle_period, "muscle_period")
        if self.muscle_previous_period is not None:
            _validate_window(self.muscle_previous_period, "muscle_previous_period")
            if self.muscle_previous_period.end >= self.muscle_period.start:
                raise ValueError("muscle_previous_period must end strictly before muscle_period starts")
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
        periods = [windows.baseline, windows.recent, self.weekly_period, self.muscle_period]
        if self.muscle_previous_period is not None:
            periods.append(self.muscle_previous_period)
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
    # Série e1RM 12 semaines par exercice top mover — même source que
    # ``top_movers`` (strength_exposures complets), zéro troncature. Clés =
    # exercise_name des top_movers uniquement.
    top_movers_series: dict[str, tuple[MoverE1RMPoint, ...]]
    attention: tuple[AttentionObservation, ...]


@dataclass(frozen=True)
class CockpitTrainingLoad:
    period: DateWindow
    summary: TrainingLoadSummary
    weekly: tuple[WeeklyTrainingLoad, ...]
    daily: tuple[DailyTrainingLoad, ...]


@dataclass(frozen=True)
class CockpitMuscles:
    period: DateWindow
    coverage: MuscleMappingCoverage
    workloads: tuple[MuscleWorkload, ...]
    unmapped_exercises: tuple[UnmappedExerciseDiagnostic, ...]
    # Fenêtre précédente (même longueur) et son résumé. None si le config
    # ne la demande pas. Les flags `*_includes_deload` servent au visuel iOS
    # pour griser la zone et neutraliser le verdict MEV/MAV/MRV sur une
    # fenêtre contaminée par une semaine de décharge.
    previous_period: DateWindow | None = None
    previous_workloads: tuple[MuscleWorkload, ...] = ()
    current_includes_deload: bool = False
    previous_includes_deload: bool = False


def _period_includes_deload(period: DateWindow, cycle_start_date: date | None) -> bool:
    """Any day of the window falls on a programmed deload week?"""
    if cycle_start_date is None:
        return False
    for i in range(period.day_count):
        if is_deload_day(period.start + timedelta(days=i), cycle_start_date):
            return True
    return False


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
    movers = tuple(top_movers(comparisons))
    movers_series = movers_e1rm_series(adapted.strength_exposures, movers, as_of=config.as_of)
    attention = tuple(no_recent_improvement(adapted.strength_exposures, observation_window=windows.recent, as_of=config.as_of))
    load_summary = summarize_training_load(adapted.training_load_exposures, period=config.weekly_period)
    muscle_summary = summarize_muscle_workload(adapted.training_load_exposures, adapted.assignments, period=config.muscle_period)
    previous_summary = None
    if config.muscle_previous_period is not None:
        previous_summary = summarize_muscle_workload(
            adapted.training_load_exposures, adapted.assignments,
            period=config.muscle_previous_period,
        )
    return CockpitAnalyticsResponse(
        as_of=config.as_of,
        progression=CockpitProgression(
            comparison_window_days=config.progression_days,
            baseline_window=windows.baseline,
            recent_window=windows.recent,
            status_counts=_status_counts(comparisons),
            comparisons=comparisons,
            top_movers=movers,
            top_movers_series=movers_series,
            attention=attention,
        ),
        training_load=CockpitTrainingLoad(
            period=config.weekly_period,
            summary=load_summary,
            weekly=tuple(weekly_training_load(adapted.training_load_exposures, period=config.weekly_period, include_empty=True)),
            daily=tuple(daily_training_load(
                adapted.training_load_exposures,
                period=config.weekly_period,
                is_deload=lambda day: is_deload_day(day, cycle_start_date),
            )),
        ),
        muscles=CockpitMuscles(
            period=config.muscle_period,
            coverage=muscle_summary.coverage,
            workloads=muscle_summary.muscles,
            unmapped_exercises=unmapped_exercise_diagnostics(
                raw_rows, period=config.muscle_period, cycle_start_date=cycle_start_date
            ),
            previous_period=config.muscle_previous_period,
            previous_workloads=previous_summary.muscles if previous_summary else (),
            current_includes_deload=_period_includes_deload(config.muscle_period, cycle_start_date),
            previous_includes_deload=(
                _period_includes_deload(config.muscle_previous_period, cycle_start_date)
                if config.muscle_previous_period is not None else False
            ),
        ),
        data_quality=CockpitDataQuality(requested_raw_period=config.raw_period, adapter=adapted.diagnostics),
    )
