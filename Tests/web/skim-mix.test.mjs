// Clips from several places and phone clips (LOCAL-CHANGES 282), read out of the page itself: when Open shows the notice
// (mixOf), what it lets in (mixPicked), a Live Photo's movie told from the still beside it (liveSet), and an iPhone HEVC
// .MOV (made here with ffmpeg and libx265, skipped without them) read as a clip with its own time, rate and HLG tag.
//
//   node --test Tests/web/skim-mix.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const st = (name, head) => new Function('Component', 'return function ' + extractMethod(src, name, head).replace(/^static /, ''));
const Component = {MIX_GAP_DAYS:+(/static MIX_GAP_DAYS = (\d+);/.exec(src) || [])[1]};
for (const [n, h] of [['mixDir', 'static mixDir(p) {'], ['mixOf', 'static mixOf(items, o) {'], ['mixPicked', 'static mixPicked(mx) {'], ['liveSet', 'static liveSet(files, relOf) {'], ['isClip', 'static isClip(f) {'],
  ['moovTime', 'static moovTime(u8) {'], ['moovRate', 'static moovRate(u8) {'], ['moovTransfer', 'static moovTransfer(u8) {']]) Component[n] = st(n, h)(Component);
const it = (i, path, t, extra = {}) => ({i, name:path.split('/').pop(), path, t, bytes:1e6, live:false, ...extra});

test('one folder, days close together: no notice', () => {
  assert.equal(Component.MIX_GAP_DAYS, 3);
  assert.equal(Component.mixOf([it(0, 'card/C0001.MP4', '2026-10-01T10:00:00'), it(1, 'card/C0002.MP4', '2026-10-02T09:00:00'), it(2, 'card/C0003.MP4', '2026-10-03T09:00:00')]), null);
  assert.equal(Component.mixOf([it(0, 'IMG_1.MOV', '2026-10-01T10:00:00'), it(1, 'IMG_2.MOV', '2026-10-01T11:00:00')]), null, 'clips picked on their own');
});

test('two folders, or days far apart, or a Live Photo movie: the notice, by day then folder', () => {
  const m = Component.mixOf([it(0, 'dump/b/B1.MP4', '2026-10-09T15:00:00'), it(1, 'dump/a/A2.MP4', '2026-10-01T10:05:00'), it(2, 'dump/a/A1.MP4', '2026-10-01T10:00:00'), it(3, 'dump/b/B0.MP4', '2026-10-01T23:00:00')]);
  assert.equal(m.folders, 2); assert.equal(m.days, 2); assert.equal(m.gap, 8); assert.equal(m.first, '2026-10-01'); assert.equal(m.last, '2026-10-09');
  assert.deepEqual(m.groups.map(g => g.day + ' ' + g.dir + ' ' + g.items.map(x => x.name).join(',')), ['2026-10-01 dump/a A1.MP4,A2.MP4', '2026-10-01 dump/b B0.MP4', '2026-10-09 dump/b B1.MP4']);
  const far = Component.mixOf([it(0, 'card/C1.MP4', '2026-06-02T10:00:00'), it(1, 'card/C2.MP4', '2026-06-05T10:00:00')]);
  assert.ok(far && far.folders === 1 && far.gap === 3, 'three days apart in one folder');
  const live = Component.mixOf([it(0, 'phone/IMG_7.MOV', '2026-10-01T10:00:00', {live:true}), it(1, 'phone/IMG_8.MOV', '2026-10-01T10:01:00')]);
  assert.ok(live && live.lives === 1);
});

test('what goes in: ticked clips in folders not taken off', () => {
  const m = Component.mixOf([it(0, 'a/1.MP4', '2026-10-01T10:00:00'), it(1, 'a/2.MP4', '2026-10-01T10:01:00'), it(2, 'b/3.MP4', '2026-10-01T10:02:00')]);
  const key = m.groups.find(g => g.dir === 'b').key;
  assert.deepEqual(Component.mixPicked({m, off:{}, gone:{}}).map(x => x.i), [0, 1, 2]);
  assert.deepEqual(Component.mixPicked({m, off:{1:true}, gone:{}}).map(x => x.i), [0, 2]);
  assert.deepEqual(Component.mixPicked({m, off:{1:true}, gone:{[key]:true}}).map(x => x.i), [0]);
});

test('a Live Photo movie: a .MOV with a still of the same name in the same folder', () => {
  const f = (name, rel) => ({name, rel});
  const s = Component.liveSet([f('IMG_0007.HEIC', 'phone/IMG_0007.HEIC'), f('IMG_0008.jpg', 'phone/IMG_0008.jpg'), f('IMG_0009.MOV', 'phone/IMG_0009.MOV')], x => x.rel);
  assert.ok(s.has('PHONE/IMG_0007') && s.has('PHONE/IMG_0008') && !s.has('PHONE/IMG_0009'));
});

test('the page keeps the shoot’s clips and the added clips’ places for a reload, and narrows a reopen to them', () => {
  const take = extractMethod(src, 'keepTake', 'keepTake(any) {');
  assert.match(take, /ks:d\.clips\.map\(c => this\.clipKey\(c\)\)/); assert.match(take, /this\.addDropped/);
  assert.match(extractMethod(src, 'keepApply', 'keepApply() {'), /k\.ap\[this\.clipKey\(c\)\]/);
  const imp = extractMethod(src, 'importFiles', 'async importFiles(files, cap, walked, pre) {');
  assert.ok(imp.indexOf('this.keptOnly(') < imp.indexOf('this.mixAsk('), 'a kept shoot coming back never asks');
});

test('a resume: every kept clip found goes straight in; some missing opens the view with what is not found', () => {
  const keptOnly = new Function('return function ' + extractMethod(src, 'keptOnly', 'keptOnly(vids, metas) {'))();
  const pg = ks => ({kept:{ks, ap:{'C3.MP4@2026-10-01T10:03:00':'/Volumes/T7/C3.MP4'}}, clipKey:c => (c.name || '').toUpperCase() + '@' + (c.t || '').slice(0, 19), iso:() => ''});
  const vids = ['C1.MP4', 'C2.MP4', 'X.MP4'].map(name => ({name})), metas = ['2026-10-01T10:01:00', '2026-10-01T10:02:00', '2026-10-01T11:00:00'].map(t => ({t}));
  const all = keptOnly.call(pg(['C1.MP4@2026-10-01T10:01:00', 'C2.MP4@2026-10-01T10:02:00']), vids, metas);
  assert.deepEqual(all.at, [0, 1]); assert.deepEqual(all.missing, []);
  const some = keptOnly.call(pg(['C1.MP4@2026-10-01T10:01:00', 'C3.MP4@2026-10-01T10:03:00']), vids, metas);
  assert.deepEqual(some.at, [0]); assert.deepEqual(some.missing, [{name:'C3.MP4', t:'2026-10-01T10:03:00', path:'/Volumes/T7/C3.MP4'}]);
  assert.equal(keptOnly.call(pg(['Z.MP4@2026-01-01T00:00:00']), vids, metas), null, 'another folder: as it is');
  const m = Component.mixOf([it(0, 'card/C1.MP4', '2026-10-01T10:01:00')], {force:true, missing:some.missing});
  assert.ok(m && m.expect && m.missing.length === 1 && m.n === 1, 'one folder still shows when clips are missing');
});

let hevc = false; try { hevc = /libx265/.test(execFileSync('ffmpeg', ['-hide_banner', '-encoders'], {encoding:'utf8'})); } catch (x) {}
test('an iPhone HEVC .MOV is a clip with its own time, rate and HLG', {skip:!hevc && 'needs ffmpeg with libx265'}, () => {
  const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-phone-')), f = path.join(T, 'IMG_0042.MOV');
  execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30000/1001:duration=1', '-c:v', 'libx265', '-x265-params', 'log-level=error', '-pix_fmt', 'yuv420p10le', '-tag:v', 'hvc1',
    '-color_primaries', 'bt2020', '-color_trc', 'arib-std-b67', '-colorspace', 'bt2020nc', '-movflags', 'use_metadata_tags', '-metadata', 'com.apple.quicktime.creationdate=2026-10-11T18:30:12-0700', '-metadata', 'com.apple.quicktime.model=iPhone 16 Pro', f]);
  const b = new Uint8Array(fs.readFileSync(f)); fs.rmSync(T, {recursive:true, force:true});
  // the moov box, as fileMoov finds it
  let mv = null; for (let o = 0; o + 8 <= b.length;) { const dv = new DataView(b.buffer, o, 8), n = dv.getUint32(0), t = String.fromCharCode(...b.slice(o + 4, o + 8)); if (t === 'moov') { mv = b.slice(o, o + n); break; } o += n; }
  assert.ok(mv, 'a moov box');
  assert.ok(Component.isClip({name:'IMG_0042.MOV', type:'video/quicktime'}) && Component.isClip({name:'1000012345', type:'video/quicktime'}));
  assert.deepEqual(Component.moovTime(mv), {local:'2026-10-11T18:30:12'}, 'the phone’s own local time, not when it was copied');
  assert.deepEqual(Component.moovRate(mv), [1001, 30000], '29.97');
  assert.equal(Component.moovTransfer(mv), 18, 'tagged HLG');
});
