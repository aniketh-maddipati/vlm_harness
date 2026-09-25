#!/usr/bin/env python3
"""Stream D — recover *sets* of accepted Lightroom recipes for one source frame.

Input is the labels file produced by `export_labels.py` (one row per
(RAW, finished Lightroom edit) pair). There is no Lightroom Classic catalog on
this machine, so the "these exports are siblings" relation is recovered from
`xmpMM:OriginalDocumentID`, which Lightroom keeps identical across every export
derived from one source frame. A second, independent grouping by the RAW file's
sha256 is computed as a cross-check; both counts are reported.

THE FALSIFIER: a group of sibling exports may differ only in CROP or in export
size, not in tone. Those are NOT variation labels. Every multi-export group is
classified into exactly one of tone-only / geometry-only / both / neither, and
only the tone-differing groups (tone-only + both) are emitted as labels.

Field parsing is not reimplemented here — the develop controls in labels.jsonl
were parsed by `lr_truth.FIELDS`, and this module imports `lr_truth` to take its
field list, its tone-field list and its numeric coercion verbatim.

Usage:
    python3 Scripts/harness/eval/virtual_copies.py [LABELS_JSONL] [OUT_DIR]

Defaults:
    LABELS_JSONL  ~/LuminaEvidence/export-labels-01/labels.jsonl
    OUT_DIR       ~/LuminaEvidence/virtual-copies-01

Writes OUT_DIR/variations.jsonl and OUT_DIR/counts.json. Reads no pixels, copies
no photographs, writes nothing to /Volumes/T7.
"""
from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lr_truth  # noqa: E402  — reused, never reimplemented

DEFAULT_LABELS = Path.home() / "LuminaEvidence" / "export-labels-01" / "labels.jsonl"
DEFAULT_OUT = Path.home() / "LuminaEvidence" / "virtual-copies-01"

# The controls the contract names, split into the two axes the falsifier tests.
# `lr_truth.TONE_FIELDS` is the tone subset minus white balance; temperature and
# tint are colour decisions and belong on the tone/colour axis here, so the tone
# axis is lr_truth.TONE_FIELDS + ("temperature", "tint").
TONE_CONTROLS: tuple[str, ...] = lr_truth.TONE_FIELDS + ("temperature", "tint")
GEOMETRY_CONTROLS: tuple[str, ...] = ("cropTop", "cropLeft", "cropBottom", "cropRight", "cropAngle")

# Per-control tolerance: a group "differs" on a control when its spread EXCEEDS
# the tolerance. Justification (one line per class):
#   integer sliders  Lightroom stores these as whole units in [-100, 100]; 0.5
#                    means "at least one whole slider unit apart", which is the
#                    smallest difference the UI can express, while absorbing any
#                    float round-trip noise.
#   exposure         EV, written to 2 decimals; 0.005 is half the stored
#                    quantum, so any real move (>= 0.01 EV) counts and nothing
#                    below the stored precision does.
#   temperature      Kelvin, stored as a whole number; 0.5 K = one stored unit.
#   crop fractions   fraction of the frame; 1e-4 of a 6000 px frame is 0.6 px,
#                    i.e. sub-pixel, so anything above it is a real re-crop.
#   cropAngle        degrees; 1e-3 deg is far below Lightroom's 0.01 deg display.
_INTEGER_SLIDER_TOL = 0.5
TOLERANCES: dict[str, float] = {
    "exposure": 0.005,
    "temperature": 0.5,
    "tint": _INTEGER_SLIDER_TOL,
    "contrast": _INTEGER_SLIDER_TOL,
    "highlights": _INTEGER_SLIDER_TOL,
    "shadows": _INTEGER_SLIDER_TOL,
    "whites": _INTEGER_SLIDER_TOL,
    "blacks": _INTEGER_SLIDER_TOL,
    "texture": _INTEGER_SLIDER_TOL,
    "clarity": _INTEGER_SLIDER_TOL,
    "dehaze": _INTEGER_SLIDER_TOL,
    "vibrance": _INTEGER_SLIDER_TOL,
    "saturation": _INTEGER_SLIDER_TOL,
    "cropTop": 1e-4,
    "cropLeft": 1e-4,
    "cropBottom": 1e-4,
    "cropRight": 1e-4,
    "cropAngle": 1e-3,
}

DEFAULTS: dict[str, float] = {key: default for _crs, key, default in lr_truth.FIELDS}

CLASSES = ("tone-only", "geometry-only", "both", "neither")

# `lr_truth.FIELDS` defaults ColorTemperature to 0.0 when the tag is absent, and
# 0 K is physically impossible (the observed range in labels.jsonl is 3850-8129 K),
# so 0.0 means NOT RECORDED, not "neutral". Comparing it against a real Kelvin
# value would fabricate a multi-thousand-Kelvin spread, which is exactly the kind
# of false variation label this task exists to catch. When any member of a group
# is missing its temperature, temperature is dropped from that group's comparison.
# No other control has an impossible-zero, so no other control gets this guard.
TEMPERATURE_ABSENT = 0.0


def load_rows(path: Path) -> list[dict]:
    if not path.is_file():
        raise SystemExit(f"STOP: labels file missing or unreadable: {path}")
    rows: list[dict] = []
    with path.open(encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise SystemExit(f"STOP: labels file unreadable at line {lineno}: {exc}")
    if not rows:
        raise SystemExit(f"STOP: labels file empty: {path}")
    return rows


def control_value(row: dict, key: str) -> float:
    return lr_truth._num(row.get(key), DEFAULTS.get(key, 0.0))


def recipe(row: dict) -> dict[str, float]:
    """The comparable recipe: every tone and geometry control this task judges."""
    return {key: control_value(row, key) for key in (*TONE_CONTROLS, *GEOMETRY_CONTROLS)}


def quantize(value: float, key: str) -> int:
    """Bucket a value so two recipes inside tolerance land in the same bucket."""
    quantum = 2.0 * TOLERANCES[key]
    return int(round(value / quantum))


def fingerprint(rec: dict[str, float], keys: tuple[str, ...]) -> tuple[int, ...]:
    return tuple(quantize(rec[key], key) for key in keys)


def spreads(recipes: list[dict[str, float]], keys: tuple[str, ...]) -> dict[str, float]:
    out: dict[str, float] = {}
    for key in keys:
        values = [rec[key] for rec in recipes]
        out[key] = max(values) - min(values)
    return out


def differing(spread: dict[str, float], keys: tuple[str, ...]) -> list[str]:
    return [key for key in keys if spread[key] > TOLERANCES[key]]


def classify(tone_diff: list[str], geom_diff: list[str]) -> str:
    if tone_diff and geom_diff:
        return "both"
    if tone_diff:
        return "tone-only"
    if geom_diff:
        return "geometry-only"
    return "neither"


def analyse_group(rows: list[dict]) -> dict:
    recipes = [recipe(row) for row in rows]
    temperature_unusable = any(rec["temperature"] == TEMPERATURE_ABSENT for rec in recipes)
    tone_keys = tuple(k for k in TONE_CONTROLS if not (temperature_unusable and k == "temperature"))
    all_keys = (*TONE_CONTROLS, *GEOMETRY_CONTROLS)
    spread = spreads(recipes, all_keys)
    if temperature_unusable:
        spread["temperature"] = 0.0  # NOT MEASURED for this group, not "no difference"
    tone_diff = differing(spread, tone_keys)
    geom_diff = differing(spread, GEOMETRY_CONTROLS)
    distinct_tone = len({fingerprint(rec, tone_keys) for rec in recipes})
    distinct_full = len({fingerprint(rec, (*tone_keys, *GEOMETRY_CONTROLS)) for rec in recipes})
    return {
        "recipes": recipes,
        "spread": spread,
        "temperatureNotMeasured": temperature_unusable,
        "toneDiffering": tone_diff,
        "geometryDiffering": geom_diff,
        "classification": classify(tone_diff, geom_diff),
        "distinctToneRecipes": distinct_tone,
        "distinctFullRecipes": distinct_full,
    }


def group_by(rows: list[dict], key: str) -> dict[str, list[dict]]:
    buckets: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        value = row.get(key)
        if value:
            buckets[str(value)].append(row)
    return dict(buckets)


def classification_counts(groups: dict[str, list[dict]]) -> dict:
    counts = {name: 0 for name in CLASSES}
    multi = 0
    temp_not_measured = 0
    for members in groups.values():
        if len(members) < 2:
            continue
        multi += 1
        analysis = analyse_group(members)
        counts[analysis["classification"]] += 1
        temp_not_measured += int(analysis["temperatureNotMeasured"])
    return {
        "groupsTotal": len(groups),
        "groupsWithMoreThanOneExport": multi,
        "classification": counts,
        "toneDifferingGroups": counts["tone-only"] + counts["both"],
        "multiExportGroupsWithTemperatureNotMeasured": temp_not_measured,
    }


def grouping_agreement(rows: list[dict]) -> dict:
    """Do 'same OriginalDocumentID' and 'same RAW file' cut the rows the same way?"""
    by_odid = group_by(rows, "originalDocumentID")
    by_sha = group_by(rows, "rawSha256")
    odid_of_row = {id(row): row.get("originalDocumentID") for row in rows}
    sha_of_row = {id(row): row.get("rawSha256") for row in rows}

    # A group SPLITS when members of one sha group carry different ODIDs, and
    # MERGES when one ODID group spans more than one RAW file.
    sha_groups_spanning_multiple_odids = {
        sha: sorted({odid_of_row[id(r)] for r in members})
        for sha, members in by_sha.items()
        if len({odid_of_row[id(r)] for r in members}) > 1
    }
    odid_groups_spanning_multiple_raws = {
        odid: sorted({sha_of_row[id(r)] for r in members})
        for odid, members in by_odid.items()
        if len({sha_of_row[id(r)] for r in members}) > 1
    }
    return {
        "agree": not sha_groups_spanning_multiple_odids and not odid_groups_spanning_multiple_raws,
        "rawShaGroupsCarryingMoreThanOneOriginalDocumentID": sha_groups_spanning_multiple_odids,
        "originalDocumentIDGroupsSpanningMoreThanOneRaw": odid_groups_spanning_multiple_raws,
    }


def spread_distribution(group_analyses: list[dict]) -> dict:
    """Per-slider spread distribution across the tone-differing groups."""
    dist: dict[str, dict] = {}
    for key in (*TONE_CONTROLS, *GEOMETRY_CONTROLS):
        values = sorted(a["spread"][key] for a in group_analyses)
        if not values:
            dist[key] = {"n": 0}
            continue
        n = len(values)

        def pct(p: float) -> float:
            idx = min(n - 1, max(0, int(round((n - 1) * p))))
            return round(values[idx], 6)

        dist[key] = {
            "n": n,
            "groupsExceedingTolerance": sum(1 for v in values if v > TOLERANCES[key]),
            "min": round(values[0], 6),
            "p50": pct(0.5),
            "p90": pct(0.9),
            "max": round(values[-1], 6),
            "mean": round(sum(values) / n, 6),
        }
    return dist


def build(labels_path: Path, out_dir: Path) -> dict:
    rows = load_rows(labels_path)
    out_dir.mkdir(parents=True, exist_ok=True)

    by_odid = group_by(rows, "originalDocumentID")
    by_sha = group_by(rows, "rawSha256")
    odid_counts = classification_counts(by_odid)
    sha_counts = classification_counts(by_sha)
    agreement = grouping_agreement(rows)

    # Emission unit: the RAW file (rawSha256), because the deliverable is "one row
    # per RAW that has >=2 tone-differing accepted recipes".
    emitted: list[dict] = []
    tone_differing_analyses: list[dict] = []
    for sha, members in sorted(by_sha.items()):
        if len(members) < 2:
            continue
        analysis = analyse_group(members)
        if analysis["classification"] not in ("tone-only", "both"):
            continue
        if analysis["distinctToneRecipes"] < 2:
            continue
        tone_differing_analyses.append(analysis)
        odids = sorted({str(r.get("originalDocumentID", "")) for r in members})
        emitted.append({
            "raw": members[0].get("raw"),
            "rawSha256": sha,
            "originalDocumentID": odids[0] if len(odids) == 1 else odids,
            "classification": analysis["classification"],
            "temperatureNotMeasured": analysis["temperatureNotMeasured"],
            "acceptedRecipeCount": len(members),
            "distinctToneRecipes": analysis["distinctToneRecipes"],
            "distinctFullRecipes": analysis["distinctFullRecipes"],
            "toneControlsThatDiffer": analysis["toneDiffering"],
            "geometryControlsThatDiffer": analysis["geometryDiffering"],
            "acceptedRecipes": [
                {
                    "jpeg": row.get("jpeg"),
                    "documentID": row.get("documentID"),
                    "hasMask": bool(row.get("hasMask")),
                    "hasRetouch": bool(row.get("hasRetouch")),
                    "untouched": bool(row.get("untouched")),
                    **{k: round(v, 6) for k, v in rec.items()},
                }
                for row, rec in zip(members, analysis["recipes"])
            ],
            "spread": {k: round(v, 6) for k, v in analysis["spread"].items()},
        })

    variations = out_dir / "variations.jsonl"
    with variations.open("w", encoding="utf-8") as handle:
        for item in emitted:
            handle.write(json.dumps(item, sort_keys=True) + "\n")

    counts = {
        "schema": 1,
        "source": str(labels_path),
        "rowsRead": len(rows),
        "distinctRawSha256": len(by_sha),
        "distinctOriginalDocumentID": len(by_odid),
        "toneControls": list(TONE_CONTROLS),
        "geometryControls": list(GEOMETRY_CONTROLS),
        "tolerances": TOLERANCES,
        "toleranceRule": (
            "a group differs on a control when (max - min) across the group EXCEEDS "
            "that control's tolerance; distinct-recipe counting buckets each value at "
            "2x tolerance"
        ),
        "groupingByOriginalDocumentID": odid_counts,
        "groupingByRawSha256": sha_counts,
        "groupingAgreement": agreement,
        "emittedRawsWithTwoOrMoreToneDifferingRecipes": len(emitted),
        "spreadDistributionAcrossToneDifferingGroups": spread_distribution(tone_differing_analyses),
        "toneDifferingGroupsByDriverControl": dict(
            Counter(
                key
                for a in tone_differing_analyses
                for key in a["toneDiffering"]
            ).most_common()
        ),
        "outputs": {
            "variations": str(variations),
            "counts": str(out_dir / "counts.json"),
        },
    }
    (out_dir / "counts.json").write_text(json.dumps(counts, indent=1, sort_keys=True), encoding="utf-8")
    return counts


def main(argv: list[str]) -> int:
    labels = Path(argv[1]).expanduser() if len(argv) > 1 else DEFAULT_LABELS
    out_dir = Path(argv[2]).expanduser() if len(argv) > 2 else DEFAULT_OUT
    counts = build(labels, out_dir)
    odid = counts["groupingByOriginalDocumentID"]
    sha = counts["groupingByRawSha256"]
    print(f"rows: {counts['rowsRead']}  distinct RAWs (sha256): {counts['distinctRawSha256']}  "
          f"distinct OriginalDocumentIDs: {counts['distinctOriginalDocumentID']}")
    for name, block in (("OriginalDocumentID", odid), ("rawSha256", sha)):
        c = block["classification"]
        print(f"grouping by {name}: {block['groupsWithMoreThanOneExport']} multi-export groups — "
              f"tone-only {c['tone-only']}, geometry-only {c['geometry-only']}, "
              f"both {c['both']}, neither {c['neither']}  "
              f"→ tone-differing {block['toneDifferingGroups']}")
    print(f"groupings agree: {counts['groupingAgreement']['agree']}")
    print(f"RAWs with >=2 tone-differing accepted recipes: "
          f"{counts['emittedRawsWithTwoOrMoreToneDifferingRecipes']}")
    print(f"wrote {counts['outputs']['variations']} and {counts['outputs']['counts']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
