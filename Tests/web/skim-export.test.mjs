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
  assert.match(text, /<format id="r1" frameDuration="1001\/24000s" width="3840" height="2160"\/>/);
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
test('camera timecode as the asset start, the clip start and the start of its rating and keyword', () => {
  const { text } = buildFixture();
  const fx2 = fixture();
  fx2.clips.forEach((c, i) => {
    const [hh, mm, ss, ff] = c.tc.split(':').map(Number), fr = ((hh * 60 + mm) * 60 + ss) * c.tcFps + ff, want = `${fr * c.fpsDen}/${c.fpsNum}s`;
    assert.equal(attr(text, 'asset', `a${i+1}`, 'start'), want, c.name + ' asset');
    assert.equal(attr(text, 'asset-clip', `a${i+1}`, 'start'), want, c.name + ' clip');
    const body = new RegExp(`<asset-clip ref="a${i+1}"[\\s\\S]*?</asset-clip>`).exec(text)[0];
    for (const m of body.matchAll(/<(rating|keyword) start="([^"]+)"/g)) assert.equal(m[2], want, c.name + ' ' + m[1]);
  });
});
test('a clip with no timecode starts at 0s', () => {
  const c = ctxFromFixture(fx, { all: true }); c.d.clips.forEach((k, i) => { k.ltc = ['', '16994420', '30000000', 'bogus', '', ''][i]; });   // none, 99 s, frame 30 at 24, not digits
  const t = loadBuildX().fn.call(c).text;
  assert.match(t, /<asset id="a1" name="[^"]+" start="0s"/); assert.doesNotMatch(t, /<asset-clip [^>]*start=/);
});
test('real audio channel count and rate', { skip: 'not built: hasAudio=1 for every clip' }, () => {});
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
