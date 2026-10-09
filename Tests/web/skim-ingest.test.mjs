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
  assert.deepEqual(page.sonyMeta(null, 'file'), { prof: { gamma: null, primaries: null, source: 'none' }, t: null, fps: 0, xdur: 0, cam: '', ltc: '' });
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
