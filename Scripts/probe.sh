#!/usr/bin/env bash
# Lumina probe suites — drive the page in WKWebView and try to break it.
#
#   bash Scripts/probe.sh screens                every v5 screen × 2 sizes, prototype and app, rendered once: the app twins must
#                                                equal the prototype byte for byte (CI: no committed reference needed)
#   bash Scripts/probe.sh scenarios NAME…        just these scenarios (Tests/probe/scenarios/NAME.json), e.g. fuzz-sample-2
#   bash Scripts/probe.sh reference [--record]   every v5 screen × 2 sizes (+ app twins) and state dumps, byte-compared to
#                                                Tests/probe/reference/manifest.json (--record rewrites it)
#   bash Scripts/probe.sh smoke                  the v5 page runs, its ?selftest passes, plumbing fits, and the app reads,
#                                                keeps, saves sidecars into the folder, reopens (app-smoke needs LUMINA_FIXTURE_ROOT);
#                                                the empty app survives a key storm
#   bash Scripts/probe.sh selftest               the design's own ?selftest (25 checks, key and large-view timing)
#   bash Scripts/probe.sh contract               plumbing.js still fits the page (run by sets_sync_design.sh)
#   bash Scripts/probe.sh fuzz                   seeded key/mouse storms on the sample shoot, and over a card image read natively
#                                                and pulled / re-inserted at random (fuzz-app-card needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh edge                   camera-data edge cases   (needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh ingest                 the same edge cases read by the app's native reader
#   bash Scripts/probe.sh card                   golden card + camera-clock parity, page vs native read (needs LUMINA_CARD_DIR)
#   bash Scripts/probe.sh stress                 a whole card: Cull scroll frame budget, fast row moves, a 3,000-input storm, memory;
#                                                the page's read, then the native read (needs LUMINA_CARD_DIR, only read)
#   bash Scripts/probe.sh app                    contract + the app on folders: read, sidecars, .lumina-bak, Lightroom's sidecars
#                                                merged in place, sessions across a relaunch, keepers renamed / deleted mid-cull,
#                                                the empty app (needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh fault                  disk images (LUMINA_LONG=1 LUMINA_DISK_IMAGES=1; they show in Finder for a moment): kill -9 mid-write + relaunch recovery,
#                                                disk full mid-copy and for a sidecar, a read-only card, a card pulled mid-read and
#                                                while its keepers wait on Save, .xmp and .XMP side by side on a case-sensitive disk
#   bash Scripts/probe.sh scroll                 scrolling Cull while a folder reads (no jump when it ends), then fast scrolling at
#                                                1440×900 and 2560×1440: frame pacing, blank tiles, thumbnail
#                                                upscale, memory. Folder: LUMINA_SCROLL_DIR, else LUMINA_CARD_DIR (only read), else
#                                                408 APFS clones of LUMINA_FIXTURE_ROOT/src, 20 s apart (built once)
#                                                (CI runs scroll-quick / scroll-quick-2560: tile 216, warm-ahead on and off)
#                                                then keys typed faster than the page takes them (keys-spam: grid and large view)
#   bash Scripts/probe.sh edit                   the Edit canvas (addendum §8): 2 s drags on exposure and shadows, look-event-to-
#                                                presented-frame latency (p95 ≤ LUMINA_EDIT_P95, default 16 ms), dropped frames,
#                                                rest render, bases resident, canvas vs export ΔE; native first, then with
#                                                nothing compiled (edit-cold), then the image fallback path (LUMINA_CANVAS=image).
#                                                Folder: LUMINA_EDIT_DIR, else as scroll
#   bash Scripts/probe.sh edit-cold              the Edit canvas as on the first launch after an update that changed a kernel: every
#                                                stage program compiled under a salted name (LUMINA_KERNEL_SALT, new per run), first
#                                                drags on stages the canvas has not rendered, gated like edit plus the first render
#                                                of each new set of stages ≤ 8 ms on the main thread. LUMINA_CANVAS_WARM=0 = no
#                                                warm-up (the "before" measure; the gate fails)
#   bash Scripts/probe.sh raw9                   RAW 9 (§8): decoder map, time to first tile / full region, export time + memory
#   bash Scripts/probe.sh video                  video budget metrics on LUMINA_VIDEO_DIR: first rows, flags for 50 clips, peak memory, proxy disk, decoders (M1 gates; FAILS until lumina.video exists)
#                                                per decoder version, the forced per-file fallback, tiles vs export ΔE per version
#   bash Scripts/probe.sh consistency            canvas vs export: ΔE between what the Edit canvas shows and what Export writes (full size,
#                                                pinned decoder), per stage of the look, on 12 distinct real ARWs of LUMINA_EDIT_DIR
#   bash Scripts/probe.sh readspeed              how fast a folder reads: Open → first rows, first thumbnail, first screen full,
#                                                100 / 500 / 1000 / 2000 photos, done; photos per second. Folder: LUMINA_READ_DIR, else as scroll
#   bash Scripts/probe.sh slowdisk               a disk whose first directory read takes 12 s (LUMINA_SLOW_DIR_MS): the app still answers
#                                                the page while the folder is listed. Folder: LUMINA_READ_DIR, else as scroll
#   bash Scripts/probe.sh all [--require-all]    everything v5 (LUMINA_LONG=1); --require-all turns a SKIP into a failure
#   bash Scripts/probe.sh sandbox MODE [ARGS…]   any mode above inside the App Sandbox, with Config/Lumina-Sets.entitlements as the
#                                                app ships them (e.g. sandbox smoke, sandbox contract, sandbox scenarios app-session).
#                                                One process per scenario; after each, what the sandbox refused the app (access
#                                                checks after every step, the bridge's own "access denied", any `Sandbox: … deny`
#                                                line and Network Process crash in the log for its pid) goes to <scenario>/
#                                                sandbox-denials.log, and a table prints PASS / FAIL / FAILED-BY-SANDBOX + denials.
#                                                How the probe gets its files in a sandbox: Tools/LuminaProbe/…/Sandbox.swift
#
# Every run ends (AGENTS.md, "Running tests without disturbing the Mac"). The suite runs under
# Scripts/test_guard.py: one screen-owning run at a time on this Mac (a second is refused, exit 75),
# a wall-clock limit per suite (LUMINA_PROBE_LIMIT=<seconds> changes it; exit 124 at the limit) and
# per scenario (180 s, or the scenario's own "deadline"; LUMINA_SCENARIO_LIMIT raises it), and on
# any exit its processes are stopped and its disk images detached. Long runs are asked for:
#   LUMINA_LONG=1          fuzz, fault, stress, consistency, all, and scenarios with a deadline over 300 s
#   LUMINA_DISK_IMAGES=1   scenarios that mount disk images (fault, fuzz-app-card, card-sandbox-*, app-xmp-both):
#                          they show in Finder for a moment; without it those scenarios SKIP
# bash Scripts/stop_tests.sh stops everything, at any time.
#
# Build fixtures once: LUMINA_CARD_DIR=/Volumes/…/DCIM/101MSDCF bash Tests/probe/forge_fixtures.sh
# Evidence goes to ~/LuminaEvidence/probe/<stamp> (not /tmp: it gets swept).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source Scripts/page_files.sh; export PAGE

suite="${1:-all}"; shift || true
sandbox=0
if [[ $suite == sandbox ]]; then sandbox=1; suite="${1:-smoke}"; shift || true; fi
record=0; extra=()
for a in "$@"; do [[ $a == --record ]] && record=1 || extra+=("$a"); done
S=Tests/probe/scenarios

PROBE="Tools/LuminaProbe/.build/release/lumina-probe"
OUT="${LUMINA_PROBE_OUT:-$HOME/LuminaEvidence/probe/$(date +%Y%m%d-%H%M%S)$([[ $sandbox == 1 ]] && echo -sandbox)}"
mkdir -p "$OUT"

# The suite's wall-clock limit in seconds: several times what it takes on this Mac, so a healthy
# run never meets it and a stuck one ends soon. `scenarios`: the sum of its scenarios' limits.
scenario_limit() { python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1])).get("deadline", 180)))' "$S/$1.json" 2>/dev/null || echo 180; }
long=0
case "$suite" in
  contract|selftest)                            limit=120 ;;
  smoke|edge|ingest|edit-cold|raw9|slowdisk)    limit=240 ;;
  screens|app|card|scroll|edit|readspeed)       limit=420 ;;
  reference)                                    limit=600 ;;
  fuzz|fault|consistency)                       limit=1200; long=1 ;;
  stress)                                       limit=1800; long=1 ;;
  all)                                          limit=3600; long=1 ;;
  scenarios) limit=60
             for n in ${extra[@]+"${extra[@]}"}; do
               [[ $n == --* ]] && continue
               l=$(scenario_limit "$n"); limit=$((limit + l)); [[ $l -gt 300 ]] && long=1
             done ;;
  sync)      echo "use: bash Scripts/sets_sync_design.sh <handoff.zip>"; exit 2 ;;
  *)         sed -n '2,69p' "$0"; exit 2 ;;
esac
[[ $sandbox == 1 ]] && limit=$((limit * 2))       # one process per scenario, then the log is read
limit="${LUMINA_PROBE_LIMIT:-$limit}"

if [[ -z ${LUMINA_PROBE_INNER:-} ]]; then
  if [[ $long == 1 && ${LUMINA_LONG:-} != 1 ]]; then
    asked="$([[ $sandbox == 1 ]] && echo 'sandbox ')$suite ${extra[*]-}"
    echo "probe.sh $asked is a long run (limit $((limit / 60)) min) and is only started on purpose:" >&2
    echo "  LUMINA_LONG=1 bash Scripts/probe.sh $asked" >&2
    exit 2
  fi
  if [[ $suite == fault && ${LUMINA_DISK_IMAGES:-} != 1 ]]; then
    echo "probe.sh fault mounts and pulls disk images (they show in Finder for a moment): add LUMINA_DISK_IMAGES=1" >&2
    exit 2
  fi
  GUARD=(python3 Scripts/test_guard.py run)
  "${GUARD[@]}" --quiet --name "probe build $ROOT" --limit 900 -- swift build -c release --package-path Tools/LuminaProbe >/dev/null
  rc=$?; [[ $rc == 75 ]] && exit 75          # refused: tests are switched off, or this build is already running
  [[ $rc == 0 ]] || { echo "probe build failed" >&2; exit 2; }
  export LUMINA_PROBE_OUT="$OUT" LUMINA_PROBE_INNER=1 LUMINA_PROBE_LIMIT="$limit"
  [[ $sandbox == 1 ]] && set -- sandbox "$suite" "$@" || set -- "$suite" "$@"
  exec "${GUARD[@]}" --name probe --limit "$limit" --screen --sweep-under "$OUT" -- bash "$0" "$@"
fi
# What is left of the limit: the probe ends itself (and detaches its images) just before the guard would.
left() { local s=$((limit - SECONDS - 10)); echo $((s > 5 ? s : 5)); }
export LUMINA_FIXTURE_ROOT="${LUMINA_FIXTURE_ROOT:-}"
# The probe is a SwiftPM tool with no bundle: the look rules come from the checkout (LookRules.bundled reads LUMINA_RULES).
export LUMINA_RULES="${LUMINA_RULES:-$ROOT/Lumina/Sets/Look/rules-v1.json}"
status=0

# Sandbox mode: the same binary in a minimal app bundle (a sandboxed process needs a bundle id; its
# own, so its container is not the app's), signed ad hoc with the app's entitlements, unchanged.
# The unsandboxed probe launches it and hands it folder grants (Sandbox.swift says which and why).
# LUMINA_SANDBOX_ENTITLEMENTS=<file> measures another set (e.g. without network.client); never for a verdict on what ships.
ENT="${LUMINA_SANDBOX_ENTITLEMENTS:-Config/Lumina-Sets.entitlements}"
if [[ $sandbox == 1 ]]; then
  SBX=Tools/LuminaProbe/.build/sandbox/LuminaProbe.app
  rm -rf "$SBX"; mkdir -p "$SBX/Contents/MacOS"
  cp "$PROBE" "$SBX/Contents/MacOS/lumina-probe"
  plutil -create xml1 "$SBX/Contents/Info.plist"
  for kv in CFBundleIdentifier=com.lumina.probe.sandboxed CFBundleExecutable=lumina-probe CFBundleName=LuminaProbe CFBundlePackageType=APPL; do
    plutil -insert "${kv%%=*}" -string "${kv#*=}" "$SBX/Contents/Info.plist"
  done
  plutil -insert LSUIElement -bool YES "$SBX/Contents/Info.plist"
  codesign --force --sign - --entitlements "$ENT" "$SBX" 2>/dev/null || { echo "could not sign $SBX" >&2; exit 2; }
  codesign -d --entitlements - --xml "$SBX" 2>/dev/null | grep -q com.apple.security.app-sandbox || { echo "$SBX is not sandboxed" >&2; exit 2; }
  echo "sandboxed probe: $SBX, entitlements $ENT"
fi

# One scenario per sandboxed process, then what the sandbox refused it (sandbox_report).
run_sandboxed() {
  local o=$1 f name rc; shift
  mkdir -p "$o"
  for f in "$@"; do
    [[ $f == *.json ]] || continue
    name="$(basename "$f" .json)"
    "$PROBE" sandbox-launch "$ROOT/$SBX/Contents/MacOS/lumina-probe" --info "$o/.launch-$name.json" -- run "$f" --out "$o" --deadline "$(left)" ${extra[@]+"${extra[@]}"}
    rc=$?
    sleep 1        # let logd take the last lines
    sandbox_report "$o" "$name" "$rc" || status=1
  done
}

# A scenario's verdict in the sandbox. Denials come from three places (Sandbox.swift explains why
# the first is needed): the probe's access checks after each step and the bridge's own reports
# (<scenario>/sandbox.json), and the unified log for the probe's pid: kernel `Sandbox: … deny`
# lines and WebKit's `Network Process … crash`. Any denial = FAILED-BY-SANDBOX, whatever the steps
# said. The web content process is sandboxed in every build; its log lines are kept, not counted.
# Neither are the kernel lines that are the harness's or the system's own (HARNESS below): macOS 15
# logs them (the CI runner), macOS 26.5 does not.
sandbox_report() {
  python3 - "$@" <<'EOF'
import json, os, subprocess, sys, time
out, name, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = os.path.join(out, name); os.makedirs(d, exist_ok=True)
launch_tmp = os.path.join(out, f".launch-{name}.json")
launch = json.load(open(launch_tmp)) if os.path.exists(launch_tmp) else {}
if launch: os.replace(launch_tmp, os.path.join(d, "sandbox-launch.json"))
load = lambda f: json.load(open(os.path.join(d, f))) if os.path.exists(os.path.join(d, f)) else {}
report, sb = load("report.json"), load("sandbox.json")
pid, web = launch.get("pid", 0), sb.get("webPid", 0)
fmt = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
log_lines, web_lines = [], []
# What the sandbox leaves in the log for this pid (measured on macOS 26.5): kernel `Sandbox: lumina-probe(pid)
# deny(1) …` lines (none for App Sandbox file denials there, but other operations may log), a framework
# saying "Sandbox is preventing …", and WebKit's helpers dying or failing to start ("Application does not
# have permission to communicate with network resources", `reason=Crash`, `Network Process … crash`).
# Lines the live web content process forwards through the probe's log ("WebContent[<its pid>] …") are its
# own sandbox at work, present in every build: kept apart, not counted.
WEBKIT = ("reason=Crash", "failed to launch", "does not have permission to communicate")
# Kernel denials of the probe's pid that are not the app's access to files, the network or a service
# (measured on the macOS 15 runner, run 36969947924; every other operation still counts):
#   process-info-rusage others [WebContent(<web pid>)]   the probe's own Sampler reading the web process's memory
#                                                         (Sampler.swift, proc_pid_rusage): the harness, not the app
#   iokit-open-user-client AppleNVMeEANUC, hid-control    30 to 40 ms after exec, before any step, grant or web view:
#                                                         system frameworks starting up, nothing Lumina asks for
#   file-issue-extension target:/ …app-sandbox.read       (run 36972481913, app-plumbing-contract only, about 150 ms
#                                                         after exec, before the page loads; all 14 steps pass.) The
#                                                         process asked to HAND OUT read access to `/`, which no
#                                                         sandboxed app may; it was not refused an access of its own.
#                                                         Who asks is NOT known yet (nothing in Lumina/ or the probe
#                                                         issues extensions in-process): docs/release/TASKS.md, P0 4.
#                                                         Only this exact line: any other target or class still counts.
def harness(l):
    if f"({pid}) deny(1) " not in l: return False
    op = l.split(f"({pid}) deny(1) ", 1)[1].strip()
    return (op == f"process-info-rusage others [com.apple.WebKit.WebContent({web})]"
            or op in ("iokit-open-user-client AppleNVMeEANUC", "hid-control",
                      "file-issue-extension target:/ extension-class:com.apple.app-sandbox.read"))
harness_lines = []
if pid:
    pred = (f'(process == "kernel" AND eventMessage CONTAINS "Sandbox: " AND eventMessage CONTAINS " deny" AND '
            f'(eventMessage CONTAINS "({pid})" OR eventMessage CONTAINS "({web})")) OR '
            f'(processID == {pid} AND (eventMessage CONTAINS "Sandbox is preventing" OR eventMessage CONTAINS "reason=Crash" OR '
            f'eventMessage CONTAINS "failed to launch" OR eventMessage CONTAINS "does not have permission to communicate" OR '
            f'(eventMessage CONTAINS "Network Process" AND eventMessage CONTAINS "crash")))')
    r = subprocess.run(["/usr/bin/log", "show", "--style", "compact", "--info", "--start", fmt(launch["start"] - 1),
                        "--end", fmt(launch.get("end", time.time()) + 2), "--predicate", pred], capture_output=True, text=True)
    for line in r.stdout.splitlines()[1:]:
        if not line[:4].isdigit(): continue                # continuation of a multi-line entry
        theirs = web and (f"WebContent[{web}]" in line or (f"({web})" in line and f"({pid})" not in line))
        (web_lines if theirs else harness_lines if harness(line) else log_lines).append(line)
checks = sb.get("denials", [])
n = len(checks) + len(log_lines)
crashes = sum(any(w in l for w in WEBKIT) or ("Network Process" in l and "crash" in l) for l in log_lines)
with open(os.path.join(d, "sandbox-denials.log"), "w") as f:
    f.write(f"# {name} · probe pid {pid} · web content pid {web} · container {sb.get('container', '?')}\n")
    f.write(f"# grants the launcher issued: {len(launch.get('grants', []))} (sandbox-launch.json)\n\n")
    f.write(f"## refused to the app ({len(checks)}): access checks after each step + the bridge's own reports\n")
    for c in checks: f.write(f"#{c['step']} {c['op']}: {c['operation']} {c['path']} ({c['role']}) {c['detail']}\n")
    f.write(f"\n## unified log, probe pid ({len(log_lines)}, of which {crashes} WebKit helper crashes or failed launches)\n")
    f.writelines(l + "\n" for l in log_lines)
    f.write(f"\n## unified log, web content pid (sandboxed in every build: kept, not counted) ({len(web_lines)})\n")
    f.writelines(l + "\n" for l in web_lines)
    f.write(f"\n## unified log, probe pid, the harness's sampler, system start-up, a refused hand-out of `/` (kept, not counted) ({len(harness_lines)})\n")
    f.writelines(l + "\n" for l in harness_lines)
if report.get("skipped"): verdict = "SKIP"
elif n: verdict = "FAILED-BY-SANDBOX"
elif rc == 0 and report.get("pass"): verdict = "PASS"
else: verdict = "FAIL"
if not report and verdict != "FAILED-BY-SANDBOX": verdict = f"FAIL (no report, exit {rc})"
steps = report.get("steps", [])
row = [name, verdict, str(n), str(len(checks)), str(len(log_lines)), str(crashes),
       f"{sum(s['ok'] for s in steps)}/{len(steps)}", str(len(report.get("failures", [])))]
with open(os.path.join(out, "sandbox-results.tsv"), "a") as f: f.write("\t".join(row) + "\n")
print(f"sandbox  {name}: {verdict} · {n} denials ({len(checks)} access, {len(log_lines)} log, {crashes} WebKit helper crashes) → {name}/sandbox-denials.log")
for c in checks: print(f"   deny #{c['step']} {c['op']}: {c['operation']} {c['path']} ({c['role']})")
for l in log_lines[:5]: print(f"   log  {l[:220]}")
sys.exit(0 if verdict in ("PASS", "SKIP") else 1)
EOF
}

sandbox_table() {
  [[ -f $OUT/sandbox-results.tsv ]] || return 0
  echo
  echo "sandboxed run ($ENT):"
  printf '  %-26s %-18s %7s %7s %5s %8s %7s %9s\n' scenario verdict denials access log webkit steps failures
  while IFS=$'\t' read -r a b c d e f g h; do printf '  %-26s %-18s %7s %7s %5s %8s %7s %9s\n' "$a" "$b" "$c" "$d" "$e" "$f" "$g" "$h"; done < "$OUT/sandbox-results.tsv"
}
run() { if [[ $sandbox == 1 ]]; then run_sandboxed "$OUT" "$@"; else "$PROBE" run "$@" --out "$OUT" --deadline "$(left)" ${extra[@]+"${extra[@]}"} || status=1; fi; }
run_out() {
  local o=$1; shift; mkdir -p "$o"
  if [[ $sandbox == 1 ]]; then run_sandboxed "$o" "$@"; else "$PROBE" run "$@" --out "$o" --deadline "$(left)" ${extra[@]+"${extra[@]}"} || status=1; fi
}

reference() {
  run "$S/screens-1920.json" "$S/screens-1440.json" "$S/smoke.json" "$S/keys-open-return.json" \
      "$S/screens-1920-app.json" "$S/screens-1440-app.json"
  local manifest=Tests/probe/reference/manifest.json now="$OUT/manifest.json"
  python3 - "$OUT" "$now" <<'EOF'
import hashlib, json, os, platform, subprocess, sys
out, dest = sys.argv[1], sys.argv[2]
files = {}
for suite in ("screens-1920", "screens-1440"):
    d = os.path.join(out, suite)
    for f in sorted(os.listdir(d)):
        if f.endswith(".png") or f.endswith(".state.json"):
            files[f"{suite}/{f}"] = hashlib.sha256(open(os.path.join(d, f), "rb").read()).hexdigest()
page = hashlib.sha256(open("design/handoff/lumina-cull/" + os.environ["PAGE"], "rb").read()).hexdigest()
osv = subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip()
json.dump({"page_sha256": page, "macos": osv, "arch": platform.machine(), "files": files}, open(dest, "w"), indent=1, sort_keys=True)
EOF
  if [[ $record == 1 ]]; then
    mkdir -p "$(dirname "$manifest")"; cp "$now" "$manifest"; echo "reference recorded → $manifest"
  elif [[ -f $manifest ]]; then
    python3 - "$manifest" "$now" "$OUT" "$PROBE" <<'EOF' || status=1
import json, subprocess, sys
ref, now, out, probe = (json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4])
if ref["page_sha256"] != now["page_sha256"]: print("NOTE  page changed since the reference was recorded")
if ref["macos"] != now["macos"]: print(f"NOTE  reference recorded on macOS {ref['macos']}, now {now['macos']} (font rendering may differ)")
bad = [k for k in ref["files"] if ref["files"][k] != now["files"].get(k)]
missing = [k for k in ref["files"] if k not in now["files"]]
for k in bad: print(f"DIFF  {k}")
print(f"reference: {len(ref['files']) - len(bad)} / {len(ref['files'])} identical" + (f", {len(missing)} missing" if missing else ""))
# The shipped app (page + plumbing.js) must render exactly what the design renders.
import hashlib, os
app_bad, app_n = [], 0
for size in ("1440", "1920"):
    d = os.path.join(out, f"screens-{size}-app")
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.endswith(".png") or f.endswith(".state.json"):
            app_n += 1
            if ref["files"].get(f"screens-{size}/{f}") != hashlib.sha256(open(os.path.join(d, f), "rb").read()).hexdigest():
                app_bad.append(f"screens-{size}-app/{f}")
for k in app_bad: print(f"APP≠DESIGN  {k}")
print(f"app vs design: {app_n - len(app_bad)} / {app_n} identical")
sys.exit(1 if bad or app_bad else 0)
EOF
  else
    echo "no reference manifest yet — run with --record"
  fi
}

# The app twins against the prototype screens from the same run (no manifest): one render of each.
screens() {
  run "$S/screens-1920.json" "$S/screens-1440.json" "$S/screens-1920-app.json" "$S/screens-1440-app.json"
  python3 - "$OUT" <<'EOF' || status=1
import hashlib, os, sys
out = sys.argv[1]
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
bad, n = [], 0
for size in ("1440", "1920"):
    app, proto = os.path.join(out, f"screens-{size}-app"), os.path.join(out, f"screens-{size}")
    for f in sorted(os.listdir(app)) if os.path.isdir(app) else []:
        if not (f.endswith(".png") or f.endswith(".state.json")): continue
        n += 1
        p = os.path.join(proto, f)
        if not os.path.exists(p) or sha(p) != sha(os.path.join(app, f)): bad.append(f"screens-{size}-app/{f}")
for b in bad: print(f"APP≠DESIGN  {b}")
print(f"app vs design: {n - len(bad)} / {n} identical")
sys.exit(1 if bad or n == 0 else 0)
EOF
}

# Suites by what they need: APP opens copies of the fixture folders; FAULT mounts small disk images.
APP=(app-plumbing-contract app-smoke app-session app-xmp-lightroom app-rename-mid-cull app-empty-start)
FAULT=(fault-kill-mid-handoff fault-native-dest fault-disk-full fault-readonly-card fault-card-pull-read fault-card-pull-cull app-xmp-both)
paths() { for n in "$@"; do echo "$S/$n.json"; done; }      # scenario paths have no spaces

# A folder big enough to scroll. The fixtures hold 12 real frames: clone them (APFS, no extra space)
# 34 times and restamp every clone 20 s apart, so each is its own tile rather than one big stack.
scrolldir() {
  [[ -n ${LUMINA_SCROLL_DIR:-} ]] && return
  if [[ -n ${LUMINA_CARD_DIR:-} ]]; then export LUMINA_SCROLL_DIR="$LUMINA_CARD_DIR"; return; fi
  [[ -n $LUMINA_FIXTURE_ROOT && -d $LUMINA_FIXTURE_ROOT/src ]] || return 0      # unset: the scenarios SKIP
  local d="$LUMINA_FIXTURE_ROOT/scroll-408"
  if [[ ! -f $d/.done ]]; then
    local exif; exif="$(command -v exiftool || ls /opt/homebrew/bin/exiftool /usr/local/bin/exiftool 2>/dev/null | head -1)"
    [[ -x $exif ]] || { echo "scroll: exiftool not found (needed once to build $d)" >&2; return 0; }
    rm -rf "$d"; mkdir -p "$d"
    local src=("$LUMINA_FIXTURE_ROOT"/src/*.[aA][rR][wW]) args="$d/.args" i=0 t0 t
    t0=$(date -j -f "%Y-%m-%d %H:%M:%S" "2026-09-01 09:00:00" +%s)
    : > "$args"
    for rep in $(seq 1 34); do for f in "${src[@]}"; do
      local n; n=$(printf "DSC%05d.ARW" $((10001 + i)))
      cp -c "$f" "$d/$n" 2>/dev/null || cp "$f" "$d/$n"
      t=$(date -r $((t0 + i * 20)) "+%Y:%m:%d %H:%M:%S")
      printf -- "-overwrite_original\n-DateTimeOriginal=%s\n-CreateDate=%s\n%s\n-execute\n" "$t" "$t" "$d/$n" >> "$args"
      i=$((i + 1))
    done; done
    "$exif" -q -q -@ "$args" && rm -f "$args" && touch "$d/.done"
  fi
  export LUMINA_SCROLL_DIR="$d"
}

# A folder of real ARWs for the Edit canvas and RAW 9 suites: LUMINA_EDIT_DIR, else the scroll folder.
editdir() {
  [[ -n ${LUMINA_EDIT_DIR:-} ]] && return
  scrolldir
  [[ -n ${LUMINA_SCROLL_DIR:-} ]] && export LUMINA_EDIT_DIR="$LUMINA_SCROLL_DIR"
  return 0
}

case "$suite" in
  reference) reference ;;
  screens)   screens ;;
  scenarios) scrolldir; editdir; files=(); for n in ${extra[@]+"${extra[@]}"}; do files+=("$S/$n.json"); done; extra=(); run "${files[@]}" ;;
  sync)      echo "use: bash Scripts/sets_sync_design.sh <handoff.zip>"; exit 2 ;;
  smoke)     run "$S/smoke.json" "$S/keys-open-return.json" "$S/selftest.json" "$S/app-plumbing-contract.json" "$S/app-offline.json" "$S/app-smoke.json" "$S/app-empty-start.json" ;;
  selftest)  run "$S/selftest.json" ;;
  fuzz)      run "$S"/fuzz-sample-*.json "$S/fuzz-app-card.json" ;;
  edge)      run "$S"/edge-*.json ;;
  ingest)    LUMINA_PROBE_MODE=app run "$S"/edge-*.json ;;
  card)      run "$S/golden-card.json" "$S/card-clock.json" ;;
  stress)    run "$S/card-stress.json"
             echo "— native read (LUMINA_PROBE_MODE=app) —"
             LUMINA_PROBE_MODE=app run_out "$OUT/app" "$S/card-stress.json" ;;
  app)       run $(paths "${APP[@]}") ;;
  contract)  run "$S/app-plumbing-contract.json" ;;
  fault)     run $(paths "${FAULT[@]}") ;;
  scroll)    scrolldir; run "$S/scroll-read.json" "$S/scroll-fast.json" "$S/scroll-fast-2560.json" "$S/keys-spam.json" ;;
  edit)      editdir; run "$S/edit-first-entry.json" "$S/edit-canvas.json"
             echo "— nothing compiled (LUMINA_KERNEL_SALT): first drags on stages the canvas has not rendered —"
             LUMINA_KERNEL_SALT="${LUMINA_KERNEL_SALT:-p$(date +%s)}" run_out "$OUT/cold" "$S/edit-cold.json"
             echo "— image fallback path (LUMINA_CANVAS=image) —"
             LUMINA_CANVAS=image run_out "$OUT/image-path" "$S/edit-canvas.json" ;;
  edit-cold) editdir; LUMINA_KERNEL_SALT="${LUMINA_KERNEL_SALT:-p$(date +%s)}" run "$S/edit-cold.json" ;;
  raw9)      editdir; run "$S/raw9.json" ;;
  video)     [[ -n ${LUMINA_VIDEO_DIR:-} ]] || { echo "video: set LUMINA_VIDEO_DIR (a card's PRIVATE/M4ROOT/CLIP, or MP4s with their M01.XML sidecars); scenario SKIPs without it"; }
             run "$S/video-budget.json" ;;
  consistency) editdir; run "$S/edit-consistency.json" ;;
  readspeed) [[ -n ${LUMINA_READ_DIR:-} ]] || { scrolldir; export LUMINA_READ_DIR="${LUMINA_SCROLL_DIR:-}"; }
             run "$S/read-speed.json" ;;
  slowdisk)  [[ -n ${LUMINA_READ_DIR:-} ]] || { scrolldir; export LUMINA_READ_DIR="${LUMINA_SCROLL_DIR:-}"; }
             LUMINA_SLOW_DIR_MS="${LUMINA_SLOW_DIR_MS:-12000}" run "$S/open-slow-disk.json" ;;
  all)       reference; run "$S/selftest.json" "$S"/fuzz-sample-*.json "$S/fuzz-app-card.json" "$S"/edge-*.json $(paths "${APP[@]}") $(paths "${FAULT[@]}")
             LUMINA_PROBE_MODE=app run "$S"/edge-*.json ;;
  *)         sed -n '2,69p' "$0"; exit 2 ;;
esac
sandbox_table
echo "evidence: $OUT"
exit $status
