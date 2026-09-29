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
rsync -a --delete --exclude '._*' "$NEW/" "$DEST/"
bash Scripts/sets_sync_ui.sh

step "7. plumbing contract + app suites"
bash Scripts/probe.sh contract || { echo "PLUMBING CONTRACT BROKEN — the page renamed/removed something Lumina/Sets/Web/plumbing.js uses"; fail=1; }

step "8. reference (every screen, byte-compared)"
if [[ $RECORD == 1 ]]; then bash Scripts/probe.sh reference --record; else bash Scripts/probe.sh reference || echo "  screens changed — expected for a design update; review evidence, then rerun with --record"; fi

step "9. robustness (fuzz + app + edge)"
bash Scripts/probe.sh fuzz || fail=1
[[ -n "${LUMINA_FIXTURE_ROOT:-}" ]] && { bash Scripts/probe.sh app || fail=1; bash Scripts/probe.sh edge || true; }

step "done"
echo "evidence: $LUMINA_PROBE_OUT"
git status --short -- "$DEST" Lumina/Sets/Web | head -20
[[ $fail == 0 ]] && echo "SYNC OK — review, then commit" || echo "SYNC HAS FAILURES — see above"
exit $fail
