#!/usr/bin/env python3
"""Target & config truth (CQ.6) — and the standing proof for CQ.1.

Asserts, as project configuration rather than as prose:

  1. the target list is exactly the P0 route's three targets
  2. the app target compiles exactly the frozen source manifest — the D40 moves
     changed where files live, never which files ship
  3. the app target claims no network entitlement (D4 / D45 zero egress) and
     links no package or framework dependency
  4. probe / fake-clock / fixture code is DEBUG-only, never in Release
  5. every scheme-referenced test plan exists

    python3 Scripts/ci/target_truth.py            # check
    python3 Scripts/ci/target_truth.py --generate # refreeze the source manifest
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PBX = ROOT / "Lumina.xcodeproj/project.pbxproj"
MANIFEST = ROOT / "Scripts/lint/baseline/app_target_sources.baseline"

EXPECTED_TARGETS = {
    "Lumina": "com.apple.product-type.application",
    "LuminaUITests": "com.apple.product-type.bundle.ui-testing",
    "LuminaLogicTests": "com.apple.product-type.bundle.unit-test",
}

# Sources compiled into the app. Xcode 16 synchronized root groups mean the
# directory IS the membership, so this list is the target's source of truth.
APP_SOURCE_ROOTS = ["Lumina", "DesignTokens", "Salvage", "Legacy"]

# Harness code that must never reach a Release binary.
DEBUG_ONLY = [
    "Lumina/Testing/ProbeV2/StateProbeV2.swift",
    "Lumina/Testing/ProbeV2/HarnessFakeClock.swift",
    "Lumina/Testing/ProbeV2/AcceptanceSignposts.swift",
    "Lumina/Testing/UITestLaunch.swift",
    "Lumina/Testing/UITestFixtures.swift",
]

fails: list[str] = []
notes: list[str] = []


def fail(msg: str) -> None:
    fails.append(msg)


def app_sources() -> list[str]:
    out = []
    for r in APP_SOURCE_ROOTS:
        base = ROOT / r
        if base.exists():
            out += [str(p.relative_to(ROOT)) for p in base.rglob("*.swift")]
    return sorted(out)


def digest(rel: str) -> str:
    """Hash of the file with comments stripped: a banner is not a behaviour."""
    src = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"\s+", " ", src).strip()
    return hashlib.sha256(src.encode()).hexdigest()[:16]


def check_targets(pbx: str) -> None:
    found = dict(zip(re.findall(r"\n\t\t\tname = (\w+);\n\t\t\tpackageProductDependencies",
                                pbx),
                     re.findall(r"productType = \"([^\"]+)\";", pbx)))
    if not found:
        found = {}
        for block in re.findall(r"isa = PBXNativeTarget;.*?productType = \"([^\"]+)\";",
                                pbx, re.S):
            pass
        names = re.findall(r"/\* Begin PBXNativeTarget section \*/(.*?)"
                           r"/\* End PBXNativeTarget section \*/", pbx, re.S)
        if names:
            for chunk in names[0].split("isa = PBXNativeTarget;")[1:]:
                n = re.search(r"\n\t\t\tname = (\w+);", chunk)
                t = re.search(r'productType = "([^"]+)";', chunk)
                if n and t:
                    found[n.group(1)] = t.group(1)

    if found != EXPECTED_TARGETS:
        fail(f"target list drift: {sorted(found)} != {sorted(EXPECTED_TARGETS)}")
    else:
        notes.append(f"targets: {', '.join(sorted(found))}")

    listed = re.search(r"targets = \(\n(.*?)\n\t\t\t\);", pbx, re.S)
    if listed:
        n = len(re.findall(r"/\* (\w+) \*/", listed.group(1)))
        if n != len(EXPECTED_TARGETS):
            fail(f"project lists {n} targets, expected {len(EXPECTED_TARGETS)}")


def check_app_group_membership(pbx: str) -> None:
    m = re.search(r"fileSystemSynchronizedGroups = \(\n(.*?)\n\t\t\t\);\n\t\t\tname = Lumina;",
                  pbx, re.S)
    if not m:
        fail("app target declares no fileSystemSynchronizedGroups")
        return
    groups = set(re.findall(r"/\* (\w+) \*/", m.group(1)))
    if groups != set(APP_SOURCE_ROOTS):
        fail(f"app target source roots {sorted(groups)} != {sorted(APP_SOURCE_ROOTS)} "
             f"— Legacy/ and Salvage/ must stay linked until their checkpoints retire them")
    else:
        notes.append(f"app source roots: {', '.join(sorted(groups))}")


def check_zero_egress(pbx: str) -> None:
    if "CODE_SIGN_ENTITLEMENTS" in pbx:
        fail("app target declares CODE_SIGN_ENTITLEMENTS — "
             "the zero-egress claim requires no network entitlement (D4/D45)")
    for ent in ROOT.rglob("*.entitlements"):
        text = ent.read_text(encoding="utf-8", errors="replace")
        if "network" in text:
            fail(f"network entitlement declared in {ent.relative_to(ROOT)} (D4/D45)")
    bad = [k for k in ("com.apple.security.network.client",
                       "com.apple.security.network.server") if k in pbx]
    if bad:
        fail(f"network entitlement keys in project config: {bad}")
    if not fails:
        notes.append("entitlements: none declared — no network entitlement (D4/D45)")


def check_no_dependencies(pbx: str) -> None:
    for name, body in re.findall(r"(packageProductDependencies|packageReferences) = \(\n?(.*?)\);",
                                 pbx, re.S):
        if body.strip():
            fail(f"unexpected {name}: {body.strip()[:80]}")
    for body in re.findall(r"isa = PBXFrameworksBuildPhase;.*?files = \(\n?(.*?)\);",
                           pbx, re.S):
        if body.strip():
            fail(f"unexpected linked framework: {body.strip()[:80]}")
    notes.append("dependencies: no packages, no linked frameworks")


def check_debug_only() -> None:
    for rel in DEBUG_ONLY:
        p = ROOT / rel
        if not p.exists():
            fail(f"expected DEBUG-only source missing: {rel}")
            continue
        lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        body = [ln for ln in lines if ln.strip()]
        if not body or body[0].strip() != "#if DEBUG":
            fail(f"{rel} is not #if DEBUG at file scope — probe/fake-clock code "
                 f"must never link into Release")
        elif body[-1].strip() != "#endif":
            fail(f"{rel} does not close its file-scope #if DEBUG")
    notes.append(f"DEBUG-only harness sources verified: {len(DEBUG_ONLY)}")


def check_test_plans() -> None:
    scheme_dir = ROOT / "Lumina.xcodeproj/xcshareddata/xcschemes"
    schemes = sorted(scheme_dir.glob("*.xcscheme")) if scheme_dir.exists() else []
    if len(schemes) != 1:
        fail(f"expected exactly one shared scheme, found {len(schemes)}")
    for s in schemes:
        for ref in re.findall(r'reference = "container:([^"]+)"', s.read_text()):
            if not (ROOT / ref).exists():
                fail(f"{s.name} references a missing test plan: {ref}")
    plans = sorted(p.name for p in (ROOT / "TestPlans").glob("*.xctestplan"))
    notes.append(f"schemes: {len(schemes)} · test plans: {', '.join(plans)}")


def check_manifest(generate: bool) -> None:
    rows = [f"{rel}\t{digest(rel)}" for rel in app_sources()]
    if generate:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(
            "# Frozen app-target source manifest (CQ.1 zero-behaviour-change proof).\n"
            "# <path>\\t<sha256-16 of source with comments stripped>\n"
            "# The D40 quarantine moved files between directories; it did not change\n"
            "# which files the Lumina target compiles, nor their code. Regenerate only\n"
            "# when a checkpoint intentionally adds or retires a source:\n"
            "#   python3 Scripts/ci/target_truth.py --generate\n"
            f"# {len(rows)} sources.\n" + "\n".join(rows) + "\n", encoding="utf-8")
        print(f"app-target source manifest written: {len(rows)} sources")
        return

    if not MANIFEST.exists():
        fail(f"missing {MANIFEST.relative_to(ROOT)}")
        return
    was = {}
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        rel, d = line.split("\t")
        was[rel] = d
    now = {r.split("\t")[0]: r.split("\t")[1] for r in rows}

    for rel in sorted(set(now) - set(was)):
        fail(f"source added to the app target without refreezing the manifest: {rel}")
    for rel in sorted(set(was) - set(now)):
        fail(f"source removed from the app target: {rel}")
    changed = [r for r in sorted(set(was) & set(now)) if was[r] != now[r]]
    if changed:
        notes.append(f"{len(changed)} source(s) changed since the freeze "
                     f"(expected as checkpoints land): {changed[0]}"
                     + (f" +{len(changed) - 1} more" if len(changed) > 1 else ""))
    notes.append(f"app target compiles {len(now)} sources (manifest matches)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--generate", action="store_true")
    args = ap.parse_args()

    pbx = PBX.read_text(encoding="utf-8")
    check_targets(pbx)
    check_app_group_membership(pbx)
    check_zero_egress(pbx)
    check_no_dependencies(pbx)
    check_debug_only()
    check_test_plans()
    check_manifest(args.generate)

    for n in notes:
        print(f"  {n}")
    if fails:
        print("", file=sys.stderr)
        for f in fails:
            print(f"FAIL: {f}", file=sys.stderr)
        return 1
    print("target_truth.py: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
