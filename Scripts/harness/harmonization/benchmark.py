"""Draft and validate event-separated, local-only harmonization benchmark manifests."""

import argparse
import json
from pathlib import Path

from inventory import atomic_json, candidates


REJECT_REASONS = {"clipping", "cast", "local_tone_artifacts", "oversharpening", "noise", "subject_mismatch", "no_anchor"}


def draft(manifest, max_scenes=40, target_assets=160):
    groups = candidates(manifest["assets"])
    selected, count = [], 0
    for group in groups:
        if not group["cross_device_candidate"]:
            continue
        if len(selected) >= max_scenes or count >= target_assets:
            break
        selected.append({"scene_id": group["candidate_id"], "asset_ids": group["asset_ids"],
                         "event_id": None, "split": "quarantine", "scene_verified": False,
                         "anchors": [], "lighting": "unreviewed", "people_consent": "unreviewed",
                         "initial_acceptability": None, "needs_correction": None, "abstain": True,
                         "approved_recipe": None, "reject_reasons": ["no_anchor"],
                         "matched_content": [], "difficulty": "unreviewed",
                         "candidate_evidence": group["evidence"], "complete_set_confirmed": False})
        count += len(group["asset_ids"])
    used = {asset for scene in selected for asset in scene["asset_ids"]}
    return {"schema_version": 1, "status": "draft_unverified", "targets": {"scenes": [30, 50], "assets": [100, 200]},
            "assets": [row for row in manifest["assets"] if row["asset_id"] in used], "scenes": selected,
            "note": "Full time buckets retained; target count never truncates a set. No scene/split/consent inferred."}


def validate(manifest, frozen=False):
    if manifest.get("schema_version") != 1:
        raise ValueError("Unsupported schema")
    assets = {row["asset_id"]: row for row in manifest["assets"]}
    if len(assets) != len(manifest["assets"]):
        raise ValueError("Duplicate asset ID")
    assignments, event_splits, identities, bursts = {}, {}, {}, {}
    scene_ids = set()
    for scene in manifest["scenes"]:
        if scene["scene_id"] in scene_ids:
            raise ValueError("Duplicate scene ID")
        scene_ids.add(scene["scene_id"])
        split = scene["split"]
        if split not in {"development", "validation", "heldout", "quarantine"}:
            raise ValueError("Invalid split")
        if not set(scene["reject_reasons"]).issubset(REJECT_REASONS):
            raise ValueError("Unknown rejection reason")
        if not set(scene["anchors"]).issubset(scene["asset_ids"]):
            raise ValueError("Anchor outside scene")
        if not scene.get("abstain", True) and not scene["anchors"]:
            raise ValueError("Non-abstaining scene needs an approved anchor")
        for match in scene.get("matched_content", []):
            if match["source_asset"] not in scene["asset_ids"] or match["anchor_asset"] not in scene["anchors"]:
                raise ValueError("Matched content outside scene or approved anchors")
            for key in ("source_roi", "anchor_roi"):
                region = match[key]
                if (len(region) != 4 or not all(isinstance(value, (int, float)) and 0 <= value <= 1 for value in region)
                        or region[2] == 0 or region[3] == 0 or region[0] + region[2] > 1 or region[1] + region[3] > 1):
                    raise ValueError("Invalid matched-content region")
        if frozen and (not scene["scene_verified"] or not scene["event_id"] or split == "quarantine"
                       or not scene["complete_set_confirmed"] or scene["people_consent"] not in {"no_people", "local_review_approved"}):
            raise ValueError("Frozen corpus requires verified scenes/events/sets and reviewed consent")
        event = scene["event_id"]
        if event and event_splits.setdefault(event, split) != split:
            raise ValueError("Event crosses split")
        for asset_id in scene["asset_ids"]:
            if asset_id not in assets:
                raise ValueError("Unknown asset")
            if asset_id in assignments:
                raise ValueError("Asset occurs in multiple scenes")
            assignments[asset_id] = split
            asset = assets[asset_id]
            for table, key in ((identities, asset["fingerprint"]["content_identity"]),
                               (bursts, asset.get("burst_id")), (bursts, asset.get("near_duplicate_group"))):
                if key and table.setdefault(key, split) != split:
                    raise ValueError("Duplicate or burst crosses split")
    if frozen and (set(assignments) != set(assets) or not {"development", "heldout"}.issubset(event_splits.values())):
        raise ValueError("Assign every asset and retain separate development/heldout events")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--draft-out", type=Path)
    parser.add_argument("--frozen", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if args.draft_out:
        out = args.draft_out.resolve()
        if any((parent / ".git").exists() for parent in (out.parent, *out.parents)):
            parser.error("Private benchmark manifests must stay outside git")
        if any(out.is_relative_to(Path(root)) for root in manifest.get("roots", [])):
            parser.error("Do not write benchmark evidence under originals")
        manifest = draft(manifest)
        atomic_json(args.draft_out, manifest)
    validate(manifest, args.frozen)
    print(json.dumps({"scenes": len(manifest["scenes"]), "assets": len(manifest["assets"]), "frozen": args.frozen}))


if __name__ == "__main__":
    main()
