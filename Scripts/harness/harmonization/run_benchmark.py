"""Run a Sony-only measurement checkpoint through the production XCTest bridge."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import uuid

from controller import ARMS, agreement, lattice, rank, select
from inventory import atomic_json, stat_key


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def code_manifest():
    root = Path(__file__).resolve().parents[3]
    return {str(path.relative_to(root)): digest(path)
            for folder, pattern in (("Lumina", "*.swift"), ("LuminaLogicTests", "*.swift"),
                                    ("Scripts/harness/harmonization", "*.py"))
            for path in sorted((root / folder).rglob(pattern))}


def execute(xctestrun, plan, output, directory):
    root = str(xctestrun.resolve().parent)
    def expand(value):
        if isinstance(value, str):
            return value.replace("__TESTROOT__", root)
        if isinstance(value, list):
            return [expand(item) for item in value]
        if isinstance(value, dict):
            return {key: expand(item) for key, item in value.items()}
        return value
    data = expand(plistlib.loads(xctestrun.read_bytes()))
    matched = 0
    for config in data["TestConfigurations"]:
        for target in config["TestTargets"]:
            if target["BlueprintName"] == "LuminaLogicTests":
                target.setdefault("EnvironmentVariables", {}).update(
                    LUMINA_HARMONIZATION_PLAN=str(plan), LUMINA_HARMONIZATION_RECEIPTS=str(output))
                matched += 1
    if not matched:
        raise ValueError("LuminaLogicTests target missing")
    testfile = directory / "run.xctestrun"
    testfile.write_bytes(plistlib.dumps(data))
    with (directory / "xcode.log").open("w") as log:
        result = subprocess.run(["/usr/bin/time", "-l", "xcodebuild", "-xctestrun", str(testfile),
            "-destination", "platform=macOS,arch=arm64", "-only-testing:LuminaLogicTests/HarmonizationRenderHarnessTests",
            "-parallel-testing-enabled", "NO", "test-without-building"], stdout=log, stderr=subprocess.STDOUT)
    if result.returncode or not output.exists():
        raise RuntimeError("Render failed or missing receipts; inspect " + str(directory / "xcode.log"))
    return json.loads(output.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--xctestrun", required=True, type=Path)
    parser.add_argument("--audit-all", action="store_true", help="Full-render all candidates for unbiased rank agreement")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    output = args.out.resolve()
    if source.suffix.lower() != ".arw":
        parser.error("Phone and non-Sony execution unsupported at this checkpoint")
    if any((parent / ".git").exists() for parent in (output, *output.parents)) or output.is_relative_to(source.parent):
        parser.error("Output must be private and outside originals")
    output.mkdir(parents=True, exist_ok=False)
    before = stat_key(source)
    source_hash = digest(source)
    atomic_json(output / "source-manifest.json", code_manifest())
    candidate_list = lattice()
    identity = str(uuid.uuid5(uuid.NAMESPACE_URL, str(source)))
    def stage(name, selected, full):
        directory = output / name
        directory.mkdir()
        plan = directory / "plan.json"
        atomic_json(plan, {"source": str(source), "photoID": identity, "fullResolution": full,
                           "currentAuto": True, "candidates": [candidate.payload() for candidate in selected]})
        return execute(args.xctestrun, plan, directory / "receipts.json", directory)
    proxy = stage("proxy", candidate_list, False)
    ranked = [row["candidateID"] for row in rank(proxy) if row["candidateID"] != "current_auto"][:3]
    selected = candidate_list if args.audit_all else [candidate for candidate in candidate_list if candidate.id in {"zero", *ranked}]
    full = stage("full", selected, True)
    if stat_key(source) != before or digest(source) != source_hash:
        raise RuntimeError("Source changed during measurement")
    attempts = []
    for candidate in candidate_list:
        attempts.append({"input_recipe": "untouched", "candidate": candidate.payload(),
                         "proxy": next((row for row in proxy if row["candidateID"] == candidate.id), None),
                         "full": next((row for row in full if row["candidateID"] == candidate.id), None),
                         "status": "measured_not_applied", "reason": "uncalibrated acceptance gates"})
    report = {"source_sha256": source_hash, "source_stat_unchanged": True,
              "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
              "working_diff_sha256": hashlib.sha256(subprocess.check_output(["git", "diff", "HEAD"])).hexdigest(),
              "arms": {arm: "measured" if arm in {"neutral", "current_auto", "lattice"} else "NOT_RUN" for arm in ARMS},
              "attempts": attempts, "current_auto": {"proxy": proxy[-1], "full": full[-1]},
              "decision": select([row for row in proxy if row["candidateID"] != "current_auto"],
                                 [row for row in full if row["candidateID"] != "current_auto"]),
              "agreement": agreement([row for row in proxy if row["candidateID"] != "current_auto"],
                                     [row for row in full if row["candidateID"] != "current_auto"]),
              "human_review": "UNMEASURED",
              "cross_device_harmonization": "UNMEASURED", "whole_set_coherence": "UNMEASURED",
              "os_cache": "uncontrolled", "application_cache": "new XCTest host per stage; candidate sequence warms RAW registry"}
    atomic_json(output / "report.json", report)
    print(json.dumps(report["decision"]))


if __name__ == "__main__":
    main()
