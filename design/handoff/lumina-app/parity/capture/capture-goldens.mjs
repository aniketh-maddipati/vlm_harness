// Renders the golden reference screenshots from the HTML prototypes in a real browser.
// Usage:  cd design_handoff_lumina_parity/capture && npm i && node capture-goldens.mjs
// Output: ../goldens/<size>/<state>.png and ../goldens/manifest.json
import { chromium } from 'playwright';
import http from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';

const PROTO = resolve(process.env.PROTO || '../../design_handoff_lumina_app/prototypes');
const OUT = resolve('../goldens');
const SIZES = [
  { id: '1100x760', w: 1100, h: 760, dpr: 2 },
  { id: '1440x900', w: 1440, h: 900, dpr: 2 },
  { id: '2560x1440', w: 2560, h: 1440, dpr: 1 },
  { id: '480x800', w: 480, h: 800, dpr: 2 },
];
// compare: "pixel" = diff pixels (tolerance in manifest); "layout" = LAYOUT_SIZING overrides the prototype here,
// so compare structure/positions/sizes per the rules, not pixels.
const layoutOnly = (size, state) => size.id === '2560x1440' || state.startsWith('cull-');

// ---------- static server (the prototypes fetch sibling files, so file:// won't do)
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png' };
const server = http.createServer(async (req, res) => {
  try { const p = join(PROTO, decodeURIComponent(new URL(req.url, 'http://x').pathname));
    const body = await readFile(p);   // read first: a missing file must answer 404, not throw after the 200 header
    res.writeHead(200, { 'content-type': MIME[extname(p)] || 'application/octet-stream' }); res.end(body); }
  catch { res.writeHead(404); res.end(); }
}).listen(0);
const BASE = `http://127.0.0.1:${server.address().port}/`;
const WF = BASE + 'Lumina%20Workflow.dc.html';

// ---------- helpers run in the page
const settle = async (page, ms = 400) => {
  await page.waitForTimeout(ms);
  await page.evaluate(async () => {
    const imgs = [...document.images].filter(i => { const r = i.getBoundingClientRect(); return r.width && r.height && r.bottom > 0 && r.top < innerHeight; });
    imgs.forEach(i => { i.loading = 'eager'; });
    await Promise.race([Promise.all(imgs.map(i => i.complete ? 0 : new Promise(r => { i.onload = i.onerror = r; }))), new Promise(r => setTimeout(r, 8000))]);
  });
  await page.waitForTimeout(250); // let 120–200ms fades finish
};
const key = (page, k) => page.keyboard.press(k);
const step = async (page, n) => { await key(page, `Meta+${n}`); await settle(page, n === 3 ? 1400 : 500); };
const fresh = async (page, { intro = false } = {}) => {
  await page.goto(WF); await page.evaluate(i => { Object.keys(localStorage).filter(k => k.startsWith('lumina.')).forEach(k => localStorage.removeItem(k)); if (!i) localStorage.setItem('lumina.edit.intro.v1', '1'); }, intro);
  await page.goto(WF); await page.waitForSelector('[role="tablist"]'); await settle(page);
};
const copied = page => page.evaluate(() => (JSON.parse(localStorage.getItem('lumina.flow.v1') || '{}').copied) || 0);
const startCull = async (page, all = true) => { await key(page, 'Enter'); if (all) await page.waitForFunction(() => (JSON.parse(localStorage.getItem('lumina.flow.v1') || '{}').copied || 0) >= 117, null, { timeout: 30000 }); await settle(page); };
const keepSome = async page => { for (const k of ['r', 'r', 'x', 'r', 'x', 'r', 'r', 'r', 'x', 'r']) { await key(page, k); await page.waitForTimeout(40); } await settle(page); };
const importFiles = (page, spec) => page.evaluate(async spec => {
  const mk = async ([name, w, h, seed, junk]) => { if (junk) return new File([new Uint8Array(junk)], name);
    const c = document.createElement('canvas'); c.width = w; c.height = h; const x = c.getContext('2d'); x.fillStyle = `hsl(${seed * 47 % 360},55%,50%)`; x.fillRect(0, 0, w, h);
    return new File([await new Promise(r => c.toBlob(r, 'image/jpeg', 0.85))], name, { type: 'image/jpeg', lastModified: Date.UTC(2026, 8, 30, 9, seed, 0) }); };
  await window.luminaImport(await Promise.all(spec.map(mk)), 'Card dump');
}, spec);

// ---------- the states (each starts from a fresh app)
const STATES = {
  'open-empty': async p => { await fresh(p); },
  'open-copying': async p => { await fresh(p); await key(p, 'Enter'); await p.waitForFunction(() => { const c = JSON.parse(localStorage.getItem('lumina.flow.v1') || '{}').copied || 0; return c > 20; }); await key(p, 'Meta+1'); await settle(p, 300); },
  'open-recent': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 1); },
  'open-startover-armed': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 1); await p.getByText(/^Start over/).click(); await settle(p, 200); },
  'open-import-message': async p => { await fresh(p); await importFiles(p, [['a.jpg', 640, 420, 1], ['b.jpg', 640, 420, 2], ['clip.mp4', 0, 0, 0, [1, 2, 3, 4]], ['notes.txt', 0, 0, 0, [104, 105]]]); await step(p, 1); },
  'open-import-nothing': async p => { await fresh(p); await importFiles(p, [['notes.txt', 0, 0, 0, [104, 105]], ['movie.mov', 0, 0, 0, [1, 2, 3]]]); await settle(p); },
  'drop-overlay': async p => { await fresh(p); await startCull(p); await p.evaluate(() => { const dt = new DataTransfer(); dt.items.add(new File(['x'], 'a.jpg', { type: 'image/jpeg' })); window.dispatchEvent(new DragEvent('dragenter', { dataTransfer: dt, bubbles: true, cancelable: true })); }); await settle(p, 300); },
  'cull-empty': async p => { await fresh(p); await step(p, 2); },
  'cull-copying': async p => { await fresh(p); await key(p, 'Enter'); await p.waitForFunction(() => (JSON.parse(localStorage.getItem('lumina.flow.v1') || '{}').copied || 0) > 30); await settle(p, 200); },
  'cull-mid': async p => { await fresh(p); await startCull(p); await keepSome(p); },
  'cull-all-decided': async p => { await fresh(p); await startCull(p); for (let i = 0; i < 117; i++) await key(p, i % 3 ? 'r' : 'x'); await settle(p); },
  'edit-empty': async p => { await fresh(p); await startCull(p); await step(p, 3); },
  'edit-intro': async p => { await fresh(p, { intro: true }); await startCull(p); await keepSome(p); await step(p, 3); },
  'edit-loaded': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); },
  'edit-edited': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); for (const k of ['.', '.', '.', ']', '.', '.']) await key(p, k); await settle(p); },
  'edit-help': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await key(p, 'Shift+Slash'); await settle(p, 300); },
  'edit-variations': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await p.keyboard.down('v'); await settle(p, 900); },
  'edit-crop': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await key(p, 'c'); await settle(p, 400); },
  'edit-zoom-1to1': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await key(p, 'z'); await settle(p, 900); },
  'edit-focus': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await key(p, 'h'); await settle(p, 400); },
  'edit-colour': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await p.getByText(/^Colour$/).first().click(); await settle(p, 300); },
  'edit-effects': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await p.getByText(/^Effects$/).first().click(); await settle(p, 300); },
  'edit-loadfail': async p => { await fresh(p); await startCull(p); await keepSome(p); await p.route(/picsum\.photos\/.*\/1800|picsum\.photos\/seed\/lumina\d+\/\d{4}/, r => r.abort()); await step(p, 3); await settle(p, 1500); },
  'edit-storage-warning': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await p.evaluate(() => { const real = Storage.prototype.setItem; Storage.prototype.setItem = function (k) { if (String(k).startsWith('lumina.')) throw new DOMException('full', 'QuotaExceededError'); return real.apply(this, arguments); }; }); await key(p, '.'); await key(p, '.'); await settle(p, 800); },
  'save-ready': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 3); await key(p, '.'); await step(p, 4); },
  'save-saved': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 4); await p.getByText(/^Save \d+ photos/).click(); await settle(p, 400); },
  'save-changed': async p => { await fresh(p); await startCull(p); await keepSome(p); await step(p, 4); await p.getByText(/^Save \d+ photos/).click(); await settle(p, 300); await p.getByText(/^JPEG$/).click(); await settle(p, 300); },
  'save-nothing': async p => { await fresh(p); await startCull(p); for (let i = 0; i < 117; i++) await key(p, 'x'); await step(p, 4); await settle(p, 1600); },
};

const browser = await chromium.launch();
const manifest = { generatedAt: new Date().toISOString(), prototype: 'design_handoff_lumina_app/prototypes', tolerance: { pixel: 0.02, perPixelDelta: 16, note: 'fail if >2% of pixels differ by more than 16/255 in any channel (font rasterisation differs slightly)' }, shots: [] };
for (const size of SIZES) {
  await mkdir(join(OUT, size.id), { recursive: true });
  for (const [state, run] of Object.entries(STATES)) {
    const ctx = await browser.newContext({ viewport: { width: size.w, height: size.h }, deviceScaleFactor: size.dpr, reducedMotion: 'no-preference' });
    const page = await ctx.newPage();
    try {
      await run(page);
      const dbg = await page.evaluate(() => { const f = JSON.parse(localStorage.getItem('lumina.flow.v1') || '{}'), e = JSON.parse(localStorage.getItem('lumina.flow.edit.v1') || '{}'), s = window.luminaState ? window.luminaState() : {};
        const keep = e.keep || {}; return { step: f.step, cur: s.cur || f.cur, copied: f.copied, kept: Object.values(keep).filter(v => v === true).length, out: Object.values(keep).filter(v => v === false).length, saved: !!f.saved, fmt: f.fmt, look: s.look || null }; });
      const file = `${size.id}/${state}.png`;
      await page.screenshot({ path: join(OUT, file) });
      manifest.shots.push({ file, state, size: size.id, viewport: [size.w, size.h], dpr: size.dpr, compare: layoutOnly(size, state) ? 'layout' : 'pixel', debugState: dbg });
      console.log('✓', file);
    } catch (e) { console.log('✗', size.id, state, e.message); manifest.shots.push({ state, size: size.id, error: e.message }); }
    await ctx.close();
  }
}
await writeFile(join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 2));
await browser.close(); server.close();
console.log(`\n${manifest.shots.filter(s => !s.error).length} goldens → ${OUT}`);
