#!/usr/bin/env python3
"""Which parts of CI a change needs (.github/workflows/lumina.yml, job `changes`).

A pull request runs the readiness gate every time (design handoff + the probe's smoke) and the
rest only when its area changed. Anything that isn't a pull request (main, nightly, run by hand)
runs everything, and so does a change to CI itself.

    python3 Scripts/ci_changes.py                 # in CI: diffs the PR's merge commit against its base
    python3 Scripts/ci_changes.py FILE…           # locally: the flags these paths would set

Writes `name=true|false` lines to $GITHUB_OUTPUT when it is set, and prints them either way, plus
`xctest=…`: the -only-testing arguments for build + tests (see xctest_args).
"""
import fnmatch, glob, os, re, subprocess, sys

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


TESTS = "LuminaLogicTests"
# Types at any depth; functions and constants only at the top level (not every local `let`).
DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:(?:public|internal|private|fileprivate|final|open|nonisolated)\s+)*"
                  r"(?:struct|class|enum|actor|protocol)\s+(\w+)"
                  r"|^(?:(?:public|internal|private|fileprivate|nonisolated)\s+)*(?:func|let|var|typealias)\s+(\w+)", re.M)


def xctest_args(files, everything):
    """The test classes a change touches, as xcodebuild -only-testing arguments.

    A changed test file runs itself. A changed Swift file under Lumina/ runs every test class whose
    file names a type or top-level name it declares (and any class named after the file). The page
    files run the tests that read the bundled page, rules-v1.json the tests that read the rules.
    Anything else Xcode builds (the project, Config, resources, the test plan) runs the whole target,
    as does everything that isn't a pull request. With nothing selected, SetsPageBytesTests still
    runs: the build has to succeed and the bundle must hold the design.
    """
    if everything:
        return f"-only-testing:{TESTS}"
    tests = {os.path.basename(f)[:-6]: open(f, encoding="utf-8", errors="replace").read()
             for f in glob.glob(f"{TESTS}/*.swift")}
    refers = lambda words: {t for t, src in tests.items()
                            if any(re.search(rf"\b{re.escape(w)}\b", src) for w in words)}
    picked = set()
    for f in files:
        if not any(fnmatch.fnmatch(f, p) for p in AREAS["swift"]):
            continue
        name = os.path.basename(f)
        if f.startswith(f"{TESTS}/") and f.endswith(".swift"):
            picked.add(name[:-6])
        elif f.startswith("Lumina/Sets/Web/"):
            picked |= {t for t, src in tests.items() if re.search(r"Web/|plumbing|\.html|PAGE", src)}
        elif f == "Lumina/Sets/Look/rules-v1.json":
            picked |= refers(["rules-v1", "LookRules"])
        elif f.startswith("Lumina/") and f.endswith(".swift"):
            src = open(f, encoding="utf-8", errors="replace").read() if os.path.exists(f) else ""
            stem = name[:-6]
            words = {w for m in DECL.findall(src) for w in m if len(w) > 3} | {stem}
            picked |= refers(words) | {t for t in tests if t.startswith(stem)}
        else:
            return f"-only-testing:{TESTS}"
    picked = (picked & set(tests)) or {"SetsPageBytesTests"}
    return " ".join(f"-only-testing:{TESTS}/{t}" for t in sorted(picked))


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
    lines.append("xctest=" + xctest_args(files or [], files is None or hit(EVERYTHING)))
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
