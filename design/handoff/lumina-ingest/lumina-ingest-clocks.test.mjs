// node lumina-ingest-clocks.test.mjs: the clock alignment on synthetic timelines with known offsets.
import { createRequire } from 'module';
import assert from 'assert/strict';
const require = createRequire(import.meta.url);
const K = require('./lumina-ingest-clocks.js');

// seeded random
let seed = 7; const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const N = K.GW * K.GH;
// a scene: RGBA bytes of a 12 × 8 image; a twin: the same scene through another camera (noise, exposure, white balance)
function scene() { const px = new Uint8ClampedArray(N * 4); const base = [rnd() * 255, rnd() * 255, rnd() * 255]; for (let i = 0; i < N; i++) { const l = rnd() * 200; for (let c = 0; c < 3; c++) px[i * 4 + c] = l * 0.6 + base[c] * 0.4; px[i * 4 + 3] = 255; } return px; }
function twin(px, amt = 10) { const o = new Uint8ClampedArray(px.length), g = 0.9 + rnd() * 0.2, wb = [rnd() * 12 - 6, 0, rnd() * 12 - 6]; for (let i = 0; i < px.length; i += 4) { for (let c = 0; c < 3; c++) o[i + c] = px[i + c] * g + wb[c] + (rnd() - 0.5) * amt; o[i + 3] = 255; } return o; }

const T0 = Date.UTC(2026, 8, 8, 8, 0, 0), H = 3600e3, M = 60e3;
let id = 0;
function shoot(body, { off = 0, n, moments, phone = false, start = 0, name = 'DSC', src = 'card' }) {
  // n photos of its own over the day + the shared moments (true time, own clock = true + off)
  const out = []; let no = 1;
  const own = Array.from({ length: n }, () => start + rnd() * 10 * H).sort((a, b) => a - b);
  const all = own.map((t) => ({ t, px: scene() })).concat((moments || []).map((m) => ({ t: m.t + (rnd() - 0.5) * 20e3, px: twin(m.px) }))).sort((a, b) => a.t - b.t);
  for (const x of all) out.push({ id: ++id, body, phone, src, name: `${name}${String(no++).padStart(5, '0')}.ARW`, t: T0 + x.t + off, truth: off, sig: K.sigFromRGBA(x.px) });
  return out;
}
const momentsAt = (k, from = 0) => Array.from({ length: k }, (_, i) => ({ t: from + (i + 0.5) * (9 * H / k), px: scene() }));
const byKey = (r, k) => r.clocks.find((c) => c.key === k);
let fails = 0; const t = (name, fn) => { try { fn(); console.log('ok  ', name); } catch (e) { fails++; console.log('FAIL', name, '\n    ', e.message); } };
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, `${msg}: ${K.fmtShift(a)} vs ${K.fmtShift(b)}`);

t('fmtShift', () => {
  assert.equal(K.fmtShift(-(1 * H + 3 * M)), '−1 h 03 min');
  assert.equal(K.fmtShift(8 * H), '+8 h');
  assert.equal(K.fmtShift(-40e3), '−40 s');
  assert.equal(K.fmtShift(5 * M + 20e3), '+5 min');
});

t('two bodies, B 1 h 03 min fast: B shifted −1 h 03 min, A untouched', () => {
  const mom = momentsAt(14);
  const items = [...shoot('ILCE-7M4 #5021', { n: 120, moments: mom }), ...shoot('ILCE-7M3 #1234', { n: 60, moments: mom, off: H + 3 * M })];
  const r = K.align(items), b = byKey(r, 'ILCE-7M3 #1234'), a = byKey(r, 'ILCE-7M4 #5021');
  assert.equal(a.shift, 0); assert.ok(a.ref);
  near(b.shift, -(H + 3 * M), 30e3, 'B'); assert.ok(b.matches >= 10, 'matches ' + b.matches); assert.equal(b.tz, null);
  console.log('     ', b.key, 'shifted', K.fmtShift(b.shift), `(${b.matches} matching moments)`);
});

t('phone is the reference even with fewer photos; a camera in another time zone (+8 h) gets tz 8', () => {
  const mom = momentsAt(10);
  const items = [...shoot('iPhone 15 Pro', { n: 30, moments: mom, phone: true, name: 'IMG_' }), ...shoot('ILCE-7M3 #1111', { n: 200, moments: mom, off: -8 * H + 25e3 })];
  const r = K.align(items), c = byKey(r, 'ILCE-7M3 #1111');
  assert.ok(byKey(r, 'iPhone 15 Pro').ref);
  near(c.shift, 8 * H - 25e3, 30e3, 'camera'); assert.equal(c.tz, 8);
});

t('a body with no overlap: no shift, no matches', () => {
  const mom = momentsAt(8);
  const items = [...shoot('A #1', { n: 50, moments: mom }), ...shoot('B #2', { n: 50, moments: mom, off: 2 * H }), ...shoot('C #3', { n: 80, off: 5 * H })];
  const r = K.align(items), c = byKey(r, 'C #3');
  assert.equal(c.shift, 0); assert.equal(c.matches, 0);
  near(byKey(r, 'B #2').shift, -2 * H, 30e3, 'B');
});

t('chained: C overlaps only B, B overlaps A → C aligned to A through B', () => {
  const ab = momentsAt(6), bc = momentsAt(6, 12 * H);
  const items = [...shoot('A #1', { n: 90, moments: ab }), ...shoot('B #2', { n: 40, moments: [...ab, ...bc], off: 30 * M }), ...shoot('C #3', { n: 20, moments: bc, off: -3 * H, start: 12 * H })];
  const r = K.align(items);
  near(byKey(r, 'B #2').shift, -30 * M, 30e3, 'B'); near(byKey(r, 'C #3').shift, 3 * H, 45e3, 'C'); assert.equal(byKey(r, 'C #3').tz, 3);
});

t('clock set back mid-card (time zone jump on one body): two clocks, the second aligned by its pairs', () => {
  const mom = momentsAt(10, 0), mom2 = momentsAt(10, 12 * H);
  const ref = shoot('A #1', { n: 60, moments: [...mom, ...mom2] });
  // body B right for the first half, then its clock set back 9 h (photos keep counting up)
  const b1 = shoot('B #2', { n: 20, moments: mom }), b2 = shoot('B #2', { n: 20, moments: mom2, off: -9 * H, start: 12 * H });
  b2.forEach((x, i) => { x.name = `DSC${String(1000 + i).padStart(5, '0')}.ARW`; });
  const r = K.align([...ref, ...b1, ...b2]);
  const segs = r.clocks.filter((c) => c.body === 'B #2');
  assert.equal(segs.length, 2, 'two clocks for B');
  assert.equal(segs[0].shift, 0); near(segs[1].shift, 9 * H, 30e3, 'B after the jump'); assert.equal(segs[1].tz, 9);
  assert.ok(segs[1].jump && segs[1].jump.by < -H);
});

t('look-alike scenes a minute apart on two in-sync bodies: under 2 min, left as shot', () => {
  const mom = momentsAt(12).map((m) => ({ ...m, t: m.t + 60e3 }));
  const a = momentsAt(12); mom.forEach((m, i) => { m.px = a[i].px; });
  const items = [...shoot('A #1', { n: 40, moments: a }), ...shoot('B #2', { n: 40, moments: mom, off: 0 })];
  const r = K.align(items), b = byKey(r, 'B #2'); assert.equal(b.shift, 0); assert.ok(Math.abs(b.small) >= 40e3, 'found the minute: ' + b.small);
});

t('random photos never agree on an offset (2 bodies × 300, no shared moments)', () => {
  const items = [...shoot('A #1', { n: 300 }), ...shoot('B #2', { n: 300, off: 4 * H })];
  const r = K.align(items); assert.equal(byKey(r, 'B #2').shift, 0); assert.equal(r.edges.length, 0);
});

t('accuracy over 50 seeded runs (offset ±12 h, 3–20 shared moments)', () => {
  const errs = []; let missed = 0, wrong = 0;
  for (let k = 0; k < 50; k++) {
    const off = Math.round((rnd() * 24 - 12) * H / 1000) * 1000, nm = 3 + Math.floor(rnd() * 18), mom = momentsAt(nm);
    const r = K.align([...shoot('A #1', { n: 80, moments: mom }), ...shoot('B #2', { n: 40, moments: mom, off })]);
    const b = byKey(r, 'B #2');
    if (Math.abs(off) < 120e3) continue;
    if (!b.shift) { missed++; continue; }
    const e = Math.abs(b.shift + off); errs.push(e); if (e > 60e3) wrong++;
  }
  errs.sort((a, b) => a - b);
  console.log(`      ${errs.length} aligned, ${missed} missed, ${wrong} off by > 1 min, median error ${Math.round(errs[errs.length >> 1] / 1000)} s, max ${Math.round(errs[errs.length - 1] / 1000)} s`);
  assert.equal(wrong, 0); assert.ok(missed <= 2, 'missed ' + missed);
});

if (fails) { console.log(fails + ' failed'); process.exit(1); }
console.log('all passed');
