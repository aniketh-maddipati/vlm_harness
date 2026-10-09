// The Export screen's list of cut clips (Component.cutList), read out of the page itself: the text a
// creator copies or downloads to delete those clips by hand in Finder. Also pins the Export defaults
// and the words on the Export screen.
//
//   node --test Tests/web/skim-cutlist.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod, fixture, loadBuildX, ctxFromFixture } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const cutList = new Function('return function ' + extractMethod(src, 'cutList', 'static cutList(clips, marks, fmtB, real) {').replace(/^static /, ''))();
const fmtB = new Function('return function ' + extractMethod(src, 'fmtB', 'fmtB(b) {'))();

const clip = (id, name, t, bytes, path) => ({ id, name, t, bytes, path });
const card = [
  clip('a', 'C0003.MP4', '2026-09-08T19:52:00', 1_500_000_000, 'Untitled/PRIVATE/M4ROOT/CLIP/C0003.MP4'),
  clip('b', 'C0001.MP4', '2026-09-08T19:50:00', 700_000_000, 'Untitled/PRIVATE/M4ROOT/CLIP/C0001.MP4'),
  clip('c', 'C0002.MP4', '2026-09-08T19:51:00', 2_000_000_000, 'Untitled/PRIVATE/M4ROOT/CLIP/C0002.MP4'),
  clip('d', 'C0004.MP4', '2026-09-08T19:53:00', 900_000_000, 'Untitled/PRIVATE/M4ROOT/CLIP/C0004.MP4'),
];

test('cutList comes out of the page', () => {
  assert.equal(typeof cutList, 'function');
  assert.equal(typeof fmtB, 'function');
});

test('only cut clips are listed, in capture order, whatever order they arrive in', () => {
  const x = cutList(card, { a: 'cut', b: 'cut', c: 'keep', d: 'maybe' }, fmtB, true);
  assert.equal(x.n, 2);
  assert.deepEqual(x.text.split('\n').slice(1, -1), [
    'Untitled/PRIVATE/M4ROOT/CLIP/C0001.MP4',
    'Untitled/PRIVATE/M4ROOT/CLIP/C0003.MP4',
  ]);
  assert.deepEqual(card.map(c => c.id), ['a', 'b', 'c', 'd'], 'the clips themselves are not reordered');
});

test('the first line states the count and the total size', () => {
  const x = cutList(card, { a: 'cut', b: 'cut', c: 'cut' }, fmtB, true);
  assert.equal(x.bytes, 4_200_000_000);
  assert.equal(x.text.split('\n')[0], '3 cut clips · 4.2 GB');
  assert.equal(cutList(card, { b: 'cut' }, fmtB, true).text.split('\n')[0], '1 cut clip · 700 MB');
});

test('one clip per line and the text ends with a newline', () => {
  const x = cutList(card, { a: 'cut', b: 'cut', c: 'cut', d: 'cut' }, fmtB, true);
  assert.ok(x.text.endsWith('.MP4\n'));
  assert.equal(x.text.split('\n').length, 1 + 4 + 1);
});

test('names only when the page has no real path', () => {
  // The sample and test loads carry made-up relative paths: real is false, so the name is what is listed.
  const sample = [clip('a', 'C0001.MP4', '1', 10e6, 'TEST/a'), clip('b', 'C0002.MP4', '2', 10e6, undefined)];
  assert.deepEqual(cutList(sample, { a: 'cut', b: 'cut' }, fmtB, false).text.split('\n').slice(1, -1), ['C0001.MP4', 'C0002.MP4']);
  // A clip with no path at all is listed by name even in a real folder.
  assert.deepEqual(cutList(sample, { b: 'cut' }, fmtB, true).text.split('\n').slice(1, -1), ['C0002.MP4']);
});

test('an absolute path is always used', () => {
  const fx = fixture();
  const marks = Object.fromEntries(fx.clips.filter(c => c.mark).map(c => [c.id, c.mark]));
  const x = cutList(fx.clips, marks, fmtB, false);
  const want = fx.clips.filter(c => c.mark === 'cut').map(c => c.path);
  assert.ok(want.length && want.every(p => p[0] === '/'));
  assert.deepEqual(x.text.split('\n').slice(1, -1), want);
});

test('no cut clips: nothing to list', () => {
  assert.deepEqual(cutList(card, { a: 'keep', b: 'maybe' }, fmtB, true), { n: 0, bytes: 0, text: '' });
  assert.deepEqual(cutList([], {}, fmtB, true), { n: 0, bytes: 0, text: '' });
});

test('Export starts on selected plus maybes, and that option is unchanged in what it produces', () => {
  const m = /ex:\{event:'',kw:'maybe',maybes:(true|false),all:(true|false)\}/.exec(src);
  assert.ok(m, 'the export defaults are in the page state');
  assert.deepEqual([m[1], m[2]], ['true', 'false']);
  const fx = fixture(), { fn } = loadBuildX();
  const x = fn.call(ctxFromFixture(fx, { all: false, maybes: true }));
  assert.equal(x.n, fx.clips.filter(c => c.mark === 'keep' || c.mark === 'maybe').length);
  assert.doesNotMatch(x.text, /value="reject"/);
});

test('the Export screen says selected / maybe / cut and nothing else for the marks', () => {
  const a = src.indexOf('data-screen-label="Export"'), b = src.indexOf('data-screen-label="Skim empty"');
  const vals = extractMethod(src, 'extraVals', 'extraVals(markN, markB, und) {');
  // visible text: what sits between tags in the template, and the string literals in the Export values
  // ('keep' on its own is the stored key of the selected mark, never shown)
  const lits = (vals.slice(vals.indexOf('if (v.isExport)')).match(/'[^'\n]*'/g) || []).filter(l => l !== "'keep'");
  assert.ok(lits.length > 20);
  const shown = src.slice(a, b).replace(/<[^>]*>/g, ' ') + ' ' + lits.join(' ');
  assert.doesNotMatch(shown, /\b(keep|kept|keepers?|reject\w*|flag\w*)\b/i);
  assert.match(shown, /Clip files are never changed\./);
  assert.match(shown, /The page cannot delete files; delete these in Finder\./);
  assert.doesNotMatch(shown, /send to Final Cut|opens? in Final Cut/i);
});
