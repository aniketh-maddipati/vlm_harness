// The Rec.709 switch: which clips it changes, and how the picture gets the preview in each place.
// The functions are read out of the page itself (as skim-export.mjs does for buildX), so there is no second copy.
//
//   node --test Tests/web/skim-rec709.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

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

test('the Viewer\'s canvas and video take the clip\'s filter, and are wired up', () => {
  const cv = src.match(/<canvas ref="\{\{ pvCvRef \}\}"[^>]*>/);
  assert.ok(cv, 'no preview canvas in the Viewer');
  assert.match(cv[0], /filter:\{\{ it\.vflt \}\}/);
  assert.match(cv[0], /transform:\{\{ it\.zt \}\}/);
  assert.match(src, /<video ref="\{\{ vidRef \}\}"[^>]*filter:\{\{ it\.vflt \}\}/);
  // the clip's own filter, whether or not a still of it has been made yet
  assert.match(src, /vflt:this\.pvOn\(cc\) \? this\.pvFlt\(cc\) : 'none'/);
  assert.match(src, /pvCvRef:this\.pvCvRef/);
  assert.match(src, /this\.syncVid\(\); this\.paintVid\(\);/);
});

test('the filter the canvas points at exists once in the page', () => {
  assert.equal(src.split('<filter id="lumina-slog3"').length - 1, 1);
});

// ---- the developer colour check (frames for a comparison with Final Cut) ----

const checkTimes = new Function('return function ' + extractMethod(src, 'checkTimes', 'static checkTimes(fps, dur) {').replace(/^static /, ''))();

test('colour check: 2, 5 and 8 s are frame numbers at the clip\'s rate, asked for inside that frame', () => {
  for (const [fps, real, per] of [[23.98, 24000 / 1001, 24], [24, 24, 24], [25, 25, 25], [29.97, 30000 / 1001, 30], [59.94, 60000 / 1001, 60], [0, 24, 24], [undefined, 24, 24]]) {
    const k = checkTimes(fps, 0);
    assert.deepEqual(k.map(x => x.sec), [2, 5, 8]);
    assert.deepEqual(k.map(x => x.n), [2 * per, 5 * per, 8 * per]);
    for (const x of k) assert.equal(Math.floor(x.t * real + 1e-9), x.n, fps + ' fps, ' + x.sec + ' s');
  }
});

test('colour check: a time past the end of the clip is left out', () => {
  assert.deepEqual(checkTimes(23.98, 6).map(x => x.sec), [2, 5]);
  assert.deepEqual(checkTimes(23.98, 1.5).map(x => x.sec), []);
  assert.deepEqual(checkTimes(23.98, 11.5).map(x => x.sec), [2, 5, 8]);
});

const pngNote = new Function('return function ' + extractMethod(src, 'pngNote', 'static pngNote(u8, key, text) {').replace(/^static /, ''))();
const crc32 = u8 => { let c = ~0; for (const b of u8) { c ^= b; for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1; } return ~c >>> 0; };
const chunk = (type, data) => { const body = new Uint8Array([...type].map(ch => ch.charCodeAt(0)).concat([...data])), out = new Uint8Array(12 + data.length), dv = new DataView(out.buffer); dv.setUint32(0, data.length); out.set(body, 4); dv.setUint32(8 + data.length, crc32(body)); return out; };
const fakePng = () => new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, ...chunk('IHDR', new Uint8Array(13)), ...chunk('IDAT', new Uint8Array([1, 2, 3])), ...chunk('IEND', [])]);
const chunks = u8 => { const out = [], dv = new DataView(u8.buffer, u8.byteOffset); for (let i = 8; i < u8.length;) { const n = dv.getUint32(i), type = String.fromCharCode(...u8.subarray(i + 4, i + 8)); out.push({type, data:u8.subarray(i + 8, i + 8 + n), ok:dv.getUint32(i + 8 + n) === crc32(u8.subarray(i + 4, i + 8 + n))}); i += 12 + n; } return out; };
const noteOf = u8 => { const c = chunks(u8).find(k => k.type === 'tEXt'), s = String.fromCharCode(...c.data); return [s.slice(0, s.indexOf('\0')), s.slice(s.indexOf('\0') + 1)]; };

test('colour check: the note goes into the picture as a valid chunk in front of the end, the rest untouched', () => {
  const png = fakePng(), out = pngNote(png, 'skim', JSON.stringify({clip:'Cé4815 — a.MP4', n:[1, 2]}));
  const cs = chunks(out);
  assert.deepEqual(cs.map(c => c.type), ['IHDR', 'IDAT', 'tEXt', 'IEND']);
  assert.ok(cs.every(c => c.ok), 'every chunk keeps a right checksum');
  const [key, text] = noteOf(out);
  assert.equal(key, 'skim'); assert.ok(/^[\x20-\x7e]*$/.test(text), 'plain ASCII');
  assert.deepEqual(JSON.parse(text), {clip:'Cé4815 — a.MP4', n:[1, 2]});
  assert.deepEqual([...out.subarray(0, png.length - 12)], [...png.subarray(0, png.length - 12)]);
});

test('colour check: S-Log3 clips only, through the page\'s own conversion; the first click reads, the second saves one picture', async () => {
  const pieces = [extractMethod(src, 'checkTimes', 'static checkTimes(fps, dur) {'), extractMethod(src, 'lookAgain', 'static lookAgain(blank, k) {'), extractMethod(src, 'pngNote', 'static pngNote(u8, key, text) {'),
    'static SL3T = ' + src.match(/static SL3T = (\[[^\]]+\]);/)[1] + ';', 'static SL3M = ' + src.match(/static SL3M = (\[[^\]]+\]);/)[1] + ';',
    extractMethod(src, 'prof', 'prof(c) {'), extractMethod(src, 'toDisplay', 'toDisplay(img, c) {'), extractMethod(src, 'sl3Table'), extractMethod(src, 'blank', 'blank(img) {'),
    extractMethod(src, 'colourCheck', 'colourCheck = async () => {') + ';'];
  const W = 960, H = 540, saved = [], asked = [];
  class ImageData { constructor(data, w, h) { this.data = data; this.width = w; this.height = h; } }
  const video = () => { const on = {}; const v = { duration:11.5, readyState:4, addEventListener:(e, f) => { on[e] = f; }, removeAttribute() {}, load() {},
    set src(u) { queueMicrotask(() => on.loadedmetadata && on.loadedmetadata()); }, set currentTime(t) { asked.push(t); v._t = t; queueMicrotask(() => on.seeked && on.seeked()); }, get currentTime() { return v._t; } }; return v; };
  const canvas = () => { const cv = { width:0, height:0, getContext:() => ({ drawImage() {}, getImageData:(x, y, w, h) => new ImageData(new Uint8ClampedArray(w * h * 4).fill(128), w, h), putImageData() {} }),
    toBlob:cb => cb({ arrayBuffer:async () => fakePng().buffer }) }; return cv; };
  const g = { document:{ createElement:t => t === 'video' ? video() : t === 'canvas' ? canvas() : { click() { saved.push([this.download, g.last]); }, remove() {} }, body:{ appendChild() {} }, documentElement:{ dataset:{} } },
    URL:{ createObjectURL:b => { g.last = b; return 'blob:x'; }, revokeObjectURL() {} }, window:{ luminaBuild:'test' }, navigator:{ userAgent:'node' }, ImageData, Blob:class { constructor(parts, o) { this.parts = parts; this.type = o && o.type; } }, setTimeout:() => 0 };
  const Component = new Function(...Object.keys(g), 'return class Component {\n' + pieces.join('\n') + '\n}')(...Object.values(g));
  const sl3 = name => ({ name, fps:23.98, _file:{}, profile:{gamma:'S-Log3', primaries:'S-Gamut3.Cine', source:'file'} });
  const p = Object.assign(new Component(), { d:{clips:[sl3('C1.MP4'), { name:'R.MP4', fps:23.98, _file:{}, profile:{gamma:'none'} }, sl3('C2.MP4')]}, painted:async () => {}, plural:(n, w) => n + ' ' + w + (n === 1 ? '' : 's'), setState() {} });
  await p.colourCheck();
  assert.equal(saved.length, 0, 'nothing is saved before the second click');
  assert.equal(asked.length, 6, 'three frames for each of the two S-Log3 clips, none for the Rec.709 clip');
  assert.match(p.ccSay, /6 frames of 2 clips ready · click again to save/); assert.equal(p.ccBusy, false);
  await p.colourCheck();
  assert.deepEqual(saved.map(x => x[0]), ['skim colour check.png']); assert.equal(saved[0][1].type, 'image/png');
  assert.equal(asked.length, 6, 'the second click reads nothing again');
  const [key, text] = noteOf(saved[0][1].parts[0]), meta = JSON.parse(text);
  assert.equal(key, 'skim');
  assert.deepEqual(meta.rows.map(r => r.clip + ' ' + r.frame), ['C1.MP4 48', 'C1.MP4 120', 'C1.MP4 192', 'C2.MP4 48', 'C2.MP4 120', 'C2.MP4 192']);
  assert.equal(meta.table.length, 256); assert.deepEqual(meta.cell, [W, H]); assert.deepEqual(meta.matrix, Component.SL3M);
  assert.match(p.ccSay, /saved 6 frames of 2 clips to Downloads/); assert.equal(p.ccFile, null);
});

test('colour check: reached from the developer panel and from luminaSkimDebug(\'colour\')', () => {
  assert.match(src, /\{t:this\.ccFile \? 'Save the colour check' : 'Colour check frames', sub:this\.ccSay \|\| [^}]*go:this\.colourCheck,/);
  assert.match(src, /what === 'colour'\) this\.colourCheck\(\)/);
});

test('exposure is noted from a full stop either way, not from 0.7', () => {
  const C = new Function('return class {\n' + extractMethod(src, 'chips', 'chips(c) {') + '\n' + extractMethod(src, 'prof', 'prof(c) {') + '\n}')();
  const p = Object.assign(new C(), { d:{shoot:{rate:24}}, state:{dis:{}}, pct:v => v + '%' });
  const keys = ev => p.chips({ id:'a', fps:24, profile:{gamma:'S-Log3', primaries:'S-Gamut3.Cine', source:'sidecar'}, facts:{state:'ready', ev, clip:0, crush:0, sharp:1, motion:null, bump:null} }).list.map(k => k.key);
  for (const ev of [0, 0.5, 0.7, 0.8, 0.9, -0.7, -0.9]) assert.ok(!keys(ev).includes('ev'), ev + ' stops is not noted');
  for (const ev of [1, 1.4, 2.3, -1, -2.3, -3.7]) assert.ok(keys(ev).includes('ev'), ev + ' stops is noted');
});
