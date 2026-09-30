#!/usr/bin/env bash
# Real Sony ARWs for machines without a card (CI): up to N files from raw.pixls.us, a public CC0
# archive of camera raw samples, into <dest>/src — the layout forge_fixtures.sh makes, so
# `LUMINA_FIXTURE_ROOT=<dest> bash Scripts/probe.sh scroll` builds its scroll folder from them.
# Never into the repo. Exits 1 if fewer than 4 usable files came down.
#
#   bash Tests/probe/fetch_public_arws.sh <dest> [N=12]
set -uo pipefail
dest="${1:?dest}"; want="${2:-12}"; mkdir -p "$dest/src"
BASE=https://raw.pixls.us/data/Sony
MODELS=(ILCE-7M4 ILCE-7M3 ILCE-7RM4 ILCE-7C ILCE-1 ILCE-9 ILCE-6400 ILCE-7SM3)
got=$(ls "$dest/src" | grep -ci '\.arw$' || true)
for m in "${MODELS[@]}"; do
  (( got >= want )) && break
  # The listing's links, URL-encoded names ending in .ARW (any case).
  for href in $(curl -fsSL --retry 2 -m 60 "$BASE/$m/" | grep -oiE 'href="[^"?]+\.arw"' | sed -E 's/^href="//; s/"$//' | head -3); do
    (( got >= want )) && break
    url="$href"; [[ $url == http* ]] || url="$BASE/$m/${href##*/}"
    out="$dest/src/${m}_$(printf %02d "$got").ARW"
    if curl -fsSL --retry 2 -m 300 -o "$out" "$url" && [[ $(head -c 2 "$out") == "II" || $(head -c 2 "$out") == "MM" ]]; then
      echo "  $m ← ${url##*/} ($(( $(wc -c < "$out") / 1048576 )) MB)"; got=$((got + 1))
    else
      rm -f "$out"; echo "  $m: ${url##*/} failed" >&2
    fi
  done
done
echo "$got real ARWs in $dest/src"
(( got >= 4 ))
