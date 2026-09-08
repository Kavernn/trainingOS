"""Pure metric primitives for the future Stats cockpit.

This module deliberately has no database, API, UI, or production-consumer
dependencies. Existing TrainingOS metric implementations are not migrated here.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from enum import Enum
import math
from typing import Mapping, Sequence


class TrackingType(str, Enum):
    REPS = "reps"
    TIME = "time"
    CARRY = "carry"
    PLYO = "plyo"
    CARDIO = "cardio"
    INTERVAL = "interval"
    PROTOCOL = "protocol"
    MOBILITY = "mobility"


@dataclass(frozen=True)
class TrackingCapabilities:
    tracking_type: TrackingType | None
    supports_e1rm: bool
    supports_tonnage: bool

    @property
    def is_known(self) -> bool:
        return self.tracking_type is not None


@dataclass(frozen=True)
class BestE1RMResult:
    best_e1rm: float | None
    used_legacy_fallback: bool


@dataclass(frozen=True)
class TonnageResult:
    applicable: bool
    value: float | None


@dataclass(frozen=True)
class DateWindow:
    start: date
    end: date

    @property
    def day_count(self) -> int:
        return (self.end - self.start).days + 1

    def contains(self, value: date) -> bool:
        return self.start <= value <= self.end


@dataclass(frozen=True)
class ComparisonWindows:
    recent: DateWindow
    baseline: DateWindow


def _tracking_type(value: object) -> TrackingType | None:
    if isinstance(value, TrackingType):
        return value
    if not isinstance(value, str):
        return None
    try:
        return TrackingType(value)
    except ValueError:
        return None


def tracking_capabilities(value: object) -> TrackingCapabilities:
    """Return explicit capabilities; unknown values never fall back to reps."""
    tracking_type = _tracking_type(value)
    supports_strength = tracking_type is TrackingType.REPS
    return TrackingCapabilities(
        tracking_type=tracking_type,
        supports_e1rm=supports_strength,
        supports_tonnage=supports_strength,
    )


def _finite_float(value: object) -> float | None:
    if isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def _integer_reps(value: object) -> int | None:
    numeric = _finite_float(value)
    if numeric is None or not numeric.is_integer():
        return None
    return int(numeric)


def estimate_e1rm(weight: object, reps: object) -> float | None:
    """Estimate 1RM for one set, returning None outside the valid domain."""
    valid_weight = _finite_float(weight)
    valid_reps = _integer_reps(reps)
    if valid_weight is None or valid_weight <= 0:
        return None
    if valid_reps is None or not 1 <= valid_reps <= 15:
        return None
    if valid_reps <= 10:
        return valid_weight * (1 + valid_reps / 30)
    return valid_weight * 36 / (37 - valid_reps)


def _legacy_rep_values(value: object) -> list[int]:
    if not isinstance(value, str):
        parsed = _integer_reps(value)
        return [parsed] if parsed is not None else []
    values: list[int] = []
    for part in value.replace(";", ",").split(","):
        parsed = _integer_reps(part.strip())
        if parsed is not None:
            values.append(parsed)
    return values


def best_e1rm_for_exposure(
    *,
    tracking_type: object,
    sets: Sequence[Mapping[str, object]] | None,
    weight: object = None,
    reps: object = None,
) -> BestE1RMResult:
    """Return the best valid set e1RM, with an explicit legacy-fallback flag.

    ``sets is None`` means per-set data is genuinely absent and permits the
    top-level fallback. An empty or invalid set collection does not.
    """
    if not tracking_capabilities(tracking_type).supports_e1rm:
        return BestE1RMResult(None, False)

    if sets is not None:
        estimates = [
            estimate_e1rm(item.get("weight"), item.get("reps"))
            for item in sets
            if isinstance(item, Mapping)
        ]
        valid = [estimate for estimate in estimates if estimate is not None]
        return BestE1RMResult(max(valid) if valid else None, False)

    estimates = [estimate_e1rm(weight, value) for value in _legacy_rep_values(reps)]
    valid = [estimate for estimate in estimates if estimate is not None]
    return BestE1RMResult(max(valid) if valid else None, True)


def analytical_tonnage(
    *,
    tracking_type: object,
    sets: Sequence[Mapping[str, object]] | None,
) -> TonnageResult:
    """Sum valid reps-set loads, distinguishing zero from non-applicability."""
    if not tracking_capabilities(tracking_type).supports_tonnage:
        return TonnageResult(applicable=False, value=None)

    total = 0.0
    has_valid_set = False
    for item in sets or ():
        if not isinstance(item, Mapping):
            continue
        valid_weight = _finite_float(item.get("weight"))
        valid_reps = _integer_reps(item.get("reps"))
        if valid_weight is None or valid_weight < 0:
            continue
        if valid_reps is None or valid_reps <= 0:
            continue
        has_valid_set = True
        total += valid_weight * valid_reps
    return TonnageResult(
        applicable=True,
        value=total if has_valid_set else None,
    )


def comparison_windows(*, today: date, days: int) -> ComparisonWindows:
    """Build adjacent, non-overlapping windows of exactly ``days`` dates."""
    if type(today) is not date:
        raise TypeError("today must be a date")
    if isinstance(days, bool) or not isinstance(days, int) or days <= 0:
        raise ValueError("days must be a positive integer")

    recent = DateWindow(start=today - timedelta(days=days - 1), end=today)
    baseline_end = recent.start - timedelta(days=1)
    baseline = DateWindow(
        start=baseline_end - timedelta(days=days - 1),
        end=baseline_end,
    )
    return ComparisonWindows(recent=recent, baseline=baseline)
