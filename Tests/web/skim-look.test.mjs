// Skim's Color card: the look's maths, read out of the page (its LOOK-BEGIN … LOOK-END block) and run on its own.
// The shader (LK_FS) does the same steps; this checks the reference it follows.
//
//   node --test Tests/web/skim-look.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
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
