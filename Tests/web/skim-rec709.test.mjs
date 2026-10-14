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

const names = ['prof', 'needsPv', 'pvFlt', 'pvOn', 'pvVia', 'pvDisabled', 'gammaName', 'vidShow', 'vidHas'];
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

// The video under the canvas: WebKit does not convert it, so it may only be seen when nothing needs converting.
const viewer = (pv, c, up = true) => { const v = { style:{opacity:'0'} }; return Object.assign(page(pv, [c]), { vidEl:v, vidFor:'a', byId:{a:c}, vidUp:up ? v : null }); };

test('S-Log3 with the switch on: the video stays hidden and the canvas is the picture', () => {
  const p = viewer(true, SL3);
  assert.equal(p.vidShow(), true);
  assert.equal(p.vidEl.style.opacity, '0');
});

test('switch off, a clip that is not log, or a filter the video takes: the video itself is on show', () => {
  for (const p of [viewer(false, SL3), viewer(true, REC), viewer(true, SL2), viewer(true, UNKNOWN)]) {
    assert.equal(p.vidShow(), false);
    assert.equal(p.vidEl.style.opacity, '1');
  }
});

test('a video that has not answered a seek yet is not shown, switch on or off', () => {
  for (const p of [viewer(true, SL3, false), viewer(false, SL3, false), viewer(true, REC, false)]) {
    assert.equal(p.vidShow(), false);
    assert.equal(p.vidEl.style.opacity, '0');
  }
});

test('a frame the video has not got yet is told from one it has', () => {
  const real = globalThis.document;
  const probe = alpha => ({ getContext:() => ({ clearRect(){}, drawImage(){}, getImageData:() => ({ data:[0, 0, 0, alpha] }) }) });
  try {
    for (const [alpha, has] of [[0, false], [255, true]]) {
      globalThis.document = { createElement:() => probe(alpha) };
      assert.equal(new Skim().vidHas({}), has);
    }
  } finally { globalThis.document = real; }
});

test('the canvas draws only a frame that is there, shows nothing of another clip, and the video is shown through vidShow alone', () => {
  const paint = method('paintVid');
  assert.match(paint, /const has = this\.vidHas\(v\);\s*if \(has\) \{/);
  assert.match(paint, /cv\.style\.opacity = this\.pvCvFor === c\.id \? '1' : '0'/);
  assert.doesNotMatch(paint, /\bv\.style\.opacity/);
  assert.doesNotMatch(src, /el\.style\.opacity = '1'/);
});

test('no transitions: the switch changes the pictures at once (LOCAL-CHANGES 161), the canvas keeps its fade only on paper', () => {
  assert.doesNotMatch(src, /@keyframes pv[AB]\{/);
  assert.doesNotMatch(src, /this\.pvAn = /);
  assert.match(src, /\*,\*::before,\*::after\{transition:none!important\}/);
  assert.match(src.match(/<canvas ref="\{\{ pvCvRef \}\}"[^>]*>/)[0], /transition:opacity 120ms/);
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

test('a sensed profile can be overridden per clip, and a click on the sensed one puts it back', () => {
  const Pick = new Function('return class Component {\n  static PRIM = {\'S-Log3\':\'S-Gamut3.Cine\', \'S-Log2\':\'S-Gamut3\', \'HLG\':\'Rec.2020\', \'none\':\'Rec.709\'};\n' + ['overrideProfile', 'applyProfile'].map(method).join('\n') + '\n}')();
  const a = { id:'a', profile:{ gamma:'S-Log3', primaries:'S-Gamut3.Cine', source:'sidecar' } };
  const b = { id:'b', profile:{ gamma:'S-Log3', primaries:'S-Gamut3.Cine', source:'sidecar' } };
  const u = { id:'u', profile:{ gamma:null, primaries:null, source:'none' } };
  const p = Object.assign(new Pick(), { state:{ cur:'a', sel:[] }, byId:{ a, b, u }, setState(){}, save(){}, remeasure(){} });
  p.overrideProfile('HLG');
  assert.deepEqual(a.profile, { gamma:'HLG', primaries:'Rec.2020', source:'you' });
  assert.equal(b.profile.gamma, 'S-Log3', 'only the current clip when nothing is selected');
  p.applyProfile({ clips:[a, b, u] }, 'S-Log2');
  assert.equal(a.profile.gamma, 'HLG', 'answering for unknown clips leaves an override alone');
  assert.equal(u.profile.gamma, 'S-Log2');
  p.overrideProfile('S-Log3');
  assert.deepEqual(a.profile, { gamma:'S-Log3', primaries:'S-Gamut3.Cine', source:'sidecar' });
  assert.equal(a._sensed, undefined);
  p.state = { cur:'a', sel:['a', 'b'] };
  p.overrideProfile('none');
  assert.equal(a.profile.gamma, 'none'); assert.equal(b.profile.gamma, 'none');
});

// Sensing a profile when the clip carries no Sony metadata: HLG from the file's colour tag, S-Log3 from its picture.
function staticMethod(name){ const body = method('static ' + name); return body; }
const Sense = new Function('return class Component {\n' + ['moovTransfer', 'rawSpread', 'looksLog'].map(staticMethod).join('\n') + '\n}')();
const frame = (lo, hi, sat) => { const W = 64, H = 36, D = new Uint8ClampedArray(W * H * 4);
  for (let i = 0; i < W * H; i++) { const y = (lo + (hi - lo) * (i % W) / (W - 1)) * 255, c = y * sat; D[i * 4] = y; D[i * 4 + 1] = y - c; D[i * 4 + 2] = y - c; D[i * 4 + 3] = 255; }
  return { data:D, width:W, height:H }; };

test('the colour tag: HLG is transfer 18 in the nclx box, anything else is not told from it', () => {
  const box = tr => Uint8Array.from([0, 0, 0, 19, ...Buffer.from('colrnclx'), 0, 9, 0, tr, 0, 9, 0]);
  assert.equal(Sense.moovTransfer(box(18)), 18);
  assert.equal(Sense.moovTransfer(box(1)), 1);
  assert.equal(Sense.moovTransfer(Uint8Array.from(Buffer.from('moov....trak....nothing here'))), null);
});

test('the picture: a flat, pale, grey-ish clip reads as log; a full-range or a dark clip does not', () => {
  const log = [0, 1, 2, 3].map(() => Sense.rawSpread(frame(0.09, 0.66, 0.12)));
  const rec = [0, 1, 2, 3].map(() => Sense.rawSpread(frame(0.0, 1.0, 0.4)));
  const dark = [0, 1, 2, 3].map(() => Sense.rawSpread(frame(0.0, 0.02, 0)));
  assert.equal(Sense.looksLog(log), true);
  assert.equal(Sense.looksLog(rec), false);
  assert.equal(Sense.looksLog(dark), false);
  assert.equal(Sense.looksLog(log.slice(0, 1)), true, 'the cover alone decides until more frames are read');
  assert.equal(Sense.looksLog([log[0], rec[0]]), false, 'with fewer than four frames, every one must agree');
  assert.equal(Sense.looksLog([]), false);
  assert.equal(Sense.looksLog([...log.slice(0, 3), rec[0]]), true, 'one odd frame does not undo it');
});

// ---- what each tile says about its profile, the switch when nothing needs it, and sensing that yields to the shoot ----

const looksLog = new Function('return function ' + extractMethod(src, 'looksLog', 'static looksLog(list) {').replace(/^static /, ''))();
const LOG_NEAR = +src.match(/static LOG_NEAR = (\d+);/)[1];
const More = new Function('Component', 'return class {\n' + [...names, 'plural', 'pvTip', 'profChip', 'chipRow', 'chipV', 'pendV', 'pictureLog', 'near', 'nearVote', 'senseNear'].map(method).join('\n')
  + '\n  pvToggle(e) {' + src.match(/\n  pvToggle = e => \{([^\n]*)\};\n/)[1] + '}\n}')({ looksLog, LOG_NEAR, letGo(){} });
const shoot = (pv, clips) => Object.assign(new More(), { state:{pv}, d:{clips}, api(){}, setState(o){ Object.assign(this.state, o); } });

test('the switch says why it does nothing, and a click or ⇧R leaves it as it is', () => {
  const all = shoot(true, [REC, REC, REC]);
  assert.equal(all.pvTip(), 'All 3 clips are already Rec.709');
  assert.equal(shoot(true, [REC]).pvTip(), 'This clip is already Rec.709');
  assert.equal(shoot(true, [REC, REC, UNKNOWN]).pvTip(), 'No log clips to convert (2 Rec.709, 1 no profile)');
  all.pvToggle(); assert.equal(all.state.pv, true, 'disabled: the state is kept for a log clip opened later');
  const mixed = shoot(true, [SL3, SL3, REC]);
  assert.equal(mixed.pvTip(), 'Rec.709 preview · ⇧R · converts 2 log clips (2 S-Log3, 1 Rec.709)');
  mixed.pvToggle(); assert.equal(mixed.state.pv, false);
  assert.match(src, /aria-disabled="\{\{ pvDis \}\}" onClick="\{\{ pvToggle \}\}" title="\{\{ pvTip \}\}"/);
  assert.match(src, /const pvOnUi = !!st\.pv && !noPv;/, 'a disabled switch shows off');
});

test('each tile leads with its profile and whether it is on screen as Rec.709', () => {
  const on = shoot(true, []), off = shoot(false, []);
  assert.equal(on.profChip(SL3).t, 'S-Log3 → 709');
  assert.equal(off.profChip(SL3).t, 'S-Log3 · as shot');
  assert.equal(on.profChip(HLG).t, 'HLG → 709');
  assert.match(on.profChip(HLG).tip, /approximately/);
  assert.equal(on.profChip(REC).t, 'Rec.709');
  assert.match(on.profChip(REC).tip, /^Rec\.709 from the clip's .XML file · shown as recorded, nothing to convert$/);
  assert.equal(on.profChip(clip('S-Log3', 'picture')).t, 'S-Log3? → 709', 'a profile read from the picture is marked as a guess');
  assert.equal(on.profChip(UNKNOWN), null, 'no profile: the "profile unknown" chip says it');
  const ch = { pending:false, list:[{key:'soft', t:'soft'}, {key:'bump', t:'bump'}, {key:'rate', t:'60p'}] };
  const row = on.chipRow({ id:'a', ...SL3 }, ch, 3, 2);
  assert.deepEqual(row.chips.map(c => c.t), ['S-Log3 → 709', 'soft', 'bump']); assert.equal(row.more, '+1');
  assert.deepEqual(on.chipRow({ id:'a', ...SL3 }, { pending:true, list:[] }, 3, 2).chips.map(c => c.t), ['S-Log3 → 709', '—'], 'known before the frames are read');
});

// Measured with ffmpeg on the T7 (8 frames each, the page's rawSpread): C0095 is Rec.709 by its metadata, C4866 is S-Log3.
const C0095 = { p2:0.098, p98:0.804, sat:0.075 }, C0094 = { p2:0.141, p98:0.867, sat:0.079 }, C4866 = { p2:0.224, p98:0.571, sat:0.075 };
const bare = (id, t, frame) => ({ id, t, profile:{gamma:null, primaries:null, source:'none'}, _raw:frame ? Object.fromEntries([0, 1, 2, 3, 4, 5, 6, 7].map(i => [i, frame])) : undefined });

test('a flat Rec.709 clip reads like S-Log3 from its picture alone (why the shoot has a say)', () => {
  assert.equal(looksLog(Array(8).fill(C0095)), true);
  assert.equal(looksLog(Array(8).fill(C4866)), true);
  assert.equal(looksLog(Array(8).fill(C0094)), false);
});

test('picture sensing yields to the clips shot around it: C0095 next to C0094 stays unconverted', () => {
  const a = bare('94', '2020-10-09T09:08:43', C0094), b = bare('95', '2020-10-09T09:09:51', C0095), p = shoot(true, [a, b]), re = [];
  p.remeasure = l => re.push(...l);
  p.senseNear(b); assert.equal(b.profile.gamma, null);
  // read before its neighbour: a guess, put back once the neighbour is read
  const a2 = bare('94', '2020-10-09T09:08:43'), b2 = bare('95', '2020-10-09T09:09:51', C0095), q = shoot(true, [a2, b2]); q.remeasure = () => {};
  q.senseNear(b2); assert.equal(b2.profile.gamma, 'S-Log3'); assert.equal(b2.profile.source, 'picture');
  a2._raw = bare('x', '', C0094)._raw; q.senseNear(a2); assert.equal(b2.profile.gamma, null);
  // metadata beside it counts the same way
  const m = { id:'m', t:'2020-10-09T09:05:00', profile:{gamma:'none', primaries:'Rec.709', source:'file'} }, c = bare('95', '2020-10-09T09:09:51', C0095), r = shoot(true, [m, c]); r.remeasure = () => {};
  r.senseNear(c); assert.equal(c.profile.gamma, null);
});

test('a log shoot is still sensed: alone, among log neighbours, or far from a Rec.709 clip', () => {
  for (const clips of [[bare('1', '2026-01-01T10:00:00', C4866)],
    [bare('1', '2026-01-01T10:00:00', C4866), bare('2', '2026-01-01T10:02:00', C4866)],
    [bare('0', '2026-01-01T09:00:00', C0094), bare('1', '2026-01-01T10:00:00', C4866)]]) {
    const p = shoot(true, clips); p.remeasure = () => {}; const last = clips[clips.length - 1];
    clips.forEach(c => p.senseNear(c));
    assert.equal(last.profile.gamma, 'S-Log3', clips.length + ' clips');
  }
  assert.ok(LOG_NEAR >= 300 && LOG_NEAR <= 3600);
});

test('a profile from metadata, or one set by hand, is never changed by a picture', () => {
  const m = { id:'m', t:'2020-10-09T09:09:51', profile:{gamma:'none', primaries:'Rec.709', source:'file'}, _raw:bare('', '', C4866)._raw };
  const y = { id:'y', t:'2020-10-09T09:09:52', profile:{gamma:'HLG', primaries:'Rec.2020', source:'you'}, _raw:bare('', '', C4866)._raw };
  const p = shoot(true, [m, y]); p.remeasure = () => {}; p.senseNear(m); p.senseNear(y);
  assert.equal(m.profile.gamma, 'none'); assert.equal(y.profile.gamma, 'HLG');
});

test('the Viewer does not call a clip steady: shake is not measured, so the motion row says — until it is', () => {
  assert.doesNotMatch(src, /'steady'/);
  assert.match(src, /facts\.push\(\{k:'motion', v:\(f\.motion \|\| '—'\)/);
});
