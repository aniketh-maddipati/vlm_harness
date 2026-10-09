// The Rec.709 switch: which clips it changes, and how the picture gets the preview in each place.
// The functions are read out of the page itself (as skim-export.mjs does for buildX), so there is no second copy.
//
//   node --test Tests/web/skim-rec709.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');

/** A class method with arguments, by brace-matching (strings skipped). */
function method(name){
  const at = src.indexOf('\n  ' + name + '(');
  assert.ok(at >= 0, 'method not found: ' + name);
  let i = src.indexOf('{', src.indexOf(')', at)), depth = 0;
  for (; i < src.length; i++){
    const ch = src[i];
    if (ch === '"' || ch === "'" || ch === '`'){ for (i++; i < src.length; i++){ if (src[i] === '\\'){ i++; continue; } if (src[i] === ch) break; } continue; }
    if (ch === '{') depth++;
    else if (ch === '}'){ depth--; if (!depth) return src.slice(at + 3, i + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

const names = ['prof', 'needsPv', 'pvFlt', 'pvOn', 'pvVia', 'pvDisabled', 'gammaName'];
const Skim = new Function('return class {\n' + names.map(method).join('\n') + '\n}')();
const page = (pv, clips = []) => Object.assign(new Skim(), { state:{pv}, d:{clips} });
const clip = (gamma, source = 'sidecar') => ({ profile:{gamma, primaries:'', source} });

const SL3 = clip('S-Log3'), SL2 = clip('S-Log2'), HLG = clip('HLG'), REC = clip('none');
const OTHER = clip('s-cinetone'), UNKNOWN = { profile:{gamma:null, primaries:null, source:'none'} }, BARE = {};

test('the camera\'s own names: log profiles are known, Rec.709 reads as nothing to convert', () => {
  const p = page(true);
  assert.equal(p.gammaName('s-log3-cine'), 'S-Log3');
  assert.equal(p.gammaName('rec709-xvycc'), 'none');
  assert.equal(p.gammaName('rec709'), 'none');
});

test('switch on: log clips are converted, every other clip is left as it is', () => {
  const p = page(true);
  for (const c of [SL3, SL2, HLG]) assert.equal(p.pvOn(c), true);
  for (const c of [REC, OTHER, UNKNOWN, BARE]) assert.equal(p.pvOn(c), false);
});

test('switch off: no clip is converted', () => {
  const p = page(false);
  for (const c of [SL3, SL2, HLG, REC, OTHER, UNKNOWN, BARE]) assert.equal(p.pvOn(c), false);
});

test('a clip that is not log looks the same with the switch on and off', () => {
  for (const c of [REC, OTHER, UNKNOWN, BARE]) assert.equal(page(true).pvOn(c), page(false).pvOn(c));
});

test('the switch is disabled only when no clip in the shoot is log', () => {
  assert.equal(page(true, [REC, REC]).pvDisabled(), true);
  assert.equal(page(true, [REC, OTHER, UNKNOWN]).pvDisabled(), true);
  assert.equal(page(true, [REC, SL3]).pvDisabled(), false);
  assert.equal(page(true, [SL3, SL3]).pvDisabled(), false);
  assert.equal(page(true, [HLG]).pvDisabled(), false);
});

test('a disabled switch never leaves a clip converted', () => {
  // every clip pvDisabled() calls "nothing to convert" is also one pvOn() leaves alone
  const shoot = [REC, OTHER, UNKNOWN, BARE], p = page(true, shoot);
  assert.equal(p.pvDisabled(), true);
  assert.deepEqual(shoot.map(c => p.pvOn(c)), [false, false, false, false]);
});

test('S-Log3 is an SVG filter, which a <video> does not take in WebKit: the Viewer draws it through the canvas', () => {
  const p = page(true);
  assert.equal(p.pvFlt(SL3), 'url(#lumina-slog3)');
  assert.equal(p.pvVia(p.pvFlt(SL3)), 'canvas');
});

test('filters written as functions, and no filter, stay on the video', () => {
  const p = page(true);
  assert.equal(p.pvVia(p.pvFlt(SL2)), 'video');
  assert.equal(p.pvVia(p.pvFlt(HLG)), 'video');
  assert.equal(p.pvVia('none'), 'video');
  assert.equal(p.pvVia(undefined), 'video');
});

test('the Viewer\'s canvas takes the same filter value as the stills and the video, and is wired up', () => {
  const cv = src.match(/<canvas ref="\{\{ pvCvRef \}\}"[^>]*>/);
  assert.ok(cv, 'no preview canvas in the Viewer');
  assert.match(cv[0], /filter:\{\{ it\.flt \}\}/);
  assert.match(cv[0], /transform:\{\{ it\.zt \}\}/);
  assert.match(src, /<video ref="\{\{ vidRef \}\}"[^>]*filter:\{\{ it\.flt \}\}/);
  assert.match(src, /pvCvRef:this\.pvCvRef/);
  assert.match(src, /this\.syncVid\(\); this\.paintVid\(\);/);
});

test('the filter the canvas points at exists once in the page', () => {
  assert.equal(src.split('<filter id="lumina-slog3"').length - 1, 1);
});
