// Shared by the Linux checks in Tests/web: the page in headless Chromium, served as the app's
// scheme handler serves it, with plumbing.js and a Node stand-in for SetsBridge.
import { createRequire } from 'module';
import { execSync } from 'child_process';
import crypto from 'crypto';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
export let pw;
try { pw = require('playwright'); } catch (_) { pw = require(path.join(execSync('npm root -g').toString().trim(), 'playwright')); }

// Every harness run ends: at its limit (LUMINA_WEB_LIMIT seconds changes it) it fails loudly and
// exits 124. Playwright closes the browsers it launched when the process exits, and on a signal.
export function deadline(name, seconds) {
  const s = +(process.env.LUMINA_WEB_LIMIT || seconds);
  setTimeout(() => { console.error(`FAIL  ${name} reached its limit of ${s} s and was stopped`); process.exit(124); }, s * 1000).unref();
}

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const WEB = path.join(ROOT, 'Lumina/Sets/Web');
export const PAGE = 'Lumina Sets v7.dc.html';
export const ORIGIN = 'http://lumina.test';
export const VENDOR = {
  'https://unpkg.com/react@18.3.1/umd/react.production.min.js': ORIGIN + '/vendor/react.production.min.js',
  'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js': ORIGIN + '/vendor/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone@7.29.0/babel.min.js': ORIGIN + '/vendor/babel.min.js',
};

// ——— synthetic ARWs
export function tiff({ date, exp = [1, 250], fl = [50, 1], iso = 400, model = 'ILCE-7M4', orient = 1, jpeg, pad = 300_000 }) {
  // IFD0: Make/Model, Orientation, JPEGInterchangeFormat(+Length), ExifIFD. Exif IFD: DateTimeOriginal, ExposureTime, FocalLength, ISO.
  const buf = Buffer.alloc(Math.max(pad, 4096 + jpeg.length + 16));
  buf.write('II', 0); buf.writeUInt16LE(42, 2); buf.writeUInt32LE(8, 4);
  const ifd0 = 8, n0 = 5, exif = ifd0 + 2 + n0 * 12 + 4, n1 = 4, data = exif + 2 + n1 * 12 + 4;
  let dp = data;
  const put = (s) => { const o = dp; buf.write(s + '\0', o, 'latin1'); dp += s.length + 1; if (dp % 2) dp++; return o; };
  const rat = ([a, b]) => { const o = dp; buf.writeUInt32LE(a, o); buf.writeUInt32LE(b, o + 4); dp += 8; return o; };
  const ent = (base, i, tag, type, cnt, val) => { const e = base + 2 + i * 12; buf.writeUInt16LE(tag, e); buf.writeUInt16LE(type, e + 2); buf.writeUInt32LE(cnt, e + 4); if (type === 3 && cnt === 1) buf.writeUInt16LE(val, e + 8); else buf.writeUInt32LE(val, e + 8); };
  const mo = put(model), dto = put(date), eo = rat(exp), fo = rat(fl);
  const jo = 4096;
  buf.writeUInt16LE(n0, ifd0);
  ent(ifd0, 0, 0x0110, 2, model.length + 1, mo);
  ent(ifd0, 1, 0x0112, 3, 1, orient);
  ent(ifd0, 2, 0x0201, 4, 1, jo);
  ent(ifd0, 3, 0x0202, 4, 1, jpeg.length);
  ent(ifd0, 4, 0x8769, 4, 1, exif);
  buf.writeUInt32LE(0, ifd0 + 2 + n0 * 12);
  buf.writeUInt16LE(n1, exif);
  ent(exif, 0, 0x829A, 5, 1, eo);
  ent(exif, 1, 0x8827, 3, 1, iso);
  ent(exif, 2, 0x9003, 2, date.length + 1, dto);
  ent(exif, 3, 0x920A, 5, 1, fo);
  buf.writeUInt32LE(0, exif + 2 + n1 * 12);
  jpeg.copy(buf, jo);
  return buf;
}

export async function makeJpegs(browser, n) {
  const p = await browser.newPage();
  const out = await p.evaluate(async n => {
    const r = [];
    for (let i = 0; i < n; i++) {
      const c = document.createElement('canvas'); c.width = 640; c.height = 427; const x = c.getContext('2d');
      x.fillStyle = `hsl(${(i * 37) % 360},50%,${30 + (i % 5) * 8}%)`; x.fillRect(0, 0, 640, 427);
      for (let k = 0; k < 60; k++) { x.fillStyle = `hsl(${(i * 13 + k * 29) % 360},70%,${(k * 7) % 100}%)`; x.fillRect((k * 53 + i * 11) % 600, (k * 31) % 400, 20 + (k % 5) * 6, 20 + (k % 3) * 9); }
      r.push(c.toDataURL('image/jpeg', 0.85).split(',')[1]);
    }
    return r;
  }, n);
  await p.close();
  return out.map(b => Buffer.from(b, 'base64'));
}

export function makeShoot(dir, jpegs, { others = [], sidecars = {} } = {}) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(path.join(dir, 'sub'), { recursive: true });
  // Two rows 20 minutes apart; a 5-frame burst in the first.
  const times = ['10:00:00', '10:00:01', '10:00:01', '10:00:02', '10:00:02', '10:03:00', '10:07:30', '10:30:00', '10:31:00', '10:33:10', '10:35:00', '10:36:40'];
  jpegs.slice(0, times.length).forEach((j, i) => {
    const name = (i >= 10 ? 'sub/' : '') + 'DSC0' + (1001 + i) + '.ARW';
    fs.writeFileSync(path.join(dir, name), tiff({ date: '2026:09:01 ' + times[i], jpeg: j, orient: i === 6 ? 6 : 1 }));
  });
  for (const o of others) fs.writeFileSync(path.join(dir, o), 'x');
  for (const [n, t] of Object.entries(sidecars)) fs.writeFileSync(path.join(dir, n), t);
}

// A camera-sized preview (1616×1080, as an α7's embedded JPEG) full of fine detail (hairlines, text,
// foliage-like noise), so a soft or over-compressed thumbnail is measurable.
export async function makeBigJpegs(browser, n) {
  const p = await browser.newPage();
  const out = await p.evaluate(async n => {
    const r = [];
    for (let i = 0; i < n; i++) {
      const W = 1616, H = 1080, c = document.createElement('canvas'); c.width = W; c.height = H; const x = c.getContext('2d');
      const g = x.createLinearGradient(0, 0, 0, H); g.addColorStop(0, `hsl(${(i * 47) % 360},45%,72%)`); g.addColorStop(1, `hsl(${(i * 47 + 120) % 360},35%,28%)`);
      x.fillStyle = g; x.fillRect(0, 0, W, H);
      let s = i * 9301 + 49297; const rnd = () => (s = (s * 9301 + 49297) % 233280) / 233280;
      for (let k = 0; k < 900; k++) { x.strokeStyle = `hsla(${(rnd() * 360) | 0},40%,${(rnd() * 60 + 10) | 0}%,0.9)`; x.lineWidth = rnd() * 2 + 0.5; const px = rnd() * W, py = H * 0.45 + rnd() * H * 0.55; x.beginPath(); x.moveTo(px, py); x.lineTo(px + (rnd() - 0.5) * 18, py - rnd() * 140); x.stroke(); }
      x.fillStyle = '#fff'; x.font = '22px sans-serif'; for (let k = 0; k < 14; k++) x.fillText('DSC0' + (1000 + i) + ' · 1/250 · f/8 · ISO 400 · 35 mm', 40, 60 + k * 30);
      for (let k = 0; k < 60; k++) { x.fillStyle = k % 2 ? '#000' : '#fff'; x.fillRect(W - 300 + k * 4, 40, 2, 200); }
      r.push(c.toDataURL('image/jpeg', 0.9).split(',')[1]);
    }
    return r;
  }, n);
  await p.close();
  return out.map(b => Buffer.from(b, 'base64'));
}

// n ARWs on one day: bursts of 5 one second apart, 2 min between bursts, a new row every 40 frames.
export function makeBigShoot(dir, jpegs, n) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  let t = 9 * 3600;
  for (let i = 0; i < n; i++) {
    t += i % 40 === 0 && i ? 20 * 60 : i % 5 === 0 ? 120 : 1;
    const hh = String(Math.floor(t / 3600)).padStart(2, '0'), mm = String(Math.floor(t / 60) % 60).padStart(2, '0'), ss = String(t % 60).padStart(2, '0');
    fs.writeFileSync(path.join(dir, 'DSC' + String(10001 + i).padStart(5, '0') + '.ARW'), tiff({ date: `2026:09:01 ${hh}:${mm}:${ss}`, jpeg: jpegs[i % jpegs.length], orient: i % 23 === 7 ? 6 : 1, pad: 4096 + jpegs[i % jpegs.length].length + 16 }));
  }
}

// ——— the Swift bridge, in Node (what SetsBridge answers)
export function list(root) {
  const name = path.basename(root), out = { name, files: [], xmp: [], others: [], workers: 4, onCard: false, skippedXmp: [], unreadableXmp: [] };
  const walk = d => { for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (e.name.startsWith('.')) continue;
    const full = path.join(d, e.name), rel = name + '/' + path.relative(root, full).split(path.sep).join('/');
    if (e.isDirectory()) { walk(full); continue; }
    const ext = path.extname(e.name).toLowerCase();
    if (ext === '.arw') out.files.push({ rel, size: fs.statSync(full).size });
    // SetsIngest.list: a sidecar that is not UTF-8 text is named in unreadableXmp, without a text.
    else if (ext === '.xmp') { const text = utf8(fs.readFileSync(full)); if (text == null) out.unreadableXmp.push(rel); else out.xmp.push({ rel, text }); }
    else if (!e.name.endsWith('.lumina-bak')) out.others.push(rel);
  } };
  walk(root);
  return out;
}

// String(data:encoding: .utf8): the text, or null when the bytes are not UTF-8.
const utf8 = buf => { try { return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(buf); } catch (_) { return null; } };

// SetsFileOps.sidecarBase: the SHA-256 of the file's bytes, or "none" when there is no file.
const sidecarBase = file => fs.existsSync(file) ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') : 'none';

export class Bridge {
  constructor(parent) {
    this.parent = parent; this.roots = {}; this.pending = null; this.calls = []; this.sessions = {}; this.index = []; this.prefs = null; this.revealed = []; this.gone = new Set(); this.denied = null;
    // The Edit canvas (no Metal here: the image path). What SetsBridge answers, and the renders lumina://render served.
    this.canvas = { path: 'image', entered: [], layouts: [], looks: [], drags: [], loupes: [], statsCalls: 0, resets: 0, updates: 0 };
    this.header = { canvas: 'image', raw9: false, raw9Present: false, decoder: 8, newest: 8, offerUpdate: false, slowed: false, bodies: { 'ILCE-7M4': { supported: [7, 8], raw9: false, fastest: 8, developMs: { 7: 30, 8: 20 } } } };
    this.renders = []; this.renderDelayMs = 0; this.renderJpeg = null; this.renderSeq = {};
  }
  // lumina://render/<rel>?look=&px=&seq=&tier=: what SetsSchemeHandler + LookRenderer answer. 409 when a
  // newer seq for the same file was already asked for; else a JPEG (this.renderJpeg, any bytes will do).
  async render(rel, q) {
    const seq = +q.seq || 0, newest = this.renderSeq[rel] || 0;
    this.renderSeq[rel] = Math.max(newest, seq);
    this.renders.push({ rel, look: q.look, px: +q.px, seq, tier: q.tier || 'base', decoder: q.decoder != null ? +q.decoder : null, t: Date.now() });
    if (this.renderDelayMs) await new Promise(r => setTimeout(r, this.renderDelayMs));
    if (this.renderSeq[rel] > seq) return { status: 409, body: 'superseded by a newer request' };
    return { status: 200, body: this.renderJpeg || Buffer.from([0xff, 0xd8, 0xff, 0xd9]), contentType: 'image/jpeg' };
  }
  // What bridge.open(url) does natively: the page opens the pending folder. Playwright evaluates it
  // directly; the WebKit sandbox (webkit-server.mjs) lets the page pick it up.
  kick() { if (this.page) this.page.evaluate('__lumina.openFolder()'); else this.kicked = (this.kicked || 0) + 1; }
  resolve(rel) {
    const [n, ...rest] = rel.split('/'); const r = this.roots[n]; if (!r || !rest.length) return null;
    const p = path.resolve(r, rest.join('/')); return p.startsWith(r + path.sep) ? p : null;
  }
  async handle(msg) {
    const { op } = msg; this.calls.push(op);
    switch (op) {
      case 'ready': this.readyMsg = msg; return !(msg.missing && msg.missing.length);
      case 'recents': return this.index.map(s => ({ id: s.id, d: s.d, n: s.n, dec: s.dec || 0, kp: s.kp || 0, last: s.last || '', where: s.path }));
      case 'openFolder': {
        const url = this.pending; this.pending = null; if (!url) return null;
        if (this.denied === url) return { denied: path.basename(url) };
        this.roots[path.basename(url)] = url; this.current = url; return list(url);
      }
      case 'shootOpened': {
        const id = 'id-' + path.basename(this.current);
        this.index = [{ id, path: this.current, n: msg.n, d: (msg.date || '').slice(0, 10).replace(/:/g, '-') }].concat(this.index.filter(s => s.id !== id));
        this.bodies = msg.bodies || null;
        return { id, session: this.sessions[id] || null, header: this.header };
      }
      case 'shootHeader': return this.header;
      case 'decoderUpdate': this.canvas.updates++; this.header = Object.assign({}, this.header, { decoder: this.header.newest, offerUpdate: false }); return this.header;
      // `asShot` (set this.asShot = {kelvin, tint} to answer it): the photo's own white balance, for the page's temperature.
      case 'canvasEnter': this.canvas.entered.push(msg); return Object.assign({ decoderCanvas: 8, decoderRegion: 8 }, this.header, this.asShot ? { asShot: this.asShot, asShotRel: msg.rel } : {});
      case 'canvasLeave': this.canvas.entered.push({ leave: true }); return true;
      case 'canvasLayout': this.canvas.layouts.push(msg); return { path: this.canvas.path };
      case 'canvasLook': this.canvas.looks.push(msg); return this.canvas.looks.length;
      case 'canvasDrag': this.canvas.drags.push(msg.start); return true;
      case 'canvasLoupe': this.canvas.loupes.push(msg); return true;
      case 'canvasStats': this.canvas.statsCalls++; if (msg.reset) this.canvas.resets++; return { path: this.canvas.path, facts: this.header, latencyMs: [], schedule: {}, bases: {}, tiles: {} };
      case 'writeInto': {
        // The Edit step's JPEGs (label 'jpeg'): what SetsBridge.writeInto answers after SetsExportJob ran the look items.
        if (msg.label !== 'jpeg') return null;
        this.jpegItems = msg.files;
        return { n: msg.files.length, bak: 0, folder: '/tmp/export', decoder: 'RAW 8', decoders: msg.files.map(() => 'raw 8'), fallbacks: [], renderMs: msg.files.map(() => 120) };
      }
      case 'saveSession': { this.sessions[msg.id] = msg.json; const s = this.index.find(x => x.id === msg.id); if (s) Object.assign(s, msg.summary || {}); this.saves = (this.saves || 0) + 1; return true; }
      case 'prefetch': if (this.prefetches) this.prefetches.push(...(msg.items || [])); return (msg.items || []).length;
      // SetsNear: the distance between two photos' previews, null when either can't be measured
      // (card out, no preview range). Here: 0 for the same photo, else a fixed 0.25.
      case 'near': {
        (this.nears = this.nears || []).push({ a: msg.a, b: msg.b });
        const okP = q => q && q.p && +q.o > 0 && +q.l > 0 && this.resolve(q.p) && !this.gone.has(q.p.split('/')[0]);
        return okP(msg.a) && okP(msg.b) ? (msg.a.p === msg.b.p ? 0 : 0.25) : null;
      }
      case 'ingestStats': return { workers: 4, inFlight: 0, maxInFlight: 4, heads: 0, previews: 0, largestRead: 0, opensAfterGone: 0, failures: 0, gone: [...this.gone] };
      case 'setPrefs': this.prefs = msg.prefs; return true;
      case 'reveal': this.revealed.push(msg.path); return true;
      case 'cullCard': return false;
      case 'workingFiles': return 1234;
      case 'removeShoot': delete this.sessions[msg.id]; this.index = this.index.filter(s => s.id !== msg.id); return true;
      case 'reopen': { const s = this.index.find(x => x.id === msg.id); if (!s) return false; this.pending = s.path; this.kick(); return true; }
      case 'reopenCurrent': this.pending = this.current; this.kick(); return true;
      case 'openSettings': this.settingsOpened = msg.what; return true;
      case 'checkAccess': return this.denied == null;
      case 'reopenDenied': return true;
      case 'readSidecars': {
        // Mirrors SetsFileOps.readSidecar: each sidecar as it is on disk now, and the base a write must match.
        const root = this.roots[msg.root]; if (!root) return null;
        return (msg.files || []).map(name => {
          const dest = path.resolve(root, name);
          if (!dest.startsWith(root + path.sep) || !/\.xmp$/i.test(dest)) return { name };
          return { name, text: fs.existsSync(dest) ? utf8(fs.readFileSync(dest)) : null, base: sidecarBase(dest) };   // not UTF-8: no text, still a base
        });
      }
      case 'writeSidecars': {
        // Mirrors SetsFileOps.writeSidecar: into the shoot folder, .xmp only, .lumina-bak first, verify.
        const root = this.roots[msg.root]; if (!root) return null;
        let n = 0, bak = 0; const errors = [];
        for (const f of msg.files) {
          const dest = path.resolve(root, f.name);
          if (!dest.startsWith(root + path.sep) || !/\.xmp$/i.test(dest)) { errors.push({ name: path.basename(f.name), reason: 'refused' }); continue; }
          // No sidecar for a RAW that is no longer beside it (renamed, moved or deleted since the read).
          const stem = path.basename(dest).replace(/\.[^.]+$/, '');
          if (!fs.readdirSync(path.dirname(dest)).some(n => /\.arw$/i.test(n) && n.replace(/\.[^.]+$/, '') === stem)) { errors.push({ name: stem, reason: 'missing' }); continue; }
          const data = Buffer.from(f.b64, 'base64');
          if (this.beforeSidecar) this.beforeSidecar(dest);            // a test's chance to be the other app, writing at this instant
          // A sidecar that is not UTF-8 text is never replaced, whatever its base (SetsFileOps.sidecarUnreadable).
          if (fs.existsSync(dest) && utf8(fs.readFileSync(dest)) == null) { errors.push({ name: stem, reason: 'unreadable' }); continue; }
          // The file must still be what the merge was based on (SetsFileOps.sidecarBase), else it is left alone.
          if (f.base != null && sidecarBase(dest) !== f.base && !(fs.existsSync(dest) && fs.readFileSync(dest).equals(data))) { errors.push({ name: stem, reason: 'changed on disk' }); continue; }
          if (fs.existsSync(dest)) { if (!fs.existsSync(dest + '.lumina-bak')) { fs.copyFileSync(dest, dest + '.lumina-bak'); bak++; } }
          fs.writeFileSync(dest + '.tmp', data); fs.renameSync(dest + '.tmp', dest);
          if (!fs.readFileSync(dest).equals(data)) errors.push({ name: path.basename(f.name), reason: 'failed' }); else n++;
        }
        return { n, bak, folder: path.basename(root), path: root, errors };
      }
      default: return null;
    }
  }
}

// A query as plumbing.js must write it (encodeURIComponent): %XX decoded once, a '+' stays a '+'.
// Stricter than SetsSchemeHandler.query (which also reads '+' as a space) on purpose, so a URL built
// with URLSearchParams fails here: a folder named "Shoot 2026" would arrive as "Shoot+2026".
export const strictQuery = u => Object.fromEntries(u.search.slice(1).split('&').filter(Boolean).map(kv => {
  const i = kv.indexOf('='); return [decodeURIComponent(i < 0 ? kv : kv.slice(0, i)), decodeURIComponent(i < 0 ? '' : kv.slice(i + 1))];
}));

// app: plumbing.js + the stand-in bridge (as the app); false: the prototype as designed.
// clockBase: fixed wall clock, as the probe's (ms since epoch). parity: plumbing's test-only sample mode.
export async function open(browser, bridge, { prefs, app = true, size = [1440, 900], scale = 1, clockBase, query = '', parity = false, ready = true } = {}) {
  const ctx = await browser.newContext({ viewport: { width: size[0], height: size[1] }, deviceScaleFactor: scale, reducedMotion: 'no-preference' });
  const page = await ctx.newPage();
  if (bridge) bridge.page = page;
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await ctx.route(ORIGIN + '/**', async route => {
    const u = new URL(route.request().url()), p = decodeURIComponent(u.pathname.slice(1));
    if (p.startsWith('render/')) {
      // The Edit preview (image path): what lumina://render answers.
      const rel = p.slice(7), q = strictQuery(u);
      if (!bridge || !bridge.resolve(rel)) return route.fulfill({ status: 404, body: 'not in an opened folder' });
      const r = await bridge.render(rel, q);
      return route.fulfill({ status: r.status, body: r.body, contentType: r.contentType || 'text/plain' });
    }
    if (p.startsWith('media/')) {
      if (bridge && bridge.delayMs) await new Promise(r => setTimeout(r, bridge.delayMs));   // a slow card
      const q = strictQuery(u), f = bridge && bridge.resolve(q.p || '');
      const [n] = (q.p || '').split('/');
      if (bridge && bridge.gone.has(n)) return route.fulfill({ status: 410, body: 'card removed' });
      if (!f || !fs.existsSync(f)) return route.fulfill({ status: 404, body: 'not in an opened folder' });
      // No /media/thumb here (no ImageIO stand-in): plumbing makes the tile in the page instead.
      if (p !== 'media/head' && p !== 'media/preview') return route.fulfill({ status: 404, body: 'unknown media' });
      const b = fs.readFileSync(f);
      const body = p === 'media/head' ? b.subarray(0, 262144) : b.subarray(+q.o, +q.o + +q.l);
      return route.fulfill({ status: 200, body, contentType: p === 'media/head' ? 'application/octet-stream' : 'image/jpeg' });
    }
    const file = p.startsWith('vendor/') ? path.join(WEB, p.slice(7)) : path.join(WEB, p);
    if (!fs.existsSync(file)) return route.fulfill({ status: 404 });
    return route.fulfill({ status: 200, body: fs.readFileSync(file), contentType: file.endsWith('.html') ? 'text/html' : 'text/javascript' });
  });
  await ctx.route(/^https?:\/\/(?!lumina\.test)/, r => r.abort());
  if (clockBase) await page.addInitScript(`(() => { const R = Date, t0 = R.now(), b = ${clockBase}; const now = () => b + (R.now() - t0);
    class D extends R { constructor(...a) { if (a.length === 0) super(now()); else super(...a); } static now() { return now(); } } window.Date = D; })();`);
  await page.addInitScript(`window.__resources=Object.assign(window.__resources||{},${JSON.stringify(VENDOR)});`);
  if (app) {
    await page.exposeFunction('__nativeCall', msg => bridge.handle(msg));
    await page.addInitScript(`window.__luminaConfig=${JSON.stringify({ debug: false, prefs: prefs || null, parity, nearLimit: 0.35 })};`);
    await page.addInitScript(`window.webkit={messageHandlers:{lumina:{postMessage:m=>window.__nativeCall(m)}}};`);
    await page.addInitScript(fs.readFileSync(path.join(WEB, 'plumbing.js'), 'utf8'));
  }
  await page.goto(ORIGIN + '/' + encodeURIComponent(PAGE) + (query ? '?' + query : ''));
  if (ready) await page.waitForFunction(app ? () => window.__lumina && __lumina.logic() && __lumina.logic().__luminaPlumbed
    : () => document.querySelector('[data-screen-label]') && window.luminaState, null, { timeout: 30000 });
  return { ctx, page, errors };
}

// The page's logic (as probe.js finds it), for either mode.
export const LOGIC = `(() => { for (const el of document.querySelectorAll('[data-screen-label], body *')) { const k = Object.keys(el).find(x => x.startsWith('__reactFiber$')); if (!k) continue;
  for (let f = el[k]; f; f = f.return) { const sn = f.stateNode; if (sn && sn.logic && typeof sn.logic.onKey === 'function' && sn.logic.state && 'view' in sn.logic.state) return sn.logic; } } return null; })`;
