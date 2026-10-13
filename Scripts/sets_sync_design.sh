#!/usr/bin/env bash
# Sync a new Claude Design handoff into the app. The design is the authority: its page ships
# byte-for-byte; this checks the new drop, installs it, and reports what moved. It never commits.
#
#   bash Scripts/sets_sync_design.sh "~/Downloads/Lumina Gallery redesign discussion (7).zip"
#   bash Scripts/sets_sync_design.sh <unzipped folder> [--record]   # --record accepts the new look
#
# Needs: node (fixtures), swift (probe). Uses LUMINA_FIXTURE_ROOT for the edge/app suites if set.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SRC="${1:?give the handoff .zip or folder}"; shift || true
RECORD=0; for a in "$@"; do [[ $a == --record ]] && RECORD=1; done
source Scripts/page_files.sh
DEST=design/handoff/lumina-cull
STAMP=$(date +%Y%m%d-%H%M%S)
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export LUMINA_PROBE_OUT="$HOME/LuminaEvidence/probe/sync-$STAMP"
fail=0; step() { printf '\n== %s\n' "$*"; }

step "1. unpack"
if [[ -d $SRC ]]; then cp -R "$SRC" "$WORK/in"; else unzip -q "$SRC" -d "$WORK/in" || { echo "can't unzip $SRC"; exit 2; }; fi
FOUND="$(find "$WORK/in" -name 'Lumina Sets *.dc.html' -not -path '*/__MACOSX/*' | head -1)"
[[ -n $FOUND ]] || { echo "no Lumina Sets page in $SRC"; exit 2; }
NEW="$(dirname "$FOUND")"
for f in "${PAGE_FILES[@]}" "$CORE_TEST"; do
  [[ -f "$NEW/$f" ]] || { echo "the handoff has no $f (page is $(basename "$FOUND")): a rename. Update Scripts/page_files.sh, SetsSchemeHandler.pageFiles, SetsPageBytesTests and the scenarios' \"page\", then rerun"; exit 2; }
done
find "$NEW" -name '._*' -delete

step "2. what changed"
diff -rq "$DEST" "$NEW" | sed "s#$NEW#new#; s#$DEST#current#" || true
for f in "$PAGE" "$CORE"; do
  [[ -f "$DEST/$f" ]] && ! cmp -s "$DEST/$f" "$NEW/$f" && echo "  $f: $(diff "$DEST/$f" "$NEW/$f" | grep -c '^[<>]') lines differ"
done

step "2b. new network + bridge surface (report only; a person reads every line)"
# A design zip is a code import: the page runs with the bridge (THREAT-MODEL T12). Every line of the
# incoming page files that the current ones don't have and that names a way out of the page or into
# the app is printed with its line number in the new file. Never fails the sync.
for f in "${PAGE_FILES[@]}"; do
  old="$DEST/$f"; [[ -f $old ]] || old=/dev/null
  awk -v name="$f" '
    BEGIN { n = split("fetch(|XMLHttpRequest|WebSocket|sendBeacon|RTCPeerConnection|EventSource|window.open|postMessage|messageHandlers|new Function|eval(|import(|http://|https://|ws://|wss://", pat, "|") }
    FILENAME == ARGV[1] { have[$0]++; next }
    have[$0] > 0 { have[$0]--; next }
    {
      for (i = 1; i <= n; i++) {
        rest = $0; off = 0
        while ((p = index(rest, pat[i])) > 0) {
          at = off + p; from = (at > 60) ? at - 60 : 1
          printf "  %s:%d: [%s] %s\n", name, FNR, pat[i], substr($0, from, 160)
          off = at + length(pat[i]) - 1; rest = substr($0, off + 1)
        }
      }
    }' "$old" "$NEW/$f" || true
done > "$WORK/surface.txt"
cat "$WORK/surface.txt"
echo "  $(grep -c . "$WORK/surface.txt") new mention(s) of network or bridge surface in the page files"

step "3. logic fixtures (node $CORE_TEST)"
(cd "$NEW" && node "$CORE_TEST" | tee "$WORK/fixtures.txt" && ! grep -q '^FAIL' "$WORK/fixtures.txt") || { echo "FIXTURES FAIL — not installing"; exit 1; }

step "4. support.js runtime pins"
for key in REACT_SRI REACT_DOM_SRI BABEL_SRI; do
  grep -q "var $key = \"$(grep -o "var $key = \"[^\"]*\"" "$DEST/support.js" | cut -d'"' -f2)\"" "$NEW/support.js" \
    || { echo "  $key changed in support.js — re-vendor design/handoff/vendor (see VENDOR.md)"; fail=1; }
done

step "5. wording + demo-layer audit (report only; fixes go to the design)"
python3 Tests/probe/design_audit.py "$NEW/$PAGE"

step "6. install"
# No --delete: the authority docs from earlier handoffs (PROMPT, ADDENDUM-1, PARITY, MENUS, …) stay
# until a handoff replaces them. uploads/ (the sample shoot's photos) and screenshots/ stay out of
# the repo (personal data, AGENTS.md): they go to ~/LuminaEvidence/design for the prototype runs.
rsync -a --exclude '._*' --exclude 'uploads/' --exclude 'screenshots/' "$NEW/" "$DEST/"
for d in uploads screenshots; do
  [[ -d "$NEW/$d" ]] && { mkdir -p "$HOME/LuminaEvidence/design/$d"; rsync -a --delete --exclude '._*' "$NEW/$d/" "$HOME/LuminaEvidence/design/$d/"; }
done
# A page from an earlier handoff (renamed since) must not linger next to the new one.
for f in "$DEST"/*.dc.html; do
  keep=0; for p in "${PAGE_FILES[@]}"; do [[ $(basename "$f") == "$p" ]] && keep=1; done
  [[ $keep == 1 || $(basename "$f") != Lumina\ Sets\ * && $(basename "$f") != Lumina\ Edit\ * ]] || { git rm -q --cached "$f" 2>/dev/null || true; rm -f "$f"; echo "removed stale $(basename "$f")"; }
done
bash Scripts/sets_sync_ui.sh

step "7. plumbing contract + app suites"
bash Scripts/probe.sh contract || { echo "PLUMBING CONTRACT BROKEN — the page renamed/removed something Lumina/Sets/Web/plumbing.js uses"; fail=1; }

step "8. reference (every screen, byte-compared)"
if [[ $RECORD == 1 ]]; then bash Scripts/probe.sh reference --record; else bash Scripts/probe.sh reference || echo "  screens changed — expected for a design update; review evidence, then rerun with --record"; fi

step "9. robustness (fuzz + app + edge)"
LUMINA_LONG=1 bash Scripts/probe.sh fuzz || fail=1      # a sync is the moment for the long storms
[[ -n "${LUMINA_FIXTURE_ROOT:-}" ]] && { bash Scripts/probe.sh app || fail=1; bash Scripts/probe.sh edge || true; }

step "done"
echo "evidence: $LUMINA_PROBE_OUT"
git status --short -- "$DEST" Lumina/Sets/Web | head -20
[[ $fail == 0 ]] && echo "SYNC OK — review, then commit" || echo "SYNC HAS FAILURES — see above"
exit $fail
