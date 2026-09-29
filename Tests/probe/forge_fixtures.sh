#!/usr/bin/env bash
# Forge camera-data edge-case folders from a handful of real ARWs.
#
#   LUMINA_CARD_DIR=/Volumes/Untitled/DCIM/101MSDCF bash Tests/probe/forge_fixtures.sh
#
# The card is only read (12 files copied off it). Every edit happens on copies under
# $LUMINA_FIXTURE_ROOT (default ~/LuminaEvidence/fixtures), never in the repo: these are
# the user's photos.
set -euo pipefail

SRC_DIR="${LUMINA_CARD_DIR:?set LUMINA_CARD_DIR to a folder of Sony ARWs}"
ROOT="${LUMINA_FIXTURE_ROOT:-$HOME/LuminaEvidence/fixtures}"
EXIF="$(command -v exiftool || ls /opt/homebrew/bin/exiftool /usr/local/bin/exiftool 2>/dev/null | head -1)"
[[ -x "$EXIF" ]] || { echo "exiftool not found" >&2; exit 2; }
ex() { "$EXIF" -q -q -overwrite_original "$@"; }

mkdir -p "$ROOT/src"
# 12 real frames, copied once. Skip AppleDouble stubs.
ls "$SRC_DIR" | grep -v '^\._' | grep -i '\.arw$' | head -12 | while read -r f; do
  [[ -f "$ROOT/src/$f" ]] || cp "$SRC_DIR/$f" "$ROOT/src/$f"
done

SRC=($(ls "$ROOT/src" | grep -i "\.arw$" | sort))
fresh() { rm -rf "$ROOT/$1"; mkdir -p "$ROOT/$1"; echo "$ROOT/$1"; }
put() { cp -c "$ROOT/src/$1" "$2" 2>/dev/null || cp "$ROOT/src/$1" "$2"; }   # APFS clone when possible
stamp() { ex "-DateTimeOriginal=$2" "-CreateDate=$2" "$1"; }

# two-bodies: A and B interleave in time; B's file numbers restart at 1.
d=$(fresh two-bodies)
for i in 0 1 2; do
  put "${SRC[$i]}" "$d/A_DSC0000$((i+1)).ARW"; ex -SerialNumber=1111111 "$d/A_DSC0000$((i+1)).ARW"
  stamp "$d/A_DSC0000$((i+1)).ARW" "2026:09:08 10:0$((i*2)):10"
  put "${SRC[$((i+3))]}" "$d/B_DSC0000$((i+1)).ARW"; ex -SerialNumber=2222222 "$d/B_DSC0000$((i+1)).ARW"
  stamp "$d/B_DSC0000$((i+1)).ARW" "2026:09:08 10:0$((i*2+1)):10"
done

# dup-dsc: counter reset — the same DSC name in two folders, different pictures.
d=$(fresh dup-dsc); mkdir -p "$d/100MSDCF" "$d/101MSDCF"
put "${SRC[0]}" "$d/100MSDCF/DSC00001.ARW"; stamp "$d/100MSDCF/DSC00001.ARW" "2026:09:07 09:00:00"
put "${SRC[1]}" "$d/101MSDCF/DSC00001.ARW"; stamp "$d/101MSDCF/DSC00001.ARW" "2026:09:08 09:00:00"

# orientation: 1, 3, 6, 8 and missing.
d=$(fresh orientation); n=0
for o in 1 3 6 8 none; do
  f="$d/DSC0010$n.ARW"; put "${SRC[$n]}" "$f"
  if [[ $o == none ]]; then ex -Orientation= -IFD0:Orientation= -IFD1:Orientation= "$f"; else ex "-IFD0:Orientation#=$o" "$f"; fi
  stamp "$f" "2026:09:08 11:0$n:00"; n=$((n+1))
done

# corrupt-preview: preview truncated, preview zeroed, file cut inside the header, zero-byte file.
d=$(fresh corrupt-preview)
put "${SRC[0]}" "$d/DSC00200.ARW"                                   # control, intact
put "${SRC[1]}" "$d/DSC00201.ARW"; truncate -s 300000 "$d/DSC00201.ARW"   # preview cut short
put "${SRC[2]}" "$d/DSC00202.ARW"; truncate -s 4096 "$d/DSC00202.ARW"     # header only
: > "$d/DSC00203.ARW"                                                 # empty
put "${SRC[3]}" "$d/DSC00204.ARW"
off=$("$EXIF" -s3 -PreviewImageStart "$d/DSC00204.ARW" 2>/dev/null || echo "")
len=$("$EXIF" -s3 -PreviewImageLength "$d/DSC00204.ARW" 2>/dev/null || echo "")
if [[ -n "$off" && -n "$len" ]]; then
  dd if=/dev/zero of="$d/DSC00204.ARW" bs=1 seek="$off" count="$len" conv=notrunc status=none   # preview bytes zeroed
fi

# junk-in-folder: ARW + JPEG pair, non-Sony files, AppleDouble stubs, a hidden file.
d=$(fresh junk-in-folder)
put "${SRC[0]}" "$d/DSC00300.ARW"; "$EXIF" -q -b -PreviewImage "$d/DSC00300.ARW" > "$d/DSC00300.JPG"
put "${SRC[1]}" "$d/DSC00301.ARW"
printf 'x' > "$d/IMG_0001.CR3"; printf 'x' > "$d/notes.txt"; printf 'x' > "$d/.DS_Store"
printf '\0\5\26\7' > "$d/._DSC00300.ARW"; printf '\0\5\26\7' > "$d/._DSC00301.ARW"

# burst-10fps: ten frames inside one second (EXIF has whole seconds only on the α7 III),
# then a single 1 s later and a single 3 s later.
d=$(fresh burst-10fps)
for i in $(seq 0 9); do f="$d/DSC004$(printf %02d $i).ARW"; put "${SRC[$i]}" "$f"; stamp "$f" "2026:09:08 12:00:00"; done
put "${SRC[10]}" "$d/DSC00410.ARW"; stamp "$d/DSC00410.ARW" "2026:09:08 12:00:01"
put "${SRC[11]}" "$d/DSC00411.ARW"; stamp "$d/DSC00411.ARW" "2026:09:08 12:00:04"

# tz-jump: camera clock moved −9 h mid-trip (later photos carry earlier times).
d=$(fresh tz-jump)
for i in 0 1 2; do f="$d/DSC0050$i.ARW"; put "${SRC[$i]}" "$f"; stamp "$f" "2026:09:08 18:0$i:00"; done
for i in 3 4 5; do f="$d/DSC0050$i.ARW"; put "${SRC[$i]}" "$f"; stamp "$f" "2026:09:08 09:1$i:00"; done

# shutter-bracket: three frames in one second, same EV comp (0), shutter 1/250 · 1/60 · 1/15.
d=$(fresh shutter-bracket); i=0
for ss in 1/250 1/60 1/15; do f="$d/DSC0060$i.ARW"; put "${SRC[$i]}" "$f"; stamp "$f" "2026:09:08 13:00:00"
  ex "-ExposureTime=$ss" -ExposureCompensation=0 "$f"; i=$((i+1)); done

# lr-sidecar: real Lightroom XMP next to its RAWs (checklist F6, gate 7). Needs Lightroom exports of
# RAWs you have: LUMINA_LR_EXPORT_DIR (JPEGs Lightroom exported, carrying crs:RawFileName) and
# LUMINA_LR_RAW_DIR (the matching ARWs). The XMP packet Lightroom embedded in each export is saved
# as the sidecar, wrapper stripped, bytes otherwise as Lightroom wrote them:
#   first  → DSC….xmp (lower case), second → DSC….XMP (upper case, and given a 2★ Red rating so
#   the merge has something to replace), third → no sidecar.
if [[ -n "${LUMINA_LR_EXPORT_DIR:-}" && -n "${LUMINA_LR_RAW_DIR:-}" ]]; then
  d=$(fresh lr-sidecar); n=0
  for jpg in $(ls "$LUMINA_LR_EXPORT_DIR" | grep -i '\.jpg$' | sort); do
    raw=$("$EXIF" -s3 -RawFileName "$LUMINA_LR_EXPORT_DIR/$jpg"); stem="${raw%.*}"
    [[ -n "$raw" && -f "$LUMINA_LR_RAW_DIR/$raw" ]] || continue
    "$EXIF" -xmp -b "$LUMINA_LR_EXPORT_DIR/$jpg" | grep -q 'crs:ProcessVersion' || continue
    cp -c "$LUMINA_LR_RAW_DIR/$raw" "$d/$raw" 2>/dev/null || cp "$LUMINA_LR_RAW_DIR/$raw" "$d/$raw"
    case $n in
      0) "$EXIF" -xmp -b "$LUMINA_LR_EXPORT_DIR/$jpg" | sed -e '/^<?xpacket/d' -e '/^ *$/d' > "$d/$stem.xmp" ;;
      1) # Rating and label added the way Lightroom writes them (attributes after CreatorTool);
         # exiftool would re-serialise the whole file and it would no longer be Lightroom's bytes.
         "$EXIF" -xmp -b "$LUMINA_LR_EXPORT_DIR/$jpg" | sed -e '/^<?xpacket/d' -e '/^ *$/d' \
           -e 's|^\( *\)xmp:CreatorTool=\(.*\)$|\1xmp:CreatorTool=\2\
\1xmp:Rating="2"\
\1xmp:Label="Red"|' > "$d/$stem.XMP" ;;
    esac
    n=$((n+1)); [[ $n == 3 ]] && break
  done
  mkdir -p "$d.orig" && rm -f "$d.orig"/* && cp "$d"/*.[xX][mM][pP] "$d.orig/"   # pristine sidecars to compare against
fi

echo "fixtures in $ROOT:"; for c in two-bodies dup-dsc orientation corrupt-preview junk-in-folder burst-10fps tz-jump shutter-bracket lr-sidecar; do
  printf '  %-16s %s files\n' "$c" "$(find "$ROOT/$c" -type f | wc -l | tr -d ' ')"; done
