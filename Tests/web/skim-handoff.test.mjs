// What Final Cut needs from the .fcpxml to take the clips without a hand: the rate the file really has, a length
// that fits inside the file, the clips' real location, and Final Cut's own name for the Sony conversion.
// Each was found by a real import into Final Cut Pro 12.4 (2026-10-09) and settled by another one; these pin
// the page's side. The functions are read out of the page.
//
//   node --test Tests/web/skim-handoff.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod, loadBuildX, validateAgainstDTD } from './skim-export.mjs';
import { MiniDOMParser } from './mini-xml.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const stat = (name, head) => new Function('return function ' + extractMethod(src, name, head).replace(/^static /, ''))();
const moovRate = stat('moovRate', 'static moovRate(u8) {'), rootSay = stat('rootSay', 'static rootSay(root, tops) {'), checkX = stat('checkX', 'static checkX(text, n, P) {');
const Meta = new Function('return class Component {\n' + [extractMethod(src, 'gammaName', 'gammaName(g) {'), extractMethod(src, 'primName', 'primName(p) {'), extractMethod(src, 'sonyMeta', 'sonyMeta(tx, src) {'),
  extractMethod(src, 'tailMeta', 'async tailMeta(f, sc) {'), extractMethod(src, 'moovRate', 'static moovRate(u8) {'), extractMethod(src, 'fileRate', 'async fileRate(f) {')].join('\n') + '\n}')();
const buildX = loadBuildX().fn;
const SL3 = { gamma:'S-Log3', primaries:'S-Gamut3.Cine', source:'file' };
const build = (clips, ex = {}, marks = {}) => buildX.call({ d:{ shoot:{ name:'trip', rate:24 }, clips }, state:{ marks, ex:{ event:'', kw:'maybe', maybes:true, all:true, root:'', ...ex } } });
const tag = (xml, t) => xml.split('\n').filter(l => l.trim().startsWith('<' + t + ' '));
const at = (line, name) => (new RegExp('\\b' + name + '="([^"]*)"').exec(line) || [])[1];
const nrt = fps => `<NonRealTimeMeta><Duration value="276"/><VideoFrame videoCodec="HEVC" captureFps="${fps}p" formatFps="${fps}p"/><Device modelName="ILCE-7SM3"/><Item name="CaptureGammaEquation" value="s-log3-cine"/><Item name="CaptureColorPrimaries" value="s-gamut3-cine"/></NonRealTimeMeta>`;

// ---- a small QuickTime header, the boxes moovRate reads ----
const u32 = n => [n >>> 24 & 255, n >>> 16 & 255, n >>> 8 & 255, n & 255], str = s => [...s].map(c => c.charCodeAt(0));
const box = (type, ...kids) => { const body = kids.flat(); return [...u32(8 + body.length), ...str(type), ...body]; };
const trak = (handler, scale, entries, v1 = false) => box('trak', box('mdia',
  box('mdhd', v1 ? [1, 0, 0, 0, ...new Array(16).fill(0), ...u32(scale), ...new Array(8).fill(0), 0, 0, 0, 0] : [0, 0, 0, 0, ...u32(0), ...u32(0), ...u32(scale), ...u32(0), 0, 0, 0, 0]),
  box('hdlr', [0, 0, 0, 0, ...u32(0), ...str(handler), ...new Array(12).fill(0)]),
  box('minf', box('stbl', box('stts', [0, 0, 0, 0, ...u32(entries.length), ...entries.flatMap(([c, d]) => [...u32(c), ...u32(d)])])))));
const moov = (...traks) => new Uint8Array(box('moov', box('mvhd', new Array(100).fill(0)), ...traks));
const fileOf = (name, bytes) => ({ name, size:bytes.length, slice:(a, b = bytes.length) => { const part = bytes.slice(Math.max(0, a), Math.min(bytes.length, b)); return { text:async () => Buffer.from(part).toString('latin1'), arrayBuffer:async () => part.buffer.slice(part.byteOffset, part.byteOffset + part.length) }; } });

test('the rate a file states: 24 is 1/24 s a frame, 23.98 is 1001/24000, read from the video track', () => {
  assert.deepEqual(moovRate(moov(trak('soun', 48000, [[1000, 1024]]), trak('vide', 2400, [[187, 100]]))), [1, 24]);
  assert.deepEqual(moovRate(moov(trak('vide', 24000, [[276, 1001]]))), [1001, 24000]);
  assert.deepEqual(moovRate(moov(trak('vide', 30000, [[1, 2002], [300, 1001]]))), [1001, 30000], 'the length most frames have');
  assert.deepEqual(moovRate(moov(trak('vide', 600, [[100, 25]], true))), [1, 24], 'a version 1 header');
});

test('a file with no video track, or cut short, gives no rate and no throw', () => {
  assert.equal(moovRate(moov(trak('soun', 48000, [[1000, 1024]]))), null);
  assert.equal(moovRate(new Uint8Array(0)), null);
  assert.equal(moovRate(moov(trak('vide', 2400, [[187, 100]])).slice(0, 60)), null);
  assert.equal(moovRate(new Uint8Array(64).fill(255)), null);
});

test('Sony metadata gives the frame length and the frame count; without it the file header is read', async () => {
  const p = new Meta();
  assert.deepEqual(p.sonyMeta(nrt('23.98'), 'file').fd, [1001, 24000]); assert.equal(p.sonyMeta(nrt('23.98'), 'file').nf, 276);
  assert.deepEqual(p.sonyMeta(nrt('24'), 'file').fd, [100, 2400]);
  assert.deepEqual(p.sonyMeta(nrt('59.94'), 'file').fd, [1001, 60000]);
  assert.deepEqual(p.sonyMeta(nrt('25'), 'file').fd, [100, 2500]);
  // a graded export: no camera metadata, picture data first, the header last
  const m = moov(trak('vide', 2400, [[187, 100]])), bytes = new Uint8Array([...box('ftyp', str('qt  ')), ...box('mdat', new Array(5000).fill(7)), ...m]);
  const meta = await p.tailMeta(fileOf('tiktok 2.MOV', bytes), null);
  assert.deepEqual(meta.fd, [1, 24]); assert.equal(meta.fps, 24); assert.equal(meta.prof.source, 'none');
  const none = await p.tailMeta(fileOf('x.MOV', new Uint8Array(str('not a movie at all'))), null);
  assert.equal(none.fd, null); assert.equal(none.fps, 0);
});

test('a 24.000 clip is written as 24, with a length that fits inside the file', () => {
  // tiktok 2.MOV on the T7: 24/1, the player reports 7.755 s. Written as 23.98 it came out 186186/24000 s = 7.7577 s,
  // longer than the file, and Final Cut refused to relink it.
  const x = build([{ id:'a', name:'tiktok 2.MOV', path:'colored/tiktok 2.MOV', dur:7.755, fps:24, fd:[1, 24], w:1920, h:1080 }]);
  assert.equal(at(tag(x.text, 'format')[0], 'frameDuration'), '1/24s');
  const du = at(tag(x.text, 'asset')[0], 'duration'), [n, d] = /^(\d+)\/(\d+)s$/.exec(du).slice(1).map(Number);
  assert.equal(du, '186/24s'); assert.ok(n / d <= 7.755, 'no longer than the file');
});

test('lengths never round up past the file; the camera\'s own frame count wins when there is one', () => {
  const one = (c) => at(tag(build([{ id:'a', name:'c.MP4', path:'d/c.MP4', w:3840, h:2160, ...c }]).text, 'asset')[0], 'duration');
  assert.equal(one({ dur:11.5096, fps:24, fd:[1001, 24000], nf:276 }), '276276/24000s', 'the frame count, not 276 / 23.98 rounded');
  assert.equal(one({ dur:11.515, fps:24, fd:[1001, 24000] }), '276276/24000s');
  assert.equal(one({ dur:11.49, fps:24, fd:[1001, 24000] }), '275275/24000s', '275.5 frames is 275, not 276');
  assert.equal(one({ dur:0.01, fps:24, fd:[1, 24] }), '1/24s', 'never nothing');
});

test('two rates in one shoot get a format each, and a shoot with no rate known keeps the old table', () => {
  const x = build([{ id:'a', name:'a.MP4', path:'d/a.MP4', dur:10, fps:24, fd:[1001, 24000], w:3840, h:2160 }, { id:'b', name:'b.MOV', path:'d/b.MOV', dur:10, fps:24, fd:[1, 24], w:3840, h:2160 }, { id:'c', name:'c.MP4', path:'d/c.MP4', dur:10, fps:24, w:3840, h:2160 }]);
  assert.deepEqual(tag(x.text, 'format').map(l => at(l, 'frameDuration')), ['1001/24000s', '1/24s']);
  assert.deepEqual(tag(x.text, 'asset').map(l => at(l, 'format')), ['r1', 'r2', 'r1']);
});

test('S-Log3 / S-Gamut3.Cine clips carry Final Cut\'s own name for its Sony conversion; nothing else does', () => {
  const c = (id, profile) => ({ id, name:id + '.MP4', path:'d/' + id + '.MP4', dur:10, fps:24, fd:[1001, 24000], w:3840, h:2160, profile });
  const x = build([c('a', SL3), c('b', { gamma:'S-Log3', primaries:'S-Gamut3', source:'file' }), c('c', { gamma:'S-Log2', primaries:'S-Gamut', source:'file' }), c('d', { gamma:'none', primaries:'Rec.709', source:'file' }), c('e', undefined), c('f', { ...SL3, source:'you' })]);
  assert.deepEqual(tag(x.text, 'asset').map(l => at(l, 'customLUTOverride') || null), ['35 (Sony_SLog3_SGamut3Cine_v2)', null, null, null, null, '35 (Sony_SLog3_SGamut3Cine_v2)']);
});

test('the folder named in Export is where the clips are; a clip inside a subfolder keeps its place', () => {
  const clips = [{ id:'a', name:'C4815.MP4', path:'friend_test_log/C4815.MP4', dur:10, fps:24 }, { id:'b', name:'x 1 (2).MP4', path:'friend_test_log/day 2/x 1 (2).MP4', dur:10, fps:24 }];
  const srcs = ex => tag(build(clips, ex).text, 'media-rep').map(l => at(l, 'src'));
  assert.deepEqual(srcs({ root:'/Volumes/T7/friend_test_log' }), ['file:///Volumes/T7/friend_test_log/C4815.MP4', 'file:///Volumes/T7/friend_test_log/day%202/x%201%20(2).MP4']);
  assert.deepEqual(srcs({ root:'  /Volumes/T7/friend_test_log/  ' }), srcs({ root:'/Volumes/T7/friend_test_log' }), 'spaces and a last / do not matter');
  assert.deepEqual(srcs({ root:'file:///Users/a%20b/friend_test_log' })[0], 'file:///Users/a%20b/friend_test_log/C4815.MP4', 'a pasted file:// location');
  assert.deepEqual(srcs({ root:'' }), ['file:///Volumes/friend_test_log/C4815.MP4', 'file:///Volumes/friend_test_log/day%202/x%201%20(2).MP4'], 'nothing named: the old guess');
  assert.deepEqual(srcs({ root:'friend_test_log' }), srcs({ root:'' }), 'not a location: the old guess');
});

test('several folders opened together: the folder named is the one that holds them', () => {
  const clips = [{ id:'a', name:'C1.MP4', path:'friend_test_log/C1.MP4', dur:10, fps:24 }, { id:'b', name:'t.MOV', path:'friend_test_colored/t.MOV', dur:10, fps:24 }];
  assert.deepEqual(tag(build(clips, { root:'/Volumes/T7' }).text, 'media-rep').map(l => at(l, 'src')), ['file:///Volumes/T7/friend_test_log/C1.MP4', 'file:///Volumes/T7/friend_test_colored/t.MOV']);
});

test('a clip whose real location the page was given keeps it, whatever the folder field says', () => {
  const x = build([{ id:'a', name:'C1.MP4', path:'/Volumes/Untitled/PRIVATE/M4ROOT/CLIP/C1.MP4', dur:10, fps:24 }], { root:'/somewhere/else' });
  assert.equal(at(tag(x.text, 'media-rep')[0], 'src'), 'file:///Volumes/Untitled/PRIVATE/M4ROOT/CLIP/C1.MP4');
});

test('the line under the folder field says what Final Cut will do', () => {
  assert.match(rootSay('', ['friend_test_log']).t, /select the folder “friend_test_log”, press ⌥⌘C, paste here\. Left empty, the clips arrive as missing/);
  assert.match(rootSay('', ['a', 'b']).t, /select the folder that holds “a”, “b”/);
  assert.match(rootSay('', []).t, /select the folder you opened/);
  assert.equal(rootSay('Volumes/T7', ['a']).bad, true); assert.match(rootSay('Volumes/T7', ['a']).t, /starts with \//);
  assert.equal(rootSay('/Volumes/T7/a', ['a']).t, 'Final Cut will look for the clips in this folder.'); assert.ok(!rootSay('/Volumes/T7/a', ['a']).bad);
  assert.match(rootSay('/Volumes/T7', ['a', 'b']).t, /which should hold “a”, “b”\.$/);
  assert.doesNotMatch(src.slice(src.indexOf('static rootSay'), src.indexOf('rootSaved(name)')), /\b(reject|delete|trash|keep)\b/i, 'neutral words');
});

test('the folder field is on the Export screen and is remembered for the shoot, outside the marks', () => {
  assert.match(src, /<input type="text" aria-label="Where the clips are"[^>]*value="\{\{ exRoot \}\}" onChange="\{\{ exRootIn \}\}"/);
  assert.match(src, /data-lumina="export-root"[^>]*>\{\{ exRootSay \}\}/);
  assert.match(src, /this\.persist\('lumina-skimroots'/);
  // the summary line above Details follows the field, and points at it when a folder (not a mounted card) was opened
  assert.match(src, /'Final Cut will look for the clips in ' \+ rt\.replace/);
  assert.match(src, /Opened a folder instead\? Say where it is under Details\./);
  assert.doesNotMatch(src, /'lumina-skim:root/, 'not under the prefix that counts saved shoots');
});

test('a file with all of it passes the page\'s own check and Final Cut\'s definition', t => {
  const clips = [{ id:'a', name:'C4815.MP4', path:'friend_test_log/C4815.MP4', dur:11.515, fps:24, fd:[1001, 24000], nf:276, w:3840, h:2160, profile:SL3 }, { id:'b', name:'tiktok 2.MOV', path:'friend_test_colored/tiktok 2.MOV', dur:7.755, fps:24, fd:[1, 24], w:1920, h:1080, profile:{ gamma:null, primaries:null, source:'none' } }];
  const x = build(clips, { root:'/Volumes/T7' }, { a:'keep', b:'maybe' });
  assert.deepEqual(checkX(x.text, 2, MiniDOMParser), { ok:true, problems:[] });
  const r = validateAgainstDTD(x.text, '1.10'); if (r.skipped) return t.skip(r.skipped);
  assert.ok(r.ok, r.errors);
});
