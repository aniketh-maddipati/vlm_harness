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
for (const [name, args] of [['zoomSettle', 'z'], ['seekVerdict', 'o'], ['skimSay', 'have, cur, vidOff']]){
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}
const at = (o = {}) => ({err:false, rs:4, seeking:false, ct:2, want:2, ms:0, tries:0, ...o});

test('a slight pinch settles back to fit, a real zoom stays', () => {
  for (const z of [1, 1.02, 1.051, 1.2, 1.249]) assert.equal(C.zoomSettle(z), 1, String(z));
  for (const z of [1.25, 1.6, 2.5, 6]) assert.equal(C.zoomSettle(z), z, String(z));
});

test('the pointer scrubs the clip in the Viewer whatever the zoom', () => {
  const m = /picMove = e => \{[^\n]*\n[^\n]*/.exec(src);
  assert.ok(m, 'picMove found');
  assert.ok(!/zc/.test(m[0]), 'picMove does not look at the zoom');
});

test('a video where it was asked to be is left alone', () => {
  assert.equal(C.seekVerdict(at()), 'ok');
  assert.equal(C.seekVerdict(at({ct:2.03, ms:99999})), 'ok');
});

test('a seek is given its time, then the file is opened again', () => {
  assert.equal(C.seekVerdict(at({seeking:true, ms:500})), 'wait');
  assert.equal(C.seekVerdict(at({seeking:true, ms:3999})), 'wait');
  assert.equal(C.seekVerdict(at({seeking:true, ms:4000})), 'again');
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
