// What the page knows about a photo before it groups anything: the header (LuminaCore.parseHead, run
// here in Node on the same 256 KB) and the measures of the embedded preview (LuminaCore.measure, which
// needs a canvas, so it runs in headless Chromium on the page's exact 360 px bitmap). This repeats the
// page's readOne; READONE is the hash of that method, so a design sync that changes it is noticed.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import { LuminaCore, CORE_FILE, PAGE_FILE, sha, coreHash } from './core.mjs';

export const READONE = '90ef314774b89942';
export function readOneHash() {
  const html = fs.readFileSync(PAGE_FILE, 'utf8'), a = html.indexOf('async readOne('), b = html.indexOf('async onDir(', a);
  return a < 0 || b < 0 ? null : sha(html.slice(a, b));
}

// The files the page reads (onDir / addSource). The one matcher: culleval.mjs walks with it.
export const RAW_FILE = /\.(arw|dng)$/i;

// What readOne builds from parseHead's m before it looks at pixels: a phone (LuminaCore.phoneOf, from
// EXIF Make/Model) is shown with its 35 mm focal length, its short name and its zoom label as the lens.
export function recordOf(parsed, file, size) {
  const m = { ...parsed }, ph = LuminaCore.phoneOf(m);
  if (ph) { m.flReal = m.fl; if (m.fl35) m.fl = m.fl35; m.model = ph.short; m.lens = ph.zoom ? ph.zoom + ' camera' : m.lens; }
  return { lowpv: false, wbK: m.wbK ?? null, wbTint: m.wbTint ?? null, name: path.basename(file), path: file, bytes: size, date: m.date || '', exp: m.exp, fl: m.fl, ev: m.ev, iso: m.iso, model: m.model || null, make: m.make || null, fnum: m.fnum || null, w: m.w || null, h: m.h || null, lens: m.lens || null, serial: m.serial || null, program: m.program ?? null, wb: m.wb ?? null, flash: m.flash ?? null, seqImage: m.seqImage ?? null, seqLength: m.seqLength ?? null, releaseMode2: m.releaseMode2 ?? null };
}

const HEAD = 262144;
export const keyOf = f => { const s = fs.statSync(f); return f + '|' + s.size + '|' + Math.round(s.mtimeMs); };

// The page's header read. Returns {m, preview: Buffer | null}.
function head(file) {
  const size = fs.statSync(file).size, fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(Math.min(HEAD, size)); fs.readSync(fd, buf, 0, buf.length, 0);
    const m = LuminaCore.parseHead(new Uint8Array(buf.buffer, buf.byteOffset, buf.length), size);
    if (!m) return null;
    // The first candidate that fits the file and starts FF D8, as the page tries them. A raw-strip
    // preview (pvParts / pvRGB, assemblePreview) is not rebuilt here: Sony ARWs always carry a JPEG.
    let preview = null;
    for (const [po, pl] of (m.previews && m.previews.length ? m.previews : m.preview ? [m.preview] : [])) {
      if (po + pl > size) continue;
      const pb = Buffer.alloc(pl); fs.readSync(fd, pb, 0, pl, po);
      if (pb[0] !== 0xFF || pb[1] !== 0xD8) continue;
      preview = pb; break;
    }
    return { m, size, preview };
  } finally { fs.closeSync(fd); }
}

function playwright() {
  const require = createRequire(import.meta.url), tries = ['playwright'];
  if (process.env.LUMINA_PLAYWRIGHT) tries.unshift(process.env.LUMINA_PLAYWRIGHT);
  try { tries.push(path.join(execSync('npm root -g', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(), 'playwright')); } catch (_) {}
  const npx = path.join(os.homedir(), '.npm/_npx');
  try { for (const d of fs.readdirSync(npx)) tries.push(path.join(npx, d, 'node_modules/playwright')); } catch (_) {}
  for (const t of tries) try { return require(t); } catch (_) {}
  throw new Error('playwright not found: npm i -g playwright && npx playwright install chromium (or set LUMINA_PLAYWRIGHT to its folder)');
}

// In the page: the preview turned upright, resized to 360 px wide and measured, as readOne does.
const IN_PAGE = async ({ url, ori }) => {
  try {
    let blob = await (await fetch(url)).blob();
    if (ori === 3 || ori === 6 || ori === 8) { const b0 = await createImageBitmap(blob, { imageOrientation: 'none' }), sw = ori !== 3, c = document.createElement('canvas'); c.width = sw ? b0.height : b0.width; c.height = sw ? b0.width : b0.height; const x = c.getContext('2d'); x.translate(c.width / 2, c.height / 2); x.rotate(ori === 6 ? Math.PI / 2 : ori === 8 ? -Math.PI / 2 : Math.PI); x.drawImage(b0, -b0.width / 2, -b0.height / 2); b0.close(); blob = await new Promise(res => c.toBlob(res, 'image/jpeg', 0.92)); }
    const sm = await createImageBitmap(blob, { resizeWidth: 360, resizeQuality: 'medium' }), portrait = sm.height > sm.width, me = LuminaCore.measure(sm); sm.close();
    return { portrait, dhash: me.dhash, lum: me.lum, focus: me.focus, clip: me.clip };
  } catch (_) { return null; }
};

// files → Map file → the record readOne would hand buildShoot (no pixels, no object URLs).
// Cached in cacheFile by path, size and mtime; the cache is dropped when the core or readOne changes.
export async function measureAll(files, cacheFile, { jobs = 4, log = () => {} } = {}) {
  const stamp = coreHash() + ':' + readOneHash();
  let cache = { stamp, items: {} };
  try { const c = JSON.parse(fs.readFileSync(cacheFile, 'utf8')); if (c.stamp === stamp) cache = c; } catch (_) {}
  const keys = new Map(files.map(f => [f, keyOf(f)])), todo = files.filter(f => !cache.items[keys.get(f)]);
  if (todo.length) {
    log('measuring ' + todo.length + ' photos in headless Chromium (cached afterwards)');
    const browser = await playwright().chromium.launch(), page = await browser.newPage(), origin = 'http://culleval.test', bytes = new Map();
    await page.route(origin + '/**', route => {
      const u = new URL(route.request().url());
      if (u.pathname === '/') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><script src="/core.js"></script>' });
      if (u.pathname === '/core.js') return route.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(CORE_FILE) });
      const b = bytes.get(u.pathname); bytes.delete(u.pathname);
      return b ? route.fulfill({ contentType: 'image/jpeg', body: b }) : route.fulfill({ status: 404, body: '' });
    });
    await page.goto(origin + '/');
    let next = 0, done = 0;
    const one = async () => {
      for (;;) {
        const i = next++; if (i >= todo.length) return;
        const f = todo[i]; let rec;
        try {
          const h = head(f); if (!h) throw new Error('unreadable');
          const m = h.m, base = recordOf(m, f, h.size);
          let me = null;
          if (h.preview) { bytes.set('/p/' + i, h.preview); me = await page.evaluate(IN_PAGE, { url: '/p/' + i, ori: m.orient || 1 }); }
          rec = me ? { ...base, ...me } : { ...base, nopv: true, portrait: false, lum: null, focus: 0, clip: 0, dhash: null };
        } catch (e) { rec = { err: String(e.message || e) }; }
        cache.items[keys.get(f)] = rec;
        if (++done % 250 === 0) log('  ' + done + ' / ' + todo.length);
      }
    };
    await Promise.all(Array.from({ length: jobs }, one));
    await browser.close();
    fs.mkdirSync(path.dirname(cacheFile), { recursive: true });
    fs.writeFileSync(cacheFile, JSON.stringify(cache));
  }
  return new Map(files.map(f => [f, { ...cache.items[keys.get(f)], path: f, src: '', lg: '' }]));
}
