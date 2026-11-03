#!/usr/bin/env bash
# What .github/workflows/lumina.yml would run for this branch, run here, then one PASS / FAIL line.
#
#   bash Scripts/ci_local.sh                 # the diff against origin/main (commits + uncommitted + untracked)
#   bash Scripts/ci_local.sh --dry-run       # print the areas and the steps, run nothing
#   bash Scripts/ci_local.sh --all           # every area, as a push to main would (still no long runs)
#   bash Scripts/ci_local.sh --probe         # also the screen-owning steps: probe smoke / screens, Skim in Safari
#   bash Scripts/ci_local.sh --base REF      # diff against REF instead of origin/main
#
# Areas come from Scripts/ci_changes.py, as in CI's `changes` job. Every step runs through
# Scripts/test_guard.py with a wall-clock limit (exit 124 at the limit); nothing runs while
# ~/LuminaEvidence/.tests-off exists (exit 75). Screen-owning steps (the probe's window, Safari)
# run only with --probe or LUMINA_LONG=1, one at a time under the screen lock; otherwise they are
# listed as SKIP and CI is their proof. Linux-only jobs (WebKitGTK) are SKIP on a Mac.
# Logs: ~/LuminaEvidence/ci-local/<time>/<step>.log. Exit 0 when nothing failed.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

BASE=origin/main DRY=0 ALL=0 PROBE=0
[[ ${LUMINA_LONG:-} == 1 ]] && PROBE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --all) ALL=1 ;;
    --probe) PROBE=1 ;;
    --base) BASE="$2"; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "ci_local: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

OFF="${LUMINA_GUARD_DIR:-$HOME/LuminaEvidence}/.tests-off"
if [[ -e $OFF && $DRY == 0 ]]; then
  echo "REFUSED  tests are switched off on this Mac ($OFF). Only the owner turns them back on." >&2
  echo "         Wanted to run: bash Scripts/ci_local.sh $*   (--dry-run lists the steps)" >&2
  exit 75
fi

# ——— what changed
if [[ $ALL == 1 ]]; then
  FILES=(".github/ (--all)")
else
  git rev-parse --verify -q "$BASE" >/dev/null || { echo "ci_local: no $BASE (git fetch origin?)" >&2; exit 2; }
  FILES=()
  while IFS= read -r f; do [[ -n $f ]] && FILES+=("$f"); done < <(
    { git diff --name-only "$BASE"...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
fi
# macOS's bash is 3.2: no associative arrays, so one variable per area (A_web, A_swift, …).
A_web=false A_swift=false A_look=false A_release=false A_screens=false A_sandbox=false XCTEST=""
if [[ ${#FILES[@]} -gt 0 ]]; then
  while IFS='=' read -r k v; do
    case "$k" in
      xctest) XCTEST="$v" ;;
      web|swift|look|release|screens|sandbox) eval "A_$k=\$v" ;;
    esac
  done < <(python3 Scripts/ci_changes.py "${FILES[@]}" | grep -v '^#')
fi
echo "ci_local: ${#FILES[@]} files vs $BASE · web=$A_web swift=$A_swift look=$A_look release=$A_release screens=$A_screens sandbox=$A_sandbox"
[[ -n $XCTEST ]] && echo "          xctest: $XCTEST"

# ——— the step runner
STAMP="$(date +%Y%m%d-%H%M%S)"
LOGS="$HOME/LuminaEvidence/ci-local/$STAMP"
[[ $DRY == 0 ]] && mkdir -p "$LOGS"
RESULTS=() FAILED=0 REFUSED=0 CR=""
[[ -t 1 ]] && CR=$'\r\033[K'
record() { RESULTS+=("$(printf '%-5s %-44s %s' "$1" "$2" "$3")"); }
skip() { record SKIP "$1" "$2"; }

# step NAME LIMIT_SECONDS [--screen] -- COMMAND…   (COMMAND runs under bash -c in the repo root)
step() {
  local name="$1" limit="$2"; shift 2
  local screen=()
  [[ $1 == --screen ]] && { screen=(--screen); shift; }
  [[ $1 == -- ]] && shift
  local cmd="$*"
  if [[ $DRY == 1 ]]; then record PLAN "$name" "${limit}s${screen:+ screen}: $(tr '\n' ' ' <<<"$cmd" | tr -s ' ')"; return; fi
  local log="$LOGS/${name//[^A-Za-z0-9._-]/_}.log" t0=$SECONDS rc
  [[ -t 1 ]] && printf '… %-44s' "$name"
  python3 Scripts/test_guard.py run --quiet --name "ci-local $name" --limit "$limit" ${screen[@]+"${screen[@]}"} -- \
    bash -c "$cmd" >"$log" 2>&1
  rc=$?
  local took="$((SECONDS - t0))s"
  if [[ $rc == 0 ]]; then
    printf "$CR"'PASS  %-44s %s\n' "$name" "$took"; record PASS "$name" "$took"
  elif [[ $rc == 75 ]]; then
    printf "$CR"'REFUS %-44s %s\n' "$name" "$(tail -1 "$log")"; record REFUS "$name" "refused (tests off, or already running): $log"; REFUSED=1
  else
    printf "$CR"'FAIL  %-44s %s (exit %s)\n' "$name" "$took" "$rc"; tail -15 "$log" | sed 's/^/      /'
    record FAIL "$name" "exit $rc · $log"; FAILED=1
  fi
}

PY_PARITY=python3
[[ -x $HOME/LuminaEvidence/venv-parity/bin/python ]] && PY_PARITY="$HOME/LuminaEvidence/venv-parity/bin/python"
NODE_GLOBAL="$(npm root -g 2>/dev/null)"
have_playwright() { NODE_PATH="$NODE_GLOBAL" node -e "require('playwright')" >/dev/null 2>&1 && ls "$HOME/Library/Caches/ms-playwright"/chromium* >/dev/null 2>&1; }
IS_MAC=0; [[ $(uname) == Darwin ]] && IS_MAC=1

# ——— this script still mirrors the workflow: every test file or script lumina.yml runs is named here
step "ci_local mirrors lumina.yml" 30 -- "python3 - <<'PY'
import re, sys
yml = open('.github/workflows/lumina.yml').read(); me = open('Scripts/ci_local.sh').read()
used = set(re.findall(r'(?:Tests|Tools|Scripts)/[\\w./-]+\\.(?:mjs|py|sh)', yml))
missing = sorted(u for u in used if u not in me and u != 'Scripts/ci_changes.py')
print('missing from Scripts/ci_local.sh:', *missing, sep='\\n  ') if missing else print(len(used), 'workflow commands mirrored')
sys.exit(1 if missing else 0)
PY"

# ——— design handoff (every PR)
step "design: lumina-core fixtures" 120 -- \
  'source Scripts/page_files.sh && cd design/handoff/lumina-cull && out="$(node "$CORE_TEST")"; rc=$?; echo "$out"; [ $rc = 0 ] && ! grep -q "^FAIL" <<<"$out"'
step "design: culleval scoring + readOne guard" 120 -- 'node --test Tools/culleval/tests/culleval.test.mjs'
step "design: page byte for byte" 60 -- '
  set -e; source Scripts/page_files.sh
  for f in "${PAGE_FILES[@]}"; do cmp "design/handoff/lumina-cull/$f" "Lumina/Sets/Web/$f"; done
  for f in react.production.min.js react-dom.production.min.js; do cmp "design/handoff/vendor/$f" "Lumina/Sets/Web/$f"; done
  [[ ! -e Lumina/Sets/Web/babel.min.js ]] || { echo "babel.min.js is back in Lumina/Sets/Web"; exit 1; }
  python3 Scripts/page_bytes.py
  grep -ho "\"page\": *\"[^\"]*\"" Tests/probe/scenarios/*.json | sed "s/.*: *\"//; s/\"\$//" | sort -u | while IFS= read -r p; do
    [[ -f "Lumina/Sets/Web/$p" ]] || { echo "a probe scenario names \"$p\", which the app does not ship"; exit 1; }
  done'
step "design: wording + demo-layer audit (report)" 60 -- 'source Scripts/page_files.sh && python3 Tests/probe/design_audit.py "design/handoff/lumina-cull/$PAGE" || true'
step "design: trust inventory" 60 -- 'python3 Scripts/trust_check.py'
if "$PY_PARITY" -c 'import numpy' 2>/dev/null; then
  step "design: parity tools" 300 -- "make parity-test PY='$PY_PARITY'"
else
  skip "design: parity tools" "no numpy (python3 -m venv ~/LuminaEvidence/venv-parity && pip install -r Tools/parity/requirements.txt)"
fi
step "design: rules-v1.json order" 30 -- \
  "python3 -c \"import json;r=json.load(open('Lumina/Sets/Look/rules-v1.json'));assert r['order'][0]=='rawDevelop' and r['order'][-1]=='outputTransform';print(len(r['stages']),'stages')\""

# ——— the page (web)
if [[ $A_web == true ]]; then
  skip "webkit: WebKitGTK sandbox" "Linux only (Tests/web/webkit.py under xvfb): CI runs it"
  step "webkit: Skim export, report, look maths" 120 -- 'node --test Tests/web/skim-export.test.mjs Tests/web/skim-report.test.mjs Tests/web/skim-look.test.mjs'
  if have_playwright; then
    step "chromium: plumbing harness" 600 -- "NODE_PATH='$NODE_GLOBAL' node Tests/web/plumbing-harness.mjs"
    step "chromium: grid zoom" 300 -- "NODE_PATH='$NODE_GLOBAL' node Tests/web/grid-zoom.mjs"
    step "chromium: Stills web preview" 300 -- "NODE_PATH='$NODE_GLOBAL' node Tests/web/stills-preview.mjs"
  else
    skip "chromium: harness, grid zoom, preview" "no playwright@1.56.1 + Chromium (npm i -g playwright@1.56.1 && npx playwright install chromium)"
  fi
  skip "skim-webkit: Skim in WebKitGTK" "Linux only: CI runs it"
  if [[ $IS_MAC == 1 && $PROBE == 1 ]]; then
    step "skim-safari: Skim in Safari" 600 --screen -- 'python3 Tests/web/skim-engine.py safari'
  else
    skip "skim-safari: Skim in Safari" "drives Safari: --probe to run it"
  fi
fi

# ——— build + tests (Mac)
if [[ $A_swift == true || $A_look == true || $A_release == true ]]; then
  if [[ $IS_MAC == 1 ]]; then
    step "app: build + LuminaLogicTests" 1800 -- \
      "xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' ${XCTEST:--only-testing:LuminaLogicTests} COMPILER_INDEX_STORE_ENABLE=NO test"
    if [[ $A_look == true ]]; then
      step "app: lumina-render ≡ LookMath ≡ numpy" 900 -- \
        "set -e; swift build -c release --package-path Tools/parity/lumina-render; d=\$(mktemp -d); Tools/parity/lumina-render/.build/release/lumina-render ramp --out \"\$d/ramp.json\"; '$PY_PARITY' Tools/parity/lookmath.py --check \"\$d/ramp.json\"; rm -rf \"\$d\""
    fi
    if [[ $A_release == true ]]; then
      step "app: release.sh local --strict" 1800 -- 'PREFLIGHT_ALLOW=D2 bash Scripts/release.sh local --strict'
      step "app: release.sh local --strict (Skim)" 1800 -- 'PREFLIGHT_ALLOW=D2 LUMINA_APP=skim bash Scripts/release.sh local --strict'
    fi
  else
    skip "app: build + tests" "macOS only"
  fi
fi

# ——— the probe (Mac, owns the screen; probe.sh takes the lock itself)
if [[ $IS_MAC == 1 && $PROBE == 1 ]]; then
  if [[ $A_sandbox == true ]]; then
    step "probe: sandbox smoke" 900 -- 'bash Scripts/probe.sh sandbox smoke'
  else
    step "probe: smoke" 900 -- 'bash Scripts/probe.sh smoke'
  fi
  [[ $A_screens == true ]] && step "probe: screens" 900 -- 'bash Scripts/probe.sh screens'
else
  skip "probe: smoke$([[ $A_screens == true ]] && echo ' + screens')" "owns the screen: --probe to run it (CI runs it on every PR into main)"
fi

# Not mirrored: the nightly long shards (fuzz, scroll, edit on Tests/web/make-shoot.mjs cards). Run those by
# name on a Mac with LUMINA_LONG=1 bash Scripts/probe.sh … (AGENTS.md "Checks").

# ——— summary
echo
echo "ci_local summary ($BASE, $(git rev-parse --short HEAD)$([[ -n $(git status --porcelain) ]] && echo ' + uncommitted'))"
printf '  %s\n' ${RESULTS[@]+"${RESULTS[@]}"}
if [[ $DRY == 1 ]]; then echo "DRY RUN  nothing ran"; exit 0; fi
if [[ $FAILED == 1 ]]; then echo "FAIL  fix the steps above before pushing · logs $LOGS"; exit 1; fi
if [[ $REFUSED == 1 ]]; then echo "REFUSED  some steps did not run · logs $LOGS"; exit 75; fi
echo "PASS  ready to push (pr-shepherd) · logs $LOGS"
