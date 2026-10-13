// Export ▸ Read back (Component.readBack, read out of the page): a .fcpxml, the page's own or one Final Cut exported,
// read as marks. Favorite is keep, reject is cut, the maybe keyword is maybe; a clip in the file with none of those is
// unmarked. Clips are found by their file's full path, else by a file name only one clip has.
//
//   node --test Tests/web/skim-readback.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod, fixture, loadBuildX, ctxFromFixture } from './skim-export.mjs';
import { MiniDOMParser } from './mini-xml.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const readBack = new Function('return function ' + extractMethod(src, 'readBack', 'static readBack(text, clips, abs, P, kw) {').replace(/^static /, ''))();
const fx = fixture(), ctx = ctxFromFixture(fx), clips = ctx.d.clips;
const abs = c => c.path;
const read = (text, kw, cs = clips, a = abs) => readBack(text, cs, a, MiniDOMParser, kw);
const marks = Object.fromEntries(fx.clips.map(c => [c.id, c.mark || null]));

test('what the page writes reads back as the same marks', () => {
  const x = loadBuildX().fn.call(ctxFromFixture(fx, { all: true, maybes: true }));
  const r = read(x.text);
  assert.deepEqual(r.missing, []);
  assert.equal(r.matched, x.n);
  for (const id of Object.keys(r.want)) assert.equal(r.want[id], marks[id], id);
});

test('a Final Cut export: a favorite range anywhere keeps, reject cuts, the keyword is maybe, nothing clears', () => {
  const asset = (id, name, at) => `<asset id="${id}" name="${name}" start="0s" duration="100s"><media-rep kind="original-media" src="file://${at.split('/').map(encodeURIComponent).join('/')}"/></asset>`;
  const text = `<?xml version="1.0"?><fcpxml version="1.11"><resources>
    ${asset('r2', 'C0002', '/Volumes/Untitled/PRIVATE/M4ROOT/CLIP/C0002.MP4')}
    ${asset('r3', 'C0003', '/elsewhere/C0003.MP4')}
    ${asset('r4', 'C0019', '/Volumes/Untitled/PRIVATE/M4ROOT/CLIP/C0019.MP4')}
    ${asset('r5', 'C0030', '/Volumes/Untitled/PRIVATE/M4ROOT/CLIP/C0030.MP4')}
    ${asset('r6', 'C9999', '/Volumes/Untitled/PRIVATE/M4ROOT/CLIP/C9999.MP4')}
  </resources><library><event name="e">
    <asset-clip ref="r2" name="C0002" duration="100s"><rating start="10s" duration="2s" value="reject"/><rating start="40s" duration="5s" value="favorite"/></asset-clip>
    <asset-clip ref="r3" name="C0003" duration="100s"><rating start="0s" duration="100s" value="reject"/></asset-clip>
    <clip name="C0019" duration="100s"><video ref="r4" duration="100s"/><keyword start="0s" duration="100s" value="b-roll, Maybe"/></clip>
    <asset-clip ref="r5" name="C0030" duration="100s"/>
    <asset-clip ref="r6" name="C9999" duration="100s"/>
  </event></library></fcpxml>`;
  const r = read(text, 'maybe');
  assert.deepEqual(r.want, { c1: 'keep', c2: 'cut', c3: 'maybe', c5: null }, 'C0003 found by its name; C0030 is in the file unmarked');
  assert.deepEqual(r.missing, ['C9999.MP4']);
  assert.equal(r.matched, 4);
  assert.equal(read(text, 'select').want.c3, null, 'another keyword is not maybe');
});

test('a name two clips share is matched only by path', () => {
  const two = [...clips, { id: 'c7', name: 'C0003.MP4', path: '/Volumes/B/CLIP/C0003.MP4' }];
  const text = `<fcpxml version="1.10"><resources><asset id="a" name="C0003" start="0s" duration="1s"><media-rep src="file:///else/C0003.MP4"/></asset></resources><library><event><asset-clip ref="a" duration="1s"><rating start="0s" duration="1s" value="favorite"/></asset-clip></event></library></fcpxml>`;
  const r = read(text, 'maybe', two);
  assert.deepEqual(r.want, {});
  assert.deepEqual(r.missing, ['C0003.MP4']);
});

test('not a Final Cut file', () => {
  assert.equal(read('<xml/>'), null);
  assert.equal(read('not xml'), null);
});
