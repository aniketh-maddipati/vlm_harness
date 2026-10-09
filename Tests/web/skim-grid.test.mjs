// The one grid, clips first: clips are the tiles, scenes the headers over them, five sizes and a scenes level that a
// pinch, − / = and the size buttons move through; skimming a tile; the Export summary; marks never stored. The page
// is the one implementation; the functions are read out of it the way skim-export.mjs reads buildX.
//
//   node --test Tests/web/skim-grid.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const f of ['ZL', 'ZL_LINES', 'ZL_WORD', 'ZL_DEF', 'KEEP_MARKS']) {
  const m = src.match(new RegExp('\\n  static ' + f + ' = ([^;]*);'));
  assert.ok(m, 'in the page: ' + f); C[f] = new Function('return ' + m[1])();
}
for (const name of ['zlGeo', 'laySecs', 'laySecAt', 'laySecNav', 'zlStep', 'skimAt', 'rubber', 'exSummary', 'isMarkKey']) {
  const m = src.match(new RegExp('\\n  static ' + name + '\\(([^)]*)\\) \\{'));
  assert.ok(m, 'in the page: ' + name);
  C[name] = new Function('Component', 'return ' + extractMethod(src, name, 'static ' + name + '(' + m[1] + ') {').replace(/^static /, 'function '))(C);
}

const geo = (zl, vw = 1440) => C.zlGeo({vw, zl});
const secsOf = ns => ns.map(n => ({n, head:true}));

test('sizes: scenes, then five clip sizes, tiles growing and columns falling', () => {
  assert.equal(C.ZL.length, 6); assert.equal(C.ZL_WORD.length, 6); assert.equal(C.ZL_WORD[0], 'scenes'); assert.equal(C.ZL_DEF, 3);
  let prev = null;
  for (let zl = 1; zl <= 5; zl++) {
    const g = geo(zl); assert.ok(g.cols >= 1); assert.ok(Math.abs(g.cols * g.tw + (g.cols - 1) * g.gx - g.W) < 1e-6, 'the row fills the width');
    assert.equal(g.ph, Math.round(g.tw * 9 / 16)); assert.equal(g.th, g.ph + C.ZL_LINES[zl]); assert.ok(g.hh > 0, 'clip sizes have scene headers');
    if (prev) { assert.ok(g.tw > prev.tw, 'larger at ' + zl); assert.ok(g.cols <= prev.cols); }
    prev = g;
  }
  assert.equal(geo(0).hh, 0, 'scene tiles have no headers');
  assert.equal(geo(9).zl, 5); assert.equal(geo(-2).zl, 0);
  for (const vw of [320, 800, 1280, 2560, 5120]) for (let zl = 0; zl <= 5; zl++) { const g = geo(zl, vw); assert.ok(g.cols >= 1 && g.tw > 0 && g.tw <= g.W + 1e-6, vw + ' ' + zl); }
});

test('sections: every tile once, in order, each section on rows of its own under its header', () => {
  const g = geo(3), ns = [13, 6, 7, 1, 30, 4], secs = secsOf(ns), L = C.laySecs({geo:g, secs});
  const tiles = L.items.filter(i => i.kind === 't'), heads = L.items.filter(i => i.kind === 'h');
  assert.deepEqual(tiles.map(t => t.g), Array.from({length:61}, (_, i) => i)); assert.equal(L.n, 61);
  assert.deepEqual(heads.map(h => h.s), [0, 1, 2, 3, 4, 5]);
  heads.forEach(h => {
    const mine = tiles.filter(t => t.s === h.s);
    assert.equal(mine.length, ns[h.s]); assert.ok(mine.every(t => t.y >= h.y + g.hh), 'under its header');
    const next = heads.find(x => x.s === h.s + 1); if (next) assert.ok(mine.every(t => t.y + t.h <= next.y), 'above the next header');
    assert.equal(mine[0].x, 0, 'a section starts a row');
  });
  tiles.forEach(t => { assert.ok(t.x + t.w <= g.W + 1e-6); assert.ok(t.y + t.h <= L.height); const at = C.laySecAt(g, secs, t.g); assert.equal(at.x, t.x); assert.equal(at.y, t.y); assert.equal(at.s, t.s); });
  assert.equal(C.laySecAt(g, secs, 61), null);
  // no headers: one section is a plain grid
  const flat = C.laySecs({geo:geo(0), secs:[{n:20, head:false}]});
  assert.equal(flat.items.filter(i => i.kind === 'h').length, 0); assert.equal(flat.items.length, 20);
});

test('sections: a window lays out what is near the screen and the current tile, nothing else', () => {
  const g = geo(2), ns = Array.from({length:60}, (_, i) => 1 + (i * 7) % 23), secs = secsOf(ns), all = C.laySecs({geo:g, secs}), N = all.n;
  for (const [top, cur] of [[0, 0], [3000, 200], [9000, 3], [all.height - 900, N - 1], [5000, null]]) {
    const L = C.laySecs({geo:g, secs, top, h:900, cur}), key = i => i.kind + (i.kind === 't' ? i.g : i.s);
    assert.equal(L.height, all.height);
    for (const it of all.items) if (it.y + it.h > top && it.y < top + 900) assert.ok(L.items.some(x => key(x) === key(it) && x.y === it.y), 'on screen: ' + key(it));
    if (cur != null) assert.ok(L.items.some(x => x.kind === 't' && x.g === cur), 'the current tile');
    assert.ok(L.items.length < all.items.length);
  }
});

test('↑ ↓ cross headers and keep the column, as far as a short row allows', () => {
  const g = {...geo(3), cols:4}, secs = secsOf([10, 2, 5]);
  // section 0: rows [0-3] [4-7] [8-9]; section 1: [10-11]; section 2: [12-15] [16]
  assert.equal(C.laySecNav(g, secs, 1, 1), 5); assert.equal(C.laySecNav(g, secs, 7, 1), 9, 'a short last row: its last tile');
  assert.equal(C.laySecNav(g, secs, 9, 1), 11, 'down into the next scene, same column as far as it goes');
  assert.equal(C.laySecNav(g, secs, 8, 1), 10); assert.equal(C.laySecNav(g, secs, 11, 1), 13);
  assert.equal(C.laySecNav(g, secs, 13, -1), 11); assert.equal(C.laySecNav(g, secs, 12, -1), 10); assert.equal(C.laySecNav(g, secs, 10, -1), 8);
  assert.equal(C.laySecNav(g, secs, 2, -1), 2, 'top row stays'); assert.equal(C.laySecNav(g, secs, 16, 1), 16, 'bottom row stays');
  assert.equal(C.laySecNav(g, secs, 16, -1), 12);
});

test('the pinch: steps between sizes come from the tile widths; past either end it only stretches', () => {
  const G = z => geo(z);
  for (let z = 1; z < 5; z++) { const up = C.zlStep(z, z + 1, G), dn = C.zlStep(z + 1, z, G); assert.ok(up > 0.15 && up < 0.6, 'step ' + z + ' ' + up); assert.ok(Math.abs(up + dn) < 1e-9); }
  assert.equal(C.zlStep(0, 1, G), 0.3); assert.equal(C.zlStep(1, 0, G), -0.3);
  assert.equal(C.rubber(-0.4, 0, 5), -0.4 * 0.3); assert.equal(C.rubber(0.4, 5, 5), 0.4 * 0.3); assert.equal(C.rubber(0.4, 0, 5), 0.4); assert.equal(C.rubber(-0.4, 3, 5), -0.4);
});

test('skimming: the pointer picks one of n parts across the picture, clamped at its edges', () => {
  assert.equal(C.skimAt(100, 100, 240, 8), 0); assert.equal(C.skimAt(339.9, 100, 240, 8), 7); assert.equal(C.skimAt(400, 100, 240, 8), 7); assert.equal(C.skimAt(50, 100, 240, 8), 0);
  assert.equal(C.skimAt(160, 100, 240, 8), 2); assert.equal(C.skimAt(220, 100, 240, 3), 1); assert.equal(C.skimAt(150, 100, 0, 8), 0);
  const seen = new Set(); for (let x = 0; x < 240; x++) seen.add(C.skimAt(x, 0, 240, 8)); assert.deepEqual([...seen], [0, 1, 2, 3, 4, 5, 6, 7]);
});

test('the page: clips first by default, every input path wired', () => {
  assert.match(src, /state = \{progOn:false,zl:3,skim:null,/);
  assert.match(src, /if \(this\.cvGrid\(\)\) return this\.cvPinch\(dz, e\);/, '⌃-wheel (Chromium) pinches the grid');
  assert.match(src, /if \(this\.cvGrid\(\) && this\.state\.step === 'skim' && !this\.pinchHold\) return this\.cvPinch\(Math\.log\(r\), e\);/, 'gesture events (WebKit) pinch the grid');
  assert.match(src, /if \(this\.pzOn\) this\.cvPinchEnd\(\);/, 'letting go springs back');
  assert.match(src, /this\.cvGrid\(\) && this\.hoverGi != null && this\.cvSkimBy\(e\.deltaX\)/, 'two fingers sideways skim the tile under the pointer');
  for (const k of ["case '[': if (this.cvGrid()) return this.cvFold(-1);", "case ']': if (this.cvGrid()) return this.cvFold(1);", 'if (this.cvGrid()) return this.cvZoom(-1);', 'if (this.cvGrid()) return this.cvZoom(1);', 'if (this.cvGrid()) return this.cvMoveRow(1);', 'if (this.cvGrid()) return this.cvMoveRow(-1);']) assert.ok(src.includes(k), k);
  assert.match(src, /onMouseMove="\{\{ fMove \}\}" onMouseLeave="\{\{ fLeave \}\}"/);
  assert.match(src, /data-scene="\{\{ h\.s \}\}" data-nobox="1" onClick="\{\{ hClick \}\}"/);
});

const fmtB = b => (b / 1e9).toFixed(1) + ' GB', fmtDur = s => Math.round(s) + ' s';
const base = {file:'Trip.fcpxml', bytes:5300, check:{ok:true, problems:[]}, n:12, dur:150, inBytes:3.1e9, total:40, totalBytes:12e9, markN:{keep:10, maybe:2, cut:20}, markB:{keep:2.6e9, maybe:0.5e9, cut:6e9}, all:false, maybes:true, event:'Trip', root:'/Volumes/T7/Trip', real:false, sample:false, slog:7};

test('Export summary: the file, the clips, what the pass did, the Final Cut steps and what to check', () => {
  const S = C.exSummary(base, fmtB, fmtDur);
  assert.equal(S.file, 'Trip.fcpxml · 5 KB · a list for Final Cut, not the footage');
  assert.equal(S.check, 'Checked: 12 clips, well formed.'); assert.equal(S.checkBad, false);
  assert.equal(S.inLine, '12 clips · 150 s · 3.1 GB of footage, linked where it is. Nothing is copied or changed.');
  assert.equal(S.where, 'Final Cut will look for them in /Volumes/T7/Trip.');
  assert.deepEqual(S.did.map(r => r.t), ['Sorted 40 clips · 12.0 GB in one pass', '10 selected · 2.6 GB · Favorites in Final Cut', '2 maybe · 0.5 GB · keyword “maybe”', '20 cut · 6.0 GB you can free · left out', '8 undecided · left out']);
  assert.ok(S.steps.some(r => /File ▸ Import ▸ XML… and pick Trip\.fcpxml/.test(r.t))); assert.ok(S.steps.some(r => /new event “Trip”/.test(r.t)));
  assert.ok(S.steps.some(r => /7 S-Log3 clips arrive with Camera LUT Sony S-Log3\/S-Gamut3\.Cine/.test(r.t)));
  assert.ok(S.look.some(r => r.t === 'The event holds 12 clips.')); assert.ok(S.look.some(r => /Relink Files/.test(r.t))); assert.ok(S.look.some(r => /Favorites: 10 clips/.test(r.t)));
});

test('Export summary: Everything, no S-Log3, nothing yet, a failed check, the app and the sample', () => {
  const E = C.exSummary({...base, all:true, n:40, slog:0}, fmtB, fmtDur);
  assert.ok(E.did.some(r => r.t === '20 cut · 6.0 GB you can free · Rejected in Final Cut')); assert.ok(E.did.some(r => r.t === '8 undecided · unrated in Final Cut'));
  assert.ok(E.steps.some(r => /Rejected; with the browser set to Hide Rejected/.test(r.t))); assert.ok(!E.steps.some(r => /S-Log3/.test(r.t))); assert.ok(!E.look.some(r => /S-Log3/.test(r.t)));
  const N = C.exSummary({...base, n:0, check:null}, fmtB, fmtDur); assert.match(N.file, /^Nothing to download yet/); assert.equal(N.check, ''); assert.equal(N.where, '');
  const B = C.exSummary({...base, check:{ok:false, problems:['A clip points at media that is not in the file.']}}, fmtB, fmtDur); assert.equal(B.check, 'Not ready: A clip points at media that is not in the file.'); assert.equal(B.checkBad, true);
  assert.equal(C.exSummary({...base, check:null}, fmtB, fmtDur).check, 'Checking the file…');
  assert.equal(C.exSummary({...base, real:true}, fmtB, fmtDur).where, 'Final Cut links to the files where Lumina read them.');
  assert.match(C.exSummary({...base, root:''}, fmtB, fmtDur).where, /Details ▸ Folder/);
  assert.match(C.exSummary({...base, sample:true}, fmtB, fmtDur).where, /^Sample clips/);
  assert.equal(C.exSummary({...base, markN:{keep:0, maybe:0, cut:0}, markB:{}, total:3}, fmtB, fmtDur).did.length, 5, 'undecided shows when there are any');
  for (const o of [base, {...base, all:true}]) { const S = C.exSummary(o, fmtB, fmtDur), words = [S.file, S.inLine, S.where, ...S.did.map(r => r.t), ...S.steps.map(r => r.t), ...S.look.map(r => r.t)].join(' '); assert.doesNotMatch(words, /\b(keep|kept|keepers?|AI|smart|auto)\b/); }
});

test('marks are never stored: nothing read back, nothing written, old entries dropped', () => {
  assert.equal(C.KEEP_MARKS, false);
  assert.match(src, /save\(\) \{\n    const s = this\.state; if \(!Component\.KEEP_MARKS \|\|/, 'save writes nothing');
  const load = extractMethod(src, 'loadData', 'loadData(d, step) {');
  assert.doesNotMatch(load, /localStorage|reconcile\(/, 'loading reads no saved marks');
  assert.match(src, /this\.dropSavedMarks\(\); this\.dedupeNames\(\);/, 'entries from earlier builds are dropped on start');
  assert.match(src, /if \(!Component\.KEEP_MARKS\) \{ Object\.keys\(all\)\.filter\(k => Component\.isMarkKey\(k\)\)\.forEach\(k => this\.persist\(k, null\)\); return; \}/, 'and in the app’s store');
  assert.equal(C.isMarkKey('lumina-skim:Trip-40-abc'), true); assert.equal(C.isMarkKey('lumina-skim:sample-fx5'), true);
  assert.equal(C.isMarkKey('lumina-skim:clock'), false); assert.equal(C.isMarkKey('lumina-skimroots'), false); assert.equal(C.isMarkKey('lumina-skimprefs:mem'), false); assert.equal(C.isMarkKey(null), false);
  assert.match(src, /window\.addEventListener\('beforeunload', this\._bu\)/, 'leaving with marks not downloaded asks first');
  assert.match(src, /forgetOn:Component\.KEEP_MARKS && /, 'no Forget marks button');
});

test('the one grid shows less: no level tabs, the scene slider and the raw file only in debug mode, Export as a sheet over the grid', () => {
  const tpl = src.slice(0, src.indexOf('class Component'));
  const tabs = tpl.indexOf('data-lumina="levels"'), tabsIf = tpl.lastIndexOf('<sc-if value="{{ lvTabsOn }}"', tabs);
  assert.ok(tabsIf > 0 && !tpl.slice(tabsIf, tabs).includes('</sc-if>'), 'the level tabs sit inside lvTabsOn');
  assert.match(src, /lvTabsOn:!st\.cv/);
  const sl = tpl.indexOf('aria-label="scenes"'), slIf = tpl.lastIndexOf('<sc-if value="{{ scOn }}"', sl);
  assert.ok(slIf > 0 && !tpl.slice(slIf, sl).includes('</sc-if>'), 'the scene slider sits inside scOn');
  assert.match(src, /vals\.scOn = !!st\.dbg;/);
  for (const k of ['By scene</span>', 'The .fcpxml</span>', '{{ exRows }}']) { const at = tpl.indexOf(k), on = tpl.lastIndexOf('<sc-if value="{{ exDbg }}"', at); assert.ok(on > 0 && !tpl.slice(on, at).includes('</sc-if>'), k); }
  assert.ok(!/data-lumina="export-problems"[\s\S]{0,40}exDbg/.test(tpl) && tpl.indexOf('export-problems') > 0, 'a failed check still shows');
  assert.match(src, /const sheet = !!st\.cv && st\.step === 'export' && this\.hasShoot\(\), sk = st\.step === 'skim' \|\| sheet;/);
  assert.match(src, /isSkim:st\.step === 'skim' \|\| sheet/);
  assert.match(src, /exOut:e => \{ if \(e\.target === e\.currentTarget\) this\.setStep\('skim'\); \}/, 'a click beside the sheet goes back');
  assert.doesNotMatch(src, /'nothing to note'/);
});
