#!/bin/bash
# Copy-contract diff — CopyContract.swift literals must appear in design/copy-contract.txt
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CONTRACT="$ROOT/design/copy-contract.txt"
COPY_SWIFT="$ROOT/Lumina/Design/CopyContract.swift"

if [[ ! -f "$CONTRACT" ]]; then
  echo "FAIL: missing $CONTRACT" >&2
  exit 1
fi
if [[ ! -f "$COPY_SWIFT" ]]; then
  echo "FAIL: missing $COPY_SWIFT" >&2
  exit 1
fi

fail=0
exempt=(pointedFolderMovedBody pointedFolderMovedAction staleRenderBody staleRenderAction)

while IFS= read -r line; do
  [[ "$line" =~ static[[:space:]]+let[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]\"(.*)\"[[:space:]]*$ ]] || continue
  name="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  value="${value//\\\"/\"}"
  skip=0
  for e in "${exempt[@]}"; do
    [[ "$name" == "$e" ]] && skip=1 && break
  done
  [[ "$skip" -eq 1 ]] && continue
  if ! grep -Fq "$value" "$CONTRACT"; then
    echo "FAIL: CopyContract.$name not in contract: $value" >&2
    fail=1
  fi
done < "$COPY_SWIFT"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "copy_contract_diff.sh: OK"
