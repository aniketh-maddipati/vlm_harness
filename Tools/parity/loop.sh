#!/usr/bin/env bash
# The refinement loop (roadmap Prompt 2 §5), one stage at a time in rules-v1.json's order.
#
#   bash Tools/parity/loop.sh              every unlocked stage
#   bash Tools/parity/loop.sh tone         one stage
#   LOOP_DRY=1 bash Tools/parity/loop.sh   measure and report, never fit, lock or commit
#
# Per stage:
#   1. make parity STAGE=<id>                                → report.md + summary.json
#   2. criteria met (every slider of the stage: median ≤ 2.0, p95 ≤ 4.0)?
#        → "locked": true in rules-v1.json, commit `parity/<stage>: locked median X p95 Y`, next stage
#   3. else fit.py --stage <id> (coefficients only; a change of form is a code change made by the
#      person or agent driving this loop), verify with a real render, keep it only if the median
#      improved and no locked stage regressed by more than 0.2 median (checked with a full run
#      of the locked stages), append one paragraph to report.md
#   4. after 12 iterations without meeting the criteria: BLOCKED-<stage>.md with the worst pairs'
#      heatmap paths and the residual-by-L* table, then the next stage
#   5. after every stage: the combos (make parity-combos); if their median > 3.0 the report says
#      so; trying other stage orders is done by editing "order" in rules-v1.json by hand and
#      re-running (each attempt's report stays in Tools/parity/report/).
# Never touched here: criteria.json, golden.json, refs.json, a locked stage's coefficients.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PARITY=Tools/parity
RULES=Lumina/Sets/Look/rules-v1.json
CRITERIA=$PARITY/criteria.json
MAX_ITER=$(python3 -c "import json;print(json.load(open('$CRITERIA'))['maxIterationsPerStage'])")
REGRESS=$(python3 -c "import json;print(json.load(open('$CRITERIA'))['lockedRegressionMedian'])")
DRY="${LOOP_DRY:-0}"
only="${1:-}"

stages() { python3 -c "import json;r=json.load(open('$RULES'));print(' '.join(s for s in r['order'] if s not in ('rawDevelop','outputTransform')))"; }
locked() { python3 -c "import json;r=json.load(open('$RULES'));print('1' if r['stages'].get('$1',{}).get('locked') else '0')"; }
latest() { python3 -c "import json;print(json.load(open('$PARITY/report/latest.json'))['report'])"; }

# stage stats from a summary.json: "<pass 0/1> <median> <p95>"
stage_stats() {
  python3 - "$1" "$2" <<'PY'
import json, sys
s = json.load(open(sys.argv[1] + '/summary.json'))['aggregate']['stages'].get(sys.argv[2])
print('0 nan nan' if not s else f"{int(s['pass'])} {s['median']:.3f} {s['p95']:.3f}")
PY
}

set_locked() {
  python3 - "$RULES" "$1" <<'PY'
import json, sys
p, stage = sys.argv[1], sys.argv[2]
r = json.load(open(p)); r['stages'][stage]['locked'] = True
json.dump(r, open(p, 'w'), indent=2); open(p, 'a').write('\n')
PY
}

append_paragraph() {  # report dir, text
  printf '\n%s\n' "$2" >> "$1/report.md"
}

# Locked stages must not regress: run them all once and compare medians with the numbers
# recorded when they were locked (Tools/parity/report/locked.json).
locked_regressed() {
  local list; list="$(for s in $(stages); do [[ $(locked "$s") == 1 ]] && printf '%s ' "$s"; done)"
  [[ -z $list ]] && return 1
  python3 - "$PARITY/report/locked.json" "$REGRESS" $list <<'PY' || return 0
import json, subprocess, sys, os
locked_path, tol, stages = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
if not os.path.exists(locked_path): sys.exit(0)
before = json.load(open(locked_path))
for st in stages:
    r = subprocess.run(['make', '-s', 'parity', f'STAGE={st}', 'LABEL=regress-' + st], capture_output=True, text=True)
    latest = json.load(open('Tools/parity/report/latest.json'))['report']
    now = json.load(open(latest + '/summary.json'))['aggregate']['stages'].get(st)
    if st in before and now and now['median'] > before[st]['median'] + tol:
        print(f"{st} regressed: median {before[st]['median']:.2f} → {now['median']:.2f}")
        sys.exit(1)
sys.exit(0)
PY
  return 1
}

record_locked() {  # stage median p95
  python3 - "$PARITY/report/locked.json" "$1" "$2" "$3" <<'PY'
import json, sys, os, datetime
p, st, med, p95 = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
d = json.load(open(p)) if os.path.exists(p) else {}
d[st] = {'median': med, 'p95': p95, 'date': datetime.datetime.now().isoformat(timespec='seconds')}
json.dump(d, open(p, 'w'), indent=1, sort_keys=True)
PY
}

blocked_note() {  # stage, report dir
  local st="$1" rep="$2" out="$PARITY/BLOCKED-$1.md"
  {
    echo "# BLOCKED: $st"
    echo
    echo "$(date '+%Y-%m-%d %H:%M') · $MAX_ITER iterations without meeting the criteria. Last report: \`$rep/report.md\`."
    echo
    echo "## Residual"
    echo
    python3 - "$rep/summary.json" "$st" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); st = sys.argv[2]
agg = s['aggregate']
for k, v in agg['sliders'].items():
    if v.get('stage') == st:
        print(f"- **{k}**: median {v['median']:.2f}, p95 {v['p95']:.2f}; regions " + ", ".join(f"{r} {m:.2f}" for r, m in v.get('regions', {}).items()))
        worst_pos = sorted(v['positions'].items(), key=lambda kv: -kv[1].get('median', 0))[:3]
        print("  worst positions: " + ", ".join(f"{p} (median {q['median']:.2f})" for p, q in worst_pos))
print()
print("Worst pairs (heatmaps under ~/LuminaEvidence/parity/report/…/heatmaps):")
for w in agg['worst']:
    print(f"- `{w['id']}` median {w['median']:.2f} p95 {w['p95']:.2f}")
PY
    echo
    echo "## Hypothesis"
    echo
    echo "_(written by whoever drives the loop: where the error sits — tone scale, hue, position in the slider's range — and what change of form would address it)_"
  } > "$out"
  echo "→ $out"
}

for st in $(stages); do
  [[ -n $only && $only != "$st" ]] && continue
  if [[ $(locked "$st") == 1 ]]; then echo "== $st: locked, skipping"; continue; fi
  echo "== $st"
  iter=0
  while :; do
    make -s parity "STAGE=$st" "LABEL=$st-$iter" || { echo "make parity failed for $st"; break; }
    rep="$(latest)"
    read -r pass med p95 <<<"$(stage_stats "$rep" "$st")"
    echo "$st iteration $iter: median $med p95 $p95 pass=$pass"
    if [[ $pass == 1 ]]; then
      if [[ $DRY == 1 ]]; then echo "(dry) would lock $st"; break; fi
      set_locked "$st"
      record_locked "$st" "$med" "$p95"
      append_paragraph "$rep" "Locked: median $med, p95 $p95 met the criteria at iteration $iter."
      git add "$RULES" "$PARITY/report" && git commit -q -m "parity/$st: locked median $med p95 $p95" \
        -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" && echo "committed"
      break
    fi
    if (( iter >= MAX_ITER )); then blocked_note "$st" "$rep"; break; fi
    if [[ $DRY == 1 ]]; then echo "(dry) would fit $st"; break; fi
    # propose: fit the coefficients, verify with a real render, keep only if better and nothing locked regressed
    cp "$RULES" "$RULES.before"
    if python3 $PARITY/fit.py --stage "$st" --label "$st-$iter" --apply; then
      make -s parity "STAGE=$st" "LABEL=$st-$iter-fit" || true
      rep2="$(latest)"
      read -r pass2 med2 p952 <<<"$(stage_stats "$rep2" "$st")"
      better=$(python3 -c "print(1 if $med2 < $med else 0)")
      if [[ $better == 1 ]] && ! locked_regressed; then
        append_paragraph "$rep2" "Iteration $iter: fit.py moved $st's coefficients; median $med → $med2, p95 $p95 → $p952. Kept. Change: $(python3 -c "import json;n=json.load(open('$HOME/LuminaEvidence/parity/render/fit-$st.json'));print(', '.join(f'{k} {a:.4g}→{b:.4g}' for k,(a,b) in n['changed'].items()))" 2>/dev/null)"
        rm -f "$RULES.before"
      else
        append_paragraph "$rep2" "Iteration $iter: fit.py's change (median $med → $med2) was reverted: not better, or a locked stage regressed by more than $REGRESS."
        mv "$RULES.before" "$RULES"
      fi
    else
      rm -f "$RULES.before"
      echo "fit.py made no progress on $st; the residual is structural — change the stage's form (LookKernels.swift + LookMath.swift + lookmath.py), then re-run"
      blocked_note "$st" "$rep"
      break
    fi
    iter=$((iter + 1))
  done
done

if [[ -z $only && $DRY != 1 ]]; then
  echo "== combos"
  make -s parity-combos || true
  rep="$(latest)"
  python3 - "$rep/summary.json" "$CRITERIA" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))['aggregate']['sliders'].get('combo'); c = json.load(open(sys.argv[2]))['combos']
if s: print(f"combos: median {s['median']:.2f} (≤ {c['median']}), p95 {s['p95']:.2f} (≤ {c['p95']}) → {'pass' if s['pass'] else 'FAIL: first suspects are stage order and working space; edit order/workingSpace in rules-v1.json (at most three orderings) and re-run'}")
PY
fi
