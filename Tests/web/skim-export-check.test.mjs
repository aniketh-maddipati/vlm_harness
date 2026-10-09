// The Export screen's own check of the .fcpxml before it lets the file go (Component.checkX, read out of
// the page). It is a check of structure. Final Cut's DTD is the other check (skim-export.test.mjs, with
// xmllint), repeated here for a maybes-only file and an Everything file.
//
// Node has no DOMParser and nothing is installed for this, so checkX runs here on Tests/web/mini-xml.mjs.
// The browser's own parser is exercised in the browser run of the Export screen, not here.
//
//   node --test Tests/web/skim-export-check.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod, fixture, loadBuildX, ctxFromFixture, validateAgainstDTD } from './skim-export.mjs';
import { MiniDOMParser } from './mini-xml.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const checkX = new Function('return function ' + extractMethod(src, 'checkX', 'static checkX(text, n, P) {').replace(/^static /, ''))();
const check = (text, n) => checkX(text, n, MiniDOMParser);
const buildX = loadBuildX().fn, fx = fixture();
const build = (over, f = fx) => buildX.call(ctxFromFixture(f, over));
const marked = (f, mark) => ({ ...f, clips: f.clips.map(c => ({ ...c, mark: typeof mark === 'function' ? mark(c) : mark })) });
const good = build({ all: false, maybes: true });
/** one change to the good file, which must take */
const broke = (from, to) => { assert.ok(good.text.includes(from), 'the file has: ' + from); return good.text.replace(from, to); };
const fails = (text, sentence, n = good.n) => {
  const r = check(text, n);
  assert.equal(r.ok, false);
  assert.ok(r.problems.includes(sentence), 'wanted "' + sentence + '", got: ' + JSON.stringify(r.problems));
  return r;
};

test('checkX comes out of the page and checks the version buildX declares', () => {
  assert.equal(typeof checkX, 'function');
  assert.match(good.text, /<fcpxml version="1\.10">/);
  assert.match(extractMethod(src, 'checkX', 'static checkX(text, n, P) {'), /'1\.10'/);
});

test('what buildX writes for the fixture passes, under every option', () => {
  for (const over of [{ all: true, maybes: true }, { all: false, maybes: true }, { all: false, maybes: false }]) {
    const x = build(over);
    assert.deepEqual(check(x.text, x.n), { ok: true, problems: [] }, JSON.stringify(over));
  }
});

test('it passes for other shoots buildX can write: maybes only, cut only with Everything, mixed rates, odd names', () => {
  const maybes = build({ all: false, maybes: true }, marked(fx, 'maybe'));
  assert.equal(maybes.n, 6);
  assert.deepEqual(check(maybes.text, 6), { ok: true, problems: [] });
  const cuts = build({ all: true, maybes: true }, marked(fx, 'cut'));
  assert.deepEqual(check(cuts.text, 6), { ok: true, problems: [] });
  const odd = { ...fx, clips: fx.clips.map((c, i) => ({ ...c, mark: 'keep', fps: [24, 25, 30, 50, 60, 120][i], name: 'A&B "<' + i + '>.MP4', path: 'My Card/day one/A&B <' + i + '>.MP4' })) };
  const x = build({ all: false, maybes: true, event: 'Tom & Jerry <"cut">' }, odd);
  assert.deepEqual(check(x.text, 6), { ok: true, problems: [] });
  // a stand-in clip as the browser lists it before it is measured: no size, no rate, a relative path
  const bare = { shoot: { name: 'friend_test_log', rate: 24 }, clips: [{ id: 'F0001', name: 'C4925.MP4', path: 'friend_test_log/C4925.MP4', dur: 0, fps: undefined, w: 0, h: 0 }] };
  const b = buildX.call({ d: bare, state: { marks: { F0001: 'keep' }, ex: { event: '', all: false, maybes: true } } });
  assert.deepEqual(check(b.text, 1), { ok: true, problems: [] });
});

test('an unclosed tag: not well-formed, and nothing else is claimed', () => {
  const r = fails(broke('    </event>\n', ''), 'The file is not well-formed XML.');
  assert.equal(r.problems.length, 1);
  fails(good.text.replace('</asset-clip>', ''), 'The file is not well-formed XML.');
  fails('', 'The file is not well-formed XML.', 0);
});

test('a clip pointing at media that is not in the file', () => {
  fails(broke('<asset-clip ref="a1"', '<asset-clip ref="a9"'), 'Clip “C0002” refers to media that is not in the file.');
});

test('a zero or missing length', () => {
  const du = /<asset-clip ref="a1" name="C0002" duration="([^"]+)"/.exec(good.text)[1];
  fails(broke(`<asset-clip ref="a1" name="C0002" duration="${du}"`, '<asset-clip ref="a1" name="C0002" duration="0s"'), 'Clip “C0002” has no length.');
  fails(broke(`<asset-clip ref="a1" name="C0002" duration="${du}"`, '<asset-clip ref="a1" name="C0002"'), 'Clip “C0002” has no length.');
  fails(broke(`<asset id="a1" name="C0002" start="0s" duration="${du}"`, '<asset id="a1" name="C0002" start="0s" duration="0/24000s"'), 'The media entry for “C0002” has no length.');
});

test('a length that is not whole frames, or longer than the media', () => {
  const du = /<asset-clip ref="a1" name="C0002" duration="(\d+)\/24000s"/.exec(good.text)[1];
  const swap = to => good.text.replace(`<asset-clip ref="a1" name="C0002" duration="${du}/24000s"`, `<asset-clip ref="a1" name="C0002" duration="${to}"`).replace(`<rating start="0s" duration="${du}/24000s"`, `<rating start="0s" duration="${to}"`);
  fails(swap((+du - 1) + '/24000s'), 'Clip “C0002” has a length that is not a whole number of frames.');
  fails(swap((+du + 1001) + '/24000s'), 'Clip “C0002” is longer than its media.');
  assert.equal(check(swap((+du - 1001) + '/24000s'), good.n).problems.join(), '', 'one frame shorter is still whole frames');
});

test('a duplicate id', () => {
  fails(broke('<asset id="a2"', '<asset id="a1"'), 'Two entries share the id “a1”.');
});

test('an empty or non-file location', () => {
  const at = /<media-rep kind="original-media" src="([^"]+)"\/>/.exec(good.text)[1];
  fails(broke(`src="${at}"`, 'src=""'), 'The media entry for “C0002” has no file location.');
  fails(broke(`src="${at}"`, 'src="file://"'), 'The media entry for “C0002” does not point at a file:// location.');
  fails(broke(`src="${at}"`, 'src="https://example.com/C0002.MP4"'), 'The media entry for “C0002” does not point at a file:// location.');
  fails(broke(`      <media-rep kind="original-media" src="${at}"/>\n`, ''), 'The media entry for “C0002” has no file location.');
});

test('a format that is not in the file, a missing name, a missing section', () => {
  fails(broke('<format id="r1"', '<format id="r7"'), 'Clip “C0002” uses a format that is not in the file.');
  fails(broke('<asset id="a1" name="C0002"', '<asset id="a1"'), 'A media entry has no name.');
  fails(good.text.replace(/  <resources>[\s\S]*<\/resources>\n/, ''), 'The file has no resources section.');
  fails(good.text.replace(/  <library>[\s\S]*<\/library>\n/, ''), 'The file has no event.');
  fails(broke('<fcpxml version="1.10">', '<fcpxml version="1.11">'), 'The file does not open as fcpxml version 1.10.');
});

test('the count must be the one the button shows', () => {
  fails(good.text, 'The file holds 3 clips but the button says 2.', 2);
  assert.equal(check(good.text, 3).ok, true);
});

test('ratings and keywords only as buildX writes them', () => {
  fails(broke('value="favorite"', 'value="loved"'), 'Clip “C0002” carries a rating this page does not write.');
  fails(broke('<rating start="0s"', '<rating start="1s"'), 'Clip “C0002” carries a rating this page does not write.');
  fails(broke('value="maybe"', 'value="b-roll"'), 'Clip “C0019” carries a keyword this page does not write.');
  fails(broke('      </asset-clip>', '        <note>x</note>\n      </asset-clip>'), 'Clip “C0002” carries something this page does not write.');
});

test('it does not say anything about Final Cut', () => {
  const body = extractMethod(src, 'checkX', 'static checkX(text, n, P) {');
  for (const l of body.match(/'[^'\n]*'/g) || []) assert.doesNotMatch(l, /Final Cut|import/i, l);
  const vals = extractMethod(src, 'extraVals', 'extraVals(markN, markB, und) {');
  assert.match(vals, /'File checked: '/);
  assert.doesNotMatch(vals, /will (open|import)|ready for Final Cut|valid/i);
});

test('Final Cut DTD: a maybes-only file and an Everything file', t => {
  const v = /<fcpxml version="([^"]+)"/.exec(good.text)[1];
  for (const [name, x] of [['maybes only', build({ all: false, maybes: true }, marked(fx, 'maybe'))], ['everything', build({ all: true, maybes: true })], ['everything, all cut', build({ all: true, maybes: true }, marked(fx, 'cut'))]]) {
    const r = validateAgainstDTD(x.text, v);
    if (r.skipped) return t.skip(r.skipped);
    assert.ok(r.ok, `${name}: not valid against FCPXMLv${v}:\n${r.errors}`);
  }
});
