#!/bin/bash
# The one way tests run on this Mac (Tests/runner/CHARTER.md).
#
#   bash Tests/runner/run.sh <template> [args…]      e.g. run.sh uitest LayoutAndSizingTests/test_R43_resizeWhileZoomed_photoStaysVisible
#   bash Tests/runner/run.sh list                     the templates
#   bash Tests/runner/stop.sh                         the kill switch
#
# Every run: one at a time (a lock), a hard time limit (the template's, never over 600 s), its own
# process group (killed whole at the limit, on Ctrl-C or on stop.sh), and a clean exit (the app,
# test runners and the probe's disk images are gone afterwards). Logs: ~/LuminaEvidence/runner/<run>/.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATES="$ROOT/Tests/runner/templates"
STATE="$HOME/LuminaEvidence/runner"
LOCK="$STATE/lock"
mkdir -p "$STATE"

if [ "${1:-}" = "" ] || [ "$1" = "list" ]; then
  echo "templates:"; for t in "$TEMPLATES"/*.sh; do printf '  %-10s %s\n' "$(basename "$t" .sh)" "$(sed -n 's/^# about: //p' "$t")"; done
  exit 0
fi
NAME="$1"; shift
T="$TEMPLATES/$NAME.sh"
[ -f "$T" ] || { echo "no template '$NAME' (run.sh list)"; exit 2; }

# The time limit the template asks for, capped.
LIMIT="$(sed -n 's/^# limit: *\([0-9]*\).*/\1/p' "$T")"; LIMIT="${LIMIT:-60}"
[ -n "${RUNNER_LIMIT:-}" ] && LIMIT="$RUNNER_LIMIT"
[ "$LIMIT" -gt 600 ] && LIMIT=600

# One run at a time: tests that own the screen must never overlap (AGENTS.md).
if ! mkdir "$LOCK" 2>/dev/null; then
  OTHER="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$OTHER" ] && kill -0 "$OTHER" 2>/dev/null; then
    echo "busy: run $(cat "$LOCK/what" 2>/dev/null) (pid $OTHER). Wait, or bash Tests/runner/stop.sh"; exit 3
  fi
  rm -rf "$LOCK"; mkdir "$LOCK"   # left over from a run that died
fi
echo $$ > "$LOCK/pid"; echo "$NAME $*" > "$LOCK/what"

RUN="$STATE/$(date +%Y%m%d-%H%M%S)-$NAME"; mkdir -p "$RUN"; LOG="$RUN/log.txt"
export ROOT RUN

cleanup() {
  local code=$?
  [ -n "${PGID:-}" ] && { kill -TERM -"$PGID" 2>/dev/null; sleep 1; kill -KILL -"$PGID" 2>/dev/null; }
  [ -n "${DOG:-}" ] && kill "$DOG" 2>/dev/null
  bash "$ROOT/Tests/runner/stop.sh" --quiet --keep-lock
  rm -rf "$LOCK"
  exit "$code"
}
trap cleanup EXIT INT TERM HUP

echo "run: $NAME $*  (limit ${LIMIT}s, log $LOG)"
START=$(date +%s)
set -m                                   # the template gets its own process group
bash "$T" "$@" >"$LOG" 2>&1 &
PID=$!; PGID=$PID
set +m
# The watchdog: at the limit the whole group goes.
( sleep "$LIMIT"; if kill -0 "$PID" 2>/dev/null; then echo "TIMEOUT after ${LIMIT}s" >>"$LOG"; kill -TERM -"$PGID" 2>/dev/null; sleep 3; kill -KILL -"$PGID" 2>/dev/null; fi ) &
DOG=$!
wait "$PID"; CODE=$?
kill "$DOG" 2>/dev/null; DOG=""
PGID=""
SECS=$(( $(date +%s) - START ))

# The verdict, and the lines that explain it.
if grep -q "^TIMEOUT" "$LOG"; then VERDICT="TIMEOUT"; CODE=124
elif [ "$CODE" = 0 ]; then VERDICT="PASS"; else VERDICT="FAIL"; fi
echo "$VERDICT in ${SECS}s ($NAME $*)" | tee "$RUN/verdict.txt"
grep -E "error:|failed \(|passed \(|Executed [0-9]+ test|TIMEOUT|BUILD (SUCCEEDED|FAILED)|Build complete" "$LOG" | grep -v "^$" | tail -25
exit "$CODE"
