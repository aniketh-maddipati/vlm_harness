// The Skim page's listing and first-look order, read out of the page itself (as skim-export does for buildX).
//
//   node --test Tests/web/skim-ingest.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const SRC = fs.readFileSync(PAGE, 'utf8');
/** A method with arguments: extractMethod only knows `name() {`, so the arguments are taken out and put back. */
function method(name, async_ = false){
  const m = SRC.match(new RegExp('\\n  ' + (async_ ? 'async ' : '') + name + '\\(([^)]*)\\) \\{'));
  assert.ok(m, 'method not found: ' + name);
  const body = extractMethod(SRC.replace(m[0], '\n  ' + name + '() {'), name);
  return new Function('return ' + (async_ ? 'async ' : '') + 'function ' + body.replace(name + '()', name + '(' + m[1] + ')'))();
}
const page = {
  gammaName: method('gammaName'), primName: method('primName'), sonyMeta: method('sonyMeta'),
  tailMeta: method('tailMeta', true), inBatches: method('inBatches', true), firstOrder: method('firstOrder'),
};

// Shaped like the NonRealTimeMeta an a7S III writes (values made up).
const NRT = `<?xml version="1.0" encoding="UTF-8"?><NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.20" lastUpdate="2026-09-12T10:21:33-07:00">
<Duration value="312"/><LtcChangeTable tcFps="24" halfStep="false"><LtcChange frameCount="0" value="11450910" status="increment"/><LtcChange frameCount="311" value="10460910" status="end"/></LtcChangeTable>
<CreationDate value="2026-09-12T10:21:20-07:00"/><VideoFormat><VideoFrame videoCodec="HEVC_3840_2160_M422P10@L51" captureFps="23.98p" formatFps="23.98p"/></VideoFormat>
<Device manufacturer="Sony" modelName="ILCE-7SM3" serialNo="1"/>
<AcquisitionRecord><Group name="CameraUnitMetadataSet"><Item name="CaptureGammaEquation" value="s-log3-cine"/><Item name="CaptureColorPrimaries" value="s-gamut3-cine"/></Group></AcquisitionRecord></NonRealTimeMeta>`;
const file = (name, tail, pad = 40000) => ({ name, size: pad + tail.length, _b: 'x'.repeat(pad) + tail,
  slice(a){ const b = this._b.slice(a); return { text: async () => b }; }, text: async function(){ return this._b; } });

test('sonyMeta: camera, profile, length, capture time and timecode from the XML alone', () => {
  const m = page.sonyMeta(NRT, 'file');
  assert.deepEqual(m.prof, { gamma: 'S-Log3', primaries: 'S-Gamut3.Cine', source: 'file' });
  assert.equal(m.t, '2026-09-12T10:21:20'); assert.equal(m.fps, 24); assert.equal(m.cam, 'ILCE-7SM3'); assert.equal(m.ltc, '11450910');
  assert.ok(Math.abs(m.xdur - 312 / 23.98) < 1e-9);
});
test('sonyMeta: nothing to read gives an empty answer, never a throw', () => {
  assert.deepEqual(page.sonyMeta(null, 'file'), { prof: { gamma: null, primaries: null, source: 'none' }, t: null, fps: 0, fd: null, nf: 0, xdur: 0, cam: '', ltc: '' });
});
test('tailMeta: reads the end of the clip when there is no sidecar, and only the last 16 KB', async () => {
  const f = file('C0001.MP4', NRT), asked = []; const sl = f.slice; f.slice = function(a){ asked.push(a); return sl.call(this, a); };
  const m = await page.tailMeta(f, undefined);
  assert.equal(m.prof.source, 'file'); assert.equal(m.cam, 'ILCE-7SM3'); assert.deepEqual(asked, [f.size - 16384]);
});
test('tailMeta: the sidecar wins when it has the metadata; a clip with neither is listed without', async () => {
  const f = file('C0002.MP4', 'no xml here'); let touched = false; const sl = f.slice; f.slice = function(a){ touched = true; return sl.call(this, a); };
  assert.equal((await page.tailMeta(f, { text: async () => NRT })).prof.source, 'sidecar'); assert.equal(touched, false);
  const none = await page.tailMeta(file('GOPR1.MP4', 'no xml here'), undefined);
  assert.equal(none.prof.source, 'none'); assert.equal(none.t, null); assert.equal(none.xdur, 0);
});
test('tailMeta: a file that cannot be read is still listed', async () => {
  const m = await page.tailMeta({ name: 'C0003.MP4', size: 10, slice(){ return { text: async () => { throw new Error('gone'); } }; } }, undefined);
  assert.equal(m.prof.source, 'none');
});
test('inBatches: answers in the order given, never more than n at once, every item once', async () => {
  let live = 0, peak = 0; const seen = [];
  const out = await page.inBatches(Array.from({ length: 401 }, (_, i) => i), 16, async i => { live++; peak = Math.max(peak, live); await new Promise(r => setTimeout(r, (i * 7) % 5)); live--; seen.push(i); return i * 2; });
  assert.equal(out.length, 401); assert.ok(out.every((v, i) => v === i * 2)); assert.equal(peak, 16); assert.equal(new Set(seen).size, 401);
  assert.deepEqual(await page.inBatches([], 16, async x => x), []);
});

const G = [['a1', 'a2', 'a3'], ['b1', 'b2'], ['c1', 'c2', 'c3'], ['d1']], ALL = [].concat(...G);
const order = o => page.firstOrder({ order: ALL, todo: new Set(ALL), have: new Set(), groups: G, ...o });
test('firstOrder: scenes on screen get their covers first, then every scene, then the rest in turns', () => {
  assert.deepEqual(order({ seenG: [2, 3] }), ['c1', 'd1', 'a1', 'b1', 'c2', 'a2', 'b2', 'c3', 'a3']);
});
test('firstOrder: clips on screen come before any cover', () => {
  assert.deepEqual(order({ seen: ['b2', 'c1', 'c2'] }).slice(0, 5), ['b2', 'c1', 'c2', 'a1', 'd1']);
});
test('firstOrder: a scene that has a frame, or a clip being read, needs no cover', () => {
  const o = order({ todo: new Set(ALL.filter(x => x !== 'a2' && x !== 'c1')), have: new Set(['a2', 'c1']) });
  assert.deepEqual(o.slice(0, 2), ['b1', 'd1']); assert.ok(!o.includes('a2') && !o.includes('c1')); assert.equal(o.length, 7);
});
test('firstOrder: in the Viewer the clip you are on and its neighbours lead', () => {
  assert.deepEqual(order({ cur: 'b2', near: 2 }).slice(0, 5), ['b2', 'c1', 'b1', 'c2', 'a3']);
});
test('firstOrder: every clip still to read comes out once, whatever the scenes are', () => {
  for (const groups of [[], [ALL], ALL.map(x => [x]), [['a1'], ['zz']]]) {
    const o = page.firstOrder({ order: ALL, todo: new Set(ALL), have: new Set(), groups, seenG: [0, 9], seen: ['nope', 'b1'] });
    assert.deepEqual(o.slice().sort(), ALL.slice().sort());
  }
});
test('firstOrder: after the covers, the clips the slider would make covers next, largest gap first', () => {
  assert.deepEqual(order({ next: ['c3', 'a2', 'c1', null, 'zz'] }).slice(0, 7), ['a1', 'b1', 'c1', 'd1', 'c3', 'a2', 'b2']);
});
test('firstOrder: the rest goes by place in the scene, the same however many are already read', () => {
  const todo = new Set(ALL.filter(x => !['a1', 'b1', 'c1', 'd1', 'a2'].includes(x)));
  assert.deepEqual(page.firstOrder({ order: ALL, todo, have: new Set(['a1', 'b1', 'c1', 'd1', 'a2']), groups: G }), ['b2', 'c2', 'a3', 'c3']);
});
test('firstOrder: regrouping changes what comes next', () => {
  const todo = new Set(ALL.filter(x => x !== 'a1')), have = new Set(['a1']);
  assert.equal(page.firstOrder({ order: ALL, todo, have, groups: [ALL] })[0], 'a2');                       // one scene, covered: card order
  assert.deepEqual(page.firstOrder({ order: ALL, todo, have, groups: G }).slice(0, 3), ['b1', 'c1', 'd1']);  // four scenes: their covers
});

// ---- measures from the first frame, and the other frames on demand (LOCAL-CHANGES 110–)
/** A static method: `static name(args) {`. */
function staticMethod(name){
  const m = SRC.match(new RegExp('\\n  static ' + name + '\\(([^)]*)\\) \\{'));
  assert.ok(m, 'static method not found: ' + name);
  const body = extractMethod(SRC.replace(m[0], '\n  ' + name + '() {'), name);
  return new Function('return function ' + body.replace(name + '()', name + '(' + m[1] + ')'))();
}
const Component = { askIdx: staticMethod('askIdx'), lookAgain: staticMethod('lookAgain') };
const fn = (name, extra = {}) => new Function('Component', 'return ' + method(name).toString())(Component);
const meas = { pix: method('pix'), factsOf: method('factsOf'), provMark: method('provMark'), factsAll: fn('factsAll'), blank: method('blank'),
  fillOrder: method('fillOrder'), fromN: method('fromN'), mp: { per: 8 }, frameIdx(){ return [0, 1, 2, 3, 4, 5, 6, 7]; } };
const img = (w, h, f) => { const data = new Uint8ClampedArray(w * h * 4); for (let i = 0, j = 0; i < data.length; i += 4, j++) { const v = f(j % w, Math.floor(j / w)); data[i] = data[i + 1] = data[i + 2] = v; data[i + 3] = 255; } return { data, width: w, height: h }; };
const grey = v => meas.pix(img(32, 18, (x, y) => ((x + y) % 2 ? v + 20 : v - 20)));

test('facts from one frame are ready and marked provisional; from all eight they are not', () => {
  const c = { _px: { 3: grey(120) } };
  const one = meas.factsAll(c);
  assert.equal(one.state, 'ready'); assert.equal(one.n, 1); assert.equal(one.of, 8); assert.equal(one.prov, true); assert.equal(c.first, true);
  assert.deepEqual(one.idx, [3]); assert.equal(one.sharpF.length, 1); assert.equal(one.bump, null);
  for (let i = 0; i < 8; i++) c._px[i] = grey(120);
  const all = meas.factsAll(c);
  assert.equal(all.n, 8); assert.equal(all.prov, undefined); assert.equal(c.first, false); assert.equal(all.sharpF.length, 8);
  assert.equal(all.ev, one.ev);                      // the same picture measures the same from one frame or eight
});
test('facts: seven frames of eight stay provisional and say seven', () => {
  const c = { _px: {} }; for (let i = 0; i < 7; i++) c._px[i] = grey(120);
  const f = meas.factsAll(c); assert.equal(f.n, 7); assert.equal(f.prov, true);
  assert.equal(meas.fromN(1), 'from one frame'); assert.equal(meas.fromN(7), 'from 7 frames');
});
test('facts: with fewer frames per clip set, that many is all of them', () => {
  const m = { ...meas, frameIdx(){ return [2, 6]; } }, c = { _px: { 2: grey(120), 6: grey(120) } };
  const f = m.factsAll(c); assert.equal(f.of, 2); assert.equal(f.prov, undefined);
});
test('an all-dark frame is a frame: it is kept after the looks, and reads as dark', () => {
  const black = img(32, 18, () => 0);
  assert.equal(meas.blank(black), true);
  assert.equal(Component.lookAgain(true, 0), true); assert.equal(Component.lookAgain(true, 1), true);
  assert.equal(Component.lookAgain(true, 2), false);      // the third look is kept, dark or not
  assert.equal(Component.lookAgain(false, 0), false);     // a picture is kept at once
  assert.ok(!/blank\(im\)\) break; im = null/.test(SRC) && !/if \(!im\) continue;/.test(SRC), 'readClip must not drop a dark frame');
  const f = meas.factsAll({ _px: { 3: meas.pix(black) } });
  assert.equal(f.state, 'ready'); assert.equal(f.ev, -5); assert.equal(f.crush, 100); assert.equal(f.clip, 0);
});
test('askIdx: a frame that is there is not asked for; one that was missed is asked for once more, then left', () => {
  const idx = [0, 1, 2, 3, 4, 5, 6, 7], fr = [null, 'u', null, 'u', null, null, null, null];
  assert.deepEqual(Component.askIdx(fr, undefined, idx), [0, 2, 4, 5, 6, 7]);
  assert.deepEqual(Component.askIdx(fr, { 0: 1, 2: 2, 4: 3 }, idx), [0, 5, 6, 7]);
  assert.deepEqual(Component.askIdx(fr, { 0: 2, 2: 2, 4: 2, 5: 2, 6: 2, 7: 2 }, idx), []);
  assert.deepEqual(Component.askIdx(fr, null, [1, 3]), []);
});

const FLAT = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'], every = () => new Set(FLAT);
const fo = o => meas.fillOrder({ flat: FLAT, todo: every(), idle: every(), near: 3, ...o });
test('fillOrder: in the Viewer the clip you are on and three each side come first, then the quiet fill', () => {
  const o = fo({ lv: 2, cur: 'e' });
  assert.deepEqual(o.slice(0, 7), [['e', 'viewer'], ['f', 'viewer'], ['d', 'viewer'], ['g', 'viewer'], ['c', 'viewer'], ['h', 'viewer'], ['b', 'viewer']]);
  assert.deepEqual(o.slice(7), [['i', 'idle'], ['a', 'idle'], ['j', 'idle']]);
});
test('fillOrder: in Clips the tile under the pointer first, then the tiles on screen nearest the clip you are on, then the rest', () => {
  const o = fo({ lv: 1, cur: 'c', hover: 'h', seen: ['a', 'b', 'c', 'd', 'h'] });
  assert.deepEqual(o.slice(0, 5), [['h', 'hover'], ['c', 'seen'], ['b', 'seen'], ['d', 'seen'], ['a', 'seen']]);
  assert.deepEqual(o.slice(5).map(x => x[1]), ['idle', 'idle', 'idle', 'idle', 'idle']);
  assert.deepEqual(o.slice(5).map(x => x[0]), ['e', 'f', 'g', 'i', 'j']);       // nearest the clip you are on first
});
test('fillOrder: in Scenes nothing is asked for on demand; only what still needs frames is ever listed, once', () => {
  assert.ok(fo({ lv: 0, cur: 'a', hover: 'b', seen: ['c'] }).every(x => x[1] === 'idle'));
  const o = fo({ lv: 1, cur: 'c', hover: 'h', seen: ['b', 'c', 'h', 'zz'], todo: new Set(['b', 'h']), idle: new Set(['b', 'j']) });
  assert.deepEqual(o, [['h', 'hover'], ['b', 'seen'], ['j', 'idle']]);
});
test('fillOrder: no quiet fill when it is over (or the limit is near), and on Export nothing but that', () => {
  assert.deepEqual(fo({ lv: 2, cur: 'e', idle: null }).length, 7);
  assert.deepEqual(fo({ lv: 1, cur: 'c', hover: 'h', seen: ['c'], idle: null }), [['h', 'hover'], ['c', 'seen']]);
  assert.ok(fo({ lv: -1, cur: 'e', hover: 'h', seen: ['c'] }).every(x => x[1] === 'idle'));
});
