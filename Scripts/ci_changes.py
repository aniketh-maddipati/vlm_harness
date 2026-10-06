#!/usr/bin/env python3
"""Which parts of CI a change needs (.github/workflows/lumina.yml, job `changes`).

A pull request runs the readiness gate every time (design handoff + the probe's smoke) and the
rest only when its area changed. Anything that isn't a pull request (main, nightly, run by hand)
runs everything, and so does a change to CI itself.

    python3 Scripts/ci_changes.py                 # in CI: diffs the PR's merge commit against its base
    python3 Scripts/ci_changes.py FILE…           # locally: the flags these paths would set

Writes `name=true|false` lines to $GITHUB_OUTPUT when it is set, and prints them either way.
"""
import fnmatch, os, subprocess, sys

# fnmatch's `*` crosses `/`, so `Lumina/*` is the whole tree under Lumina/.
AREAS = {
    # The page and its plumbing: the WebKitGTK + Chromium job, and the probe's screens.
    "web": ["design/*", "Lumina/Sets/Web/*", "Tests/web/*", "Tests/core/*", "Scripts/page_files.sh"],
    # Anything Xcode builds or tests: the Debug build + LuminaLogicTests.
    "swift": ["Lumina/*", "Lumina.xcodeproj/*", "LuminaLogicTests/*", "TestPlans/*", "Config/*"],
    # The look pipeline and lumina-render (they share Lumina/Sets/Look through symlinks).
    "look": ["Lumina/Sets/Look/*", "Tools/parity/*"],
    # What the Release archive and the strict preflight check: signing, entitlements, settings.
    "release": ["Config/*", "Lumina.xcodeproj/*", "Scripts/release*", "Scripts/write_build_manifest.sh",
                "*.entitlements", "*Info.plist", "*.xcconfig", "Lumina/Resources/*", "docs/release/TASKS.md"],
    # The probe's screens: the page, plumbing, or the probe itself.
    "screens": ["design/*", "Lumina/Sets/Web/*", "Tools/LuminaProbe/*", "Tests/probe/*", "Scripts/probe.sh",
                "Scripts/page_files.sh"],
    # The App Sandbox run: native code, entitlements, plumbing, the probe's sandbox launcher.
    "sandbox": ["Config/*", "*.entitlements", "Lumina/LuminaApp.swift", "Lumina/Sets/Sets*.swift", "Lumina/Sets/Core/*",
                "Lumina/Sets/Web/plumbing.js", "Tools/LuminaProbe/*", "Scripts/probe.sh", "Scripts/test_guard.py"],
}
EVERYTHING = [".github/*", "Scripts/ci_changes.py"]


def changed_files():
    if len(sys.argv) > 1:
        return sys.argv[1:]
    if os.environ.get("GITHUB_EVENT_NAME") != "pull_request":
        return None
    # actions/checkout puts a pull request on its merge commit; with fetch-depth 2 the first parent
    # is the base branch's tip, so this is exactly what merging would change.
    r = subprocess.run(["git", "diff", "--name-only", "HEAD^1", "HEAD"], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"git diff failed, running everything: {r.stderr.strip()}", file=sys.stderr)
        return [".github/ (diff unavailable)"]
    return [l for l in r.stdout.splitlines() if l]


def main():
    files = changed_files()
    hit = lambda pats: any(fnmatch.fnmatch(f, p) for f in files for p in pats)
    if files is None or hit(EVERYTHING):
        why = "not a pull request" if files is None else "CI itself changed"
        flags = {k: True for k in AREAS}
    else:
        why = f"{len(files)} files changed"
        flags = {k: hit(p) for k, p in AREAS.items()}
    lines = [f"{k}={'true' if v else 'false'}" for k, v in flags.items()]
    print(f"# {why}")
    for f in (files or [])[:50]:
        print(f"#   {f}")
    print("\n".join(lines))
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as fh:
            fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
