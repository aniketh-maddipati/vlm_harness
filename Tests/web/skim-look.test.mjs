// Skim's Color card: the look's maths, read out of the page (its LOOK-BEGIN … LOOK-END block) and run on its own.
// The shader (LK_FS) does the same steps; this checks the reference it follows.
//
//   node --test Tests/web/skim-look.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { PAGE } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const a = src.indexOf('// LOOK-BEGIN'), b = src.indexOf('// LOOK-END');
assert.ok(a > 0 && b > a, 'the page has the look block');
const C = new Function('class Component {\n' + src.slice(a, b) + '\n}\nreturn Component;')();

const ramp = Array.from({length: 33}, (_, i) => i / 32);
const close = (x, y, e = 1e-6) => Math.abs(x - y) <= e;

test('a flat look leaves the picture alone (round trip through linear light)', () => {
  for (const v of ramp) for (const rgb of [[v, v, v], [v, 0.3, 0.7], [0.9, v, 0.1]]) {
    const out = C.lkPx(rgb, {});
    rgb.forEach((x, i) => assert.ok(close(out[i], x, 1e-6), JSON.stringify([rgb, out])));
  }
});

test('every light and colour move keeps a grey grey and a ramp in order', () => {
  const moves = [];
  for (const [p, , mx] of [...C.LK_ROWS.light, ...C.LK_ROWS.color]) for (const v of [-mx, -mx / 2, mx / 2, mx]) if (p !== 'temp' && p !== 'tint') moves.push({[p]: v});
  for (const h of C.LK_HUES) for (const k of ['h', 's', 'l']) for (const v of [-100, 100]) moves.push({['mix.' + h[0] + '.' + k]: v});
  moves.push({ev: 1.5, con: 60, sh: 80, hl: -70, wh: 30, bl: -40, vib: 50, sat: -20});
  for (const L of moves) {
    let prev = -1;
    for (const v of ramp) {
      const [r, g, bb] = C.lkPx([v, v, v], L);
      assert.ok(close(r, g, 1e-9) && close(g, bb, 1e-9), 'grey stays grey: ' + JSON.stringify(L) + ' at ' + v);
      assert.ok(r >= prev - 1e-9, 'in order: ' + JSON.stringify(L) + ' at ' + v); prev = r;
    }
  }
});

test('exposure: a stop up brightens the middle, never past white, and the highlights roll off', () => {
  assert.ok(C.lkPx([0.95, 0.95, 0.95], {ev: 1})[0] < 1, 'rolled off, not clipped');
  assert.ok(close(C.lkPx([0.95, 0.95, 0.95], {con: 1})[0], C.lkPx([0.95, 0.95, 0.95], {})[0], 0.01), 'no roll-off without an exposure push');
  const [m0] = C.lkPx([0.45, 0.45, 0.45], {}), [m1] = C.lkPx([0.45, 0.45, 0.45], {ev: 1}), [w] = C.lkPx([1, 1, 1], {ev: 4});
  assert.ok(m1 > m0 + 0.1, m0 + ' → ' + m1); assert.ok(w <= 1);
});

test('temp warms: red up, blue down; tint against green', () => {
  const [r0, g0, b0] = C.lkPx([0.5, 0.5, 0.5], {}), [r1, , b1] = C.lkPx([0.5, 0.5, 0.5], {temp: 60}), [, g2] = C.lkPx([0.5, 0.5, 0.5], {tint: 60});
  assert.ok(r1 > r0 && b1 < b0); assert.ok(g2 < g0);
});

test('mix on blue moves a sky and leaves skin and greys', () => {
  const sky = [0.35, 0.55, 0.85], skin = [0.85, 0.6, 0.48], grey = [0.5, 0.5, 0.5];
  const L = {'mix.blue.s': 60, 'mix.blue.l': -40, 'mix.blue.h': 30};
  const s0 = C.lkHsv(...C.lkPx(sky, {})), s1 = C.lkHsv(...C.lkPx(sky, L));
  assert.ok(s1[1] > s0[1] + 0.05, 'bluer: ' + s0 + ' → ' + s1); assert.ok(s1[2] < s0[2], 'darker'); assert.ok(s1[0] !== s0[0], 'hue moved');
  C.lkPx(skin, L).forEach((x, i) => assert.ok(close(x, C.lkPx(skin, {})[i], 1e-9), 'skin untouched'));
  C.lkPx(grey, L).forEach((x, i) => assert.ok(close(x, C.lkPx(grey, {})[i], 1e-9), 'grey untouched'));
});

test('grading: a shadow tint reaches the shadows more than the highlights', () => {
  const L = {'grade.sh.h': 220, 'grade.sh.s': 80};
  const d = v => { const o = C.lkPx([v, v, v], L), z = C.lkPx([v, v, v], {}); return o[2] - z[2]; };
  assert.ok(d(0.15) > 0.02, 'blue in the shadows'); assert.ok(d(0.15) > d(0.9) * 3, 'little in the highlights');
});

test('the look values: clean, flat and words', () => {
  assert.equal(C.lkClean('ev', 9), 4); assert.equal(C.lkClean('ev', 0.123), 0.12); assert.equal(C.lkClean('grade.sh.h', -30), 330);
  assert.equal(C.lkClean('grade.blend', 140), 100); assert.equal(C.lkClean('mix.blue.s', -250), -100);
  assert.ok(C.lkFlat({})); assert.ok(C.lkFlat(null)); assert.ok(C.lkFlat({'grade.blend': 50})); assert.ok(C.lkFlat({'grade.sh.h': 200}), 'a hue with no strength is no tint');
  assert.ok(!C.lkFlat({ev: 0.3}));
  assert.equal(C.lkWords({}), 'as shot');
  assert.equal(C.lkWords({ev: 0.5, 'mix.blue.s': -20}), 'Exposure +0.50 · Blue saturation -20');
  assert.match(C.lkWords({ev: 1, con: 10, hl: -20, sh: 30, wh: 5}), / · 2 more$/);
  assert.equal(C.lkWords({'grade.sh.h': 210, 'grade.sh.s': 18}), 'shadows tint 210°');
});

test('the shader takes every uniform the reference uses', () => {
  const fs_ = src.match(/static LK_FS = `([\s\S]*?)`;/)[1];
  for (const n of ['uEv', 'uTemp', 'uTint', 'uCon', 'uHl', 'uSh', 'uWh', 'uBl', 'uVib', 'uSat', 'uBlend', 'uBal', 'uMixC', 'uMixH', 'uMixS', 'uMixL', 'uGH', 'uGS', 'uGL', 'uLut', 'uM', 'uO', 'uMode'])
    assert.ok(new RegExp('\\b' + n + '\\b').test(fs_), n);
  for (const k of ['0.12', '0.8', '0.6', '0.35', '0.125', '0.25', '1.5', '30.0', '0.15', '0.2', '2.5']) assert.ok(fs_.includes(k), 'constant ' + k + ' in the shader');
});

// ---- The look as a .cube (Export: one per clip with a look, Final Cut's Custom LUT effect).
const parseCube = text => {
  const lines = text.split('\n'), n = +(lines.find(l => /^LUT_3D_SIZE /.test(l)) || '').split(' ')[1], v = [];
  for (const l of lines) if (/^-?[\d.]+ -?[\d.]+ -?[\d.]+$/.test(l)) v.push(l.split(' ').map(Number));
  return {n, v};
};
// trilinear, the way Final Cut (and every .cube reader) samples it; red fastest
const sample = ({n, v}, rgb) => {
  const p = rgb.map(x => Math.max(0, Math.min(1, x)) * (n - 1)), i = p.map(x => Math.min(n - 2, Math.floor(x))), f = p.map((x, k) => x - i[k]), out = [0, 0, 0];
  for (let dz = 0; dz < 2; dz++) for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
    const w = (dx ? f[0] : 1 - f[0]) * (dy ? f[1] : 1 - f[1]) * (dz ? f[2] : 1 - f[2]), e = v[(i[0] + dx) + (i[1] + dy) * n + (i[2] + dz) * n * n];
    for (let k = 0; k < 3; k++) out[k] += w * e[k];
  }
  return out;
};
let seed = 7; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const LOOKS = [{ev: 0.6, con: 30, sh: 40, hl: -50, sat: 15}, {temp: 40, tint: -20, vib: 60, 'mix.blue.s': -40, 'mix.orange.h': 30},
  {'grade.sh.h': 210, 'grade.sh.s': 40, 'grade.hi.h': 40, 'grade.hi.s': 30, 'grade.blend': 70, 'grade.bal': -20, wh: 20, bl: -30}];

test('the cube is a 33-point .cube Final Cut reads: header, 35,937 rows, red fastest', () => {
  const t = C.lkCube({ev: 1}, false, 'C0001 "x"'), c = parseCube(t);
  assert.match(t, /^TITLE "C0001  x "\n/); assert.equal(c.n, 33); assert.equal(c.v.length, 33 ** 3);
  // red fastest: row 1 is (1/32, 0, 0) through the look
  const exp = C.lkPx([1 / 32, 0, 0], {ev: 1}); c.v[1].forEach((x, k) => assert.ok(close(x, exp[k], 1e-6)));
});

test('a flat look gives identity for Rec. 709 clips, and just the S-Log3 step for log clips', () => {
  const id = parseCube(C.lkCube({}, false));
  for (let k = 0; k < 200; k++) { const p = [rnd(), rnd(), rnd()], o = sample(id, p); p.forEach((x, j) => assert.ok(close(o[j], x, 1e-5), JSON.stringify([p, o]))); }
  // the page's S-Log3 step is piecewise linear on the same 33 points, so the cube holds it exactly away from clipping
  const lg = parseCube(C.lkCube({}, true));
  // (on codes a camera writes: grey ± modest colour, where no corner of the cell is clipped by the matrix)
  for (let k = 0; k < 200; k++) { const y = 0.1 + rnd() * 0.5, p = [0, 1, 2].map(() => y + (rnd() - 0.5) * 0.06), o = sample(lg, p), e = C.lkSl3(p); e.forEach((x, j) => assert.ok(close(o[j], x, 1e-3), JSON.stringify([p, o, e]))); }
});

test('the cube sampled anywhere matches the preview (lkPreview: the S-Log3 step, then lkPx) within the 33-point interpolation error', () => {
  for (const log of [false, true]) for (const L of LOOKS) {
    const c = parseCube(C.lkCube(L, log)); let worst = 0, sum = 0; const N = 3000;
    for (let k = 0; k < N; k++) {
      const p = [rnd(), rnd(), rnd()], o = sample(c, p), e = C.lkPreview(p, L, log ? 1 : 0), d = Math.max(...o.map((x, j) => Math.abs(x - e[j])));
      worst = Math.max(worst, d); sum += d;
    }
    // in 8-bit levels (measured 2026-11-03: 709 mean 0.1–0.2, worst 2–3.5; log mean 0.3–0.5, worst 9–12, all at codes so
    // saturated that the S-Gamut3.Cine matrix clips them, which a camera does not write)
    const m = sum / N * 255, w = worst * 255, tag = (log ? 'log ' : '709 ') + JSON.stringify(L) + ' mean ' + m.toFixed(2) + ' worst ' + w.toFixed(2);
    assert.ok(m < (log ? 0.7 : 0.35), tag); assert.ok(w < (log ? 16 : 5), tag);
  }
});

test('on what an S-Log3 camera writes (log grey ± colour) the cube is within two levels on average', () => {
  for (const L of LOOKS) {
    const c = parseCube(C.lkCube(L, true)); let worst = 0, sum = 0; const N = 3000;
    for (let k = 0; k < N; k++) {
      const y = 0.1 + rnd() * 0.6, p = [y + (rnd() - 0.5) * 0.12, y + (rnd() - 0.5) * 0.12, y + (rnd() - 0.5) * 0.12], o = sample(c, p), e = C.lkPreview(p, L, 1), d = Math.max(...o.map((x, j) => Math.abs(x - e[j])));
      worst = Math.max(worst, d); sum += d;
    }
    const tag = JSON.stringify(L) + ' mean ' + (sum / N * 255).toFixed(2) + ' worst ' + (worst * 255).toFixed(2);
    // measured 2026-11-03: mean 0.3–1.5 levels (vibrance and the mix bend fastest near grey), worst 6–9
    assert.ok(sum / N * 255 < 2, tag); assert.ok(worst * 255 < 10, tag);
  }
});

test('lkSl3 is the preview’s S-Log3 step: the table and matrix at the grid points', () => {
  const T = C.SL3T, M = C.SL3M;
  for (const i of [0, 8, 16, 22]) { const v = i / 32, o = C.lkSl3([v, v, v]); const e = Math.max(0, Math.min(1, (M[0] + M[1] + M[2]) * T[i] + M[3])); assert.ok(close(o[0], e, 1e-9)); }
});

// ---- Final Cut's name for a custom LUT (lkLutHash, lkLutParam), against Final Cut 12.4's own export.
test('the LUT reference is byte for byte what Final Cut 12.4 wrote for a cube in its Custom LUTs folder', () => {
  const g = fs.readFileSync(new URL('./fixtures/fcp-12.4-custom-lut.xml', import.meta.url), 'utf8');
  const v = /<param name="LUT" key="3" value="([^"]+)"/.exec(g)[1];
  assert.equal(C.lkLutHash('C4815 look.cube'), 'fdae335f2734874baad6bf9a77ea4005');
  assert.equal(C.lkLutParam('fdae335f2734874baad6bf9a77ea4005:C4815 look'), v);
  assert.match(g, /<param name="Input" key="100\/101" value="0 \(Rec\. 709\)"\/>/);
});

test('lkMd5 is MD5', () => {
  const hex = u => Buffer.from(u).toString('hex');
  assert.equal(hex(C.lkMd5(Buffer.from(''))), 'd41d8cd98f00b204e9800998ecf8427e');
  assert.equal(hex(C.lkMd5(Buffer.from('abc'))), '900150983cd24fb0d6963f7d28e17f72');
  const long = Buffer.from('x'.repeat(1000)); assert.equal(hex(C.lkMd5(long)), crypto.createHash('md5').update(long).digest('hex'));
});

test('a long or non-ASCII name still makes a plist Final Cut can read (offset table, UTF-16 strings)', () => {
  for (const name of ['Café · 夕方 C0007 a1b2c3', 'C'.repeat(200)]) {
    const oz = Buffer.from(C.lkLutParam('0123456789abcdef0123456789abcdef:' + name), 'base64').toString('latin1');
    const dv = /<dataValue>([^<]+)</.exec(oz)[1], A = '*-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    let bits = ''; for (const ch of dv) bits += A.indexOf(ch).toString(2).padStart(6, '0');
    const b = []; for (let i = 0; i + 8 <= bits.length; i += 8) b.push(parseInt(bits.slice(i, i + 8), 2));
    const len = b[4] << 24 | b[5] << 16 | b[6] << 8 | b[7], p = b.slice(9, 9 + len);
    assert.equal(Buffer.from(p.slice(0, 8)).toString(), 'bplist00');
    // trailer: offset size, ref size, 13 objects, top 0, table offset; the last object is the reference
    const t = p.slice(-32), osz = t[6], tbl = t[31] | t[30] << 8, off = k => osz === 1 ? p[tbl + k] : p[tbl + 2 * k] << 8 | p[tbl + 2 * k + 1];
    assert.equal(t[15], 13); assert.ok(osz === 1 || osz === 2);
    const o = off(12), mk = p[o] >> 4; let n = p[o] & 15, at = o + 1; if (n === 15) { const w = 1 << (p[at] & 15); n = 0; for (let i = 0; i < w; i++) n = n * 256 + p[at + 1 + i]; at += 1 + w; }
    const s = mk === 5 ? Buffer.from(p.slice(at, at + n)).toString('latin1') : String.fromCharCode(...Array.from({length: n}, (_, i) => p[at + 2 * i] << 8 | p[at + 2 * i + 1]));
    assert.equal(s, '0123456789abcdef0123456789abcdef:' + name);
  }
});

test('Exposure on S-Log3 is the preview\u2019s shift of the code (#335), not the look\u2019s gain; elsewhere the gain', () => {
  const ev = /static EV_CODE = ([^;]+);/.exec(src)[1], EV = new Function('return ' + ev)();
  for (const x of [0.5, -1.25, 2]) for (const p of [[0.3, 0.4, 0.5], [0.55, 0.5, 0.45], [0.2, 0.2, 0.2]]) {
    const got = C.lkPreview(p, {ev: x, con: 20}, 1), want = C.lkPx(C.lkSl3(p, x * EV), {con: 20});
    got.forEach((v, k) => assert.ok(close(v, want[k], 1e-12), JSON.stringify([x, p, got, want])));
    const gain = C.lkPx(C.lkSl3(p), {ev: x, con: 20}); assert.ok(gain.some((v, k) => Math.abs(v - got[k]) > 1e-3), 'not the gain');
    const rec = C.lkPreview(p, {ev: x, con: 20}, 0), rw = C.lkPx(p, {ev: x, con: 20}); rec.forEach((v, k) => assert.ok(close(v, rw[k], 1e-12)));
  }
  // to 1/100 stop, as gradeDraw rounds it
  const a = C.lkPreview([0.4, 0.4, 0.4], {ev: 0.504}, 1), b = C.lkPreview([0.4, 0.4, 0.4], {ev: 0.5}, 1); assert.deepEqual(a, b);
  // and the cube carries it
  const cube = parseCube(C.lkCube({ev: 1}, 1)), g = [16 / 32, 12 / 32, 10 / 32], e = C.lkPreview(g, {ev: 1}, 1), o = cube.v[16 + 12 * 33 + 10 * 33 * 33];
  o.forEach((v, k) => assert.ok(close(v, e[k], 1e-6)));
});
