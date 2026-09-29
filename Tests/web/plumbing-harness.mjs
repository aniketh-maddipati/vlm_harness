// Linux check for plumbing.js: the real page (Lumina/Sets/Web) in headless Chromium, plumbing.js
// injected exactly as the app injects it, and a stand-in for the Swift bridge (SetsBridge) written in
// Node. It exercises the JavaScript half of the bridge only. The Swift half, WebKit, and pixel parity
// still need the Mac (probe.sh). Synthetic ARWs (a TIFF with EXIF and an embedded JPEG) are made in
// a temp folder; no personal data.
//
//   node Tests/web/plumbing-harness.mjs            all checks, prints ok / FAIL lines
//   node Tests/web/plumbing-harness.mjs --hash     print the fnv of the page's onDir + readOne (ONDIR)
import { createRequire } from 'module';
import { execSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch (_) { pw = require(path.join(execSync('npm root -g').toString().trim(), 'playwright')); }

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const WEB = path.join(ROOT, 'Lumina/Sets/Web');
const PAGE = 'Lumina Sets v5.dc.html';
const ORIGIN = 'http://lumina.test';
const VENDOR = {
  'https://unpkg.com/react@18.3.1/umd/react.production.min.js': ORIGIN + '/vendor/react.production.min.js',
  'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js': ORIGIN + '/vendor/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone@7.29.0/babel.min.js': ORIGIN + '/vendor/babel.min.js',
};
const hashOnly = process.argv.includes('--hash');
let fails = 0;
const ok = (cond, what, extra) => { if (!cond) fails++; console.log((cond ? 'ok   ' : 'FAIL ') + what + (extra !== undefined && !cond ? '  got ' + JSON.stringify(extra) : '')); };

// ——— synthetic ARWs
function tiff({ date, exp = [1, 250], fl = [50, 1], iso = 400, model = 'ILCE-7M4', orient = 1, jpeg, pad = 300_000 }) {
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

async function makeJpegs(browser, n) {
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

function makeShoot(dir, jpegs, { others = [], sidecars = {} } = {}) {
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

// ——— the Swift bridge, in Node (what SetsBridge answers)
function list(root) {
  const name = path.basename(root), out = { name, files: [], xmp: [], others: [], workers: 4, onCard: false };
  const walk = d => { for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (e.name.startsWith('.')) continue;
    const full = path.join(d, e.name), rel = name + '/' + path.relative(root, full).split(path.sep).join('/');
    if (e.isDirectory()) { walk(full); continue; }
    const ext = path.extname(e.name).toLowerCase();
    if (ext === '.arw') out.files.push({ rel, size: fs.statSync(full).size });
    else if (ext === '.xmp') out.xmp.push({ rel, text: fs.readFileSync(full, 'utf8') });
    else if (!e.name.endsWith('.lumina-bak')) out.others.push(rel);
  } };
  walk(root);
  return out;
}

class Bridge {
  constructor(parent) { this.parent = parent; this.roots = {}; this.pending = null; this.calls = []; this.sessions = {}; this.index = []; this.prefs = null; this.revealed = []; this.gone = new Set(); this.denied = null; }
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
        return { id, session: this.sessions[id] || null };
      }
      case 'saveSession': { this.sessions[msg.id] = msg.json; const s = this.index.find(x => x.id === msg.id); if (s) Object.assign(s, msg.summary || {}); this.saves = (this.saves || 0) + 1; return true; }
      case 'prefetch': return (msg.items || []).length;
      case 'ingestStats': return { workers: 4, inFlight: 0, maxInFlight: 4, heads: 0, previews: 0, largestRead: 0, opensAfterGone: 0, failures: 0, gone: [...this.gone] };
      case 'setPrefs': this.prefs = msg.prefs; return true;
      case 'reveal': this.revealed.push(msg.path); return true;
      case 'cullCard': return false;
      case 'workingFiles': return 1234;
      case 'removeShoot': delete this.sessions[msg.id]; this.index = this.index.filter(s => s.id !== msg.id); return true;
      case 'reopen': { const s = this.index.find(x => x.id === msg.id); if (!s) return false; this.pending = s.path; this.page.evaluate('__lumina.openFolder()'); return true; }
      case 'reopenCurrent': this.pending = this.current; this.page.evaluate('__lumina.openFolder()'); return true;
      case 'openSettings': this.settingsOpened = msg.what; return true;
      case 'checkAccess': return this.denied == null;
      case 'reopenDenied': return true;
      case 'writeSidecars': {
        // Mirrors SetsFileOps.writeSidecar: into the shoot folder, .xmp only, .lumina-bak first, verify.
        const root = this.roots[msg.root]; if (!root) return null;
        let n = 0, bak = 0; const errors = [];
        for (const f of msg.files) {
          const dest = path.resolve(root, f.name);
          if (!dest.startsWith(root + path.sep) || !/\.xmp$/i.test(dest)) { errors.push({ name: path.basename(f.name), reason: 'refused' }); continue; }
          const data = Buffer.from(f.b64, 'base64');
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

async function open(browser, bridge, { prefs } = {}) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  bridge.page = page;
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await ctx.route(ORIGIN + '/**', async route => {
    const u = new URL(route.request().url()), p = decodeURIComponent(u.pathname.slice(1));
    if (p.startsWith('media/')) {
      const q = Object.fromEntries(u.searchParams), f = bridge.resolve(q.p || '');
      const [n] = (q.p || '').split('/');
      if (bridge.gone.has(n)) return route.fulfill({ status: 410, body: 'card removed' });
      if (!f || !fs.existsSync(f)) return route.fulfill({ status: 404, body: 'not in an opened folder' });
      const b = fs.readFileSync(f);
      const body = p === 'media/head' ? b.subarray(0, 262144) : b.subarray(+q.o, +q.o + +q.l);
      return route.fulfill({ status: 200, body, contentType: p === 'media/head' ? 'application/octet-stream' : 'image/jpeg' });
    }
    const file = p.startsWith('vendor/') ? path.join(WEB, p.slice(7)) : path.join(WEB, p);
    if (!fs.existsSync(file)) return route.fulfill({ status: 404 });
    return route.fulfill({ status: 200, body: fs.readFileSync(file), contentType: file.endsWith('.html') ? 'text/html' : 'text/javascript' });
  });
  await ctx.route(/^https?:\/\/(?!lumina\.test)/, r => r.abort());
  await page.exposeFunction('__nativeCall', msg => bridge.handle(msg));
  await page.addInitScript(`window.__resources=Object.assign(window.__resources||{},${JSON.stringify(VENDOR)});`);
  await page.addInitScript(`window.__luminaConfig=${JSON.stringify({ debug: false, prefs: prefs || null })};`);
  await page.addInitScript(`window.webkit={messageHandlers:{lumina:{postMessage:m=>window.__nativeCall(m)}}};`);
  await page.addInitScript(fs.readFileSync(path.join(WEB, 'plumbing.js'), 'utf8'));
  await page.goto(ORIGIN + '/' + encodeURIComponent(PAGE));
  await page.waitForFunction(() => window.__lumina && __lumina.logic() && __lumina.logic().__luminaPlumbed, null, { timeout: 30000 });
  return { ctx, page, errors };
}

const S = page => page.evaluate(() => { const l = __lumina.logic(); return { view: l.state.view, cur: l.state.cur, marks: l.state.marks, realInfo: l.state.realInfo, n: l.data.order.length, notes: l.state.notes, openNote: l.state.openNote }; });
const key = (page, k, o = {}) => page.evaluate(([k, o]) => { const codes = { p: 'KeyP', f: 'KeyF', ArrowDown: 'ArrowDown', ArrowRight: 'ArrowRight', Enter: 'Enter', '3': 'Digit3', '2': 'Digit2', o: 'KeyO' }; dispatchEvent(new KeyboardEvent('keydown', { key: k, code: codes[k] || k, bubbles: true, ...o })); dispatchEvent(new KeyboardEvent('keyup', { key: k, code: codes[k] || k, bubbles: true, ...o })); }, [k, o]);
const loaded = page => page.waitForFunction(() => { const l = __lumina.logic(); return !!(l.real && l.real.length && !l.state.realLoad && l.state.realInfo); }, null, { timeout: 30000 });

(async () => {
  const browser = await pw.chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
  const tmp = fs.mkdtempSync(path.join(process.env.LUMINA_HARNESS_TMP || os.tmpdir(), 'lumina-harness-'));
  const bridge = new Bridge();
  let { ctx, page, errors } = await open(browser, bridge, { prefs: { rating: 4, adv: true, tsz: 1, enter: true } });

  if (hashOnly) { console.log(await page.evaluate(() => __lumina.readHash())); await browser.close(); return; }

  // Contract
  ok((await page.evaluate(() => __lumina.missing())).length === 0, 'contract: every page member plumbing needs exists', await page.evaluate(() => __lumina.missing()));
  ok(await page.evaluate(() => __lumina.ready()), 'contract: ready');
  ok(bridge.readyMsg && !bridge.readyMsg.missing, 'contract: native told ready');
  const drift = await page.evaluate(() => __lumina.drift());
  ok(drift.length === 0, 'contract: onDir/readOne match ONDIR', drift);
  ok(await page.evaluate(() => JSON.parse(localStorage.getItem('lumina-prefs')).rating === 4 && __lumina.logic().state.prefs.rating === 4), 'prefs: seeded from __luminaConfig.prefs');
  ok(await page.evaluate(() => __lumina.logic().state.view === 'import' && __lumina.logic().data.order.length === 0), 'start: empty Open screen, no sample shoot');

  // The probe's contract scenario, its expect steps run here as they run in WKWebView.
  await page.evaluate(() => { window.__probe = { logic: () => __lumina.logic() }; });
  const contract = JSON.parse(fs.readFileSync(path.join(ROOT, 'Tests/probe/scenarios/app-plumbing-contract.json'), 'utf8'));
  for (const st of contract.steps.filter(x => x.do === 'expect')) {
    let got; try { got = await page.evaluate(src => (new Function(src))(), st.js); } catch (e) { got = 'threw ' + e.message; }
    ok('equals' in st ? JSON.stringify(got) === JSON.stringify(st.equals) : !!got, 'scenario app-plumbing-contract: ' + st.js.slice(0, 70), got);
  }
  await page.evaluate(() => __lumina.logic().setState({ glance: false, prefsOn: false, faq: false, hideHints: false }));

  // Menu command hook
  ok(await page.evaluate(() => __lumina.command('settings') === true && __lumina.logic().state.prefsOn === true), 'menu: luminaCommand(settings) opens Settings');
  await page.evaluate(() => __lumina.command('settings'));
  await page.evaluate(() => __lumina.logic().setPref({ rating: 5 }));
  ok(bridge.prefs && bridge.prefs.rating === 5, 'prefs: setPref reaches lumina.setPrefs', bridge.prefs);
  await page.evaluate(() => __lumina.logic().setPref({ rating: 3 }));

  // No ARW: the page's open note, from the native listing's other names
  const jpegs = await makeJpegs(browser, 12);
  const empty = path.join(tmp, 'NoRaw'); fs.mkdirSync(empty, { recursive: true });
  for (const n of ['A.CR3', 'B.CR3', 'C.JPG', 'D.MP4']) fs.writeFileSync(path.join(empty, n), 'x');
  bridge.pending = empty; await page.evaluate(() => __lumina.openFolder());
  await page.waitForFunction(() => !!__lumina.logic().state.openNote, null, { timeout: 5000 }).catch(() => {});
  ok((await S(page)).openNote === 'no ARW found · 2 CR3 · 1 JPEG / HEIF · 1 videos · only Sony ARW is supported', 'intake: no-ARW note uses non-ARW names from the listing', (await S(page)).openNote);

  // A shoot
  const shoot = path.join(tmp, '2026-09-01');
  makeShoot(shoot, jpegs, { others: ['DSC01001.JPG', 'X.CR3', 'clip.MP4'], sidecars: { 'DSC01002.xmp': '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="2"/></rdf:RDF></x:xmpmeta>' } });
  bridge.pending = shoot; await page.evaluate(() => __lumina.openFolder());
  await loaded(page);
  let s = await S(page);
  ok(s.view === 'cull', 'read: lands in Cull', s.view);
  ok(s.n === 12 && s.realInfo.n === 12 && s.realInfo.bad === 0, 'read: 12 photos, 0 unreadable', s.realInfo);
  ok(s.realInfo.name === '2026-09-01' && s.realInfo.date === '2026-09-01', 'read: realInfo name + date', s.realInfo);
  ok(s.realInfo.rows >= 2, 'read: rows', s.realInfo);
  const notes = (s.notes || []).map(x => x.t).join(' | ');
  ok(/1 CR3/.test(notes) && /1 video skipped/.test(notes) && /1 already have a \.xmp sidecar/.test(notes) && /1 already rated/.test(notes), 'read: import notes from intake + sidecars', notes);
  const insp = await page.evaluate(() => __lumina.inspect());
  ok(insp.lgHeld === 0 && insp.srcNotBlob === 0 && insp.dupPaths === 0 && insp.zsrcOff === 0, 'read: previews by lumina:// URL, thumbs held as blobs', insp);
  const p7 = await page.evaluate(() => { const l = __lumina.logic(); const p = Object.values(l.data.byId).find(p => p.file === 'DSC01007.ARW' || p.name === 'DSC01007.ARW'); return p && { portrait: p.portrait, lg: p.lg, model: p.model, xpath: p.xpath, path: p.path }; });
  ok(p7 && p7.portrait === true && /\/media\/preview\?/.test(p7.lg), 'read: orientation 6 → portrait, large view by URL', p7);
  ok(p7 && p7.model === 'ILCE-7M4' && p7.path === '2026-09-01/DSC01007.ARW', 'read: v5 fields (model, path)', p7);
  ok(bridge.calls.includes('shootOpened'), 'session: shootOpened sent');
  ok(await page.evaluate(() => window.lumina.readingCard === false), 'card: readingCard false for a folder');

  // Decisions + autosave
  await key(page, 'p'); await page.waitForTimeout(100);
  await key(page, 'ArrowDown'); await page.waitForTimeout(100); await key(page, 'p'); await page.waitForTimeout(100);
  s = await S(page);
  const keptN = Object.values(s.marks).filter(v => v === 'keep').length;
  ok(keptN >= 1, 'cull: P keeps', s.marks);
  await page.waitForTimeout(2300);
  const sid = await page.evaluate(() => __lumina.shootId());
  const saved = bridge.sessions[sid] && JSON.parse(bridge.sessions[sid]);
  ok(saved && Object.keys(saved.marks).length === keptN && Object.keys(saved.marks).every(k => /DSC0\d+\.ARW$/.test(k) && !k.startsWith('2026')), 'session: marks saved by path inside the folder', saved && saved.marks);
  ok(saved && typeof saved.cur === 'string' && saved.seen && Object.keys(saved.seen).length >= 1, 'session: cur + seen saved', saved && { cur: saved.cur, seen: saved.seen });
  ok(bridge.index[0] && bridge.index[0].kp === keptN, 'session: recents summary (kp) sent', bridge.index[0]);
  ok((await page.evaluate(() => __lumina.unsaved())) === keptN, 'quit: unsaved keepers counted');

  // Save → sidecars INTO the folder
  const before2 = fs.readFileSync(path.join(shoot, 'DSC01002.xmp'), 'utf8');
  await page.evaluate(() => __lumina.command('stepSave')); await page.waitForTimeout(300);
  ok((await S(page)).view === 'export', 'save: ⌘3 via luminaCommand');
  await page.waitForTimeout(900);            // the page ignores ⌘⏎ for 800 ms after a step change
  await page.evaluate(() => __lumina.command('save'));
  await page.waitForFunction(() => { const r = __lumina.logic().state.ex; return r && r.result; }, null, { timeout: 5000 }).catch(() => {});
  const res = await page.evaluate(() => __lumina.logic().state.ex.result);
  ok(res && res.t === keptN + ' saved' && !res.bad, 'save: result "N saved"', res);
  const xmps = fs.readdirSync(shoot).filter(f => /\.xmp$/.test(f));
  ok(xmps.length >= keptN, 'save: sidecars written next to the RAWs', xmps);
  const kept1 = Object.keys(saved.marks)[0].replace(/\.ARW$/, '.xmp');
  ok(fs.existsSync(path.join(shoot, kept1)) && /Rating="3"|<xmp:Rating>3</.test(fs.readFileSync(path.join(shoot, kept1), 'utf8')), 'save: sidecar rated 3★', kept1);
  if (Object.keys(saved.marks).includes('DSC01002.ARW')) ok(fs.readFileSync(path.join(shoot, 'DSC01002.xmp.lumina-bak'), 'utf8') === before2, 'save: .lumina-bak keeps the old sidecar');
  ok(res && res.where === shoot, 'save: where = the shoot folder path', res && res.where);
  ok((await page.evaluate(() => __lumina.unsaved())) === 0, 'quit: nothing unsaved after Save');
  await page.evaluate(() => __lumina.command('finder')); await page.waitForTimeout(100);
  ok(bridge.revealed.length === 1, 'save: ⌘R reveals', bridge.revealed);

  // Reopen: session restored by path
  const marksBefore = (await S(page)).marks;
  await page.evaluate(() => __lumina.closeShoot()); await page.waitForTimeout(200);
  ok((await S(page)).view === 'import', 'close shoot: back to Open');
  const recents = await page.evaluate(() => __lumina.logic().recents());
  ok(recents.length === 1 && recents[0].id && recents[0].kp === keptN, 'recents: the shoot, with keepers', recents);
  await page.evaluate(() => __lumina.logic().libOpen(__lumina.logic().recents()[0]));
  await loaded(page); await page.waitForTimeout(300);
  s = await S(page);
  ok(JSON.stringify(Object.keys(s.marks).sort()) === JSON.stringify(Object.keys(marksBefore).sort()), 'reopen: marks restored', { now: s.marks, before: marksBefore });
  ok((await page.evaluate(() => __lumina.unsaved())) === 0, 'reopen: saved keepers remembered');

  // Card removed mid-read, then back
  bridge.gone.add('2026-09-01');
  await page.evaluate(() => __lumina.cardGone(['2026-09-01'], true)); await page.waitForTimeout(100);
  ok(await page.evaluate(() => __lumina.logic().state.gone === true), 'card: luminaCardGone(true) on pull');
  bridge.gone.clear();
  await page.evaluate(() => __lumina.cardBack()); await page.waitForTimeout(100);
  ok(await page.evaluate(() => __lumina.logic().state.gone === false), 'card: luminaCardGone(false) on remount');

  // readingCard: Save refuses on a card
  await page.evaluate(() => { window.lumina.card = { name: 'Untitled', photos: 12 }; window.lumina.readingCard = true; });
  ok(await page.evaluate(() => __lumina.logic().onCard()), 'card: page sees onCard() from lumina.readingCard');
  await page.evaluate(() => { window.lumina.card = null; window.lumina.readingCard = false; });

  // Access denied
  const locked = path.join(tmp, 'Locked'); fs.mkdirSync(locked, { recursive: true });
  bridge.denied = locked; bridge.pending = locked; await page.evaluate(() => __lumina.openFolder()); await page.waitForTimeout(200);
  ok(await page.evaluate(() => { const a = __lumina.logic().state.acc; return !!a && a.what === 'Locked'; }), 'access: luminaAccess(true, name) on denial');
  bridge.denied = null;
  await page.evaluate(() => __lumina.logic().accRetry()); await page.waitForTimeout(200);
  ok(await page.evaluate(() => !__lumina.logic().state.acc), 'access: checkAccess → banner cleared');

  ok(errors.length === 0, 'no page errors', errors);
  await ctx.close();
  await browser.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(fails ? fails + ' FAIL' : 'all ok');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
