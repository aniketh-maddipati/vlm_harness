#!/bin/bash
# Constitution v6 presence harness — re-seal asserts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

need=(
  design/contract-v5.md
  design/contract-v6.md
  design/tokens.yaml
  design/copy-contract.txt
  design/fixture-manifest.md
  design/checkpoint-sequence-v6.md
)
for f in "${need[@]}"; do
  [[ -f "$f" ]] || report "missing artifact $f"
done

if [[ -f design/contract-v5.md ]]; then
  for n in 1 10 11 24 27 36 40; do
    grep -q "\*\*D${n}\." design/contract-v5.md || report "contract-v5.md missing D${n}"
  done
fi

if [[ -f design/contract-v6.md ]]; then
  grep -q 'Conflicts — closed this re-seal' design/contract-v6.md || report "contract-v6.md missing closed-conflicts section"
  grep -q 'Amended v5 entries' design/contract-v6.md || report "contract-v6.md missing amended v5 section"
  grep -q 'D59' design/contract-v6.md || report "contract-v6.md missing D59"
  grep -q 'D60' design/contract-v6.md || report "contract-v6.md missing D60"
  # First-pass absence CONFLICT must not remain as an open blocker
  if grep -q 'Contract v5 (D1–D40) is not present' design/contract-v6.md; then
    report "contract-v6.md still claims v5 is absent"
  fi
fi

if [[ -f design/checkpoint-sequence-v6.md ]]; then
  grep -q 'Reorder decision: none' design/checkpoint-sequence-v6.md || report "checkpoint-sequence missing reorder decision"
  grep -q 'SPIKE A' design/checkpoint-sequence-v6.md || report "checkpoint-sequence missing SPIKE A"
  grep -q 'CP8' design/checkpoint-sequence-v6.md || report "checkpoint-sequence missing CP8"
fi

if [[ -f design/copy-contract.txt ]]; then
  grep -q 'BANNED WORDS' design/copy-contract.txt || report "copy-contract missing banned-words line"
  grep -Fq 'Re-pressing the mark on a marked frame clears it to unreviewed, in place. Decision keys never autorepeat.' design/copy-contract.txt \
    || report "copy-contract missing same-mark-clears verbatim"
  grep -Fq 'P keeps · X rejects · same key again clears' design/copy-contract.txt \
    || report "copy-contract missing same-mark footer verbatim"
  grep -Fq 'After ⇧⏎ stages, ⏎ cannot commit until Return is physically released. One held press can never stage-and-commit.' design/copy-contract.txt \
    || report "copy-contract missing Return-release gate verbatim"
  grep -q 'PLACEHOLDER' design/copy-contract.txt && report "copy-contract still has PLACEHOLDER lines"
  # Superseded hover string must not remain as a shippable frozen row
  if grep -v '^#' design/copy-contract.txt | grep -Fq 'drag to move (hover)'; then
    report "copy-contract still ships hover parenthetical"
  fi
fi

if [[ -f Lumina/Design/CopyContract.swift ]]; then
  grep -q 'tableFooterHover' Lumina/Design/CopyContract.swift && report "CopyContract still defines tableFooterHover"
  grep -q 'tableFooterHints' Lumina/Design/CopyContract.swift || report "CopyContract missing tableFooterHints"
  if grep -Fq 'drag to move (hover)' Lumina/Design/CopyContract.swift; then
    report "CopyContract still contains superseded hover string"
  fi
fi

bash Scripts/lint/copy_contract_diff.sh || report "copy_contract_diff.sh failed"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "contract_v6_presence.sh: OK"
