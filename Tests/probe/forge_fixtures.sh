#!/usr/bin/env bash
# Forge camera-data edge-case folders from a handful of real ARWs.
#
#   LUMINA_CARD_DIR=/Volumes/Untitled/DCIM/101MSDCF bash Tests/probe/forge_fixtures.sh
#
# The card is only read (12 files copied off it). Every edit happens on copies under
# $LUMINA_FIXTURE_ROOT (default ~/LuminaEvidence/fixtures), never in the repo: these are
# the user's photos.
#
#   bash Tests/probe/forge_fixtures.sh scale [N…]
#
# Scale fixtures (release task Q1, STRESS-MATRIX.md 1), synthetic only: no card, no photos. Under
# $LUMINA_SCALE_ROOT (default ~/LuminaEvidence/fixtures/scale):
#   folder-N/      N ARWs in one folder, for each N given (default 5000 10000): bursts of 5 one
#                  second apart, 2 min between bursts, a new row every 40 frames, across days
#   tree-200/      200 subfolders × 10 ARWs, plus a chain 16 folders deep with one ARW per level
#   junk-50000/    500 ARWs beside 50,000 files that are not ARWs (stubs, AppleDouble, sidecars of nothing)
#   recents/s001…s100   100 three-photo shoots, for the Open screen's recents
# Every ARW is a small TIFF (Make/Model, Orientation, DateTimeOriginal, exposure) around a camera-sized
# 1616 × 1080 detailed JPEG preview (24 distinct ones, drawn here, encoded by sips). ~0.5 MB each:
# check free space first (10,000 ≈ 5 GB). Delete the folders when done; keep this generator.
set -euo pipefail

if [[ ${1:-} == scale ]]; then
  shift
  SCALE="${LUMINA_SCALE_ROOT:-$HOME/LuminaEvidence/fixtures/scale}"
  sizes=("$@"); [[ ${#sizes[@]} -gt 0 ]] || sizes=(5000 10000)
  mkdir -p "$SCALE/jpegs"
  # 24 previews: a gradient sky, grass-like strokes, hairlines and text-like bars, so a soft or
  # over-compressed thumbnail shows. Drawn as BMP in Node, encoded to JPEG by sips (no npm packages).
  if [[ $(ls "$SCALE/jpegs" 2>/dev/null | grep -c '\.jpg$') -lt 24 ]]; then
    node - "$SCALE/jpegs" <<'EOF'
const fs = require('fs'), path = require('path'), dir = process.argv[2], W = 1616, H = 1080;
for (let i = 0; i < 24; i++) {
  const px = Buffer.alloc(W * H * 3);
  let s = i * 9301 + 49297; const rnd = () => (s = (s * 9301 + 49297) % 233280) / 233280;
  const hue = (i * 47) % 360, base = [Math.cos(hue / 57.3), Math.cos((hue - 120) / 57.3), Math.cos((hue + 120) / 57.3)].map(c => 0.5 + 0.35 * c);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const o = (y * W + x) * 3, g = 1 - 0.7 * y / H, n = (rnd() - 0.5) * 14;
    for (let c = 0; c < 3; c++) px[o + c] = Math.max(0, Math.min(255, base[c] * 255 * g + n));
  }
  for (let k = 0; k < 900; k++) {                       // strokes in the lower half
    const x0 = rnd() * W, y0 = H * 0.45 + rnd() * H * 0.55, len = rnd() * 140, dx = (rnd() - 0.5) * 18, v = rnd() * 200;
    for (let t = 0; t < len; t++) { const x = Math.round(x0 + dx * t / len), y = Math.round(y0 - t); if (x >= 0 && x < W && y >= 0 && y < H) { const o = (y * W + x) * 3; px[o] = v; px[o + 1] = 255 - v; px[o + 2] = v / 2; } }
  }
  for (let k = 0; k < 60; k++) for (let y = 40; y < 240; y++) for (let w = 0; w < 2; w++) { const o = (y * W + W - 300 + k * 4 + w) * 3; px.fill(k % 2 ? 0 : 255, o, o + 3); }
  for (let r = 0; r < 14; r++) for (let x = 40; x < 640; x++) if ((x * 7 + r * 13 + i) % 11 < 6) for (let y = 60 + r * 30; y < 76 + r * 30; y++) { const o = (y * W + x) * 3; px.fill(255, o, o + 3); }
  const bmp = Buffer.alloc(54 + W * H * 3);              // 24-bit BMP, bottom-up, BGR (W * 3 is a multiple of 4)
  bmp.write('BM', 0); bmp.writeUInt32LE(bmp.length, 2); bmp.writeUInt32LE(54, 10); bmp.writeUInt32LE(40, 14);
  bmp.writeInt32LE(W, 18); bmp.writeInt32LE(H, 22); bmp.writeUInt16LE(1, 26); bmp.writeUInt16LE(24, 28); bmp.writeUInt32LE(W * H * 3, 34);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const s0 = (y * W + x) * 3, d = 54 + ((H - 1 - y) * W + x) * 3; bmp[d] = px[s0 + 2]; bmp[d + 1] = px[s0 + 1]; bmp[d + 2] = px[s0]; }
  fs.writeFileSync(path.join(dir, `p${String(i).padStart(2, '0')}.bmp`), bmp);
}
EOF
    for b in "$SCALE"/jpegs/*.bmp; do sips -s format jpeg -s formatOptions 85 "$b" --out "${b%.bmp}.jpg" >/dev/null && rm -f "$b"; done
  fi
  # The ARWs. node <root> <spec…>; a spec is kind:dir:arg.
  arws() {
    node - "$SCALE" "$@" <<'EOF'
const fs = require('fs'), path = require('path'), [root, ...specs] = process.argv.slice(2);
const jpegs = fs.readdirSync(path.join(root, 'jpegs')).filter(f => f.endsWith('.jpg')).sort().map(f => fs.readFileSync(path.join(root, 'jpegs', f)));
// The TIFF of Tests/web/lib.mjs tiff(): IFD0 Make/Model, Orientation, JPEG offset + length, Exif IFD; Exif: exposure, ISO, date, focal length.
function tiff({ date, orient = 1, jpeg, model = 'ILCE-7M4' }) {
  const buf = Buffer.alloc(4096 + jpeg.length + 16);
  buf.write('II', 0); buf.writeUInt16LE(42, 2); buf.writeUInt32LE(8, 4);
  const ifd0 = 8, n0 = 5, exif = ifd0 + 2 + n0 * 12 + 4, n1 = 4; let dp = exif + 2 + n1 * 12 + 4;
  const put = s => { const o = dp; buf.write(s + '\0', o, 'latin1'); dp += s.length + 1; if (dp % 2) dp++; return o; };
  const rat = ([a, b]) => { const o = dp; buf.writeUInt32LE(a, o); buf.writeUInt32LE(b, o + 4); dp += 8; return o; };
  const ent = (base, i, tag, type, cnt, val) => { const e = base + 2 + i * 12; buf.writeUInt16LE(tag, e); buf.writeUInt16LE(type, e + 2); buf.writeUInt32LE(cnt, e + 4); if (type === 3 && cnt === 1) buf.writeUInt16LE(val, e + 8); else buf.writeUInt32LE(val, e + 8); };
  const mo = put(model), dto = put(date), eo = rat([1, 250]), fo = rat([50, 1]);
  buf.writeUInt16LE(n0, ifd0);
  ent(ifd0, 0, 0x0110, 2, model.length + 1, mo); ent(ifd0, 1, 0x0112, 3, 1, orient);
  ent(ifd0, 2, 0x0201, 4, 1, 4096); ent(ifd0, 3, 0x0202, 4, 1, jpeg.length); ent(ifd0, 4, 0x8769, 4, 1, exif);
  buf.writeUInt16LE(n1, exif);
  ent(exif, 0, 0x829A, 5, 1, eo); ent(exif, 1, 0x8827, 3, 1, 400); ent(exif, 2, 0x9003, 2, date.length + 1, dto); ent(exif, 3, 0x920A, 5, 1, fo);
  jpeg.copy(buf, 4096);
  return buf;
}
let clock = Date.UTC(2026, 8, 1, 9, 0, 0) / 1000, k = 0;     // one camera clock across every folder made in this run
const stamp = t => new Date(t * 1000).toISOString().replace('T', ' ').slice(0, 19).replace(/-/g, ':');
function shoot(dir, n, first = 10001) {
  fs.mkdirSync(dir, { recursive: true });
  for (let i = 0; i < n; i++, k++) {
    clock += i % 40 === 0 && i ? 20 * 60 : i % 5 === 0 ? 120 : 1;
    if (stamp(clock).slice(11) > '19:00:00') clock += 14 * 3600;   // the evening ends; the next day starts at 9
    fs.writeFileSync(path.join(dir, 'DSC' + String(first + i).padStart(5, '0') + '.ARW'), tiff({ date: stamp(clock), jpeg: jpegs[k % jpegs.length], orient: k % 23 === 7 ? 6 : 1 }));
  }
}
const fresh = d => { fs.rmSync(d, { recursive: true, force: true }); fs.mkdirSync(d, { recursive: true }); return d; };
for (const spec of specs) {
  const [kind, name, arg] = spec.split(':'), d = fresh(path.join(root, name));
  if (kind === 'folder') shoot(d, +arg);
  if (kind === 'tree') {
    for (let s = 0; s < 200; s++) shoot(path.join(d, 'set' + String(s + 1).padStart(3, '0')), 10, 10001 + s * 10);
    let deep = path.join(d, 'deep');
    for (let l = 1; l <= 16; l++) { deep = path.join(deep, 'level' + String(l).padStart(2, '0')); shoot(deep, 1, 30000 + l); }
  }
  if (kind === 'junk') {
    shoot(d, 500);
    const ext = ['txt', 'dat', 'THM', 'MP4', 'XML', 'CR3', 'json', 'bin'];
    for (let i = 0; i < 50000; i++) {
      const n = i % 10 === 9 ? `._DSC9${String(i).padStart(5, '0')}.ARW` : `file${String(i).padStart(5, '0')}.${ext[i % ext.length]}`;
      fs.writeFileSync(path.join(d, n), i % 10 === 9 ? Buffer.from([0, 5, 22, 7]) : 'x');
    }
  }
  if (kind === 'recents') for (let s = 1; s <= +arg; s++) shoot(path.join(d, 's' + String(s).padStart(3, '0')), 3);
  fs.writeFileSync(path.join(d, '.done'), new Date().toISOString());
  console.log(`  ${name}`);
}
EOF
  }
  specs=(); for n in "${sizes[@]}"; do specs+=("folder:folder-$n:$n"); done
  [[ -n ${LUMINA_SCALE_ONLY_FOLDERS:-} ]] || specs+=("tree:tree-200:" "junk:junk-50000:" "recents:recents:100")
  echo "scale fixtures in $SCALE:"; arws "${specs[@]}"
  du -sh "$SCALE" | sed 's/^/  total /'
  exit 0
fi

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
  # lr-sidecar-both: one RAW with both DSC….xmp (Lightroom's) and DSC….XMP (the same packet at 1★
  # Yellow, as another app might leave it). A case-insensitive disk can't hold both names, so the
  # upper-case one is stored as DSC….upper.XMP; app-xmp-both renames it on a case-sensitive image.
  first=$(ls "$d" | grep '\.xmp$' | head -1); stem="${first%.*}"
  b=$(fresh lr-sidecar-both)
  cp -c "$d/$stem.ARW" "$b/" 2>/dev/null || cp "$d/$stem.ARW" "$b/"
  cp "$d/$stem.xmp" "$b/$stem.xmp"
  sed 's|^\( *\)xmp:CreatorTool=\(.*\)$|\1xmp:CreatorTool=\2\
\1xmp:Rating="1"\
\1xmp:Label="Yellow"|' "$d/$stem.xmp" > "$b/$stem.upper.XMP"
fi

echo "fixtures in $ROOT:"; for c in two-bodies dup-dsc orientation corrupt-preview junk-in-folder burst-10fps tz-jump shutter-bracket lr-sidecar lr-sidecar-both; do
  printf '  %-16s %s files\n' "$c" "$(find "$ROOT/$c" -type f | wc -l | tr -d ' ')"; done
