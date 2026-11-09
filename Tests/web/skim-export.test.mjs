// buildX, the Skim page's Final Cut export, against a six-clip fixture taken off a real card
// (401 ILCE-7M3 clips, 3840x2160 AVC 23.98p, 2ch LPCM16 48 kHz, free-run timecode from the
// Sony sidecars). Three scenes, and one clip for each of selected / maybe / cut / unrated.
//
//   node --test Tests/web/skim-export.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod, loadBuildX, fixture, buildFixture, ctxFromFixture, decodeLtc, validateAgainstDTD } from './skim-export.mjs';
import { MiniDOMParser } from './mini-xml.mjs';

const fx = fixture();
const attr = (xml, tag, id, name) => {
  const el = new RegExp(`<${tag}[^>]*\\b(?:id|ref)="${id}"[^>]*>`).exec(xml);
  assert.ok(el, `${tag} ${id} is in the export`);
  const m = new RegExp(`\\b${name}="([^"]*)"`).exec(el[0]);
  return m && m[1];
};

test('buildX comes out of the page', () => {
  const { fn, source } = loadBuildX();
  assert.equal(typeof fn, 'function');
  assert.match(source, /^buildX\(\) \{/);
  assert.match(source, /DOCTYPE fcpxml/);
});

test('the Sony timecode decoder matches the clips own timecode', () => {
  // Every tc in the fixture was read back from the file with ffprobe, so this pins the decoder.
  assert.equal(fx.clips.length, 6);
  for (const c of fx.clips) assert.equal(decodeLtc(c.tcRaw, c.tcFps), c.tc, c.name);
  assert.equal(decodeLtc('16324420', 24), '20:44:32:16');   // C0001, the first clip on the card
  assert.equal(decodeLtc('03364420', 24), '20:44:36:03');   // its last frame
});

test('the decoder declines what it cannot read rather than guessing', () => {
  // 60p material carries frame numbers past 24, so a frame field out of range for the stated
  // tcFps means flag bits or a rate this has not been checked against. Either way, not a guess.
  assert.equal(decodeLtc('54344800', 24), null);        // frame 54 cannot be 24 fps timecode
  assert.equal(decodeLtc('54344800', 60), '00:48:34:54'); // at 60 fps it is ordinary
  assert.equal(decodeLtc('16324420'), '20:44:32:16');   // no tcFps given: no range check
  assert.equal(decodeLtc('16994420', 24), null);        // 99 seconds
  assert.equal(decodeLtc('bogus', 24), null);
});
test('Everything exports every clip; Only selected narrows it', () => {
  assert.equal(buildFixture().n, 6);
  // inc(): ex.all || keep || (ex.maybes && maybe)
  assert.equal(buildFixture({ all: false }).n, 3);                   // 2 selected + 1 maybe
  assert.equal(buildFixture({ all: false, maybes: false }).n, 2);    // 2 selected
});

test('durations are whole frames of the clip format', () => {
  const { text } = buildFixture();
  assert.match(text, /<format id="r1" name="FFVideoFormat3840x2160p2398" frameDuration="1001\/24000s" width="3840" height="2160"\/>/);
  fx.clips.forEach((c, i) => {
    const want = `${c.durF * 1001}/24000s`;
    assert.equal(attr(text, 'asset', `a${i+1}`, 'duration'), want, c.name);
    assert.equal(attr(text, 'asset-clip', `a${i+1}`, 'duration'), want, c.name);
  });
});

test('marks become Final Cut ratings and the maybe keyword', () => {
  const { text } = buildFixture();
  const clip = id => {
    const m = new RegExp(`<asset-clip ref="${id}"[\\s\\S]*?</asset-clip>`).exec(text);
    return m ? m[0] : '';
  };
  const want = { keep: 'favorite', cut: 'reject' };
  fx.clips.forEach((c, i) => {
    const body = clip(`a${i+1}`);
    if (want[c.mark]) assert.match(body, new RegExp(`<rating[^>]*value="${want[c.mark]}"/>`), c.name);
    else assert.doesNotMatch(body, /<rating/, `${c.name} is unrated`);
    if (c.mark === 'maybe') assert.match(body, /<keyword[^>]*value="maybe"\/>/, c.name);
  });
});

test('the same shoot always exports the same bytes', () => {
  assert.equal(buildFixture().text, buildFixture().text);
});

test('every clip is referenced by an original-media rep at its real path', () => {
  const { text } = buildFixture();
  for (const c of fx.clips)
    assert.ok(text.includes(`<media-rep kind="original-media" src="file://${encodeURI(c.path)}"/>`), c.name);
});

// Step 2 of design/handoff/lumina-skim/FRIEND-DEMO.md. Each of these needs a change to buildX,
// and the ones marked (FCP) can only be settled by importing into Final Cut Pro.
test('every clip starts at 0s, where Final Cut reads its media, camera timecode or not', () => {
  // Final Cut takes a file's start from the file and reads 00:00:00:00 for these Sony MP4s; a start at the camera's
  // LtcChange left each clip "Modified File" with "no shared media range" on relink (2026-10-15).
  const { text } = buildFixture();
  assert.ok(fixture().clips.every(c => c.tc && c.tc !== '00:00:00:00'), 'the fixture has camera timecode');
  for (const a of text.match(/<asset [^>]*>/g)) assert.match(a, / start="0s" /, a);
  assert.doesNotMatch(text, /<asset-clip [^>]*start=/);
  for (const m of text.matchAll(/<(rating|keyword) start="([^"]+)"/g)) assert.equal(m[2], '0s', m[0]);
});
test('a clip with no timecode starts at 0s', () => {
  const c = ctxFromFixture(fx, { all: true }); c.d.clips.forEach((k, i) => { k.ltc = ['', '16994420', '30000000', 'bogus', '', ''][i]; });   // none, 99 s, frame 30 at 24, not digits
  const t = loadBuildX().fn.call(c).text;
  assert.match(t, /<asset id="a1" name="[^"]+" start="0s"/); assert.doesNotMatch(t, /<asset-clip [^>]*start=/);
});
// round 2, fcpxml item 3: the sound as the camera states it (LOCAL-CHANGES 296)
test('real audio channel count and rate', () => {
  const t = buildFixture({ all: true }).text;
  for (const a of t.match(/<asset [^>]*>/g)) {
    assert.match(a, /hasAudio="1" audioSources="1" audioChannels="2" audioRate="48k"/, a);
  }
  const c = ctxFromFixture(fx, { all: true });
  c.d.clips[0].ach = 0; c.d.clips[1].ach = null; c.d.clips[2].ach = 4; c.d.clips[2].arate = 44100; c.d.clips[3].arate = 22050;
  const u = loadBuildX().fn.call(c).text, as = u.match(/<asset [^>]*>/g);
  assert.match(as[0], /hasAudio="0"/, 'a clip with no sound track says so'); assert.doesNotMatch(as[0], /audioChannels/);
  assert.match(as[1], /hasAudio="1" format=/, 'sound never read keeps the bare hasAudio');
  assert.match(as[2], /audioChannels="4" audioRate="44.1k"/);
  assert.match(as[3], /audioChannels="2" format=/, 'a rate the DTD does not list is left out');
});
// S-Log3's Sony conversion, the clips' real location and the true frame rate: built, in Tests/web/skim-handoff.test.mjs.
test('the export is DTD-valid against the version it declares', t => {
  const { text } = buildFixture();
  const v = /<fcpxml version="([^"]+)"/.exec(text)[1];
  const r = validateAgainstDTD(text, v);
  if (r.skipped) return t.skip(r.skipped);
  // Each DTD fixes its own version (<!ATTLIST fcpxml version CDATA #FIXED "1.10">), so a file is
  // only ever valid against the DTD for the version it declares.
  assert.ok(r.ok, `not valid against FCPXMLv${v}:\n${r.errors}`);
});
test('the file tells Final Cut to leave the clips where they are', () => {
  // Without it Final Cut copies media it imports from a removable drive into the library (71 GB off the T7, 2026-10-14).
  const { text } = buildFixture();
  assert.match(text, /<fcpxml version="1\.10">\n  <import-options>\n    <option key="copy assets" value="0"\/>\n  <\/import-options>\n  <resources>/);
});
test('a standard size and rate carries Final Cut\'s own format name, which the timeline needs', () => {
  // An unnamed format on the sorted project's sequence imported with "Encountered an unexpected value. (format=\"r1\" …/sequence[1]/)".
  const { text } = buildFixture();
  const seq = /<sequence format="(r\d+)"/.exec(text)[1];
  assert.match(text, new RegExp('<format id="' + seq + '" name="FFVideoFormat3840x2160p2398" frameDuration="1001/24000s"'));
});
test('Final Cut honours rating, keyword and timecode on import', { skip: '(FCP) needs an import check' }, () => {});

// ---- Export's In Final Cut options (ratings, the maybe keyword, scenes as keywords, the Camera LUT) ----
const src = fs.readFileSync(PAGE, 'utf8');
const checkX = new Function('return function ' + extractMethod(src, 'checkX', 'static checkX(text, n, P, kws) {').replace(/^static /, ''))();
const scenesCtx = over => { const c = ctxFromFixture(fx, over); c.G = fx.scenes.map(sc => ({ title: sc.label.replace(/^Scene \d+ · /, ''), clips: c.d.clips.filter((_, i) => fx.clips[i].scene === sc.n) })); return c; };
const fxBuild = over => loadBuildX().fn.call(scenesCtx(over));
const clipOf = (text, name) => text.split('<asset-clip ').find(b => b.startsWith('ref') && b.includes('name="' + name + '"')) || '';

test('Ratings off: no clip is rated, and the file still passes the page check', () => {
  const x = fxBuild({ all: true, rate: false });
  assert.doesNotMatch(x.text, /<rating /);
  assert.deepEqual(checkX(x.text, x.n, MiniDOMParser, x.kws), { ok: true, problems: [] });
});

test('the maybe keyword is what was typed, or none at all', () => {
  const b = fxBuild({ all: false, maybes: true, kw: 'b-roll' });
  assert.match(clipOf(b.text, 'C0019'), /<keyword [^>]*value="b-roll"\/>/);
  assert.deepEqual(b.kws, ['b-roll']);
  assert.deepEqual(checkX(b.text, b.n, MiniDOMParser, b.kws), { ok: true, problems: [] });
  assert.equal(checkX(b.text, b.n, MiniDOMParser).ok, false, 'a keyword the file was not written with fails');
  const none = fxBuild({ all: false, maybes: true, kw: '  ' });
  assert.doesNotMatch(none.text, /<keyword /);
  assert.match(fxBuild({ kw: 'a, b' }).text, /value="a b"/, 'a comma would split it in Final Cut');
});

test('one keyword per scene', () => {
  const x = fxBuild({ all: true, scenes: true });
  for (const c of fx.clips) {
    const label = fx.scenes.find(sc => sc.n === c.scene).label;
    const kw = /<keyword [^>]*value="([^"]*)"/.exec(clipOf(x.text, c.name.replace(/\.\w+$/, '')));
    assert.ok(kw, c.name + ' has a keyword');
    assert.ok(kw[1].split(', ').includes(label.replace(/–/g, '–')), c.name + ': ' + kw[1]);
    if (c.mark === 'maybe') assert.ok(kw[1].split(', ').includes('maybe'), 'the maybe keyword stays beside the scene');
  }
  assert.deepEqual(checkX(x.text, x.n, MiniDOMParser, x.kws), { ok: true, problems: [] });
  const r = validateAgainstDTD(x.text);
  if (!r.skipped) assert.ok(r.ok, r.errors);
});

test('Camera LUT off: no S-Log3 clip carries Final Cut\u2019s Sony conversion', () => {
  const c = ctxFromFixture(fx, { all: true }); c.d.clips.forEach(k => { k.profile = { gamma: 'S-Log3', primaries: 'S-Gamut3.Cine' }; });
  assert.match(loadBuildX().fn.call(c).text, /customLUTOverride/);
  c.state.ex.lut = false;
  assert.doesNotMatch(loadBuildX().fn.call(c).text, /customLUTOverride/);
});

test('in the app the clips point at the folder Lumina read them from, unless a folder was typed', () => {
  const c = ctxFromFixture(fx, { all: true });
  c.d.clips.forEach(k => { k.path = 'dump/CLIP/' + k.name; }); c.d.shoot.real = true; c.exHost = { clips: '/Volumes/T7/dump' };
  assert.match(loadBuildX().fn.call(c).text, /src="file:\/\/\/Volumes\/T7\/dump\/CLIP\/C0002\.MP4"/);
  c.state.ex.root = '/Volumes/Other/dump';
  assert.match(loadBuildX().fn.call(c).text, /src="file:\/\/\/Volumes\/Other\/dump\/CLIP\/C0002\.MP4"/);
});

// round 2, F1: the sorted timeline, a project in the same event (LOCAL-CHANGES 293)
test('the sorted timeline: selected, maybe, unmarked, cut, a marker at the start of each part, back to back', () => {
  const x = buildFixture({ all: true }), mk = Object.fromEntries(fx.clips.map(c => [c.id, c.mark || 'und']));
  const ev = x.text.slice(x.text.indexOf('<event'), x.text.indexOf('<project')), sp = x.text.slice(x.text.indexOf('<spine>'), x.text.indexOf('</spine>'));
  assert.equal((x.text.match(/<project /g) || []).length, 1);
  const eventRefs = [...ev.matchAll(/<asset-clip ref="(a\d+)"/g)].map(m => m[1]), spine = [...sp.matchAll(/<asset-clip ref="(a\d+)" offset="(\d+)(?:\/(\d+))?s"[^>]*duration="(\d+)\/(\d+)s"/g)];
  assert.equal(spine.length, eventRefs.length, 'every clip in the event is on the timeline once');
  const byRef = {}; fx.clips.forEach((c, i) => { byRef['a' + (i + 1)] = mk[c.id]; });
  const rank = { keep: 0, maybe: 1, und: 2, cut: 3 }, ranks = spine.map(m => rank[byRef[m[1]]]);
  assert.deepEqual(ranks, [...ranks].sort((a, b) => a - b), 'parts in order: ' + spine.map(m => byRef[m[1]]).join(' '));
  let at = 0; spine.forEach(m => { assert.equal(+m[2], at, 'each clip starts where the last ended'); at += +m[4]; });
  const markers = [...sp.matchAll(/<marker [^>]*value="([^"]*)"/g)].map(m => m[1]);
  assert.equal(markers.length, new Set(ranks).size, 'one marker per part: ' + markers.join(' | '));
  assert.match(markers[0], /^Selected · \d+ clips?$/);
  assert.ok(Component_checkX(x.text, x.n, x.kws).ok, 'the page check takes the file with its timeline');
  assert.ok(!/<project /.test(buildFixture({ all: true, sorted: false }).text), 'Sorted timeline off: only the event');
  const r = validateAgainstDTD(x.text); if (!r.skipped) assert.ok(r.ok, r.errors);
});
function Component_checkX(text, n, kws) {
  const src = fs.readFileSync(PAGE, 'utf8'), body = extractMethod(src, 'checkX', 'static checkX(text, n, P, kws) {').replace(/^static /, '');
  return new Function('return function ' + body)()(text, n, MiniDOMParser, kws);
}

// round 2, fcpxml item 3: the Skim folder in the event's browser (LOCAL-CHANGES 296)
test('a Skim folder: smart collections for Selected, Maybe and Cut, a keyword collection per scene', () => {
  const x = fxBuild({ all: true, scenes: true });
  const f = /<collection-folder name="Skim">([\s\S]*?)<\/collection-folder>/.exec(x.text);
  assert.ok(f, 'the folder is in the event');
  assert.ok(x.text.indexOf('<collection-folder') < x.text.indexOf('<project'), 'before the project');
  assert.match(f[1], /<smart-collection name="Selected" match="all">\s*<match-ratings value="favorites"\/>/);
  assert.match(f[1], /<smart-collection name="Maybe" match="all">\s*<match-keywords rule="includesAny">\s*<keyword-name value="maybe"\/>/);
  assert.match(f[1], /<smart-collection name="Cut" match="all">\s*<match-ratings value="rejected"\/>/);
  const kc = [...f[1].matchAll(/<keyword-collection name="([^"]*)"\/>/g)].map(m => m[1]);
  assert.equal(kc.length, fx.scenes.length, 'one per scene');
  for (const k of kc) assert.ok(x.kws.includes(k), k + ' is a keyword the clips carry');
  assert.deepEqual(checkX(x.text, x.n, MiniDOMParser, x.kws), { ok: true, problems: [] });
  const r = validateAgainstDTD(x.text);
  if (!r.skipped) assert.ok(r.ok, r.errors);
});
test('the Skim folder holds only what the file can fill', () => {
  const off = fxBuild({ all: true, rate: false, kw: '', scenes: false });
  assert.doesNotMatch(off.text, /<collection-folder/, 'no ratings, no keyword, no scenes: no folder');
  const sel = fxBuild({ all: false, maybes: false });
  assert.doesNotMatch(sel.text, /name="Maybe"|name="Cut"/);
  assert.match(sel.text, /<smart-collection name="Selected"/);
  const bad = sel.text.replace('<match-ratings value="favorites"/>', '<match-text rule="includes" value="x"/>');
  assert.equal(checkX(bad, sel.n, MiniDOMParser, sel.kws).ok, false, 'the check refuses what the page does not write');
});

// round 2, fcpxml item 4: Skim's flags as markers at their moment (LOCAL-CHANGES 296)
test('soft frames and a brightness jump become markers at the frame Skim measured', () => {
  const c = ctxFromFixture(fx, { all: true }), k = c.d.clips[0];
  k.facts = { state: 'ready', idx: [0, 2, 5], sharpF: [0.8, 0.21, 0.9], bump: 2 };
  const t = loadBuildX().fn.call(c).text, ev = t.slice(t.indexOf('<event'), t.indexOf('<project'));
  const body = /<asset-clip ref="a1"[\s\S]*?<\/asset-clip>/.exec(ev)[0];
  const mk = [...body.matchAll(/<marker start="(\d+)\/(\d+)s" duration="(\d+)\/\d+s" value="([^"]*)"\/>/g)];
  assert.deepEqual(mk.map(m => m[4]), ['soft · sharpness 0.21', 'bump · brightness jumps']);
  const s0 = /<asset-clip ref="a1"[^>]*start="(\d+)\/(\d+)s"/.exec(body), fr = m => +m[1] / +m[3];
  const base = s0 ? +s0[1] / 1001 : 0, slot = j => Math.floor((j + 0.5) / 8 * k.dur * 24000 / 1001);
  assert.equal(fr(mk[0]) - base, slot(2)); assert.equal(fr(mk[1]) - base, slot(5));
  assert.ok(body.indexOf('<rating') < body.indexOf('<marker'), 'after the rating, as the DTD orders them');
  assert.ok(Component_checkX(t, 6, ['maybe']).ok, 'the page check takes the markers');
  for (const q of c.d.clips.slice(1)) assert.doesNotMatch(new RegExp('<asset-clip ref="a' + (c.d.clips.indexOf(q) + 1) + '"[\\s\\S]*?</asset-clip>').exec(ev)[0], /<marker /, 'no facts, no markers');
  k.facts.state = 'reading';
  const u = loadBuildX().fn.call(c).text; assert.doesNotMatch(u.slice(0, u.indexOf('<project')), /<marker /, 'only facts that finished');
});

// ---- Looks: a clip with a look goes with Camera LUT None and Final Cut's Custom LUT effect naming its cube (lkLuts).
const pageSrc = fs.readFileSync(PAGE, 'utf8');
const LK = (() => { const a = pageSrc.indexOf('// LOOK-BEGIN'), b = pageSrc.indexOf('// LOOK-END'); return new Function('class Component {\n' + pageSrc.slice(a, b) + '\n}\nreturn Component;')(); })();
const lkLuts = new Function('Component', 'return function ' + extractMethod(pageSrc, 'lkLuts', 'lkLuts(clips, event) {'))(LK);
const lkEvs = new Function('Component', 'return function ' + extractMethod(pageSrc, 'lkEvs', 'lkEvs(clips) {'))(LK);
const withLooks = (over = {}) => {
  const c = ctxFromFixture(fx, { all: true, ...over });
  c.d.clips.forEach((k, i) => { k.profile = i < 3 ? { gamma: 'S-Log3', primaries: 'S-Gamut3.Cine' } : null; });
  const ids = c.d.clips.map(k => k.id), M = { [ids[0]]: { ev: 0.5, temp: 30 }, [ids[3]]: { sat: -40 }, [ids[1]]: { ev: -0.25 } };
  c.looks = () => M; c.lkLuts = lkLuts; c.lkEvs = lkEvs; return { c, ids };
};
test('looks: one Custom LUT effect, a filter on each clip with a look (event and timeline), Camera LUT None for those only', () => {
  const { c, ids } = withLooks(), x = loadBuildX().fn.call(c);
  assert.deepEqual(Object.keys(x.luts).sort(), [ids[0], ids[3]].sort());
  assert.equal((x.text.match(/<effect id="lut1" name="Custom LUT" uid="FxPlug:14B39AEF-607D-42DF-98DD-DB3DD345E925"\/>/g) || []).length, 1);
  assert.equal((x.text.match(/<filter-video ref="lut1" name="Custom LUT">/g) || []).length, 4, 'two clips, each in the event and in the sorted timeline');
  assert.equal(attr(x.text, 'asset', 'a1', 'customLUTOverride'), null, 'the log clip with a look: Camera LUT None, its cube converts');
  assert.equal(attr(x.text, 'asset', 'a2', 'customLUTOverride'), '35 (Sony_SLog3_SGamut3Cine_v2)', 'a log clip without a look keeps today’s conversion');
  const e = x.luts[ids[0]];
  assert.match(e.rel, /^Lumina Skim\/[^/]+\/[^/]+ [0-9a-f]{6}\.cube$/); assert.equal(e.mode, 1); assert.equal(x.luts[ids[3]].mode, 0);
  assert.ok(x.text.includes('value="' + e.param + '"'));
  assert.equal(e.param, LK.lkLutParam(LK.lkLutHash(e.rel) + ':' + e.name));
  assert.match(e.text, new RegExp('^TITLE "' + e.name + '"\\nLUT_3D_SIZE 33\\n'));
});
test('looks: the file passes the page check and Final Cut’s DTD', t => {
  const { c } = withLooks(), x = loadBuildX().fn.call(c);
  const checkX = new Function('return function ' + extractMethod(pageSrc, 'checkX', 'static checkX(text, n, P, kws) {').replace(/^static /, ''))();
  const r = checkX(x.text, x.n, MiniDOMParser, x.kws); assert.ok(r.ok, r.problems.join('\n'));
  const v = validateAgainstDTD(x.text, '1.10'); if (v.skipped) return t.skip(v.skipped); assert.ok(v.ok, v.errors);
});
test('looks: a changed look is a new cube name; the same look again is the same name; Looks off writes none', () => {
  const { c, ids } = withLooks(), a = loadBuildX().fn.call(c).luts[ids[0]].name;
  assert.equal(loadBuildX().fn.call(c).luts[ids[0]].name, a);
  const M = c.looks(); M[ids[0]] = { ev: 0.6, temp: 30 }; c.bxM = null;
  assert.equal(loadBuildX().fn.call(c).luts[ids[0]].name, a, 'only the Exposure changed: same cube, the slider moves');
  M[ids[0]] = { ev: 0.6, temp: 35 }; c.bxM = null;
  assert.notEqual(loadBuildX().fn.call(c).luts[ids[0]].name, a);
  c.state.ex.looks = false; c.bxM = null; const off = loadBuildX().fn.call(c);
  assert.deepEqual(off.luts, {}); assert.doesNotMatch(off.text, /Custom LUT|Color Adjustments/); assert.match(attr(off.text, 'asset', 'a1', 'customLUTOverride'), /Sony_SLog3/);
});
test('looks: the page check refuses an effect or a filter it does not write', () => {
  const { c } = withLooks(), x = loadBuildX().fn.call(c);
  const checkX = new Function('return function ' + extractMethod(pageSrc, 'checkX', 'static checkX(text, n, P, kws) {').replace(/^static /, ''))();
  assert.ok(!checkX(x.text.replace('FxPlug:14B39AEF', 'FxPlug:00000000'), x.n, MiniDOMParser, x.kws).ok);
  assert.ok(!checkX(x.text.replace('<param name="Output"', '<param name="Mix" key="9" value="1"/><param name="Output"'), x.n, MiniDOMParser, x.kws).ok);
});

// ---- A look's Exposure goes on Final Cut's own Exposure slider (Color Adjustments), after the LUT: 50 per stop, ±100 at most.
test('exposure: 50 per stop on Final Cut’s slider, rounded to 0.1, ±100 at most, none at 0', () => {
  assert.equal(LK.lkFcpEv({ ev: 0.5 }), 25); assert.equal(LK.lkFcpEv({ ev: -0.25 }), -12.5); assert.equal(LK.lkFcpEv({ ev: 0.333 }), 16.5);
  assert.equal(LK.lkFcpEv({ ev: 3 }), 100); assert.equal(LK.lkFcpEv({ ev: -4 }), -100);
  assert.equal(LK.lkFcpEv({}), 0); assert.equal(LK.lkFcpEv(null), 0); assert.equal(LK.lkFcpEv({ ev: 0.001 }), 0);
  assert.ok(Object.is(LK.lkFcpEv({ ev: -0.001 }), 0), 'never -0 in the file');
});
test('exposure: a Color Adjustments filter after the LUT, the cube without the Exposure, an exposure-only clip keeps the Camera LUT', () => {
  const { c, ids } = withLooks(), x = loadBuildX().fn.call(c);
  assert.equal((x.text.match(/<effect id="ca1" name="Color Adjustments" uid="FxPlug:7E2022A5-202B-4EEB-A311-AC2B585D01B0"\/>/g) || []).length, 1);
  assert.equal((x.text.match(/<filter-video ref="ca1" name="Color Adjustments">\n\s*<param name="Exposure" key="3" value="25"\/>\n\s*<\/filter-video>/g) || []).length, 2, 'ev +0.5: event and timeline');
  assert.equal((x.text.match(/<param name="Exposure" key="3" value="-12.5"\/>/g) || []).length, 2, 'ev −0.25: event and timeline');
  assert.ok(x.text.indexOf('name="Custom LUT">') < x.text.indexOf('name="Color Adjustments">'), 'the LUT first, then the Exposure');
  assert.equal(x.luts[ids[1]], undefined, 'an exposure-only look writes no cube');
  assert.equal(attr(x.text, 'asset', 'a2', 'customLUTOverride'), '35 (Sony_SLog3_SGamut3Cine_v2)', 'and keeps Final Cut’s S-Log3 conversion');
  const flat = parseCubeFirst(x.luts[ids[0]].text), ref = parseCubeFirst(lkLuts.call({ looks: () => ({ [ids[0]]: { temp: 30 } }), lkCubes: new Map() }, [c.d.clips[0]], 'e')[ids[0]].text);
  assert.equal(flat, ref, 'the cube is the look without its Exposure');
});
test('exposure: the file passes the page check and Final Cut’s DTD; the check refuses a filter it does not write', t => {
  const { c } = withLooks(), x = loadBuildX().fn.call(c);
  const checkX = new Function('return function ' + extractMethod(pageSrc, 'checkX', 'static checkX(text, n, P, kws) {').replace(/^static /, ''))();
  const r = checkX(x.text, x.n, MiniDOMParser, x.kws); assert.ok(r.ok, r.problems.join('\n'));
  assert.ok(!checkX(x.text.replace('<param name="Exposure" key="3" value="25"/>', '<param name="Exposure" key="3" value="25"/><param name="Contrast" key="17" value="4"/>'), x.n, MiniDOMParser, x.kws).ok, 'a second parameter');
  assert.ok(!checkX(x.text.replace('value="25"/>', 'value="140"/>'), x.n, MiniDOMParser, x.kws).ok, 'past Final Cut’s range');
  const fl = /(\s*<filter-video ref="lut1"[\s\S]*?<\/filter-video>)(\s*<filter-video ref="ca1"[\s\S]*?<\/filter-video>)/;
  assert.ok(!checkX(x.text.replace(fl, '$2$1'), x.n, MiniDOMParser, x.kws).ok, 'the Exposure before the LUT');
  const v = validateAgainstDTD(x.text, '1.10'); if (v.skipped) return t.skip(v.skipped); assert.ok(v.ok, v.errors);
});
function parseCubeFirst(text){ return text.split('\n').filter(l => /^[\d.]+ [\d.]+ [\d.]+$/.test(l)).join('\n'); }
