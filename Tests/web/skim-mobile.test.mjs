// The Skim page on a phone: clips from the iPhone's Photos and Android's picker (what they are, when they were shot),
// touch, and every clickable a real button. The functions are read out of the page itself.
//
//   node --test Tests/web/skim-mobile.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const template = src.slice(0, src.indexOf('</x-dc>'));
const stat = (name, head) => new Function('return function ' + extractMethod(src, name, head).replace(/^static /, ''))();
const moovTime = stat('moovTime', 'static moovTime(u8) {'), isClip = stat('isClip', 'static isClip(f) {'), extOf = stat('extOf', 'static extOf(f) {'), tAxis = stat('tAxis', 'static tAxis(dx, dy) {');
/** A method that reads the global navigator, with a navigator of our own. */
const withNav = (name, head) => ua => new Function('navigator', 'return function ' + extractMethod(src, name, head))({ userAgent:ua, maxTouchPoints:/iPhone|iPad|Android/.test(ua) ? 5 : 0 });
const UA = {
  iphone:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
  iphoneChrome:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/138.0 Mobile/15E148 Safari/604.1',
  android:'Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0 Mobile Safari/537.36',
  mac:'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15',
  macChrome:'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0 Safari/537.36',
};

// ---- small QuickTime headers ----
const u32 = n => [n >>> 24 & 255, n >>> 16 & 255, n >>> 8 & 255, n & 255], str = s => [...Buffer.from(s, 'utf8')];
const box = (type, ...kids) => { const body = kids.flat(); return [...u32(8 + body.length), ...[...type].map(c => c.charCodeAt(0) & 255), ...body]; };
const mvhd = secs1904 => box('mvhd', [0, 0, 0, 0, ...u32(secs1904), ...u32(secs1904), ...new Array(88).fill(0)]);
const at1904 = iso => Math.round(Date.parse(iso) / 1000) + 2082844800;
// what an iPhone writes: moov/meta (no version in QuickTime) with hdlr mdta, keys, ilst
const appleMeta = (date, fullBox = false) => box('meta', ...(fullBox ? [[0, 0, 0, 0]] : []),
  box('hdlr', [0, 0, 0, 0, ...u32(0), ...str('mdta'), ...new Array(12).fill(0)]),
  box('keys', [0, 0, 0, 0, ...u32(2), ...u32(8 + 32), ...str('mdta'), ...str('com.apple.quicktime.make'.padEnd(32, ' ')).slice(0, 32),
    ...u32(8 + 32), ...str('mdta'), ...str('com.apple.quicktime.creationdate')]),
  box('ilst', box('\u0000\u0000\u0000\u0001', box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...str('Apple')])), box('\u0000\u0000\u0000\u0002', box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...str(date)]))));

test('moovTime: an iPhone clip says its own wall-clock time, offset and all', () => {
  const t0 = at1904('2026-07-04T19:02:11Z');
  assert.deepEqual(moovTime(new Uint8Array(box('moov', mvhd(t0), appleMeta('2026-07-04T12:02:11-0700')))), { local:'2026-07-04T12:02:11' });
  assert.deepEqual(moovTime(new Uint8Array(box('moov', mvhd(t0), appleMeta('2026-07-04T12:02:11-0700', true)))), { local:'2026-07-04T12:02:11' }, 'meta as an MP4 full box');
});
test('moovTime: ©day in udta, then the header’s UTC time; a zero or impossible time is no time', () => {
  const day = box('udta', box('©day', [0, 18, 0, 0, ...str('2026-05-01T08:30:00+0200')]));
  assert.deepEqual(moovTime(new Uint8Array(box('moov', mvhd(0), day))), { local:'2026-05-01T08:30:00' });
  const t = at1904('2026-03-09T10:11:12Z');
  assert.deepEqual(moovTime(new Uint8Array(box('moov', mvhd(t)))), { utc:Date.parse('2026-03-09T10:11:12Z') }, 'Android: mvhd only, in UTC');
  assert.equal(moovTime(new Uint8Array(box('moov', mvhd(0)))), null, 'a re-export with no time');
  assert.equal(moovTime(new Uint8Array(box('moov', mvhd(at1904('1999-12-31T00:00:00Z'))))), null);
  assert.equal(moovTime(new Uint8Array(0)), null); assert.equal(moovTime(new Uint8Array(40).fill(255)), null);
});

test('isClip / extOf: what a phone’s picker hands over is a clip by its type when its name says nothing', () => {
  assert.ok(isClip({ name:'IMG_4012.MOV', type:'video/quicktime' }));
  assert.ok(isClip({ name:'C0001.MP4', type:'' }), 'a card clip with no type');
  assert.ok(isClip({ name:'1000012345', type:'video/mp4' }), 'Android picker, a name with no extension');
  assert.ok(isClip({ name:'PXL_20261012_101010123.mp4', type:'video/mp4' }));
  assert.ok(isClip({ name:'clip.3gp', type:'' }));
  assert.ok(!isClip({ name:'._C0001.MP4', type:'video/mp4' }), 'macOS resource forks stay out');
  assert.ok(!isClip({ name:'IMG_0001.HEIC', type:'image/heic' })); assert.ok(!isClip({ name:'C0001M01.XML', type:'text/xml' }));
  assert.equal(extOf({ name:'IMG_4012.MOV', type:'video/quicktime' }), 'MOV');
  assert.equal(extOf({ name:'1000012345', type:'video/mp4' }), 'MP4'); assert.equal(extOf({ name:'x', type:'video/quicktime' }), 'MOV');
});

test('tailMeta: a phone clip with no Sony metadata is timed by when it was shot, not by when it was picked', async () => {
  const P = new Function('return class Component {\n' + [['gammaName', 'gammaName(g) {'], ['primName', 'primName(p) {'], ['sonyMeta', 'sonyMeta(tx, src) {'], ['tailMeta', 'async tailMeta(f, sc) {'],
    ['moovRate', 'static moovRate(u8) {'], ['moovAudio', 'static moovAudio(u8) {'], ['moovTransfer', 'static moovTransfer(u8) {'], ['moovTime', 'static moovTime(u8) {'], ['fileRate', 'async fileRate(f) {'], ['fileMoov', 'async fileMoov(f) {'], ['iso', 'iso(ms) {']].map(([n, h]) => extractMethod(src, n, h)).join('\n') + '\n}')();
  const bytes = new Uint8Array([...box('ftyp', str('qt  ')), ...box('mdat', new Array(4000).fill(9)), ...box('moov', mvhd(at1904('2026-07-04T19:02:11Z')), appleMeta('2026-07-04T12:02:11-0700'))]);
  const f = { name:'IMG_4012.MOV', type:'video/quicktime', size:bytes.length, lastModified:Date.parse('2026-10-12T21:00:00Z'),
    slice:(a, b = bytes.length) => { const part = bytes.slice(Math.max(0, a), Math.min(bytes.length, b)); return { text:async () => Buffer.from(part).toString('latin1'), arrayBuffer:async () => part.buffer.slice(part.byteOffset, part.byteOffset + part.length) }; } };
  const m = await new P().tailMeta(f, null);
  assert.equal(m.t, '2026-07-04T12:02:11'); assert.equal(m.prof.source, 'none');
});

test('devName and notSafari: the words follow the device; every browser on an iPhone is WebKit', () => {
  const dev = withNav('devName', 'devName() {'), ns = withNav('notSafari', 'notSafari() {');
  assert.equal(dev(UA.iphone)(), 'this iPhone'); assert.equal(dev(UA.android)(), 'this phone'); assert.equal(dev(UA.mac)(), 'this Mac');
  assert.equal(ns(UA.iphone)(), false); assert.equal(ns(UA.iphoneChrome)(), false, 'Chrome on iOS plays what Safari plays');
  assert.equal(ns(UA.mac)(), false); assert.equal(ns(UA.macChrome)(), true); assert.equal(ns(UA.android)(), true);
});

test('tAxis: a finger is read as sideways or up-and-down once it is 8 px out', () => {
  assert.equal(tAxis(3, -4), null); assert.equal(tAxis(12, 3), 'x'); assert.equal(tAxis(-12, 5), 'x'); assert.equal(tAxis(4, 20), 'y'); assert.equal(tAxis(9, -9), 'y');
});

test('every clickable is a <button>: no div or span with a button, tab or switch role, every onClick on a button or a tile', () => {
  assert.doesNotMatch(template, /<(div|span)\b[^>]*\brole="(button|tab|switch)"/);
  const script = fileURLToPath(new URL('../../Scripts/skim-buttons.py', import.meta.url));
  execFileSync('python3', [script, '--check', fileURLToPath(PAGE)]);   // throws on a page that is not done
  const open = [...template.matchAll(/<([a-z]+)\b([^>]*)\bonClick="/g)].filter(m => m[1] !== 'button');
  // left as they are: the grid's tiles and the Viewer's picture (skim, scrub, box select; pictures, not controls), and
  // the reading line and bar (status, the P panel is also a button), and the scrim behind the Export sheet (a tap
  // outside it closes it; Back to Skim is the button)
  for (const m of open) assert.match(m[2], /data-gi=|data-clip=|data-pic=|role="status"|role="progressbar"|data-screen-label="Export"/, m[0]);
  const btns = [...template.matchAll(/<button\b[^>]*>/g)].map(m => m[0]);
  assert.ok(btns.length >= 39, btns.length); for (const b of btns) assert.match(b, /type="button"/);
});

test('touch: 44 px controls, no key hints, the page’s own pinch and skim; one column on a phone; the screen height that fits', () => {
  const css = src.slice(src.indexOf('<style>'), src.indexOf('</style>'));
  const touch = css.slice(css.indexOf('@media (hover:none) and (pointer:coarse)')), narrow = css.slice(css.indexOf('@container skim (max-width:640px)'));
  assert.match(touch, /button\{min-height:44px/); assert.match(touch, /\[data-kbd\],\[data-lumina=hints\]\{display:none!important\}/);
  assert.match(touch, /\[data-gi\],\[data-clip\],\[data-pic\]\{touch-action:pan-y/);
  assert.match(narrow, /\[data-screen-label=Clip\]\{grid-template-columns:minmax\(0,1fr\)!important/);
  assert.match(css, /@supports \(height:100dvh\)/);
  assert.match(template, /<input ref="\{\{ clipRef \}\}" type="file" accept="video\/\*[^"]*" multiple=""/);
  assert.match(template, /<input ref="\{\{ fileRef \}\}" type="file" webkitdirectory=""/);
  for (const k of ['nav-grid', 'nav-prev', 'nav-next']) assert.match(template, new RegExp('<button type="button" data-lumina="' + k + '"'));
  assert.doesNotMatch(template, /data-lumina="pick-alt"/);   // no second Open button (Choose clips… / Choose a folder…)
});

test('Phone view: a button narrows the page to an iPhone’s width, and the narrow rules follow the page, not the window', () => {
  const css = src.slice(src.indexOf('<style>'), src.indexOf('</style>'));
  assert.match(css, /\[data-screen-label=Skim\]\{container:skim \/ inline-size\}/); assert.doesNotMatch(css, /@media \(max-width:640px\)/);
  assert.match(css, /\[data-view=phone\]\{width:390px;max-width:100%/);
  assert.match(template, /<div data-screen-label="Skim" data-view="\{\{ viewName \}\}"/);
  assert.match(template, /<sc-if value="\{\{ phoneViewOn \}\}"[^>]*><button type="button" data-lumina="phone-view" aria-pressed="\{\{ phoneA \}\}" onClick="\{\{ phoneToggle \}\}"/);
  assert.match(src, /localStorage\.getItem\('lumina-skimview'\) === 'phone'/);
});

test('Phone view is off for now: no Phone button, and neither ?phone=1 nor a saved choice turns it on', () => {
  assert.match(src, /static PHONE_VIEW = false;/);
  assert.match(src, /phoneSaved\(\) \{ if \(!Component\.PHONE_VIEW\) return false;/);
  assert.match(src, /phoneViewOn:Component\.PHONE_VIEW,/);
});
