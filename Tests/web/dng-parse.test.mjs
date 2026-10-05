// LuminaCore.parseHead + phoneOf on the synthetic DNG fixtures (dng-fixtures.mjs), read the way the v7 page's
// readOne reads a file: the first 256 KB as the head, the file size alongside, the preview sliced from the file.
// Loads the app's copy of lumina-core-v4.js the way design/handoff/lumina-cull/lumina-core-v4.test.mjs does.
//
//   node Tests/web/dng-parse.test.mjs      (ok / FAIL per check, exit 1 on any FAIL; "note" lines are observations)
import { createRequire } from 'node:module';
import { fixtures, PAGE_HEAD } from './dng-fixtures.mjs';

const LC = createRequire(import.meta.url)('../../Lumina/Sets/Web/lumina-core-v4.js');
let bad = 0;
const eq = (n, a, b) => { const ok = JSON.stringify(a) === JSON.stringify(b); console.log(ok ? 'ok  ' : 'FAIL', n); if (!ok) { bad++; console.log('  got ', JSON.stringify(a), '\n  want', JSON.stringify(b)); } };
const truthy = (n, v) => eq(n, !!v, true);
const note = s => console.log('note', s);

const read = bytes => { const head = bytes.slice(0, Math.min(PAGE_HEAD, bytes.length)); return LC.parseHead(head, bytes.length); };
// The page's phone remap after parseHead (v7 readOne): model → short name, lens → "<zoom> camera", fl → fl35.
const remap = m => { const r = { ...m }, ph = LC.phoneOf(m); if (ph) { r.flReal = r.fl; if (r.fl35) r.fl = r.fl35; r.model = ph.short; r.lens = ph.zoom ? ph.zoom + ' camera' : r.lens; } return r; };

const want = {
  iphone: { short: 'iPhone 15 Pro', zoom: '1×', lens: '1× camera', fl: 6.765 },
  pixel: { short: 'Pixel 8 Pro', zoom: '5×', lens: '5× camera', fl: 18 },
  'pixel-rgb-thumb': { short: 'Pixel 8 Pro', zoom: '1×', lens: '1× camera', fl: 6.9 },
  'iphone-far-preview': { short: 'iPhone 15 Pro', zoom: '3×', lens: '3× camera', fl: 9 },
};

const all = fixtures();
for (const f of all) {
  const x = f.expect, t = s => `${f.id} · ${s}`;
  if (x.truncated) {
    let m, threw = null; try { m = read(f.bytes); } catch (e) { threw = e; }
    eq(t('no exception on a head cut mid-IFD0'), threw && String(threw), null);
    eq(t('no preview, no make, not a phone'), m && { preview: m.preview, make: m.make, model: m.model, phone: LC.phoneOf(m) }, m ? { preview: null, make: null, model: null, phone: null } : null);
    note(`${f.id}: parseHead returned ${m === null ? 'null (page: "unreadable")' : 'a record, not null: the page keeps the file as a photo with no preview and no date'}`);
    let tiny = null; try { tiny = LC.parseHead(f.bytes.slice(0, 4), 4); tiny = 'returned ' + JSON.stringify(tiny && tiny.preview); } catch (e) { tiny = 'threw ' + e.constructor.name + ': ' + e.message; }
    note(`${f.id}: a 4-byte head "II*\\0" ${tiny}`);
    continue;
  }
  const m = read(f.bytes);
  truthy(t('parses'), m);
  if (!m) continue;
  eq(t('make'), m.make, x.make);
  eq(t('model'), m.model, x.model);
  eq(t('dng flag'), m.dng, x.dng);
  eq(t('orientation'), m.orient, x.orient);
  eq(t('date'), m.date, x.date);
  eq(t('fl35'), m.fl35, x.fl35);
  eq(t('preview [offset, length]'), m.preview, x.preview);
  if (m.preview) {
    const [po, pl] = m.preview;
    truthy(t('preview inside the file'), po > 0 && po + pl <= f.bytes.length);
    const pb = f.bytes.slice(po, po + pl);
    eq(t('preview is the drawn JPEG (SOI … EOI, same bytes)'), [pb[0], pb[1], pb[pl - 2], pb[pl - 1], Buffer.compare(Buffer.from(pb), Buffer.from(f.preview))], [0xFF, 0xD8, 0xFF, 0xD9, 0]);
    if (f.id === 'iphone-far-preview') truthy(t('preview starts past the 256 KB head'), po >= PAGE_HEAD);
  }
  const ph = LC.phoneOf(m), r = remap(m);
  eq(t(x.phone ? 'phoneOf names the phone' : 'phoneOf: not a phone'), ph && { short: ph.short, zoom: ph.zoom }, x.phone ? { short: want[f.id].short, zoom: want[f.id].zoom } : null);
  if (x.phone) {
    eq(t('page remap: model, lens text, fl = fl35, flReal = fl'), { model: r.model, lens: r.lens, fl: r.fl, flReal: r.flReal }, { model: want[f.id].short, lens: want[f.id].lens, fl: x.fl35, flReal: want[f.id].fl });
  } else {
    eq(t('page leaves a camera alone'), { model: r.model, lens: r.lens, fl: r.fl }, { model: m.model, lens: x.lens, fl: m.fl });
  }
}
const total = all.reduce((s, f) => s + f.bytes.length, 0);
truthy(`fixtures total ${total} bytes, under 2 MB`, total < 2 * 1024 * 1024);
process.exit(bad ? 1 : 0);
