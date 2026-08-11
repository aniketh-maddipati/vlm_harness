#!/usr/bin/env bash
# D40 quarantine lint (CQ.2) — permanent.
#
# Legacy/  is the D40 quarantine. It may only shrink.
#   * a reference to a Legacy/-owned symbol from outside Legacy/ that is not in
#     the frozen seam baseline                                     -> FAIL
#   * a NEW file under Legacy/                                     -> FAIL
#   * a public/open declaration under Legacy/ or Salvage/          -> FAIL
#   * a Legacy//Salvage/ source without its quarantine banner      -> FAIL
#
# Salvage/ is grouping-only salvage (D40: EmbeddingService + burst grouping,
# ExifToolService). Callers may use the grouping API; the taste/scoring
# re-entry primitives are deny-listed by symbol name and ratcheted to zero.
#
#   Scripts/lint/quarantine_d40.sh             # check (FAST lane)
#   Scripts/lint/quarantine_d40.sh --refresh   # rewrite baselines after a
#                                              # checkpoint retires a slice
#
# Contract: design/contract-v6.md D40 · design/checkpoint-sequence-v6.md
set -uo pipefail
# Byte ordering everywhere: sort and comm must agree or the seam diff is noise.
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

REFRESH=0
[[ "${1:-}" == "--refresh" ]] && REFRESH=1

BASE="$ROOT/Scripts/lint/baseline"
SEAM="$BASE/quarantine_seam.baseline"
MANIFEST="$BASE/legacy_manifest.baseline"
SALVAGE_SEAM="$BASE/salvage_seam.baseline"
OWNERS="$BASE/quarantine_owners.tsv"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

[[ -d Legacy ]] || { echo "FAIL: Legacy/ quarantine root is missing" >&2; exit 1; }
[[ -d Salvage ]] || { echo "FAIL: Salvage/ root is missing" >&2; exit 1; }
mkdir -p "$BASE"

# owner_for <path> — longest matching prefix from quarantine_owners.tsv
owner_for() {
  awk -v p="$1" -F'\t' '
    !/^#/ && NF==2 && index(p, $1)==1 && length($1) > best { best=length($1); own=$2 }
    END { print own }
  ' "$OWNERS"
}

# ==========================================================================
# Collect current facts
# ==========================================================================

# --- Legacy file manifest ---
find Legacy -name '*.swift' | LC_ALL=C sort > "$TMP/legacy_now.txt"

# --- symbols the quarantine alone owns ---
type_names() {
  grep -rhE '^(@[A-Za-z_]+[[:space:]]+)*(final[[:space:]]+)?(struct|class|enum|protocol|actor)[[:space:]]+[A-Za-z_]' \
    "$@" --include='*.swift' 2>/dev/null \
    | sed -E 's/^.*(struct|class|enum|protocol|actor)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
    | LC_ALL=C sort -u
}
type_names Legacy > "$TMP/legacy_symbols.txt"
type_names Lumina Salvage DesignTokens > "$TMP/outside_symbols.txt"
# A name declared on both sides is ambiguous; the seam is about names the
# quarantine alone owns.
comm -23 "$TMP/legacy_symbols.txt" "$TMP/outside_symbols.txt" > "$TMP/owned.txt"

# --- references to those symbols from outside Legacy/ (comments stripped) ---
: > "$TMP/refs.txt"
if [[ -s "$TMP/owned.txt" ]]; then
  while IFS= read -r f; do
    sed -E 's@//.*@@' "$f" > "$TMP/stripped.swift"
    grep -onwF -f "$TMP/owned.txt" "$TMP/stripped.swift" 2>/dev/null \
      | sed -E 's@^[0-9]+:@@' | LC_ALL=C sort -u | sed "s@^@$f\t@" >> "$TMP/refs.txt"
  done < <(find Lumina Salvage DesignTokens -name '*.swift')
fi
LC_ALL=C sort -u "$TMP/refs.txt" -o "$TMP/refs.txt"

# --- Salvage: grouping API vs taste/scoring re-entry primitives ---
SALVAGE_ALLOW=(embedAndCluster batchCaptureDates extractPreview isAvailable
               captureDates runDataPublic)
SALVAGE_DENY=(embed l2Distance buildProfile)

: > "$TMP/salvage_refs.txt"
for sym in "${SALVAGE_DENY[@]}"; do
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    printf '%s\t%s\n' "${hit%%:*}" "$sym" >> "$TMP/salvage_refs.txt"
  done < <(grep -rlE "(EmbeddingService|ExifToolService)\.${sym}\b" \
             Lumina Legacy --include='*.swift' 2>/dev/null | sed 's/$/:/')
done
LC_ALL=C sort -u "$TMP/salvage_refs.txt" -o "$TMP/salvage_refs.txt"

# ==========================================================================
# Refresh mode — freeze current facts as the new (smaller) baselines
# ==========================================================================
if [[ "$REFRESH" -eq 1 ]]; then
  [[ -f "$OWNERS" ]] || { echo "FAIL: missing $OWNERS" >&2; exit 1; }

  {
    echo "# Frozen Legacy/ file manifest — the D40 quarantine may only shrink."
    echo "# Regenerate after a checkpoint retires a slice:"
    echo "#   Scripts/lint/quarantine_d40.sh --refresh"
    echo "# $(wc -l < "$TMP/legacy_now.txt") files under quarantine."
    cat "$TMP/legacy_now.txt"
  } > "$MANIFEST"

  {
    echo "# P0 -> Legacy/ seam, frozen at checkpoint CQ. Each edge is a real compile"
    echo "# dependency of the live path on a quarantined symbol, owned by the"
    echo "# checkpoint that retires it (design/checkpoint-sequence-v6.md)."
    echo "# New edges FAIL. Edges may only be cut."
    echo "#"
    printf "# file\tsymbol\towner\n"
    while IFS=$'\t' read -r f s; do
      [[ -z "$f" ]] && continue
      printf '%s\t%s\t%s\n' "$f" "$s" "$(owner_for "$f")"
    done < "$TMP/refs.txt"
  } > "$SEAM"

  {
    echo "# Salvage/ deny-list seam — callers reaching a taste/scoring re-entry"
    echo "# primitive of a salvaged service. D40 salvages EmbeddingService for"
    echo "# grouping only; these edges ratchet to zero."
    echo "#"
    printf "# file\tsymbol\towner\n"
    while IFS=$'\t' read -r f s; do
      [[ -z "$f" ]] && continue
      printf '%s\t%s\t%s\n' "$f" "$s" "$(owner_for "$f")"
    done < "$TMP/salvage_refs.txt"
  } > "$SALVAGE_SEAM"

  echo "quarantine baselines refreshed:"
  echo "  legacy files : $(wc -l < "$TMP/legacy_now.txt")"
  echo "  seam edges   : $(wc -l < "$TMP/refs.txt")"
  echo "  salvage edges: $(wc -l < "$TMP/salvage_refs.txt")"
  # An unowned row is unowned debt.
  if grep -qP '\t$' "$SEAM" "$SALVAGE_SEAM"; then
    echo "FAIL: baseline rows without a checkpoint owner (add a rule to $OWNERS)" >&2
    grep -nP '\t$' "$SEAM" "$SALVAGE_SEAM" >&2
    exit 1
  fi
  exit 0
fi

# ==========================================================================
# Check mode
# ==========================================================================

# 1. Legacy/ may not grow.
if [[ -f "$MANIFEST" ]]; then
  grep -v '^#' "$MANIFEST" | grep -v '^$' | LC_ALL=C sort > "$TMP/legacy_was.txt"
  while IFS= read -r f; do
    [[ -n "$f" ]] && report "NEW file under Legacy/: $f — the quarantine may only shrink (D40)"
  done < <(comm -23 "$TMP/legacy_now.txt" "$TMP/legacy_was.txt")
  retired="$(comm -13 "$TMP/legacy_now.txt" "$TMP/legacy_was.txt" | wc -l)"
  [[ "$retired" -gt 0 ]] && \
    echo "quarantine: $retired legacy file(s) retired since the baseline — run --refresh to reap"
else
  report "missing $MANIFEST"
fi

# 2. No public/open surface under quarantine; every file wears its banner.
while IFS= read -r hit; do
  [[ -n "$hit" ]] && report "public/open declaration under quarantine: $hit"
done < <(grep -rnE '^[[:space:]]*(public|open) ' Legacy Salvage --include='*.swift' 2>/dev/null)

while IFS= read -r f; do
  head -1 "$f" | grep -qE '^// (QUARANTINED|SALVAGE)\(D40\)' || \
    report "missing // QUARANTINED(D40) banner: $f"
done < <(find Legacy Salvage -name '*.swift')

# 3. Seam: no new references into the quarantine.
if [[ -f "$SEAM" ]]; then
  grep -v '^#' "$SEAM" | grep -v '^$' > "$TMP/seam_rows.txt"
  cut -f1,2 "$TMP/seam_rows.txt" | LC_ALL=C sort -u > "$TMP/seam_was.txt"
  while IFS=$'\t' read -r sf ss so; do
    [[ -z "${so:-}" ]] && report "seam row without a checkpoint owner: $sf -> $ss"
  done < "$TMP/seam_rows.txt"

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    report "reference to quarantined symbol '${row#*$'\t'}' from outside Legacy/: ${row%%$'\t'*} (D40)"
  done < <(comm -23 "$TMP/refs.txt" "$TMP/seam_was.txt")

  cut="$(comm -13 "$TMP/refs.txt" "$TMP/seam_was.txt" | wc -l)"
  [[ "$cut" -gt 0 ]] && \
    echo "quarantine: $cut seam edge(s) cut since the baseline — run --refresh to reap"
else
  report "missing $SEAM"
fi

# 4. Salvage: grouping only.
if [[ -f "$SALVAGE_SEAM" ]]; then
  grep -v '^#' "$SALVAGE_SEAM" | grep -v '^$' > "$TMP/salv_rows.txt"
  cut -f1,2 "$TMP/salv_rows.txt" | LC_ALL=C sort -u > "$TMP/salvage_was.txt"
  while IFS=$'\t' read -r sf ss so; do
    [[ -z "${so:-}" ]] && report "salvage seam row without an owner: $sf -> $ss"
  done < "$TMP/salv_rows.txt"

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    report "salvage scoring/judging entry point '${row#*$'\t'}' used in ${row%%$'\t'*} — Salvage/ is grouping-only (D40)"
  done < <(comm -23 "$TMP/salvage_refs.txt" "$TMP/salvage_was.txt")
else
  report "missing $SALVAGE_SEAM"
fi

# 5. No unreviewed salvage API may appear.
KNOWN="$(printf '%s\n' "${SALVAGE_ALLOW[@]}" "${SALVAGE_DENY[@]}" | paste -sd'|' -)"
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  sym="${hit##*.}"
  grep -qxE "$KNOWN" <<< "$sym" || \
    report "unreviewed salvage API '.$sym' — Salvage/ exposes a grouping surface only (D40)"
done < <(grep -rhoE "(EmbeddingService|ExifToolService)\.[A-Za-z_][A-Za-z0-9_]*" \
           Lumina Legacy --include='*.swift' 2>/dev/null | LC_ALL=C sort -u)

if [[ "$fail" -ne 0 ]]; then
  echo "" >&2
  echo "The D40 quarantine may only shrink. When a checkpoint retires a slice," >&2
  echo "delete it and re-run: Scripts/lint/quarantine_d40.sh --refresh" >&2
  exit 1
fi

echo "quarantine_d40.sh: OK"
