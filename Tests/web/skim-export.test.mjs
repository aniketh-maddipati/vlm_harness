// buildX, the Skim page's Final Cut export, against a six-clip fixture taken off a real card
// (401 ILCE-7M3 clips, 3840x2160 AVC 23.98p, 2ch LPCM16 48 kHz, free-run timecode from the
// Sony sidecars). Three scenes, and one clip for each of selected / maybe / cut / unrated.
//
//   node --test Tests/web/skim-export.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadBuildX, fixture, buildFixture, decodeLtc, validateAgainstDTD } from './skim-export.mjs';

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
test('camera timecode as the asset start', { skip: 'not built: asset start is still 0s' }, () => {});
test('one keyword per scene', { skip: 'not built: only the maybe keyword is written' }, () => {});
test('real audio channel count and rate', { skip: 'not built: hasAudio=1 for every clip' }, () => {});
test('S-Log3 asks Final Cut for its Sony Log conversion', { skip: 'not built; no S-Log3 material reachable yet' }, () => {});
test('the app passes real clip URLs, the browser says Relink', { skip: 'not built: paths are guessed as /Volumes/<name>' }, () => {});
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
