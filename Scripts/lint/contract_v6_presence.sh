#!/bin/bash
# Constitution v6 presence harness — documents-only session asserts.
# Fails if required artifacts are missing or if sealed rulings lack citations.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

need=(
  design/contract-v6.md
  design/tokens.yaml
  design/copy-contract.txt
  design/fixture-manifest.md
  design/checkpoint-sequence-v6.md
)
for f in "${need[@]}"; do
  [[ -f "$f" ]] || report "missing artifact $f"
done

# Conflict honesty — v5 absence must remain flagged until sealed
if [[ -f design/contract-v6.md ]]; then
  grep -q 'CONFLICT' design/contract-v6.md || report "contract-v6.md missing CONFLICT block"
  grep -q 'D41' design/contract-v6.md || report "contract-v6.md missing D41 ruling entry"
  grep -q 'D57' design/contract-v6.md || report "contract-v6.md missing D57 (R-Q.1)"
  grep -q 'D36' design/contract-v6.md || report "contract-v6.md missing D36 amendment"
  grep -q 'D48' design/contract-v6.md || report "contract-v6.md missing D48 hover deletion"
fi

if [[ -f design/tokens.yaml ]]; then
  grep -q 'halo_width' design/tokens.yaml || report "tokens.yaml missing halo_width"
  grep -q 'warm_in_crossfade' design/tokens.yaml || report "tokens.yaml missing warm_in_crossfade"
  grep -q 'cite:' design/tokens.yaml || report "tokens.yaml missing cite fields"
fi

if [[ -f design/copy-contract.txt ]]; then
  grep -q 'BANNED WORDS' design/copy-contract.txt || report "copy-contract missing banned-words line"
  grep -q 'Sample shoot — yours replaces it' design/copy-contract.txt || report "copy-contract missing R-M.3 sample string"
  grep -q 'Rejects to Trash' design/copy-contract.txt || report "copy-contract missing R-M.1 trash string"
  grep -q 'sharpness not final' design/copy-contract.txt || report "copy-contract missing R-5.1 class exemplar"
  grep -q '⌥⌘E changes the recipe' design/copy-contract.txt || report "copy-contract missing R-8.1 string"
fi

if [[ -f design/fixture-manifest.md ]]; then
  grep -q 'iphone-proraw' design/fixture-manifest.md || report "fixture-manifest missing iphone-proraw"
  grep -q 'card-mixed-video' design/fixture-manifest.md || report "fixture-manifest missing mixed-video"
  grep -q 'Sample shoot' design/fixture-manifest.md || report "fixture-manifest missing sample shoot spec"
fi

if [[ -f design/checkpoint-sequence-v6.md ]]; then
  grep -q 'CONFLICT' design/checkpoint-sequence-v6.md || report "checkpoint-sequence missing CONFLICT"
  grep -q 'Reorder decision this session' design/checkpoint-sequence-v6.md || report "checkpoint-sequence missing reorder decision"
fi

# Swift copy literals must still resolve into the frozen table
bash Scripts/lint/copy_contract_diff.sh || report "copy_contract_diff.sh failed"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "contract_v6_presence.sh: OK"
