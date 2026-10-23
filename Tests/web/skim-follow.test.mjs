// Follow in the Skim Viewer: the times a shape is followed at, the outline shown at a time, the measures inside the
// shape, the matte's frames and size, and the matte in the .fcpxml. The page is the one implementation; the functions
// are read out of it the way skim-export.mjs reads buildX. The Mac's half is SkimFollowTests (Swift).
//
//   node --test Tests/web/skim-follow.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod, loadBuildX, ctxFromFixture, fixture } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = { FDS: {24:[1001, 24000], 25:[100, 2500], 30:[1001, 30000], 50:[100, 5000], 60:[1001, 60000], 100:[100, 10000], 120:[1001, 120000]} };
for (const [name, args] of [['folTimes', 't0, dur, step'], ['folStep', 'dur'], ['folAt', 'samples, t'], ['folInside', 'px, total'], ['clipFd', 'c, rate'], ['matteSize', 'w, h'], ['folSeen', 'samples'], ['folStrip', 'samples, dur'], ['folSpan', 't, strip, dur'], ['folMerged', 'base, patch, from, to']]) {
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}

test('a shape is followed forward from the frame on show, then back to the start', () => {
  const T = C.folTimes(1, 2, 0.25);
  assert.deepEqual(T.fwd, [1, 1.25, 1.5, 1.75]);
  assert.deepEqual(T.back, [0.75, 0.5, 0.25, 0]);
  assert.deepEqual(C.folTimes(0, 0.5, 0.25), {fwd:[0, 0.25], back:[]}, 'from the first frame: forward only');
  assert.deepEqual(C.folTimes(9, 1, 0.5).fwd, [0.98], 'a time past the end starts at the end');
  assert.equal(C.folStep(30), 0.125, 'eight a second');
  assert.equal(C.folStep(600), 1, 'at most 600 frames in a long clip');
  const long = C.folTimes(0, 3600, C.folStep(3600)); assert.ok(long.fwd.length <= 601, long.fwd.length);
});

test('the Viewer shows the followed frame nearest its time', () => {
  const s = [{t:0}, {t:0.125}, {t:0.25}];
  assert.equal(C.folAt(s, 0.1).t, 0.125);
  assert.equal(C.folAt(s, 9).t, 0.25);
  assert.equal(C.folAt([], 0), null);
  assert.equal(C.folAt(null, 0), null);
});

test('inside the shape: the clip facts\' own scales, over the frames it was in', () => {
  const I = C.folInside([{mean:0.46, hi:0.01, lo:0, lap:0.05}, null, {mean:0.46, hi:0.03, lo:0.02, lap:0.02}], 4);
  assert.equal(I.ev, 0, 'middle grey is 0 stops');
  assert.equal(I.clip, 2);
  assert.equal(I.crush, 1);
  assert.equal(I.sharp, 0.4, 'the lowest frame');
  assert.equal(I.seen, 50, 'in two of four frames');
  assert.equal(C.folInside([null], 3), null);
  assert.equal(C.folInside([], 0), null);
  assert.equal(C.folInside([{mean:0.92, hi:0, lo:0, lap:1}], 1).ev, 2.2);
});

test('a track on the Mac: where the shape is, and how much is worth a look', () => {
  const S = [{outline:[[0]], sure:'sure'}, {outline:[[0]], sure:'shaky'}, {outline:null, sure:'lost'}, {outline:[[0]], sure:'sure'}];
  assert.deepEqual(C.folSeen(S), {seen:75, shaky:25});
  assert.equal(C.folSeen([{outline:null, sure:'lost'}]), null);
  assert.equal(C.folSeen([]), null);
  assert.match(src, /api\.trackEnd\(r\.track\)/, 'Let go ends the track');
  assert.match(src, /r\.track \? \{track:r\.track\}/, 'the matte is made from the track');
});

test('the strip, a fix\'s stretch, and the fix in place', () => {
  const S = [0, 0.5, 1, 1.5, 2, 2.5].map((t, i) => ({t, sure:i === 2 || i === 3 ? 'shaky' : i === 4 ? 'lost' : 'sure'}));
  const st = C.folStrip(S, 3);
  assert.deepEqual(st.map(x => x.sure), ['sure', 'shaky', 'lost', 'sure']);
  assert.deepEqual(st.map(x => x.l), ['0.00%', '25.00%', '58.33%', '75.00%'], 'each stretch from halfway to its neighbour');
  assert.equal(st[3].w, '25.00%', 'the last to the end of the clip');
  assert.deepEqual(C.folStrip([], 3), []);
  assert.deepEqual(C.folSpan(1.2, st, 3), {from:0.5, to:2.5}, 'from the last sure frame before to the first after');
  assert.deepEqual(C.folSpan(2.8, [{sure:'lost', t0:2.6, t1:3}], 3), {from:0, to:3});
  const m = C.folMerged(S, [{t:1, sure:'sure'}, {t:2.5, sure:'shaky'}], 1, 2);
  assert.deepEqual(m.map(x => x.t + ':' + x.sure), ['0:sure', '0.5:sure', '1:sure', '2.5:sure'], 'the stretch replaced, nothing outside it touched');
});

test('the matte is the clip\'s length in its frames, at most 1920 on the long edge and even', () => {
  assert.deepEqual(C.clipFd({fps:24, dur:10}), {fd:[1001, 24000], nf:239});
  assert.deepEqual(C.clipFd({fps:25, dur:2}), {fd:[100, 2500], nf:50});
  assert.deepEqual(C.clipFd({fps:24, dur:10, nf:240, fd:[1001, 24000]}), {fd:[1001, 24000], nf:240}, 'the camera\'s own count wins');
  assert.deepEqual(C.matteSize(3840, 2160), {w:1920, h:1080});
  assert.deepEqual(C.matteSize(1280, 720), {w:1280, h:720});
  assert.deepEqual(C.matteSize(4096, 2161), {w:1920, h:1012});
  assert.equal(C.matteSize(0, 0), null);
});

test('a saved matte is listed beside its clip in the .fcpxml', () => {
  const fx = fixture(), ctx = ctxFromFixture(fx), keep = fx.clips.find(c => c.mark === 'keep'), { fn } = loadBuildX();
  const plain = fn.call(ctx).text;
  ctx.mattes = () => ({[keep.id]: {path:'/Volumes/T7/Export/' + keep.name.replace(/\.\w+$/, '') + ' matte.mov', name:'x matte.mov', shape:'Person 1'}});
  const x = fn.call(ctx).text;
  assert.doesNotMatch(plain, /matte/);
  assert.match(x, /<asset id="m\d+" name="[^"]+ matte · Person 1" start="0s" duration="[^"]+" hasVideo="1" hasAudio="0" format="r\d+">/);
  assert.match(x, /<media-rep kind="original-media" src="file:\/\/\/Volumes\/T7\/Export\/[^"]+%20matte\.mov"\/>/);
  assert.match(x, /<asset-clip ref="m\d+" name="[^"]+ matte · Person 1" duration="[^"]+" format="r\d+" tcFormat="NDF">\n\s+<keyword start="0s" duration="[^"]+" value="matte"\/>/);
  assert.match(x, /<keyword-collection name="matte"\/>/);
  // the matte's format: the clip's frame length at the matte's size
  const fm = /<asset id="m\d+"[^>]* format="(r\d+)"/.exec(x)[1], f = new RegExp('<format id="' + fm + '"(?: name="[^"]+")? frameDuration="([^"]+)" width="(\\d+)" height="(\\d+)"/').exec(x);
  assert.ok(f, 'the matte has a format of its own'); assert.ok(+f[2] <= 1920 && +f[3] <= 1920 && +f[2] % 2 === 0 && +f[3] % 2 === 0, f[0]);
  // the same length as the clip
  const a = new RegExp('<asset id="a\\d+" name="' + keep.name.replace(/\.\w+$/, '') + '"[^>]* duration="([^"]+)"').exec(x)[1], m = /<asset id="m\d+"[^>]* duration="([^"]+)"/.exec(x)[1];
  assert.equal(m, a);
  // a matte for a clip left out of the file is left out too
  const cut = fx.clips.find(c => c.mark === 'cut');
  const sel = ctxFromFixture(fx, {all:false}); sel.mattes = () => ({[cut.id]: {path:'/tmp/c matte.mov', name:'c matte.mov'}});
  assert.doesNotMatch(fn.call(sel).text, /matte/);
});

test('a removal is connected above its clip in the sorted timeline, and listed in the event', () => {
  const fx = fixture(), ctx = ctxFromFixture(fx), keep = fx.clips.find(c => c.mark === 'keep'), { fn } = loadBuildX();
  ctx.patches = () => ({[keep.id]: {path:'/Volumes/T7/Export/' + keep.name.replace(/\.\w+$/, '') + ' patch.mov', name:'x patch.mov', shape:'Person 1'}});
  const x = fn.call(ctx).text;
  assert.match(x, /<asset id="p\d+" name="[^"]+ patch · Person 1" start="0s" duration="[^"]+" hasVideo="1" hasAudio="0" format="r\d+">/);
  assert.match(x, /<media-rep kind="original-media" src="file:\/\/\/Volumes\/T7\/Export\/[^"]+%20patch\.mov"\/>/);
  assert.match(x, /<keyword-collection name="patch"\/>/);
  // in the project: the patch is a connected clip (lane 1) inside its clip, the same length, from the clip's start
  const pid = /<asset id="(p\d+)"/.exec(x)[1], aid = 'a' + pid.slice(1);
  const m = new RegExp('<asset-clip ref="' + aid + '" offset="[^"]+" name="[^"]+" duration="([^"]+)"[^>]*[^/]>\\n\\s+<asset-clip ref="' + pid + '" lane="1" offset="0s" name="[^"]+ patch" duration="([^"]+)" format="r\\d+" tcFormat="NDF"/>').exec(x);
  assert.ok(m, 'connected above its clip');
  assert.equal(m[2], m[1], 'as long as its clip');
  // every asset-clip that opens is closed
  const proj = x.slice(x.indexOf('<project'), x.indexOf('</project>'));
  assert.equal((proj.match(/<asset-clip [^>]*[^/]>/g) || []).length, (proj.match(/<\/asset-clip>/g) || []).length);
});

test('the page: Follow only with the app, in plain words, ended on the Mac', () => {
  assert.match(src, /folApi\(\) \{[^\n]*v\.follow && v\.matte/);
  assert.match(src, /api\.followEnd\(id\)/, 'every follow is ended');
  assert.match(src, /data-lumina="follow-go"/);
  assert.match(src, /data-lumina="follow-matte"/);
  const words = ['Follow through the clip', 'Stop', 'Save matte', 'Let go', 'following ', ' followed', 'matte saved · ', 'not followed: ', ' · not in the clip', 'in the next .fcpxml'];
  for (const w of words) assert.ok(src.includes(w), w);
  const banned = /\b(AI|smart|intelligent|detects?|understands|suggests?|recommended|magic|auto\w*|learns|confidence|score)\b/i;
  for (const w of words) assert.doesNotMatch(w, banned, w);
  const tpl = src.slice(src.indexOf('data-lumina="follow"'), src.indexOf('data-lumina="follow-say"'));
  assert.doesNotMatch(tpl.replace(/<[^>]*>/g, ' '), banned);
});
