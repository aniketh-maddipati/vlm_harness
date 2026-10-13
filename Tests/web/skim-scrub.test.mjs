// Scrubbing in the Skim page's Viewer: what a pinch settles to, what to do about a video that
// does not land where it was asked, and what the line under a picture says when there is little
// or nothing to scrub. The page is the one implementation; the functions are read out of it the
// way skim-export.mjs reads buildX.
//
//   node --test Tests/web/skim-scrub.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const [name, args] of [['zoomSettle', 'z'], ['zoomHeld', 'z'], ['pointerScrubs', 'z, isCur'], ['panTo', 'zo, dx, dy, w, h, z'], ['seekVerdict', 'o'], ['skimSay', 'have, cur, vidOff']]){
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}
const at = (o = {}) => ({err:false, rs:4, seeking:false, ct:2, want:2, ms:0, tries:0, ...o});

test('a slight pinch settles back to fit, a real zoom stays', () => {
  for (const z of [1, 1.02, 1.051, 1.2, 1.249]) assert.equal(C.zoomSettle(z), 1, String(z));
  for (const z of [1.25, 1.6, 2.5, 6]) assert.equal(C.zoomSettle(z), z, String(z));
});

// Zoomed in means hold the frame and look around; at fit means skim.
test('at fit the pointer skims; so does the moment of a slight pinch', () => {
  for (const z of [1, 1.02, 1.051, 1.2, 1.249]){
    assert.equal(C.zoomHeld(z), false, String(z));
    assert.equal(C.pointerScrubs(z, true), true, String(z));
    assert.equal(C.pointerScrubs(z, false), true, String(z));
  }
});

test('zoomed in, the pointer holds the frame of the clip in the Viewer; its neighbours still skim', () => {
  for (const z of [1.25, 1.6, 2.5, 6]){
    assert.equal(C.zoomHeld(z), true, String(z));
    assert.equal(C.pointerScrubs(z, true), false, String(z));
    assert.equal(C.pointerScrubs(z, false), true, String(z));
  }
});

test('held is exactly what would not settle: the label and the hold never show for a zoom that is about to go back to fit', () => {
  for (let z = 1; z <= 6; z += 0.01) assert.equal(C.zoomHeld(z), C.zoomSettle(z) !== 1, z.toFixed(2));
});

test('the page asks the rule, in the pointer, the click, the drag and the swipe', () => {
  const line = name => { const m = new RegExp('\\n  ' + name + ' = e => \\{[^\\n]*(\\n    [^\\n]*)*').exec(src); assert.ok(m, name + ' found'); return m[0]; };
  for (const name of ['picMove', 'picDown', 'picClick']) assert.ok(/Component\.pointerScrubs\(/.test(line(name)), name);
  assert.ok(!/zc > 1\.01\) return this\.panBy/.test(src), 'a swipe pans only when zoomHeld');
  assert.ok(/zOn:isC && Component\.zoomHeld\(st\.zc\), zT:'zoomed · Z to fit'/.test(src), 'the label');
});

test('a drag moves the picture with the hand', () => {
  const zo = {x:0.5, y:0.5}, w = 900, h = 506, z = 2.5;
  assert.deepEqual(C.panTo(zo, 0, 0, w, h, z), zo);
  // the picture is drawn scaled about its origin: a point at p lands at o·W + (p − o·W)·z, so moving the origin by d moves it by −d·W·(z − 1)
  const shift = (a, b) => -(b.x - a.x) * w * (z - 1);
  const b = C.panTo(zo, 120, 0, w, h, z); assert.ok(Math.abs(shift(zo, b) - 120) < 1e-9, 'x follows 120 px'); assert.equal(b.y, 0.5);
  const c = C.panTo(zo, -60, 45, w, h, z); assert.ok(c.x > 0.5 && c.y < 0.5);
  assert.ok(Math.abs(-(c.y - 0.5) * h * (z - 1) - 45) < 1e-9, 'y follows 45 px');
});

test('a drag stops at the edges of the picture', () => {
  assert.deepEqual(C.panTo({x:0.5, y:0.5}, 99999, 99999, 900, 506, 2.5), {x:0, y:0});
  assert.deepEqual(C.panTo({x:0.5, y:0.5}, -99999, -99999, 900, 506, 2.5), {x:1, y:1});
  const e = C.panTo({x:0.5, y:0.5}, 10, 10, 0, 0, 1.25); assert.ok(isFinite(e.x) && isFinite(e.y));
});

test('a video where it was asked to be is left alone', () => {
  assert.equal(C.seekVerdict(at()), 'ok');
  assert.equal(C.seekVerdict(at({ct:2.03, ms:99999})), 'ok');
});

test('a seek is given its time, then the file is opened again', () => {
  assert.equal(C.seekVerdict(at({seeking:true, ms:500})), 'wait');
  assert.equal(C.seekVerdict(at({seeking:true, ms:2499})), 'wait');
  assert.equal(C.seekVerdict(at({seeking:true, ms:2500})), 'again');
  assert.equal(C.seekVerdict(at({ct:0.75, ms:4500})), 'again');           // not seeking, yet not where asked
});

test('opening a file gets longer than a seek', () => {
  assert.equal(C.seekVerdict(at({rs:0, ms:9000})), 'wait');
  assert.equal(C.seekVerdict(at({rs:0, ms:10000})), 'again');
});

test('an error is not waited on', () => {
  assert.equal(C.seekVerdict(at({err:true, ms:0})), 'again');
});

test('retry is bounded: after two more goes the video is left off', () => {
  assert.equal(C.seekVerdict(at({seeking:true, ms:5000, tries:1})), 'again');
  assert.equal(C.seekVerdict(at({seeking:true, ms:5000, tries:2})), 'off');
  assert.equal(C.seekVerdict(at({err:true, tries:2})), 'off');
  assert.equal(C.seekVerdict(at({tries:2})), 'ok');                        // a video that came back is fine again
});

test('the line under the picture says when there is little to scrub', () => {
  assert.equal(C.skimSay(8, true, false), '');
  assert.equal(C.skimSay(0, true, false), '');
  assert.equal(C.skimSay(8, true, true), 'the clip isn’t answering · showing its 8 sampled frames');
  assert.equal(C.skimSay(1, true, true), 'the clip isn’t answering · nothing to scrub');
  assert.equal(C.skimSay(1, false, false), 'one frame read · click to scrub');
  assert.equal(C.skimSay(8, false, false), '');
  assert.equal(C.skimSay(0, false, false), '');
});

test('the words stay neutral', () => {
  for (const s of [C.skimSay(8, true, true), C.skimSay(1, true, true), C.skimSay(1, false, false)]) assert.ok(!/\bkeep|kept|keepers\b/i.test(s), s);
});
