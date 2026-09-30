// Linux check for plumbing.js: the real page (Lumina/Sets/Web) in headless Chromium, plumbing.js
// injected exactly as the app injects it, and a stand-in for the Swift bridge (SetsBridge) written in
// Node. It exercises the JavaScript half of the bridge only. The Swift half, WebKit, and pixel parity
// still need the Mac (probe.sh). Synthetic ARWs (a TIFF with EXIF and an embedded JPEG) are made in
// a temp folder; no personal data.
//
//   node Tests/web/plumbing-harness.mjs            all checks, prints ok / FAIL lines
//   node Tests/web/plumbing-harness.mjs --hash     print the fnv of the page's onDir + readOne (ONDIR)
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pw, ROOT, WEB, makeJpegs, makeShoot, makeBigShoot, Bridge, open } from './lib.mjs';

const hashOnly = process.argv.includes('--hash');
let fails = 0;
const ok = (cond, what, extra) => { if (!cond) fails++; console.log((cond ? 'ok   ' : 'FAIL ') + what + (extra !== undefined && !cond ? '  got ' + JSON.stringify(extra) : '')); };

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
  // Grid thumbnails: sharper than the page's 360 px bitmap (never upscaled), while every measure
  // still comes from that bitmap, redone here exactly as the page's readOne does it.
  const th = await page.evaluate(async () => {
    const l = __lumina.logic(), out = [];
    for (const p of l.real.filter(q => !q.portrait).slice(0, 4)) {
      const q = new URL(p.lg).searchParams, blob = await (await fetch(p.lg.replace(/ori=\d/, 'ori=1'))).blob();
      const sm = await createImageBitmap(blob, { resizeWidth: 360, resizeQuality: 'medium' }), me = LuminaCore.measure(sm); sm.close();
      const full = await createImageBitmap(blob), im = new Image(); im.src = p.src; await im.decode();
      out.push({ same: me.dhash === p.dhash && me.focus === p.focus && me.lum === p.lum && me.clip === p.clip, w: im.naturalWidth, full: full.width, ori: q.get('ori'),
        want: Math.min(full.width, 720, Math.max(360, Math.ceil(324 * (window.devicePixelRatio || 1)))) }); full.close();
    }
    return out;
  });
  ok(th.length && th.every(t => t.same), 'thumbs: measures identical to the page\'s 360 px bitmap', th);
  // No native thumbnail here (the stand-in has no ImageIO): the in-page fallback, sized for the largest
  // tile on this screen (324 CSS px × devicePixelRatio, 360–720), never upscaled.
  ok(th.length && th.every(t => t.w === t.want), 'thumbs: fallback tile image sized for the largest tile, never upscaled', th);
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

  // Moving and keeping while a folder is still being read: nothing jumps when the read ends, and on a
  // reopen the decisions made during the read are kept alongside the saved ones.
  const slow = path.join(tmp, '2026-09-02');
  makeBigShoot(slow, jpegs, 160);
  const during = async (label, moves) => {
    bridge.delayMs = 25; bridge.pending = slow; await page.evaluate(() => __lumina.openFolder());
    await page.waitForFunction(() => { const l = __lumina.logic(); return l.state.view === 'cull' && l.state.realLoad && l.real && l.real.length >= 48; }, null, { timeout: 30000 });
    for (const k of moves) { await key(page, k); await page.waitForTimeout(120); }
    await key(page, 'p'); await page.waitForTimeout(150);
    const mid = await page.evaluate(() => { const l = __lumina.logic(), p = l.data.byId[l.state.cur], el = l.scrollRef.current;
      return { cur: p && p.path, kept: l.kept().map(id => l.data.byId[id].path), still: !!l.state.realLoad, top: el.scrollTop }; });
    await loaded(page); await page.waitForTimeout(600);
    const end = await page.evaluate(() => { const l = __lumina.logic(), p = l.data.byId[l.state.cur], el = l.scrollRef.current;
      return { cur: p && p.path, kept: l.kept().map(id => l.data.byId[id].path), top: el.scrollTop, n: l.real.length }; });
    bridge.delayMs = 0;
    ok(mid.still && mid.kept.length === 1, label + ': kept a photo while the folder was still being read', mid);
    ok(end.n === 160 && end.cur === mid.cur, label + ': the read ends on the reader\'s photo, not the first', { mid, end });
    ok(Math.abs(end.top - mid.top) < 400, label + ': no scroll jump when the read ends', { mid: mid.top, end: end.top });
    return { mid, end };
  };
  const first = await during('during read', ['ArrowDown', 'ArrowDown', 'ArrowRight']);
  ok(first.end.kept.length === 1, 'during read: the keep survives the end of the read', first.end.kept);
  await page.waitForTimeout(2300);            // autosave
  const saved2 = bridge.sessions['id-2026-09-02'] && JSON.parse(bridge.sessions['id-2026-09-02']);
  ok(saved2 && Object.keys(saved2.marks).length === 1, 'during read: the keep made while reading is saved', saved2 && saved2.marks);
  await page.evaluate(() => __lumina.closeShoot()); await page.waitForTimeout(200);
  const again = await during('reopen during read', ['ArrowDown', 'ArrowDown', 'ArrowDown', 'ArrowDown', 'ArrowDown', 'ArrowRight', 'ArrowRight']);
  ok(again.end.kept.length === 2 && again.end.kept.includes(first.end.kept[0]), 'reopen during read: the saved keep and the new one both kept', { first: first.end.kept, again: again.end.kept });

  ok(errors.length === 0, 'no page errors', errors);
  await ctx.close();
  await browser.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(fails ? fails + ' FAIL' : 'all ok');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
