// LuminaCore.phoneOf on the seven unit cases of design/handoff/lumina-cull/TEST-PLAN.md ("Automated"), three ways:
// as direct calls on records, through parseHead on synthetic DNGs (dng-families.mjs, plus dng-fixtures.mjs for
// Apple / Google / SONY ILCE-7M4), and through the page's own phone remap line, taken from readOne in
// the Sets page Scripts/page_files.sh names (PAGE). Loads the app's lumina-core-v4.js the way dng-parse.test.mjs does.
// TEST-PLAN is the expectation: a case phoneOf gets wrong prints FAIL.
//
//   node Tests/web/dng-families.test.mjs      (ok / FAIL per check, exit 1 on any FAIL; "note" lines are observations)
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { families } from './dng-families.mjs';
import { fixtures, PAGE_HEAD } from './dng-fixtures.mjs';

const LC = createRequire(import.meta.url)('../../Lumina/Sets/Web/lumina-core-v4.js');
let bad = 0, good = 0;
const eq = (n, a, b) => { const ok = JSON.stringify(a) === JSON.stringify(b); console.log(ok ? 'ok  ' : 'FAIL', n); if (ok) good++; else { bad++; console.log('  got ', JSON.stringify(a), '\n  want', JSON.stringify(b)); } };
const note = s => console.log('note', s);
const isPhone = m => !!LC.phoneOf(m);

// ---- the page's remap, read from readOne's source, run as written ----------------------------------------
const PAGE = (readFileSync(new URL('../../Scripts/page_files.sh', import.meta.url), 'utf8').match(/^PAGE="([^"]+)"/m) || [])[1];
const page = readFileSync(new URL('../../Lumina/Sets/Web/' + PAGE, import.meta.url), 'utf8');
const lineAt = page.split('\n').findIndex(l => l.includes('async readOne(') ), remapLine = lineAt < 0 ? null
  : page.split('\n').slice(lineAt, lineAt + 12).map(l => l.trim()).find(l => l.startsWith('const ph=LuminaCore.phoneOf(m);'));
eq('page: readOne has the phone remap line', !!remapLine, true);
const pageRemap = remapLine ? new Function('LuminaCore', 'm', remapLine) : null;
const remap = m => { const r = { ...m }; if (pageRemap) pageRemap(LC, r); return r; };

// ---- 1. TEST-PLAN's seven cases as direct calls ------------------------------------------------------------
const PLAN = [
  ['Apple/iPhone → phone', { make: 'Apple', model: 'iPhone 15 Pro' }, true],
  ['Google/Pixel → phone', { make: 'Google', model: 'Pixel 8 Pro' }, true],
  ['samsung/SM-S918B → phone', { make: 'samsung', model: 'SM-S918B' }, true],
  ['samsung/NX500 → camera', { make: 'samsung', model: 'NX500' }, false],
  ['SONY/XQ-DQ54 → phone', { make: 'SONY', model: 'XQ-DQ54' }, true],
  ['SONY/ILCE-7M4 → camera', { make: 'SONY', model: 'ILCE-7M4' }, false],
  ['empty make → camera', { make: '', model: '' }, false],
];
for (const [n, rec, phone] of PLAN) eq(`direct · ${n}`, isPhone(rec), phone);
// "empty make" read the other ways a record can carry it.
eq('direct · empty make (null make and model) → camera', isPhone({ make: null, model: null }), false);
eq('direct · empty make (no fields) → camera', isPhone({}), false);
eq('direct · empty make with a camera model (ILCE-7M4) → camera', isPhone({ make: '', model: 'ILCE-7M4' }), false);
eq('direct · empty make with a camera model (NX500) → camera', isPhone({ make: '', model: 'NX500' }), false);
eq('direct · whitespace make → camera', isPhone({ make: '   ', model: '' }), false);
note(`empty make with model "iPhone 15 Pro" → ${isPhone({ make: '', model: 'iPhone 15 Pro' }) ? 'phone' : 'camera'} (TEST-PLAN does not say; the model regex decides)`);
// The names phoneOf gives the phones (the remap shows them as the model).
eq('direct · short names', PLAN.filter(p => p[2]).map(p => LC.phoneOf(p[1]).short), ['iPhone 15 Pro', 'Pixel 8 Pro', 'Samsung SM-S918B', 'Sony XQ-DQ54']);

// ---- 2. the same cases through parseHead on synthetic files -----------------------------------------------
const read = bytes => LC.parseHead(bytes.slice(0, Math.min(PAGE_HEAD, bytes.length)), bytes.length);
const c4 = Object.fromEntries(fixtures().map(f => [f.id, f])), fam = families(), byId = Object.fromEntries(fam.map(f => [f.id, f]));
const VIA = [
  ['Apple/iPhone → phone', c4.iphone, true],
  ['Google/Pixel → phone', c4.pixel, true],
  ['samsung/SM-S918B → phone', byId['samsung-expert-raw'], true],
  ['samsung/NX500 → camera', byId['samsung-nx'], false],
  ['SONY/XQ-DQ54 → phone', byId.xperia, true],
  ['SONY/ILCE-7M4 → camera (ARW)', c4['sony-arw'], false],
  ['SONY/ILCE-7M4 → camera (DNG)', c4['sony-dng'], false],
  ['empty make → camera', byId['no-make'], false],
  ['LEICA CAMERA AG/LEICA Q2 → camera', byId['leica-q2'], false],
  ['DJI/FC3582 → camera', byId.dji, false],
];
for (const [n, f, phone] of VIA) {
  const m = read(f.bytes);
  eq(`parseHead · ${f.id} · ${n}`, !!m && isPhone(m), phone);
}

// ---- 3. each family fixture read in full: fields, preview, and the page's remap -------------------------
for (const f of fam) {
  const x = f.expect, t = s => `${f.id} · ${s}`, m = read(f.bytes);
  eq(t('parses'), !!m, true);
  if (!m) continue;
  eq(t('make, model, dng, orientation, date, fl35'), { make: m.make, model: m.model, dng: m.dng, orient: m.orient, date: m.date, fl35: m.fl35 },
    { make: x.make, model: x.model, dng: x.dng, orient: x.orient, date: x.date, fl35: x.fl35 });
  eq(t('preview [offset, length]'), m.preview, x.preview);
  if (m.preview) {
    const [po, pl] = m.preview, pb = f.bytes.slice(po, po + pl);
    eq(t('preview is the drawn JPEG'), po + pl <= f.bytes.length && Buffer.compare(Buffer.from(pb), Buffer.from(f.preview)) === 0, true);
  }
  const ph = LC.phoneOf(m), r = remap(m);
  if (x.phone) {
    eq(t('phoneOf short name and zoom'), ph && { short: ph.short, zoom: ph.zoom }, { short: x.short, zoom: x.zoom });
    eq(t('page remap: model, lens, fl = fl35, flReal'), { model: r.model, lens: r.lens, fl: r.fl, flReal: r.flReal }, { model: x.short, lens: x.lens, fl: x.fl35, flReal: x.fl });
  } else {
    eq(t('phoneOf: not a phone'), ph, null);
    eq(t('page remap leaves a camera alone'), { model: r.model, lens: r.lens, fl: r.fl, flReal: r.flReal }, { model: x.model, lens: x.lens, fl: x.fl, flReal: undefined });
  }
}
const total = fam.reduce((s, f) => s + f.bytes.length, 0);
eq(`family fixtures total ${total} bytes, under 2 MB`, total < 2 * 1024 * 1024, true);
console.log(`${good} ok, ${bad} FAIL`);
process.exit(bad ? 1 : 0);
