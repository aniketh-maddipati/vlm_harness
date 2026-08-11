#!/bin/bash
# Agent-rules vs Contract v6 — permanent drift gate.
# Agent-instruction files teaching outdated grammar are the same FAIL class as copy drift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

# --- D63: crop mode keys = R/O; A and X banned from remapping ---
check_crop_d63() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  # Must not teach A/X re-scoping inside crop
  if grep -Eiq 'Inside crop latch|crop latch' "$f" \
    && grep -Eiq 'Toggle aspect|Flip crop orientation|decision keys are \*\*re-scoped\*\*|re-scoped.*crop|crop.*re-scop' "$f"; then
    # Allow historical "banned from remapping" / "NOT re-scoped" prose
    if grep -Eq 're-scoped' "$f" && ! grep -Eq 'NOT re-scoped|not re-scoped|banned from remapping' "$f"; then
      report "$f: teaches crop decision-key re-scoping (contradicts D63)"
    fi
  fi

  # Explicit old hi-fi remap rows
  if grep -Eq '`A`.*Toggle aspect|Toggle aspect-ratio lock' "$f"; then
    report "$f: maps A → aspect inside crop (D63 bans A/X remap)"
  fi
  if grep -Eq '`X`.*Flip crop|Flip crop orientation \(never marks reject\)' "$f"; then
    report "$f: maps X → orientation inside crop (D63 bans A/X remap)"
  fi

  # Affirmative D63 markers required when crop latch is documented
  if grep -Eqi 'cropSession|crop latch|Crop mode' "$f"; then
    grep -Eq '`R`|R frees|Free the aspect' "$f" || report "$f: crop docs missing R (aspect) per D63"
    grep -Eq '`O`|O flips|Flip crop orientation' "$f" || report "$f: crop docs missing O (orientation) per D63"
    grep -Eqi 'banned from remapping|NOT re-scoped|never remapped inside crop|A/X remap banned' "$f" \
      || report "$f: crop docs missing A/X remap ban (D63)"
  fi
}

RULE_FILES=(
  .cursorrules
  AGENTS.md
  CLAUDE.md
  .cursor/rules
)

shopt -s nullglob
for path in "${RULE_FILES[@]}"; do
  if [[ -d "$path" ]]; then
    for f in "$path"/*; do
      [[ -f "$f" ]] || continue
      check_crop_d63 "$f"
    done
  elif [[ -f "$path" ]]; then
    check_crop_d63 "$path"
  fi
done

# Broader scan for CLAUDE.md anywhere under repo root (depth-limited)
while IFS= read -r -d '' f; do
  check_crop_d63 "$f"
done < <(find . -maxdepth 3 -name 'CLAUDE.md' -print0 2>/dev/null)

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "agent_rules_contract.sh: OK (D63 crop keys; A/X remap banned)"
