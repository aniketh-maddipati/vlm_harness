// Outlines in the Skim Viewer (O): where a click lands in a frame drawn object-fit: cover, which shape it chooses,
// and what the chips and the line under the picture say. The page is the one implementation; the functions are
// read out of it the way skim-export.mjs reads buildX. The page in a browser is skim-outlines-browser.mjs.
//
//   node --test Tests/web/skim-outlines.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const [name, args] of [['olPoint', 'r, vw, vh, cx, cy'], ['olInside', 'loops, x, y'], ['olHit', 'list, x, y'], ['olName', 's'], ['olSay', 'f, n']]) {
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}
const sq = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];

test('a click maps to the frame through the cover crop', () => {
  // a 4:3 frame in a 16:9 box: cover scales by the width and crops top and bottom
  const r = {left:100, top:50, width:1600, height:900};
  const mid = C.olPoint(r, 1440, 1080, 900, 500); assert.ok(Math.abs(mid.x - 0.5) < 1e-9 && Math.abs(mid.y - 0.5) < 1e-9);
  const tl = C.olPoint(r, 1440, 1080, 100, 50); assert.ok(Math.abs(tl.x) < 1e-9); assert.ok(Math.abs(tl.y - 0.125) < 1e-9, 'an eighth cropped off the top: ' + tl.y);
  // the same frame size as the box: straight through
  const same = C.olPoint({left:0, top:0, width:320, height:180}, 1920, 1080, 80, 45); assert.ok(Math.abs(same.x - 0.25) < 1e-9 && Math.abs(same.y - 0.25) < 1e-9);
  assert.equal(C.olPoint({left:0, top:0, width:0, height:0}, 1920, 1080, 1, 1), null);
  assert.equal(C.olPoint({left:0, top:0, width:10, height:10}, 0, 0, 1, 1), null, 'a video with no size yet');
});

test('inside is even-odd: a hole is outside', () => {
  const ring = [sq(0.2, 0.2, 0.8, 0.8), sq(0.4, 0.4, 0.6, 0.6).reverse()];
  assert.equal(C.olInside(ring, 0.3, 0.3), true);
  assert.equal(C.olInside(ring, 0.5, 0.5), false, 'in the hole');
  assert.equal(C.olInside(ring, 0.9, 0.5), false);
  assert.equal(C.olInside([], 0.5, 0.5), false);
});

test('a click chooses the smallest shape under it, else the background', () => {
  const subject = {id:'subject', kind:'subject', area:0.36, outline:[sq(0.2, 0.2, 0.8, 0.8)]};
  const person = {id:'person-1', kind:'person', area:0.36, outline:[sq(0.2, 0.2, 0.8, 0.8)]};
  const ball = {id:'object-1', kind:'object', area:0.01, outline:[sq(0.6, 0.6, 0.7, 0.7)]};
  const bg = {id:'background', kind:'background', area:0.63, outline:[sq(0, 0, 1, 1), sq(0.2, 0.2, 0.8, 0.8).reverse()]};
  const list = [subject, person, ball, bg];
  assert.equal(C.olHit(list, 0.65, 0.65).id, 'object-1', 'the ball, not the subject around it');
  assert.equal(C.olHit(list, 0.3, 0.3).id, 'subject', 'the same size: the first listed');
  assert.equal(C.olHit(list, 0.1, 0.1).id, 'background');
  assert.equal(C.olHit([subject], 0.1, 0.1), null, 'nothing there and no background');
  assert.equal(C.olHit(null, 0.5, 0.5), null);
});

test('chips and the line say what is there in plain words', () => {
  assert.deepEqual([{id:'subject', kind:'subject'}, {id:'person-2', kind:'person'}, {id:'object-3', kind:'object'}, {id:'sky', kind:'sky'}, {id:'background', kind:'background'}].map(C.olName),
    ['Subject', 'Person 2', 'Object 3', 'Sky', 'Background']);
  const lines = [C.olSay(undefined, 0), C.olSay('wait', 0), C.olSay(null, 0), C.olSay([], 0), C.olSay([{}], 0), C.olSay([{}, {}], 2)];
  assert.deepEqual(lines, ['reading this frame…', 'reading this frame…', 'this frame couldn’t be read', 'nothing to choose in this frame', 'click a shape to choose it', '2 chosen']);
  const banned = /\b(AI|smart|intelligent|detects?|understands|suggests?|recommended|magic|auto\w*|learns|confidence|score)\b/i;
  for (const s of lines.concat(['Outlines', 'Subject', 'Person', 'Object', 'Sky', 'Background'])) assert.doesNotMatch(s, banned, s);
});

test('the page: a held frame for clicks, one read per frame, the app only', () => {
  assert.match(src, /if \(!Component\.pointerScrubs\(this\.state\.zc, id === this\.state\.cur\) \|\| this\.olHold\(id\)\)/, 'picMove holds the frame');
  assert.match(src, /if \(this\.olHold\(id\)\) return this\.olPick\(e\);/, 'picClick chooses');
  assert.match(src, /olApi\(\) \{ const v = typeof window !== 'undefined' && window\.lumina && window\.lumina\.video; return v && v\.masks \? v : null; \}/);
  assert.match(src, /const m = this\.olMap \|\| \(this\.olMap = new Map\(\)\); if \(m\.has\(k\)\) return;/, 'each frame once');
});
