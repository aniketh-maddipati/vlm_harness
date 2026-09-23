"""Bounded experiment planning and evidence selection; never creates image pixels."""

from dataclasses import asdict, dataclass, replace
import math


VERSION = "bounded-lattice-1"
ARMS = ("neutral", "current_auto", "lattice", "coarse_to_fine", "learned_scorer", "learned_ranges", "vlm")


@dataclass(frozen=True)
class Candidate:
    id: str = "zero"
    exposure: float = 0
    temperature: float | None = None
    tint: float = 0
    contrast: float = 0
    highlights: float = 0
    shadows: float = 0
    saturation: float = 0
    vibrance: float = 0

    def payload(self):
        values = asdict(self)
        bounds = {"exposure": (-1, 1), "temperature": (2500, 10000), "tint": (-10, 10),
                  "contrast": (-15, 15), "highlights": (-40, 0), "shadows": (0, 30),
                  "saturation": (-10, 10), "vibrance": (-10, 10)}
        for key, (lower, upper) in bounds.items():
            value = values[key]
            if key == "temperature" and value is None:
                continue
            if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or not lower <= value <= upper:
                raise ValueError("Invalid candidate control: " + key)
        if not self.id or self.temperature is None and self.tint != 0:
            raise ValueError("Missing identity or ambiguous as-shot tint")
        if self.id == "zero" and self != Candidate():
            raise ValueError("Candidate zero must be untouched")
        return values


def lattice():
    zero = Candidate()
    return [zero, replace(zero, id="exposure_down", exposure=-1 / 3),
            replace(zero, id="exposure_up", exposure=1 / 3),
            replace(zero, id="highlights", highlights=-20),
            replace(zero, id="shadows", shadows=15)]


def rank(receipts):
    valid = [receipt for receipt in receipts if not receipt["failures"]
             and all(isinstance(receipt.get(key), (float, int)) and math.isfinite(receipt[key])
                     for key in ("mean", "highlightClipFraction", "shadowClipFraction"))]
    return sorted(valid, key=lambda receipt: (receipt["highlightClipFraction"] + receipt["shadowClipFraction"],
                                             receipt["candidateID"] != "zero", receipt["candidateID"]))


def select(proxy, full, calibration=None):
    proxy_rank = rank(proxy)
    full_rank = rank(full)
    zero = next((row for row in full_rank if row["candidateID"] == "zero"), None)
    best = full_rank[0] if full_rank else None
    reason = "uncalibrated_and_incomplete_technical_safety"
    if not zero:
        reason = "missing_safe_candidate_zero_at_same_fidelity"
    elif not best or best["candidateID"] == "zero":
        reason = "no_improvement"
    return {
        "policy_version": VERSION, "status": "abstained", "selected_candidate": "zero",
        "reason": reason, "calibration": calibration, "production_acceptance_enabled": False,
        "proxy_top_three": [row["candidateID"] for row in proxy_rank[:3]],
        "full_rank": [row["candidateID"] for row in full_rank],
        "score_components": "sampled highlight + shadow clip fractions; diagnostic only, no aesthetic reward",
        "required_before_acceptance": ["heldout_margin_calibration", "full_pixel_safety", "verified_anchor_context",
                                       "matched_content_coherence", "source_output_profile_hdr", "human_acceptability"],
        "stop_reason": "single bounded pass; no validated expected-gain model for further iterations",
        "acceptance_margin": None, "remaining_expected_gain": None,
    }


def average_ranks(values):
    ordered = sorted(set(values))
    return [sum(index + 1 for index, item in enumerate(sorted(values)) if item == value)
            / values.count(value) for value in values] if ordered else []


def agreement(proxy, full):
    proxy_safe, full_safe = rank(proxy), rank(full)
    proxy_by_id = {row["candidateID"]: row for row in proxy_safe}
    full_by_id = {row["candidateID"]: row for row in full_safe}
    common = sorted(proxy_by_id.keys() & full_by_id.keys())
    correlation = None
    if len(common) >= 2:
        scores = lambda rows: [rows[key]["highlightClipFraction"] + rows[key]["shadowClipFraction"] for key in common]
        left, right = average_ranks(scores(proxy_by_id)), average_ranks(scores(full_by_id))
        left_mean, right_mean = sum(left) / len(left), sum(right) / len(right)
        numerator = sum((a - left_mean) * (b - right_mean) for a, b in zip(left, right))
        denominator = math.sqrt(sum((value - left_mean) ** 2 for value in left) * sum((value - right_mean) ** 2 for value in right))
        if denominator:
            correlation = numerator / denominator
    complete = {row["candidateID"] for row in proxy} == {row["candidateID"] for row in full}
    full_failures = {row["candidateID"] for row in full if row["failures"]}
    proxy_top = proxy_safe[0]["candidateID"] if proxy_safe else None
    full_top = full_safe[0]["candidateID"] if full_safe else None
    return {"complete_candidate_audit": complete, "paired_safe_count": len(common),
            "top1_retention": proxy_top == full_top if complete and proxy_top and full_top else None,
            "top3_contains_full_winner": full_top in {row["candidateID"] for row in proxy_safe[:3]} if complete and full_top else None,
            "spearman_paired_subset": correlation,
            "proxy_winner_failed_full": proxy_top in full_failures if proxy_top in {row["candidateID"] for row in full} else None,
            "full_render_elapsed_ms": sum(row["elapsedMS"] for row in full),
            "added_peak_memory": "UNMEASURED; compare external process peaks in separate runs",
            "caveat": "Diagnostic sampled clipping ranks, not harmonization quality. Subset correlation is selection-biased."}
