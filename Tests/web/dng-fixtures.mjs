// Synthetic phone-DNG fixtures for LuminaCore.parseHead / phoneOf. Built in memory, no photo anywhere:
// every preview is a JPEG drawn here from flat 8×8 blocks (a few hundred bytes), every raw is stand-in bytes.
// The TIFF containers are real (header, IFDs, SubIFDs, Exif IFD, DNGVersion, strip / JPEG pointers).
//
//   import {fixtures} from './dng-fixtures.mjs'
//   fixtures() → [{id, name, bytes: Uint8Array, expect}]   (fresh bytes on every call)
//
// Layouts, per family (what each is based on, and how sure):
// - iPhone ProRAW (Apple / iPhone 15 Pro), little-endian, DNG 1.6: IFD0 is a small reduced-resolution
//   JPEG thumbnail (one strip, NewSubfileType 1), SubIFD 0 the raw (NewSubfileType 0), SubIFD 1 the larger
//   JPEG preview (NewSubfileType 1), SubIFD 2 a semantic-mask stand-in (NewSubfileType 4). The preview in a
//   SubIFD is what PACK-2 asks for; the thumbnail/raw/mask arrangement is from memory of exiftool dumps of
//   ProRAW files, medium confidence. Real ProRAW tiles the raw (TileOffsets); here it is one lossless-JPEG
//   strip on purpose, larger than the preview and starting FF D8, so the NewSubfileType check is what keeps
//   it out of the preview pick.
// - Pixel (Google / Pixel 8 Pro), little-endian: IFD0 is the reduced-resolution preview as one JPEG strip
//   (NewSubfileType 1, Compression 7), SubIFD 0 the uncompressed CFA raw. Based on memory of Android's
//   DngCreator (frameworks/base android_hardware_camera2_DngCreator.cpp: thumbnail in IFD0, raw in one
//   SubIFD) and of exiftool dumps of Google Camera DNGs showing a preview in IFD0. No network to check:
//   confidence medium for "IFD0 + SubIFD", low for the compression. DngCreator itself writes that IFD0
//   thumbnail as uncompressed 8-bit RGB, not JPEG; `pixel-rgb-thumb` is that variant (no JPEG anywhere).
// - Sony ARW control (SONY / ILCE-7M4), little-endian, no DNGVersion: preview through JPEGInterchangeFormat
//   in IFD0, a 160×120-style thumbnail the same way in IFD1, raw in a SubIFD. Matches ARW 2.3 as exiftool
//   shows it; high confidence for the pointers, the sizes are synthetic.
// - Sony DNG (SONY / ILCE-7M4 through a DNG converter), big-endian: IFD0 an uncompressed RGB thumbnail,
//   SubIFD 0 the raw, SubIFD 1 the JPEG preview. Adobe DNG Converter's layout as I remember it (MM byte
//   order, 256 px RGB thumbnail in IFD0, preview in SubIFD 1); medium-high confidence.

const PAGE_HEAD = 262144;

// ---- a tiny baseline JPEG: greyscale, W×H multiple of 8, each 8×8 block flat (DC only) -------------------
// Standard luminance DC table (ITU T.81 K.3); the AC table holds one code, "0" = EOB.
const DC_BITS = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], DC_VALS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
function dcCodes() { const codes = {}; let code = 0, k = 0; for (let len = 1; len <= 16; len++) { for (let i = 0; i < DC_BITS[len - 1]; i++) codes[DC_VALS[k++]] = [code++, len]; code <<= 1; } return codes; }

export function drawJpeg(w, h, shade) {
  const out = [], seg = (marker, body) => { out.push(0xFF, marker, (body.length + 2) >> 8, (body.length + 2) & 255, ...body); };
  out.push(0xFF, 0xD8);
  seg(0xDB, [0x00, ...new Array(64).fill(8)]);
  seg(0xC0, [8, h >> 8, h & 255, w >> 8, w & 255, 1, 1, 0x11, 0]);
  seg(0xC4, [0x00, ...DC_BITS, ...DC_VALS]);
  seg(0xC4, [0x10, 1, ...new Array(15).fill(0), 0x00]);
  seg(0xDA, [1, 1, 0x00, 0, 63, 0]);
  const C = dcCodes(); let acc = 0, nb = 0, prev = 0; const bits = (v, n) => { for (let i = n - 1; i >= 0; i--) { acc = (acc << 1) | ((v >> i) & 1); if (++nb === 8) { out.push(acc); if (acc === 0xFF) out.push(0); acc = 0; nb = 0; } } };
  for (let by = 0; by < h / 8; by++) for (let bx = 0; bx < w / 8; bx++) {
    const s = Math.max(0, Math.min(255, Math.round(shade(bx, by)))) - 128, diff = s - prev; prev = s;
    const cat = diff === 0 ? 0 : 32 - Math.clz32(Math.abs(diff)); bits(C[cat][0], C[cat][1]);
    if (cat) bits(diff < 0 ? diff - 1 + (1 << cat) : diff, cat);
    bits(0, 1);
  }
  if (nb) bits((1 << (8 - nb)) - 1, 8 - nb);
  out.push(0xFF, 0xD9);
  return Uint8Array.from(out);
}

// ---- a TIFF writer: IFD chains, SubIFDs, an Exif IFD, blobs placed at a minimum offset ----------------------
// An IFD is {entries: [[tag, type, value]], subs: [IFD], exif: IFD, next: IFD}. value: string (ASCII),
// number[] (BYTE/SHORT/LONG), [n, d][] (RATIONAL/SRATIONAL), {blob: name} or {len: name} (offset / length of a blob).
const T = { BYTE: 1, ASCII: 2, SHORT: 3, LONG: 4, RATIONAL: 5, UNDEFINED: 7, SRATIONAL: 10 };
const SIZE = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 10: 8 };

export function buildTiff({ le, ifd0, blobs, blobAt = {} }) {
  const order = [], walk = d => { if (!d || order.includes(d)) return; order.push(d); (d.subs || []).forEach(walk); walk(d.exif); walk(d.next); }; walk(ifd0);
  const full = d => { const e = [...d.entries]; if (d.subs && d.subs.length) e.push([0x014A, T.LONG, { subs: d.subs }]); if (d.exif) e.push([0x8769, T.LONG, { ifd: d.exif }]); return e.sort((a, b) => a[0] - b[0]); };
  const count = (type, v) => typeof v === 'string' ? v.length + 1 : v.subs ? v.subs.length : (v.blob || v.len || v.ifd) ? 1 : v.length;
  let off = 8; const at = new Map(), extra = new Map();
  for (const d of order) { const es = full(d); at.set(d, off); off += 2 + es.length * 12 + 4; let x = 0; for (const [, type, v] of es) { const n = SIZE[type] * count(type, v); if (n > 4) x += n + (n & 1); } extra.set(d, off); off += x; }
  const bo = {}; for (const [name, b] of Object.entries(blobs)) { off = Math.max(off, blobAt[name] || 0); off += off & 1; bo[name] = off; off += b.length; }
  const u8 = new Uint8Array(off), dv = new DataView(u8.buffer), w16 = (p, v) => dv.setUint16(p, v, le), w32 = (p, v) => dv.setUint32(p, v, le);
  u8.set(le ? [0x49, 0x49, 42, 0] : [0x4D, 0x4D, 0, 42]); w32(4, at.get(ifd0));
  const put = (p, type, vals) => { for (const v of vals) { if (type === T.SHORT) w16(p, v); else if (type === T.LONG) w32(p, v); else if (type === T.RATIONAL) { w32(p, v[0]); w32(p + 4, v[1]); } else if (type === T.SRATIONAL) { dv.setInt32(p, v[0], le); dv.setInt32(p + 4, v[1], le); } else u8[p] = v; p += SIZE[type]; } };
  for (const d of order) {
    const es = full(d); let p = at.get(d), x = extra.get(d); w16(p, es.length); p += 2;
    for (const [tag, type, v] of es) {
      const vals = typeof v === 'string' ? [...v].map(c => c.charCodeAt(0)).concat(0) : v.subs ? v.subs.map(s => at.get(s)) : v.ifd ? [at.get(v.ifd)] : v.blob ? [bo[v.blob]] : v.len ? [blobs[v.len].length] : v;
      const n = SIZE[type] * vals.length; w16(p, tag); w16(p + 2, type); w32(p + 4, vals.length);
      if (n > 4) { w32(p + 8, x); put(x, type, vals); x += n + (n & 1); } else put(p + 8, type, vals);
      p += 12;
    }
    w32(p, d.next ? at.get(d.next) : 0);
  }
  for (const [name, b] of Object.entries(blobs)) u8.set(b, bo[name]);
  return { bytes: u8, offsets: bo };
}

// ---- tags --------------------------------------------------------------------------------------------------
const strip = (nst, w, h, cmp, photometric, blob, spp = 1, bps = [8]) => [
  [0x00FE, T.LONG, [nst]], [0x0100, T.LONG, [w]], [0x0101, T.LONG, [h]], [0x0102, T.SHORT, bps], [0x0103, T.SHORT, [cmp]],
  [0x0106, T.SHORT, [photometric]], [0x0111, T.LONG, { blob }], [0x0115, T.SHORT, [spp]], [0x0116, T.LONG, [h]], [0x0117, T.LONG, { len: blob }]];
const camera = (make, model, orient) => [[0x010F, T.ASCII, make], [0x0110, T.ASCII, model], [0x0112, T.SHORT, [orient]]];
const dng = (version, unique) => [[0xC612, T.BYTE, version], [0xC613, T.BYTE, [1, 4, 0, 0]], [0xC614, T.ASCII, unique]];
const exif = ({ date, exp, fnum, iso, fl, fl35, lens, ev = [0, 1] }) => ({ entries: [
  [0x829A, T.RATIONAL, [exp]], [0x829D, T.RATIONAL, [fnum]], [0x8827, T.SHORT, [iso]], [0x9003, T.ASCII, date],
  [0x9204, T.SRATIONAL, [ev]], [0x920A, T.RATIONAL, [fl]], ...(fl35 ? [[0xA405, T.SHORT, [fl35]]] : []), ...(lens ? [[0xA434, T.ASCII, lens]] : [])] });
const lossless = n => { const b = new Uint8Array(n); b.set([0xFF, 0xD8, 0xFF, 0xC3]); b.set([0xFF, 0xD9], n - 2); return b; };
const cfa = n => { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = (i * 37) & 255; return b; };

// ---- fixtures ----------------------------------------------------------------------------------------------
function iphone({ name, id, date, fl, fl35, lens, previewAt = 0, orient = 6 }) {
  const thumb = drawJpeg(16, 16, (x, y) => 60 + 90 * x + 40 * y), preview = drawJpeg(64, 48, (x, y) => 30 + 25 * x + 12 * y), raw = lossless(4096), mask = lossless(600);
  const ifd0 = { entries: [...strip(1, 16, 16, 7, 6, 'thumb', 3, [8, 8, 8]), ...camera('Apple', 'iPhone 15 Pro', orient), [0x0131, T.ASCII, '18.0'], ...dng([1, 6, 0, 0], 'iPhone 15 Pro')],
    subs: [{ entries: strip(0, 64, 64, 7, 34892, 'raw', 3, [16, 16, 16]) },
      { entries: strip(1, 64, 48, 7, 6, 'preview', 3, [8, 8, 8]) },
      { entries: [...strip(4, 32, 32, 7, 52527, 'mask'), [0xCD2E, T.ASCII, 'Skin']] }],
    exif: exif({ date, exp: [1, 120], fnum: [178, 100], iso: 80, fl, fl35, lens }) };
  const { bytes, offsets } = buildTiff({ le: true, ifd0, blobs: { thumb, raw, mask, preview }, blobAt: { preview: previewAt } });
  return { id, name, bytes, preview, expect: { make: 'Apple', model: 'iPhone 15 Pro', dng: true, orient, date, fl35, preview: [offsets.preview, preview.length], phone: true } };
}

function pixel() {
  const date = '2026:09:12 18:07:02', preview = drawJpeg(48, 32, (x, y) => 200 - 20 * x - 10 * y), raw = cfa(64 * 48 * 2);
  const ifd0 = { entries: [...strip(1, 48, 32, 7, 6, 'preview', 3, [8, 8, 8]), ...camera('Google', 'Pixel 8 Pro', 1), [0x0131, T.ASCII, 'HDR+ 1.0.612345678zd'], ...dng([1, 4, 0, 0], 'Pixel 8 Pro')],
    subs: [{ entries: [...strip(0, 64, 48, 1, 32803, 'raw', 1, [16]), [0x828D, T.SHORT, [2, 2]], [0x828E, T.BYTE, [1, 0, 2, 1]]] }],
    exif: exif({ date, exp: [1, 250], fnum: [280, 100], iso: 50, fl: [1800, 100], fl35: 113 }) };
  const { bytes, offsets } = buildTiff({ le: true, ifd0, blobs: { preview, raw } });
  return { id: 'pixel', name: 'PXL_20260912_180702114.RAW-01.ORIGINAL.dng', bytes, preview, expect: { make: 'Google', model: 'Pixel 8 Pro', dng: true, orient: 1, date, fl35: 113, preview: [offsets.preview, preview.length], phone: true } };
}

function pixelRgbThumb() {
  const date = '2026:09:12 18:07:40', thumb = cfa(32 * 24 * 3), raw = cfa(64 * 48 * 2);
  const ifd0 = { entries: [...strip(1, 32, 24, 1, 2, 'thumb', 3, [8, 8, 8]), ...camera('Google', 'Pixel 8 Pro', 1), ...dng([1, 4, 0, 0], 'Pixel 8 Pro')],
    subs: [{ entries: [...strip(0, 64, 48, 1, 32803, 'raw', 1, [16]), [0x828D, T.SHORT, [2, 2]], [0x828E, T.BYTE, [1, 0, 2, 1]]] }],
    exif: exif({ date, exp: [1, 60], fnum: [168, 100], iso: 400, fl: [690, 100], fl35: 24 }) };
  return { id: 'pixel-rgb-thumb', name: 'PXL_20260912_180740520.dng', bytes: buildTiff({ le: true, ifd0, blobs: { thumb, raw } }).bytes, preview: null,
    expect: { make: 'Google', model: 'Pixel 8 Pro', dng: true, orient: 1, date, fl35: 24, preview: null, phone: true } };
}

function sonyArw() {
  const date = '2026:09:12 18:10:15', preview = drawJpeg(64, 40, (x, y) => (x + y) % 2 ? 220 : 40), thumb = drawJpeg(16, 8, () => 128), raw = cfa(64 * 48 * 2);
  const ifd1 = { entries: [[0x0103, T.SHORT, [6]], [0x0201, T.LONG, { blob: 'thumb' }], [0x0202, T.LONG, { len: 'thumb' }]] };
  const ifd0 = { entries: [[0x00FE, T.LONG, [1]], [0x0103, T.SHORT, [6]], ...camera('SONY', 'ILCE-7M4', 8), [0x0201, T.LONG, { blob: 'preview' }], [0x0202, T.LONG, { len: 'preview' }]],
    subs: [{ entries: [...strip(0, 64, 48, 32767, 32803, 'raw', 1, [14])] }],
    exif: exif({ date, exp: [1, 1000], fnum: [40, 10], iso: 400, fl: [850, 10], fl35: 85, lens: 'FE 85mm F1.8', ev: [-7, 10] }), next: ifd1 };
  const { bytes, offsets } = buildTiff({ le: true, ifd0, blobs: { preview, thumb, raw } });
  return { id: 'sony-arw', name: 'DSC01234.ARW', bytes, preview, expect: { make: 'SONY', model: 'ILCE-7M4', dng: undefined, orient: 8, date, fl35: 85, preview: [offsets.preview, preview.length], phone: false, lens: 'FE 85mm F1.8' } };
}

function sonyDng() {
  const date = '2026:09:12 18:11:30', thumb = cfa(32 * 21 * 3), preview = drawJpeg(56, 40, (x, y) => 90 + 15 * ((x * 3 + y) % 7)), raw = lossless(3000);
  const ifd0 = { entries: [...strip(1, 32, 21, 1, 2, 'thumb', 3, [8, 8, 8]), ...camera('SONY', 'ILCE-7M4', 1), [0x0131, T.ASCII, 'Adobe DNG Converter 16.0'], ...dng([1, 6, 0, 0], 'Sony ILCE-7M4')],
    subs: [{ entries: strip(0, 64, 48, 7, 32803, 'raw', 1, [16]) }, { entries: strip(1, 56, 40, 7, 6, 'preview', 3, [8, 8, 8]) }],
    exif: exif({ date, exp: [1, 500], fnum: [56, 10], iso: 200, fl: [350, 10], fl35: 35, lens: 'FE 35mm F1.4 GM' }) };
  const { bytes, offsets } = buildTiff({ le: false, ifd0, blobs: { thumb, raw, preview } });
  return { id: 'sony-dng', name: 'DSC05678.DNG', bytes, preview, expect: { make: 'SONY', model: 'ILCE-7M4', dng: true, orient: 1, date, fl35: 35, preview: [offsets.preview, preview.length], phone: false, lens: 'FE 35mm F1.4 GM' } };
}

function truncated() {
  const whole = iphone({ id: 'x', name: 'x', date: '2026:09:12 18:12:00', fl: [6765, 1000], fl35: 24 }).bytes, bytes = whole.slice(0, 120);
  return { id: 'truncated', name: 'IMG_0003.DNG', bytes, preview: null, expect: { truncated: true, cutAt: 120, wholeSize: whole.length } };
}

export function fixtures() {
  return [
    iphone({ id: 'iphone', name: 'IMG_0001.DNG', date: '2026:09:12 18:04:31', fl: [6765, 1000], fl35: 24, lens: 'iPhone 15 Pro back triple camera 6.765mm f/1.78' }),
    pixel(),
    pixelRgbThumb(),
    sonyArw(),
    sonyDng(),
    iphone({ id: 'iphone-far-preview', name: 'IMG_0002.DNG', date: '2026:09:12 18:05:10', fl: [9000, 1000], fl35: 77, lens: 'iPhone 15 Pro back triple camera 9mm f/2.8', previewAt: PAGE_HEAD + 4096, orient: 1 }),
    truncated(),
  ];
}

export { PAGE_HEAD };
