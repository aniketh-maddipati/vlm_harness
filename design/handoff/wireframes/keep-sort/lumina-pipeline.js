// lumina-pipeline.js — Rec.709 for S-Log3 and the Final Cut stringout package, for the Sort / Export wireframe.
// No dependencies. ES module (node tests: `node lumina-pipeline.test.mjs`) and `window.LuminaPipeline` for the page
// (load with <script type="module" src="lumina-pipeline.js">).
//
// Rec.709 chain (lumina-skim/REC709.md steps 3–6; steps 1–2, decode and YUV→RGB, belong to the decoder):
//   S-Log3 code value → scene linear (Sony's published curve)
//   → S-Gamut3.Cine → Rec.709 primaries (3×3 in linear light, built from the published primaries, D65)
//   → tone map (≈15 stops into Rec.709) → Rec.709 OETF.
// REC709.md defines the tone map by its reference, Final Cut's built-in "Sony S-Log3/S-Gamut3.Cine" camera LUT. The
// curve here is Skim's SL3T table (LOCAL-CHANGES 139: 33 points refitted to Final Cut Pro 12.4 stills of that LUT),
// used for its neutral axis only: tone(x) = OETF⁻¹(SL3T(S-Log3(x))), applied per channel after the linear matrix.
// Greys therefore follow the fitted curve; hue comes from the true linear-light matrix. No ΔE is claimed here.
//
// Code values: the default input is what an NLE or a browser hands a filter for 10-bit video-range S-Log3 —
// legal range expanded, v = (cv10 − 64) / 876 — which is the domain SL3T was fitted in and the domain the .cube
// is written for. Pass {input:'cv'} for Sony's normalised code value cv10 / 1023 (the white paper's form).

export const VERSION = '2026-10-28';

// ---------- S-Log3 (Sony, "Technical Summary for S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3") ----------
export function slog3CvToLinear(cv) { // cv = 10-bit code value / 1023
  const c = cv * 1023;
  return c >= 171.2102946929
    ? Math.pow(10, (c - 420) / 261.5) * (0.18 + 0.01) - 0.01
    : (c - 95) * 0.01125 / (171.2102946929 - 95);
}
export function linearToSlog3Cv(x) {
  return x >= 0.01125
    ? (420 + Math.log10((x + 0.01) / (0.18 + 0.01)) * 261.5) / 1023
    : (x * (171.2102946929 - 95) / 0.01125 + 95) / 1023;
}
export const legalToCv = v => (v * 876 + 64) / 1023;
export const cvToLegal = cv => (cv * 1023 - 64) / 876;

// ---------- primaries ----------
const SG3C = [[0.766, 0.275], [0.225, 0.800], [0.089, -0.087]]; // S-Gamut3.Cine
const BT709 = [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]];
const D65 = [0.3127, 0.3290];
function inv3(m) {
  const [a, b, c] = m[0], [d, e, f] = m[1], [g, h, i] = m[2];
  const A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g, det = a * A + b * B + c * C;
  return [[A / det, -(b * i - c * h) / det, (b * f - c * e) / det],
          [B / det, (a * i - c * g) / det, -(a * f - c * d) / det],
          [C / det, -(a * h - b * g) / det, (a * e - b * d) / det]];
}
const mul3 = (a, b) => a.map(r => [0, 1, 2].map(j => r[0] * b[0][j] + r[1] * b[1][j] + r[2] * b[2][j]));
const apply3 = (m, v) => m.map(r => r[0] * v[0] + r[1] * v[1] + r[2] * v[2]);
function rgbToXyz(P, W) {
  const xyz = ([x, y]) => [x / y, 1, (1 - x - y) / y];
  const M = [0, 1, 2].map(r => P.map(p => xyz(p)[r])); // columns = primaries
  const S = apply3(inv3(M), xyz(W));
  return M.map(r => r.map((v, j) => v * S[j]));
}
export const SG3C_TO_709 = mul3(inv3(rgbToXyz(BT709, D65)), rgbToXyz(SG3C, D65));

// ---------- Rec.709 OETF ----------
// BT.709 / BT.2020 constants at full precision, so the two pieces meet and the inverse round-trips exactly
const A709 = 1.09929682680944, B709 = 0.018053968510807;
export const oetf709 = L => L < B709 ? 4.5 * L : A709 * Math.pow(L, 0.45) - (A709 - 1);
export const oetf709Inv = V => V < 4.5 * B709 ? V / 4.5 : Math.pow((V + A709 - 1) / A709, 1 / 0.45);

// ---------- tone map (neutral axis of Final Cut's Sony camera LUT, via Skim's SL3T fit) ----------
export const SL3T = [0.0000, 0.0225, 0.0459, 0.0709, 0.0984, 0.1292, 0.1631, 0.1996, 0.2387, 0.2810, 0.3268, 0.3766, 0.4301, 0.4876, 0.5500, 0.6167, 0.6851, 0.7530, 0.8170, 0.8740, 0.9223, 0.9604, 0.9866, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000];
function sl3t(v) { // v: legal-range S-Log3 code, 0–1 → Rec.709 display code 0–1
  const n = SL3T.length - 1, x = Math.min(1, Math.max(0, v)) * n, i = Math.min(n - 1, Math.floor(x)), f = x - i;
  return SL3T[i] + (SL3T[i + 1] - SL3T[i]) * f;
}
// scene linear → display linear (the part of the chain before the OETF)
export const toneMap = x => oetf709Inv(sl3t(cvToLegal(linearToSlog3Cv(x))));

// One pixel: S-Log3 / S-Gamut3.Cine RGB code values → Rec.709 display RGB, 0–1.
export function slog3ToRec709(rgb, opts) {
  const cv = opts && opts.input === 'cv' ? rgb : rgb.map(legalToCv);
  const lin = apply3(SG3C_TO_709, cv.map(slog3CvToLinear));
  return lin.map(x => Math.min(1, Math.max(0, oetf709(toneMap(x)))));
}

// .cube 3D LUT (Adobe/Resolve/Final Cut "Custom LUT" format): red varies fastest. Input legal-range S-Log3.
export const CUBE_NAME = 'SLog3-SGamut3Cine_to_Rec709.cube';
export function buildCube(size = 33) {
  size = Math.max(2, Math.min(65, size | 0));
  const out = ['TITLE "Lumina S-Log3 S-Gamut3.Cine to Rec.709"',
    '# S-Log3 (video range, 0-1) / S-Gamut3.Cine -> Rec.709 display. Lumina ' + VERSION + '.',
    '# Neutral axis fitted to Final Cut Pro\'s Sony S-Log3/S-Gamut3.Cine camera LUT; linear-light gamut matrix.',
    'LUT_3D_SIZE ' + size, 'DOMAIN_MIN 0.0 0.0 0.0', 'DOMAIN_MAX 1.0 1.0 1.0'];
  const d = size - 1;
  for (let b = 0; b < size; b++) for (let g = 0; g < size; g++) for (let r = 0; r < size; r++)
    out.push(slog3ToRec709([r / d, g / d, b / d]).map(v => v.toFixed(6)).join(' '));
  return out.join('\n') + '\n';
}

// ---------- gamma: Log or 709, from what the clip says ----------
const gammaName = g => /s-?log3/i.test(g) ? 'S-Log3' : /s-?log2/i.test(g) ? 'S-Log2' : /d-?log/i.test(g) ? 'D-Log'
  : /v-?log/i.test(g) ? 'V-Log' : /hlg/i.test(g) ? 'HLG' : /709|rec|cine-?tone/i.test(g) ? 'Rec.709' : String(g);
const primName = p => /gamut3.?cine/i.test(p) ? 'S-Gamut3.Cine' : /gamut3/i.test(p) ? 'S-Gamut3' : /d-?gamut/i.test(p) ? 'D-Gamut'
  : /2020/.test(p) ? 'Rec.2020' : /709/.test(p) ? 'Rec.709' : String(p);
const PRIM = {'S-Log3':'S-Gamut3.Cine', 'S-Log2':'S-Gamut3', 'D-Log':'D-Gamut', 'HLG':'Rec.2020', 'Rec.709':'Rec.709'};
// Wireframe sources that stand in for Sony bodies (log there means S-Log3/S-Gamut3.Cine) and for a DJI drone.
const SONY_SRC = new Set(['card', 'ssd', 't7b', 't7c', 'acam', 'bcam']);
// Sony sidecar (<name>M01.XML): <Item name="CaptureGammaEquation" value="s-log3-cine"/>, or the attribute form.
export function readSonyXml(tx) {
  const sv = n => (String(tx).match(new RegExp(n + '="([^"]+)"', 'i')) || String(tx).match(new RegExp('name="' + n + '"\\s+value="([^"]+)"', 'i')) || [])[1];
  const g = sv('captureGammaEquation'), p = sv('captureColorPrimaries');
  return g || p ? {captureGammaEquation:g || null, captureColorPrimaries:p || null} : null;
}
// Final Cut's own name for its built-in Sony conversion, as Final Cut Pro 12.4 writes it on a clip whose Camera LUT
// is Sony S-Log3/S-Gamut3.Cine (Skim LOCAL-CHANGES 143/145, proven by import). Only this pair is known.
export const FCP_SONY_SLOG3 = '35 (Sony_SLog3_SGamut3Cine_v2)';
export function gammaOf(clip) {
  const c = clip || {};
  let g = null, p = null, source = 'default';
  const sc = c.sidecar ? (typeof c.sidecar === 'string' ? readSonyXml(c.sidecar) : c.sidecar) : null;
  if (c.profile && c.profile.gamma) { g = c.profile.gamma; p = c.profile.primaries; source = 'profile'; }
  else if (sc && sc.captureGammaEquation) { g = sc.captureGammaEquation; p = sc.captureColorPrimaries; source = 'sidecar'; }
  else if (c.gamma) { g = c.gamma; p = c.primaries; source = 'field'; }
  else if (c.log === true) { g = SONY_SRC.has(c.src) ? 'S-Log3' : c.src === 'drone' ? 'D-Log' : 'Log'; source = 'wireframe'; }
  else if (c.log === false) { g = 'Rec.709'; source = 'wireframe'; }
  const gamma = g ? gammaName(g) : 'Rec.709', primaries = p ? primName(p) : (PRIM[gamma] || null);
  const kind = gamma === 'Rec.709' ? '709' : 'log';
  const known = gamma === 'S-Log3' && primaries === 'S-Gamut3.Cine';
  return {kind, gamma, primaries, source, rec709:known, fcpLut:known ? FCP_SONY_SLOG3 : null};
}

// ---------- clip facts the wireframe does not carry ----------
// Paths in the wireframe are stand-ins: each source gets a plausible place on a volume.
export const SOURCE_ROOT = {
  ssd:'/Volumes/T7/Road trip/Clips/A-cam', t7b:'/Volumes/T7/Road trip/Clips/B-cam', t7c:'/Volumes/T7/Road trip/Clips/FX3',
  card:'/Volumes/Untitled/PRIVATE/M4ROOT/CLIP', acam:'/Volumes/A-cam/PRIVATE/M4ROOT/CLIP', bcam:'/Volumes/B-cam/PRIVATE/M4ROOT/CLIP',
  drone:'/Volumes/DJI/DCIM/100MEDIA', phone:'/Volumes/iPhone/DCIM/100APPLE',
};
const EXT = {phone:'MOV'};
// [frameDuration n, d, width, height] by source
const FMT = {phone:[1001, 30000, 1920, 1080], drone:[1001, 30000, 3840, 2160]};
const FMT_DEF = [1001, 24000, 3840, 2160];
export function pathOf(c) {
  if (c.path && c.path[0] === '/') return c.path;
  const name = /\.\w{2,4}$/.test(c.name) ? c.name : c.name + '.' + (c.ext || EXT[c.src] || 'MP4');
  return (SOURCE_ROOT[c.src] || '/Volumes/' + (c.src || 'Media')) + '/' + name;
}
export const fileUrl = p => 'file://' + String(p).split('/').map(encodeURIComponent).join('/');
function fmtOf(c) {
  const d = FMT[c.src] || FMT_DEF;
  return {n:c.fd ? c.fd[0] : d[0], dd:c.fd ? c.fd[1] : d[1], w:c.w || d[2], h:c.h || d[3]};
}
// Axis time: the file's clock plus the per-source shift the clock-align pass found (the page's clipSec).
export function axisSec(c, shift) {
  const v = Date.parse(String(c.t || '').slice(0, 19) + 'Z');
  return isFinite(v) ? v / 1000 + ((shift && shift[c.src]) | 0) : NaN;
}
// Kept clips in Sort's axis order (ties keep their input order).
export function stringoutClips(handoff) {
  const h = handoff || {}, keep = new Set(h.keeps || []);
  return (h.clips || []).map((c, i) => ({c, i, t:axisSec(c, h.shift)}))
    .filter(x => keep.has(x.c.id) || x.c.kept === true)
    .sort((a, b) => (isFinite(a.t) ? a.t : Infinity) - (isFinite(b.t) ? b.t : Infinity) || a.i - b.i)
    .map(x => x.c);
}

// ---------- FCPXML 1.10 ----------
const xe = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const FFS = {'1280x720':'720p', '1920x1080':'1080p', '3840x2160':'3840x2160p', '4096x2160':'4096x2160p'};
const FFR = {'1001/24000':'2398', '100/2400':'24', '100/2500':'25', '1001/30000':'2997', '100/3000':'30', '100/5000':'50', '1001/60000':'5994', '100/6000':'60'};
const ffName = f => FFS[f.w + 'x' + f.h] && FFR[f.n + '/' + f.dd] ? 'FFVideoFormat' + FFS[f.w + 'x' + f.h] + FFR[f.n + '/' + f.dd] : '';
const rt = (frames, f) => frames ? frames * f.n + '/' + f.dd + 's' : '0s';

// handoff: {name, clips:[{id,name,src,log,dur,t,(path,fd,w,h,nf,profile,sidecar)}], keeps:[id], shift:{src:s}, rec709:bool}
export function buildFcpxml(handoff) {
  const h = handoff || {}, name = String(h.name || 'Stringout'), clips = stringoutClips(h), rec = h.rec709 !== false;
  const fmts = new Map(), fl = [];
  const fmt = c => { const f = fmtOf(c), k = f.n + '/' + f.dd + '-' + f.w + 'x' + f.h;
    if (!fmts.has(k)) { const id = 'r' + (fmts.size + 1); fmts.set(k, {...f, id, count:0});
      fl.push('    <format id="' + id + '"' + (ffName(f) ? ' name="' + ffName(f) + '"' : '') + ' frameDuration="' + f.n + '/' + f.dd + 's" width="' + f.w + '" height="' + f.h + '"/>'); }
    const F = fmts.get(k); F.count++; return F; };
  // whole frames, never longer than the file: the camera's frame count when given, else the length rounded down
  const items = clips.map((c, i) => { const f = fmt(c); return {c, f, id:'a' + (i + 1), nf:c.nf || Math.max(1, Math.floor((c.dur || 1) * f.dd / f.n + 1e-6)), g:gammaOf(c), nm:xe(String(c.name).replace(/\.\w+$/, ''))}; });
  // the timeline runs at the format most keeps share (first one on a tie); it needs one of Final Cut's named formats
  let S = null; fmts.forEach(F => { if (!S || F.count > S.count) S = F; });
  const al = [], ev = [], sp = []; let at = 0, logN = 0, lutN = 0;
  items.forEach(x => {
    const lut = rec && x.g.fcpLut ? ' customLUTOverride="' + xe(x.g.fcpLut) + '"' : '';
    if (x.g.kind === 'log') logN++; if (lut) lutN++;
    al.push('    <asset id="' + x.id + '" name="' + x.nm + '" start="0s" duration="' + rt(x.nf, x.f) + '" hasVideo="1" hasAudio="1" format="' + x.f.id + '"' + lut + '>',
      '      <media-rep kind="original-media" src="' + xe(fileUrl(pathOf(x.c))) + '"/>', '    </asset>');
    ev.push('      <asset-clip ref="' + x.id + '" name="' + x.nm + '" duration="' + rt(x.nf, x.f) + '" format="' + x.f.id + '" tcFormat="NDF"/>');
    const k = Math.max(1, Math.floor(x.nf * x.f.n * S.dd / (x.f.dd * S.n) + 1e-9)); // whole timeline frames
    sp.push('            <asset-clip ref="' + x.id + '" offset="' + rt(at, S) + '" name="' + x.nm + '" duration="' + rt(k, S) + '" format="' + x.f.id + '" tcFormat="NDF"/>');
    at += k;
  });
  const proj = clips.length ? ['      <project name="' + xe(name + ' · stringout') + '">',
    '        <sequence format="' + S.id + '" duration="' + rt(at, S) + '" tcStart="0s" tcFormat="NDF">', '          <spine>', ...sp, '          </spine>', '        </sequence>', '      </project>'] : [];
  const text = ['<?xml version="1.0" encoding="UTF-8"?>', '<!DOCTYPE fcpxml>', '', '<fcpxml version="1.10">',
    '  <import-options>', '    <option key="copy assets" value="0"/>', '  </import-options>',
    '  <resources>', ...fl, ...al, '  </resources>', '  <library>', '    <event name="' + xe(name) + '">', ...ev, ...proj, '    </event>', '  </library>', '</fcpxml>', ''].join('\n');
  return {text, n:clips.length, log:logN, lut:lutN, frames:at, timeline:S ? {frameDuration:S.n + '/' + S.dd + 's', w:S.w, h:S.h} : null};
}

// One quiet line for the Export sheet.
export function summaryLine(handoff) {
  const x = buildFcpxml(handoff), rec = (handoff || {}).rec709 !== false, P = (n, w) => n + ' ' + w + (n === 1 ? '' : 's');
  if (!x.n) return 'Final Cut · nothing kept yet';
  let s = 'Final Cut · ' + P(x.n, 'clip');
  if (!x.log) return s + ' · all Rec.709';
  if (!rec) return s + ' · Log left as shot';
  if (x.lut) s += ' · Log → Rec.709 LUT applied';
  if (x.log > x.lut) s += ' · ' + (x.log - x.lut) + ' Log as shot';
  return s;
}

export function buildPackage(handoff) {
  const h = handoff || {}, name = String(h.name || 'Stringout'), x = buildFcpxml(h), clips = stringoutClips(h), rec = h.rec709 !== false;
  const base = name.replace(/[\/:\\]/g, '-') + ' stringout';
  const other = clips.filter(c => { const g = gammaOf(c); return g.kind === 'log' && !g.fcpLut; });
  const readme = [base, '='.repeat(base.length), '',
    'Open ' + base + '.fcpxml in Final Cut Pro 10.6 or later (File > Import > XML). It makes one event with one',
    'project: the ' + x.n + ' kept clip' + (x.n === 1 ? '' : 's') + ' as a stringout in Sort\'s time order (each source\'s clock shift applied).',
    '',
    'Paths are placeholders. This wireframe has no real files; each clip points at a made-up place on a volume',
    '(e.g. /Volumes/T7/Road trip/Clips/A-cam/C4401.MP4). Final Cut will show them as missing: use File > Relink Files.',
    '', 'Colour:',
    rec ? (x.lut ? '- ' + x.lut + ' S-Log3 / S-Gamut3.Cine clip' + (x.lut === 1 ? ' carries' : 's carry') + ' Final Cut\'s own camera LUT (Info > Camera LUT: Sony S-Log3/S-Gamut3.Cine).' : '- No Sony S-Log3 clips among the keeps.')
        : '- Rec.709 was off in Sort: Log clips arrive as shot (Camera LUT: None).',
    rec && other.length ? '- ' + other.length + ' other Log clip' + (other.length === 1 ? ' (' : 's (') + [...new Set(other.map(c => gammaOf(c).gamma))].join(', ') + (other.length === 1 ? ') arrives as shot; set its' : ') arrive as shot; set their') + ' Camera LUT in Final Cut.' : null,
    '- ' + CUBE_NAME + ' is Lumina\'s S-Log3 → Rec.709 conversion (S-Log3 video range in, Rec.709 out).',
    '  It is not applied by the .fcpxml; use it with Effects > Color > Custom LUT, or in another app.',
    '', 'Made by Lumina ' + VERSION + '.'].filter(l => l !== null).join('\n') + '\n';
  return {name:base, files:[{name:base + '.fcpxml', text:x.text}, {name:CUBE_NAME, text:buildCube(33)}, {name:'README.txt', text:readme}], summary:summaryLine(h), fcpxml:x};
}

// ---------- a stored (uncompressed) zip, so one click is one download ----------
const CRC = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
export function crc32(u8) { let c = 0xFFFFFFFF; for (let i = 0; i < u8.length; i++) c = CRC[(c ^ u8[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
export function zipStore(files, folder) {
  const enc = new TextEncoder(), parts = [], cd = []; let off = 0;
  const d = new Date(), dt = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate(), tm = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
  for (const f of files) {
    const nm = enc.encode((folder ? folder + '/' : '') + f.name), data = typeof f.text === 'string' ? enc.encode(f.text) : f.data, crc = crc32(data);
    const lh = new DataView(new ArrayBuffer(30));
    [[0, 0x04034b50, 4], [4, 20, 2], [6, 0x0800, 2], [8, 0, 2], [10, tm, 2], [12, dt, 2], [14, crc, 4], [18, data.length, 4], [22, data.length, 4], [26, nm.length, 2], [28, 0, 2]]
      .forEach(([o, v, s]) => s === 4 ? lh.setUint32(o, v, true) : lh.setUint16(o, v, true));
    const ch = new DataView(new ArrayBuffer(46));
    [[0, 0x02014b50, 4], [4, 20, 2], [6, 20, 2], [8, 0x0800, 2], [10, 0, 2], [12, tm, 2], [14, dt, 2], [16, crc, 4], [20, data.length, 4], [24, data.length, 4], [28, nm.length, 2], [30, 0, 2], [32, 0, 2], [34, 0, 2], [36, 0, 2], [38, 0, 4], [42, off, 4]]
      .forEach(([o, v, s]) => s === 4 ? ch.setUint32(o, v, true) : ch.setUint16(o, v, true));
    parts.push(new Uint8Array(lh.buffer), nm, data); cd.push(new Uint8Array(ch.buffer), nm); off += 30 + nm.length + data.length;
  }
  const cdLen = cd.reduce((s, p) => s + p.length, 0), end = new DataView(new ArrayBuffer(22));
  [[0, 0x06054b50, 4], [4, 0, 2], [6, 0, 2], [8, files.length, 2], [10, files.length, 2], [12, cdLen, 4], [16, off, 4], [20, 0, 2]]
    .forEach(([o, v, s]) => s === 4 ? end.setUint32(o, v, true) : end.setUint16(o, v, true));
  const all = [...parts, ...cd, new Uint8Array(end.buffer)], out = new Uint8Array(all.reduce((s, p) => s + p.length, 0));
  let p = 0; for (const a of all) { out.set(a, p); p += a.length; } return out;
}

const API = {VERSION, slog3CvToLinear, linearToSlog3Cv, legalToCv, cvToLegal, SG3C_TO_709, oetf709, oetf709Inv, toneMap, slog3ToRec709,
  buildCube, CUBE_NAME, readSonyXml, gammaOf, FCP_SONY_SLOG3, SOURCE_ROOT, pathOf, fileUrl, axisSec, stringoutClips, buildFcpxml,
  summaryLine, buildPackage, crc32, zipStore};
if (typeof window !== 'undefined') window.LuminaPipeline = API;
export default API;
