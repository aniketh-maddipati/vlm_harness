#!/usr/bin/env bash
# LuminaPlayground + InjectionIII sole-UI smoke.
#
# Branch/worktree: cursor/workbench-hot-reload @ /Users/aniketh/lumina-wt/workbench-hot
# Hot reload ONLY works on LuminaPlayground (bundle com.lumina.playground), never on
# ordinary Lumina Debug builds from agent DerivedData paths.
#
# Usage:
#   bash Scripts/workbench_hot_smoke.sh              # check + sole lease + build + launch
#   bash Scripts/workbench_hot_smoke.sh --check-only
#   bash Scripts/workbench_hot_smoke.sh --list
#   bash Scripts/workbench_hot_smoke.sh --sole-quit   # gentle quit ALL Lumina* only
#   bash Scripts/workbench_hot_smoke.sh --no-launch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="${LUMINA_WORKBENCH_DD:-/private/tmp/lumina-playground-hot/DD}"
APP="$DD/Build/Products/Debug/LuminaPlayground.app"
CHECK_ONLY=0
NO_LAUNCH=0
LIST_ONLY=0
SOLE_QUIT=0
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    --list) LIST_ONLY=1 ;;
    --sole-quit) SOLE_QUIT=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  esac
done

list_instances() {
  echo "-- Lumina / LuminaPlayground processes --"
  local found=0
  for name in Lumina LuminaPlayground; do
    while read -r p; do
      found=1
      ps -p "$p" -o pid=,etime=,command=
    done < <(pgrep -x "$name" 2>/dev/null || true)
  done
  if [[ "$found" -eq 0 ]]; then
    echo "(none)"
  fi
  echo
  echo "Tip: only ONE Playground from $APP should exist for hot reload."
  echo "Agent Debug Lumina.app paths under /private/tmp or */DD/* are a different UI."
}

gentle_quit_all() {
  echo "-- gentle quit (AppleScript, not pkill -x Lumina) --"
  osascript <<'EOF' 2>/dev/null || true
try
  tell application "Lumina" to quit
end try
try
  tell application "LuminaPlayground" to quit
end try
EOF
  sleep 1
  if pgrep -x Lumina >/dev/null 2>&1 || pgrep -x LuminaPlayground >/dev/null 2>&1; then
    echo "WARN still running:"
    list_instances
    return 1
  fi
  echo "OK  all quit"
  return 0
}

if [[ "$LIST_ONLY" -eq 1 ]]; then
  list_instances
  exit 0
fi

if [[ "$SOLE_QUIT" -eq 1 ]]; then
  gentle_quit_all
  exit $?
fi

echo "== workbench hot smoke =="
echo "repo:  $ROOT"
echo "DD:    $DD"
echo "branch:$(git -C "$ROOT" branch --show-current 2>/dev/null || echo '?')"
echo

fail=0
echo "-- InjectionIII --"
[[ -d /Applications/InjectionIII.app ]] && echo "OK  InjectionIII.app" || { echo "FAIL install InjectionIII"; fail=1; }
[[ -d /Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle ]] && echo "OK  macOSInjection.bundle" || { echo "FAIL bundle"; fail=1; }

echo
echo "-- watched path --"
defaults read com.johnholdsworth.InjectionIII lastWatched 2>/dev/null | sed 's/^/lastWatched: /' || echo "lastWatched: unset"
echo "this tree: $ROOT"
if [[ "$(defaults read com.johnholdsworth.InjectionIII lastWatched 2>/dev/null || true)" != "$ROOT" ]]; then
  echo "WARN InjectionIII lastWatched ≠ this worktree — open InjectionIII on $ROOT"
fi

echo
list_instances

echo "-- hot call sites --"
rg -n 'workbenchHot\(\)' "$ROOT/Lumina" --glob '*.swift' || true

[[ "$fail" -ne 0 ]] && exit 1
[[ "$CHECK_ONLY" -eq 1 ]] && { echo; echo "Next: bash Scripts/workbench_hot_smoke.sh"; exit 0; }

gentle_quit_all || exit 2

echo
echo "-- InjectionIII --"
open -a InjectionIII
open -a InjectionIII "$ROOT/Lumina.xcodeproj" 2>/dev/null || open -a InjectionIII "$ROOT"

echo
echo "-- build LuminaPlayground --"
mkdir -p "$DD"
xcodebuild \
  -project "$ROOT/Lumina.xcodeproj" \
  -scheme LuminaPlayground \
  -configuration Debug \
  -derivedDataPath "$DD" \
  -destination 'platform=macOS,arch=arm64' \
  build

BIN="$APP/Contents/MacOS/LuminaPlayground"
[[ -x "$BIN" ]] || { echo "FAIL $BIN"; exit 1; }
echo "OK  $BIN"
find "$APP" -name 'macOSInjection.bundle' | head -3 | sed 's/^/OK  /'

[[ "$NO_LAUNCH" -eq 1 ]] && exit 0

echo
echo "-- launch sole Playground --"
FIXTURE_ROOT="${FIXTURE_ROOT:-${LUMINA_FIXTURE_ROOT:-$HOME/Pictures/lumina-fixtures}}"
export FIXTURE_ROOT
# Separate argv tokens — Xcode scheme used to glue "--card card-…" into one arg (broken).
open "$APP" --args --workbench --card card-clean-500 --surface table

sleep 2
list_instances

cat <<EOF

== inject proof ==
1. Window must show "Playground" capsule (com.lumina.playground).
2. Edit+Save under THIS tree only, e.g. ElasticTableView / ElasticRootView / P0OpenView.
3. InjectionIII flashes OK → pixels update.
4. If agents rebuild other DDs, run:  bash Scripts/workbench_hot_smoke.sh --sole-quit
   then relaunch only this app.

List:   bash Scripts/workbench_hot_smoke.sh --list
Quit:   bash Scripts/workbench_hot_smoke.sh --sole-quit
EOF
