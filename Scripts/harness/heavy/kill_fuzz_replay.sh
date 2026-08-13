#!/bin/bash
# HEAVY/CP2 — kill-fuzz replay delegates to F06 full corpus.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
exec python3 "$ROOT/Scripts/harness/cp2/f06_data_safety.py" --full
