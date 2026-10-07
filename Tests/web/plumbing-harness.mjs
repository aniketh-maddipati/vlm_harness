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
import { pw, ROOT, WEB, makeJpegs, makeShoot, makeBigShoot, Bridge, open, deadline } from './lib.mjs';

deadline('plumbing-harness.mjs', 300);

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
  ok((await S(page)).openNote === 'no ARW or DNG found · 2 CR3 · 1 JPEG / HEIF · 1 videos · Lumina reads ARW and DNG', 'intake: no-ARW note uses non-ARW names from the listing', (await S(page)).openNote);

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

  // Retakes (DESIGN-ASKS Prompt 2 C): lumina.near(pathA, pathB) is the Mac's distance between two photos'
  // previews, lumina.nearLimit its threshold. The page names photos by path; plumbing sends where each
  // preview is, as the native read found it.
  const near = await page.evaluate(async () => {
    const P = __lumina.logic().real, a = P[0].path, b = P[1].path;
    return { limit: lumina.nearLimit, ab: await lumina.near(a, b), aa: await lumina.near(a, a), unknown: await lumina.near(a, 'nowhere/DSC0.ARW'), none: await lumina.near(), a, b };
  });
  ok(near.limit === 0.35, 'near: lumina.nearLimit comes from the app config', near.limit);
  ok(near.ab === 0.25 && near.aa === 0, 'near: lumina.near(pathA, pathB) resolves to the Mac\'s distance', near);
  const sent = (bridge.nears || [])[0];
  ok(sent && sent.a.p === near.a && sent.b.p === near.b && sent.a.o > 0 && sent.a.l > 0 && sent.a.ori >= 1, 'near: the Mac gets each preview\'s path, byte range and orientation', sent);
  ok(near.unknown === null && near.none === null && (bridge.nears || []).length === 2, 'near: a path that was not read resolves to null without asking the Mac', { near, asked: (bridge.nears || []).length });
  ok(await page.evaluate(() => window.lumina.readingCard === false), 'card: readingCard false for a folder');

  // Decisions + autosave
  // A decision is saved on the next tick, not the next 2 s loop: the page's process can stop at any
  // moment. Two keeps 500 ms apart: one tick of a 2 s loop could save one of them in time, never both.
  const sid = await page.evaluate(() => __lumina.shootId());
  const keeps = m => Object.values(m || {}).filter(v => v === 'keep').length, soon = [];
  const sample = async () => { await page.waitForTimeout(400); soon.push([keeps((await S(page)).marks), keeps(bridge.sessions[sid] && JSON.parse(bridge.sessions[sid]).marks)]); };
  await key(page, 'p'); await sample();
  await key(page, 'ArrowDown'); await page.waitForTimeout(100); await key(page, 'p'); await sample();
  ok(soon.every(([have, saved]) => have >= 1 && saved === have), 'session: every keep is saved within 400 ms of its key', soon);
  s = await S(page);
  const keptN = Object.values(s.marks).filter(v => v === 'keep').length;
  ok(keptN >= 1, 'cull: P keeps', s.marks);
  await page.waitForTimeout(2300);
  const saved = bridge.sessions[sid] && JSON.parse(bridge.sessions[sid]);
  ok(saved && Object.keys(saved.marks).length === keptN && Object.keys(saved.marks).every(k => /DSC0\d+\.ARW$/.test(k) && !k.startsWith('2026')), 'session: marks saved by path inside the folder', saved && saved.marks);
  ok(saved && typeof saved.cur === 'string' && saved.seen && Object.keys(saved.seen).length >= 1, 'session: cur + seen saved', saved && { cur: saved.cur, seen: saved.seen });
  ok(bridge.index[0] && bridge.index[0].kp === keptN, 'session: recents summary (kp) sent', bridge.index[0]);
  ok((await page.evaluate(() => __lumina.unsaved())) === keptN, 'quit: unsaved keepers counted');
  // Looks (the Edit step, roadmap "Rendering contract"): `look` per photo by path, `rowLook` per row, in the session, never in XMP.
  await page.evaluate(() => { const l = __lumina.logic(); l.setState({ look: { [l.state.cur]: 'ev:+0.50 con:+12' }, rowLook: { r1: 'wb:5200/+3' } }); });
  await page.waitForTimeout(2300);
  const savedLook = bridge.sessions[sid] && JSON.parse(bridge.sessions[sid]);
  ok(savedLook && savedLook.look && Object.entries(savedLook.look).some(([k, v]) => /DSC0\d+\.ARW$/.test(k) && v === 'ev:+0.50 con:+12'), 'session: look saved per photo by path', savedLook && savedLook.look);
  ok(savedLook && savedLook.rowLook && savedLook.rowLook.r1 === 'wb:5200/+3', 'session: rowLook saved per row', savedLook && savedLook.rowLook);
  await page.evaluate(() => { const l = __lumina.logic(); l.setState({ look: {}, rowLook: {} }); });

  // The Edit canvas (addendum §2–7, RAW 9 §1): window.lumina.edit on the image path (no Metal here),
  // lumina://render with latest wins and two tiers, the 500 ms save debounce, the shoot header.
  ok(bridge.bodies && bridge.bodies['ILCE-7M4'] === '2026-09-01/DSC01001.ARW', 'edit: shootOpened names one RAW per body for the decoder map', bridge.bodies);
  bridge.renderJpeg = jpegs[0];
  const rel0 = await page.evaluate(() => __lumina.logic().real[0].path);
  ok(await page.evaluate(() => ['preview', 'canvasRect', 'drag', 'roi'].every(k => typeof lumina[k] === 'function')), 'edit: Prompt 1 §3\'s lumina.preview / canvasRect / drag / roi exist');
  const hooks = await page.evaluate(async rel => {
    window.__editImages = []; window.__editFacts = []; window.__facts = [];
    window.luminaEditImage = (u, seq, tier) => window.__editImages.push({ seq, tier, url: u });
    window.luminaEditFacts = (t, f) => window.__editFacts.push(t);
    window.luminaFacts = f => window.__facts.push(f);
    const f = await lumina.edit.enter(rel, 'ev:+0.50');
    lumina.edit.layout({ x: 300, y: 80, w: 900, h: 600 }, true);
    await new Promise(r => setTimeout(r, 400));
    return { facts: f, state: lumina.edit.state(), images: window.__editImages.slice(), factsSeen: window.__editFacts.slice(), factsObjs: window.__facts.slice() };
  }, rel0);
  ok(hooks.facts && hooks.facts.canvas === 'image' && /^canvas: image · raw 9: no/.test(hooks.facts.text), 'edit: facts say canvas: image and raw 9: no', hooks.facts);
  ok(hooks.factsObjs.length && hooks.factsObjs[0].canvas === 'image' && hooks.factsObjs[0].raw9 === false && hooks.factsObjs[0].decoder === '8' && hooks.factsObjs[0].note === null, 'edit: luminaFacts({canvas, raw9, decoder, note}) as Prompt 1 §3 names it', hooks.factsObjs);
  // Prompt 1 §3's preview(): the URL to show on the image path, quarter tier while a slider drags.
  const pv = await page.evaluate(rel => { const a = lumina.preview(rel, 'ev:+0.20', 1800, 7); lumina.drag('start'); const b = lumina.preview(rel, 'ev:+0.25', 1800, 8); lumina.drag('end'); return [a, b]; }, rel0);
  ok(pv[0] && /\/render\/2026-09-01\/DSC01001\.ARW\?/.test(pv[0]) && /look=ev%3A%2B0.20/.test(pv[0]) && /px=1800/.test(pv[0]) && /seq=7/.test(pv[0]) && /tier=base/.test(pv[0]) && /decoder=8/.test(pv[0]), 'edit: lumina.preview returns the lumina://render URL at rest (tier=base)', pv[0]);
  ok(pv[1] && /seq=8/.test(pv[1]) && /tier=small/.test(pv[1]), 'edit: lumina.preview returns the quarter tier while a slider drags', pv[1]);
  const pv2 = await page.evaluate(rel => lumina.preview(rel, 'ev:+0.30 con:+10', 900, 9), rel0);
  ok(pv2 && /look=ev%3A%2B0.30%20con%3A%2B10/.test(pv2) && !/\+/.test(pv2.split('?')[1]) && /&o=\d+&l=\d+&ori=/.test(pv2), 'edit: a two-key look is encoded with %20 (never +) and the preview range rides along', pv2);
  await page.waitForTimeout(700);
  ok(bridge.canvas.entered[0] && bridge.canvas.entered[0].rel === rel0 && bridge.canvas.entered[0].model === 'ILCE-7M4' && bridge.canvas.entered[0].next && bridge.canvas.entered[0].preview && +bridge.canvas.entered[0].preview.l > 0,
    'edit: canvasEnter carries the photo, its body, its preview range and its neighbours', bridge.canvas.entered[0]);
  ok(bridge.canvas.layouts[0] && bridge.canvas.layouts[0].w === 900 && bridge.canvas.layouts[0].visible === true && bridge.canvas.layouts[0].dpr >= 1, 'edit: canvasLayout carries the rect, visibility and dpr', bridge.canvas.layouts[0]);
  { const vh = await page.evaluate(() => window.innerHeight), L0 = bridge.canvas.layouts[0];
    ok(L0 && L0.vh === vh && vh > 0, 'edit: canvasLayout carries the page viewport height, so the Mac places the canvas below a title bar the web view keeps out of the page', { vh, sent: L0 && L0.vh }); }
  // Page chrome over the photo rides along as `holes`, on the rect or in the options; a hidden canvas sends none.
  { const n0 = bridge.canvas.layouts.length, hole = { x: 110, y: 60, w: 40, h: 20 };
    await page.evaluate(h => { const r = Object.assign({}, lumina.edit.state().rect); lumina.canvasRect(Object.assign({}, r, { holes: [h] })); lumina.edit.layout(r, true, { holes: [h, h] }); lumina.edit.layout(r, true); }, hole);
    await page.waitForTimeout(100);
    const L = bridge.canvas.layouts.slice(n0);
    ok(L.length === 3 && L[0].holes.length === 1 && L[0].holes[0].w === 40 && L[1].holes.length === 2 && Array.isArray(L[2].holes) && L[2].holes.length === 0 && L[2].w === 900 && L[2].visible === true,
      'edit: canvasLayout carries the page chrome over the photo as holes, and none when the page names none', L); }
  ok(hooks.images.length === 1 && hooks.images[0].tier === 'base' && /\/render\/2026-09-01\/DSC01001\.ARW\?/.test(hooks.images[0].url), 'edit (image path): entering loads one full-quality image (an <img>, no CORS) and hands its URL to luminaEditImage', hooks.images);
  ok(bridge.renders.length >= 1 && bridge.renders[0].look === 'ev:+0.50 shp:40' && bridge.renders[0].px === 900 && bridge.renders[0].decoder === 8, 'edit (image path): the render asks for the look at the canvas size with the canvas decoder', bridge.renders[0]);
  // A 2 s drag: 60 looks at ~25 ms, renders slower than that (60 ms): only the newest value is fetched,
  // at the small tier, one at a time; drag end brings one full-quality render of the last value.
  bridge.renders = []; bridge.renderDelayMs = 60;
  await page.waitForTimeout(2300);            // let the 2 s autosave flush what came before
  const savesBefore = bridge.saves || 0;
  const mid = await page.evaluate(async () => {
    window.__editImages = [];
    lumina.edit.dragStart();
    const l = __lumina.logic();
    for (let i = 1; i <= 60; i++) {
      const look = 'ev:' + (i / 100).toFixed(2);
      l.setState({ look: Object.assign({}, l.state.look, { [l.state.cur]: look }) });      // as the page's slider does
      lumina.edit.look(look, { drag: true }); await new Promise(r => setTimeout(r, 25));
    }
    return lumina.edit.state();
  });
  // Counted while the thumb is still down: the write is due 500 ms after the last change, so a
  // count taken 500 ms after the drag ends races the debounce itself (it lost on a slow runner).
  const savesInDrag = bridge.saves || 0;
  const drag = await page.evaluate(async (mid) => {
    lumina.edit.dragEnd();
    // Shorter than the 500 ms debounce: the save that follows a drag must not land before the
    // "no session write during the drag" check below reads the count (the rest render needs ~250 ms).
    await new Promise(r => setTimeout(r, 400));
    return { mid, end: lumina.edit.state(), images: window.__editImages.slice() };
  }, mid);
  const dragRenders = bridge.renders.filter(r => r.tier === 'small'), restRenders = bridge.renders.filter(r => r.tier === 'base');
  ok(dragRenders.length >= 8 && dragRenders.length <= 45, 'edit (image path): a 2 s drag of 60 values renders the newest value at most once per render, at the small tier', { small: dragRenders.length, total: bridge.renders.length });
  ok(dragRenders.every(r => r.px === Math.round(900)), 'edit (image path): small tier renders ask the canvas size with tier=small (the Mac quarters it)', dragRenders.slice(0, 2));
  ok(restRenders.length >= 1 && restRenders[restRenders.length - 1].look === 'ev:0.60 shp:40', 'edit (image path): drag end renders the final value at full quality', restRenders);
  ok(drag.end.image.tier === 'base' && drag.end.image.shown === drag.end.seq && !drag.end.image.inFlight && !drag.end.image.pending, 'edit (image path): the last shown image is the newest seq at the base tier, nothing left in flight', drag.end.image);
  ok(drag.images.length && drag.images.every((im, i) => i === 0 || im.seq > drag.images[i - 1].seq), 'edit (image path): images reach the page in increasing seq only (latest wins)', drag.images.map(i => i.seq));
  ok(bridge.renders.every((r, i) => i === 0 || r.t >= bridge.renders[i - 1].t + 55), 'edit (image path): renders never overlap (one in flight)', bridge.renders.slice(0, 3).map(r => r.t));
  ok(drag.mid.dragging === true && drag.end.dragging === false && bridge.canvas.drags.join() === 'true,false,true,false', 'edit: drag(start/end) and dragStart / dragEnd reach the Mac', bridge.canvas.drags);
  ok(savesInDrag === savesBefore, 'edit: no session write during the drag (500 ms debounce)', { before: savesBefore, after: savesInDrag });
  await page.waitForTimeout(2600);
  ok((bridge.saves || 0) > savesBefore, 'edit: the session is written after the drag settles', { before: savesBefore, after: bridge.saves });
  // Keystroke: a full-quality render at once, no small tier. Loupe: reaches the Mac with its region.
  bridge.renders = []; bridge.renderDelayMs = 0;
  await page.evaluate(async () => { lumina.edit.look('ev:+1.00', { key: true }); lumina.edit.loupe(true, { x: 0.25, y: 0.25, w: 0.5, h: 0.5 }); await new Promise(r => setTimeout(r, 200)); });
  ok(bridge.renders.length === 1 && bridge.renders[0].tier === 'base' && bridge.renders[0].look === 'ev:+1.00 shp:40', 'edit (image path): a keystroke renders once at full quality', bridge.renders);
  ok(bridge.canvas.loupes[0] && bridge.canvas.loupes[0].on === true && bridge.canvas.loupes[0].roi.w === 0.5, 'edit: loupe on with its region reaches the Mac (RAW 9 region)', bridge.canvas.loupes[0]);
  await page.evaluate(() => { lumina.roi({ x: 0.1, y: 0.1, w: 0.3, h: 0.3 }); lumina.roi(null); });
  ok(bridge.canvas.loupes.length === 3 && bridge.canvas.loupes[1].on === true && bridge.canvas.loupes[1].roi.x === 0.1 && bridge.canvas.loupes[2].on === false, 'edit: lumina.roi(region) / roi(null) drive the RAW 9 region', bridge.canvas.loupes.slice(1));
  const upd = await page.evaluate(async () => { const f = await lumina.edit.updateDecoder(); const s = await lumina.edit.stats(true); return { f, s }; });
  ok(upd.f.decoder === '8' && bridge.canvas.updates === 1 && bridge.canvas.resets === 1 && upd.s.path === 'image', 'edit: updateDecoder pins the newest; stats(reset) reaches the Mac', upd);
  await page.evaluate(() => { __lumina.editFacts('canvas: image · image file · raw 8 · region'); });
  ok(await page.evaluate(() => /raw 8 · region$/.test(lumina.edit.facts().text) && lumina.edit.facts().note === 'raw 8 · region'), 'edit: the Mac\'s facts (region, refining) join the facts line as the note', await page.evaluate(() => lumina.edit.facts()));
  const hist = await page.evaluate(() => { window.__hist = []; window.__pres = []; window.luminaHistogram = h => window.__hist.push(h); window.luminaPresented = s => window.__pres.push(s);
    __lumina.editStats({ seq: 12, histogram: { r: [1, 2], g: [3, 4], b: [5, 6] }, clipHi: 0.01, clipLo: 0.02, source: 'jpeg' }); __lumina.editPresented(12); return { h: window.__hist, p: window.__pres }; });
  ok(hist.h.length === 1 && hist.h[0].seq === 12 && hist.h[0].r[1] === 2 && hist.h[0].clipHi === 0.01 && hist.p[0] === 12, 'edit: luminaHistogram({seq, r, g, b, clipHi, clipLo}) and luminaPresented(seq) reach the page', hist);
  // The page's white balance rests on its own as-shot pair: it rides along as wbref, the same in the
  // render URL, the canvas and the JPEG export; a look without shp is the page's 40.
  const wbRef = await page.evaluate(rel => { const p = Object.values(__lumina.logic().data.byId).find(q => q.path === rel); return Math.round(+p.wbK || 5500) + '/' + ((t => (t > 0 ? '+' : '') + t)(p.wbTint != null ? Math.round(+p.wbTint) : 0)); }, rel0);
  const pvWb = await page.evaluate(rel => decodeURIComponent(lumina.preview(rel, 'wb:6600/+3 shp:20', 900, 60).split('look=')[1].split('&')[0]), rel0);
  ok(pvWb === 'wb:6600/+3 shp:20 wbref:' + wbRef, 'edit: a moved white balance carries the page\'s as-shot pair (wbref); an explicit shp stays', { pvWb, wbRef });
  // Once the canvas has read the RAW's as-shot pair, the page's White balance rests on it, and so does wbref.
  const pvShot = await page.evaluate(rel => { lumina.edit.header({ asShot: { kelvin: 4800, tint: 7 }, asShotRel: rel }); return decodeURIComponent(lumina.preview(rel, 'wb:6600/+3', 900, 61).split('look=')[1].split('&')[0]); }, rel0);
  ok(pvShot === 'wb:6600/+3 wbref:4800/+7 shp:40', 'edit: after the canvas reads the as-shot pair, wbref is that pair', pvShot);
  // Prompt 1 §7: writeInto(files, 'jpeg') renders natively with the body's pinned decoder.
  const jp = await page.evaluate(rel => __lumina.logic().writeInto([{ name: 'JPEG/DSC01001.jpg', look: { src: rel, look: 'ev:+0.50', px: 2048 } }], 'jpeg'), rel0);
  ok(jp && jp.n === 1 && jp.decoder === 'RAW 8' && bridge.jpegItems && bridge.jpegItems[0].look.model === 'ILCE-7M4' && bridge.jpegItems[0].look.px === 2048 && bridge.jpegItems[0].look.look === 'ev:+0.50 shp:40', 'edit: writeInto(files, "jpeg") reaches the Mac with the look, size and body; the result names the decoder', { jp, items: bridge.jpegItems });
  await page.evaluate(() => { lumina.edit.leave(); delete window.luminaEditImage; delete window.luminaEditFacts; });
  ok(bridge.canvas.entered.some(e => e.leave) && (await page.evaluate(() => lumina.edit.state().rel)) === null && bridge.canvas.layouts[bridge.canvas.layouts.length - 1].visible === false, 'edit: leave hides the canvas and tells the Mac');
  ok((await page.evaluate(() => { try { lumina.edit.look('ev:+0.10', { drag: true }); lumina.edit.dragEnd(); return true; } catch (e) { return String(e); } })) === true, 'edit: calls after leave are harmless no-ops');

  // The native canvas and a photo's first look (the "rendering…" that never left on the first entry
  // into Edit): the photo and the page's first look go to the Mac together, so the frame that shows
  // it is acknowledged with the page's seq; looks that follow wait until the Mac has the photo. A
  // photo the Mac refuses is answered at once with the reason in the facts line. The page never
  // draws its own preview on the native path: lumina.preview answers null, never false.
  { bridge.canvas.path = 'native'; bridge.header = Object.assign({}, bridge.header, { canvas: 'native' }); bridge.canvas.enterMs = 300;
    const rels = await page.evaluate(() => __lumina.logic().real.slice(0, 3).map(p => p.path));
    const e0 = bridge.canvas.entered.length, k0 = bridge.canvas.looks.length, a0 = bridge.canvas.answered || 0;
    const first = await page.evaluate(async rel => {
      __lumina.editHeader({ canvas: 'native' });
      window.__shown = []; window.luminaPresented = s => window.__shown.push(s); window.__facts = []; window.luminaFacts = f => window.__facts.push(f);
      lumina.canvasRect({ x: 300, y: 80, w: 900, h: 600, holes: [] });
      const r = lumina.preview(rel, 'ev:+0.10', 1800, 7);            // the page's first look for the photo
      const sync = r && typeof r.then === 'function' ? 'promise' : r;
      lumina.preview(rel, 'ev:+0.20', 1800, 8); lumina.preview(rel, 'ev:+0.30', 1800, 9);   // while the Mac is still entering
      return { sync, v: await r, st: lumina.edit.state() };
    }, rels[0]);
    await new Promise(r => setTimeout(r, 100));
    const ent = bridge.canvas.entered.slice(e0).filter(x => !x.leave), looks = bridge.canvas.looks.slice(k0);
    ok(first.sync === 'promise' && first.v === null && ent.length === 1 && ent[0].rel === rels[0] && ent[0].seq === 7 && ent[0].look === 'ev:+0.10 shp:40',
      'edit (native): a photo\'s first look goes with canvasEnter, with the page\'s seq; lumina.preview answers null', { first, ent });
    ok(looks.length === 1 && looks[0].seq === 9 && looks[0].look === 'ev:+0.30 shp:40' && looks[0].answered > a0,
      'edit (native): looks sent while the Mac enters the photo wait; the newest goes once it has', looks);
    bridge.canvas.enterMs = 0; bridge.canvas.refuse = 'not in an opened folder';
    const l0 = bridge.canvas.layouts.length, k1 = bridge.canvas.looks.length;
    const bad = await page.evaluate(async rel => {
      window.__shown = []; window.__facts = [];
      const v = await lumina.preview(rel, 'ev:+0.10', 1800, 11);
      const again = lumina.preview(rel, 'ev:+0.20', 1800, 12);
      await new Promise(r => setTimeout(r, 50));
      return { v, again, shown: window.__shown.slice(), text: lumina.edit.facts().text, seen: window.__facts[window.__facts.length - 1], visible: lumina.edit.state().visible };
    }, rels[1]);
    ok(bad.v === null && bad.again === null && bad.shown.join() === '11,12' && bad.visible === true && !bridge.canvas.layouts.slice(l0).some(l => l.visible === false) && bridge.canvas.looks.length === k1,
      'edit (native): a photo canvasEnter refuses is answered (no frame to wait for); the page is not told to draw its own preview and the canvas stays', bad);
    ok(/can't show [^ ]+ · not in an opened folder/.test(bad.text) && bad.seen && /not in an opened folder/.test(bad.seen.note || ''), 'edit (native): the facts line says why the photo is not on the canvas', bad);
    bridge.canvas.refuse = null;
    const good = await page.evaluate(async rel => { const v = await lumina.preview(rel, '', 1800, 13); return { v, text: lumina.edit.facts().text }; }, rels[2]);
    ok(good.v === null && !/can't show/.test(good.text) && bridge.canvas.entered[bridge.canvas.entered.length - 1].seq === 13, 'edit (native): the next photo enters as usual and the reason is gone', good);
    await page.evaluate(() => { lumina.edit.leave(); delete window.luminaPresented; delete window.luminaFacts; __lumina.editHeader({ canvas: 'image' }); });
    bridge.header = Object.assign({}, bridge.header, { canvas: 'image' });
    bridge.canvas.path = 'image'; }

  // Edit v22 through the page itself (not lumina.edit): it names a photo by its file name, so plumbing's
  // editShoot gives each photo its path; the chrome over the photo becomes holes; the RAW's as-shot
  // white balance reaches the page's photo.
  { const e0 = bridge.canvas.entered.length, l0 = bridge.canvas.layouts.length;
    await page.evaluate(() => __lumina.logic().setView('edit', true));
    await page.waitForTimeout(1500);
    const ent = bridge.canvas.entered.slice(e0).filter(x => !x.leave);
    const rels = await page.evaluate(() => __lumina.logic().real.map(p => (__lumina.logic().state.realInfo.name || '') + '/' + p.path.split('/').slice(1).join('/')));
    ok(ent.length >= 1 && rels.includes(ent[0].rel) && ent[0].model === 'ILCE-7M4', 'edit v22 (page): opening Edit enters the canvas with the photo\'s path in the folder', { ent: ent.slice(0, 1), rel: rels[0] });
    const pv = await page.evaluate(() => (window.luminaShoot ? window.luminaShoot().P : []).slice(0, 2).map(p => p.rel));
    ok(pv.length === 2 && pv.every(r => rels.includes(r)), 'edit v22 (page): luminaShoot photos carry rel', pv);
    const L = bridge.canvas.layouts.slice(l0).filter(x => x.visible), last = L[L.length - 1];
    const inside = h => h.x >= last.x && h.y >= last.y && h.x + h.w <= last.x + last.w && h.y + h.h <= last.y + last.h;
    ok(last && Array.isArray(last.holes) && last.holes.length >= 1 && last.holes.length <= 16 && last.holes.every(inside) && last.holes.every(h => h.w * h.h < 0.6 * last.w * last.h),
      'edit v22 (page): the chrome over the photo (the zoom pill) is sent as holes inside the rect, nothing full-size', last && last.holes);
    // A chip appearing without the rect changing sends the holes again.
    const n1 = bridge.canvas.layouts.length;
    await page.evaluate(() => { const d = document.createElement('div'); d.id = '__chip'; d.style.cssText = 'position:absolute;left:12px;top:12px;width:60px;height:24px'; document.querySelector('[data-lumina="canvas"]').appendChild(d); });
    await page.waitForTimeout(300);
    const L2 = bridge.canvas.layouts.slice(n1);
    ok(L2.length >= 1 && L2[L2.length - 1].visible && L2[L2.length - 1].holes.length === last.holes.length + 1, 'edit v22 (page): a chip that appears over the photo is sent as one more hole', L2.map(x => x.holes));
    await page.evaluate(() => document.getElementById('__chip').remove()); await page.waitForTimeout(300);
    // As-shot white balance from the canvas (the base landed): the page's photo starts there.
    const shot = await page.evaluate(rel => {
      __lumina.editHeader({ asShot: { kelvin: 4321, tint: 7 }, asShotRel: rel });
      const el = document.querySelector('[data-lumina="canvas"]'), k = Object.keys(el).find(x => x.startsWith('__reactFiber$'));
      let E = null; for (let f = el[k]; f && !E; f = f.return) if (f.stateNode && f.stateNode.logic && f.stateNode.logic.nbInfo) E = f.stateNode.logic;
      const p = Object.values(E.data.byId).find(q => q.rel === rel), q = window.luminaShoot().P.find(x => x.rel === rel);
      return { page: p && [p.wbShot, p.tintShot], shoot: q && [q.wbShot, q.tintShot], def: p && E.def('wb', p) };
    }, ent[0] && ent[0].rel);
    ok(shot.page && shot.page[0] === 4321 && shot.page[1] === 7 && shot.shoot[0] === 4321 && shot.def === 4321, 'edit v22 (page): the RAW\'s as-shot white balance becomes the photo\'s wbShot / tintShot (Edit and later opens)', shot);
    await page.evaluate(() => __lumina.editHeader({ asShot: { kelvin: 'x', tint: 1 }, asShotRel: 'nope' }));
    // The page's own zoom (pinch, the zoom pill): the part of the photo in the canvas box reaches the Mac
    // at every zoom, as fractions of the photo's box; none at fit. Edit v22's lumina.roi (image px, above
    // 1.2× only) does not place the picture.
    { const zoomTo = z => page.evaluate(z => {
        const el = document.querySelector('[data-lumina="canvas"]'), k = Object.keys(el).find(x => x.startsWith('__reactFiber$'));
        let E = null; for (let f = el[k]; f && !E; f = f.return) if (f.stateNode && f.stateNode.logic && f.stateNode.logic.nbInfo) E = f.stateNode.logic;
        E.zoomTo(z, null, null, false);
      }, z);
      const box = () => page.evaluate(() => { const c = document.querySelector('[data-lumina="canvas"]').getBoundingClientRect(), b = document.querySelector('[data-lumina="canvas"] [data-lumina-img]').parentElement.getBoundingClientRect(); return { x: (c.left - b.left) / b.width, y: (c.top - b.top) / b.height, w: c.width / b.width, h: c.height / b.height }; });
      const near = (a, b) => !!a && !!b && ['x', 'y', 'w', 'h'].every(k => Math.abs(a[k] - b[k]) < 0.01);
      const z0 = bridge.canvas.zooms.length, lp0 = bridge.canvas.loupes.length;
      await zoomTo(3); await page.waitForTimeout(700);
      const in3 = bridge.canvas.zooms[bridge.canvas.zooms.length - 1], b3 = await box();
      ok(bridge.canvas.zooms.length > z0 && in3 && in3.w < 0.6 && in3.h < 0.6 && near(in3, b3), 'edit v22 (page): zoomed in, the canvas box as a part of the photo reaches the Mac (canvasZoom)', { sent: in3, page: b3 });
      { const R = bridge.canvas.zoomRests.slice(z0);
        ok(R.length >= 2 && R[0] === false && R[R.length - 1] === true && R.filter(Boolean).length === 1, 'edit v22 (page): a moving zoom is followed, then the Mac is told once that it rests (its full-quality render)', R); }
      const lp = bridge.canvas.loupes.slice(lp0).filter(l => l.on), st =await page.evaluate(() => lumina.edit.state());
      ok(lp.length === 1 && near(lp[0].roi, in3) && near(st.zoom, in3), 'edit v22 (page): once the zoom rests, the same region goes to RAW 9, once, in fractions (not the page\'s image px)', { loupes: bridge.canvas.loupes.slice(lp0), zoom: st.zoom });
      await zoomTo(1.1); await page.waitForTimeout(500);
      const in11 = bridge.canvas.zooms[bridge.canvas.zooms.length - 1];
      ok(in11 && near(in11, await box()) && in11.w > 0.5, 'edit v22 (page): between fit and 1.2× the canvas follows too', in11);
      await zoomTo(0.5); await page.waitForTimeout(500);
      const out = bridge.canvas.zooms[bridge.canvas.zooms.length - 1];
      ok(out && out.w > 1 && out.h > 1 && out.x < 0 && out.y < 0 && near(out, await box()), 'edit v22 (page): zoomed out, the region reaches beyond the photo', out);
      await zoomTo(1); await page.waitForTimeout(500);
      ok(bridge.canvas.zooms[bridge.canvas.zooms.length - 1] === null && (await page.evaluate(() => lumina.edit.state().zoom)) === null, 'edit v22 (page): back at fit, no region (the Mac fits the photo)', bridge.canvas.zooms.slice(-2)); }
    const n2 = bridge.canvas.layouts.length;
    await page.evaluate(() => __lumina.logic().setView('cull')); await page.waitForTimeout(500);
    const L3 = bridge.canvas.layouts.slice(n2);
    ok(L3.length >= 1 && L3[L3.length - 1].visible === false, 'edit v22 (page): leaving Edit hides the canvas', L3); }

  // Save → sidecars INTO the folder
  const before2 = fs.readFileSync(path.join(shoot, 'DSC01002.xmp'), 'utf8');
  await page.evaluate(() => __lumina.command('stepSave')); await page.waitForTimeout(300);
  ok((await S(page)).view === 'export', 'save: ⌘4 via luminaCommand');
  await page.waitForTimeout(900);            // the page ignores ⌘⏎ for 800 ms after a step change
  await page.evaluate(() => __lumina.command('save'));
  // v8's Save guard: rows not looked at this pass arm ⌘⏎ once; the second ⌘⏎ saves.
  if (await page.evaluate(() => __lumina.logic().state.armed === 'save')) await page.evaluate(() => __lumina.command('save'));
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

  // Scrolling while a folder is read, and keys typed fast. The page's own scroll handler still runs
  // under plumbing's lead (the time axis follows the scroll); the grid is never rebuilt under a moving
  // scroll; tiles that scrolled in keep the page's fade for later changes; a menu shortcut runs after
  // the keys still queued.
  await page.evaluate(() => __lumina.closeShoot()); await page.waitForTimeout(200);
  bridge.delayMs = 120; bridge.pending = slow; await page.evaluate(() => __lumina.openFolder());
  await page.waitForFunction(() => { const l = __lumina.logic(); return l.state.view === 'cull' && l.state.realLoad && l.real && l.real.length >= 48; }, null, { timeout: 60000 });
  const SCROLL = async ([frames, dy]) => {
    const l = __lumina.logic(), el = l.scrollRef.current; let data = l.data, under = 0, axOff = 0, axN = 0, moved = -1e9, top = el.scrollTop;
    for (let i = 0; i < frames; i++) {
      el.scrollTop += dy; await new Promise(r => requestAnimationFrame(r));
      const now = performance.now(); if (el.scrollTop !== top) { top = el.scrollTop; moved = now; }
      if (l.data !== data) { data = l.data; if (l.state.realLoad && now - moved < 400) under++; }
      const ax = l.axInRef && l.axInRef.current; if (ax) { axN++; const m = /translate3d\(0(?:px)?,\s*(-?[\d.]+)px/.exec(ax.style.transform || ''); if (!m || Math.abs(+m[1] + el.scrollTop) > 1) axOff++; }
    }
    return { under, axOff, axN, reading: !!l.state.realLoad };
  };
  const sr = await page.evaluate(SCROLL, [150, 4]);
  ok(sr.reading, 'scroll during read: the folder was still being read', sr);
  ok(sr.under === 0, 'scroll during read: the grid is not rebuilt under a moving scroll', sr);
  ok(sr.axN > 0 && sr.axOff === 0, 'scroll during read: the time axis follows the scroll every frame', sr);
  bridge.delayMs = 0; await loaded(page); await page.waitForTimeout(600);
  await page.evaluate(() => { __lumina.logic().scrollRef.current.scrollTop = 0; }); await page.waitForTimeout(400);
  const sa = await page.evaluate(SCROLL, [40, 90]);
  ok(sa.axN > 0 && sa.axOff === 0, 'scroll: the time axis follows the scroll every frame', sa);
  await page.waitForTimeout(800);
  const fades = await page.evaluate(() => { const im = Array.from(__lumina.logic().scrollRef.current.querySelectorAll('img')); return { n: im.length, none: im.filter(i => i.style.transition === 'none').length }; });
  ok(fades.n > 0 && fades.none === 0, 'scroll: tiles that scrolled in keep the page\'s fade (brightness, opacity) once shown', fades);
  const order = await page.evaluate(async () => {
    const l = __lumina.logic(); l.setState({ marks: {}, undo: [], cur: l.data.order[0] }); await new Promise(r => setTimeout(r, 300));
    const d = (key, code) => dispatchEvent(new KeyboardEvent('keydown', { key, code, bubbles: true })), a = l.state.cur;
    d('p', 'KeyP'); d('ArrowRight', 'ArrowRight'); d('ArrowRight', 'ArrowRight'); d('p', 'KeyP');
    const queued = (l._kq || []).length; __lumina.command('undo'); await new Promise(r => setTimeout(r, 600));
    dispatchEvent(new KeyboardEvent('keyup', { key: 'p', code: 'KeyP', bubbles: true }));
    return { queued, firstKept: l.state.marks[a] === 'keep', kept: l.kept().length };
  });
  ok(order.queued > 0 && order.firstKept && order.kept === 1, 'keys: menu Undo runs after the keys still queued (undoes the last keep)', order);

  // T4: a sidecar another app rewrote between open and Save. Save merges the rating onto the text on
  // disk NOW (the page's own xmpFor, on text re-read by the Mac), never onto the text from the open.
  const lr = path.join(tmp, '2026-09-03');
  const lrXmp = (crs, rating) => '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"' + (rating == null ? '' : ' xmp:Rating="' + rating + '"') + ' crs:HasSettings="True" ' + crs + '/></rdf:RDF></x:xmpmeta>\n';
  const atOpen = { 'DSC01001.xmp': lrXmp('crs:Exposure2012="+0.10"', 1), 'DSC01003.xmp': lrXmp('crs:Exposure2012="+0.30"', 2), 'DSC01004.xmp': lrXmp('crs:Exposure2012="+0.40"', 0) };
  makeShoot(lr, jpegs.slice(0, 4), { sidecars: atOpen });
  const lrFile = n => path.join(lr, n), lrRead = n => fs.readFileSync(lrFile(n), 'utf8');
  bridge.delayMs = 0; bridge.pending = lr; await page.evaluate(() => __lumina.openFolder());
  await loaded(page); await page.waitForTimeout(300);
  await page.evaluate(() => { const l = __lumina.logic(); l.setState({ marks: Object.fromEntries(l.data.order.map(id => [id, 'keep'])) }); });
  ok((await page.evaluate(() => __lumina.logic().kept().length)) === 4, 'stale sidecar: 4 keepers');
  // After the open, "Lightroom" saves new develop settings into one sidecar, makes one where there was
  // none, and one is deleted. The fourth is untouched.
  const newer1 = lrXmp('crs:Exposure2012="+1.50" crs:Contrast2012="+20"', 1), made2 = lrXmp('crs:Exposure2012="-0.70" crs:Shadows2012="+35"', null);
  fs.writeFileSync(lrFile('DSC01001.xmp'), newer1); fs.writeFileSync(lrFile('DSC01002.xmp'), made2); fs.rmSync(lrFile('DSC01003.xmp'));
  const save = async () => {
    await page.evaluate(() => { const l = __lumina.logic(); l.exSet({ result: null }); return l.runExport(); });
    await page.waitForFunction(() => { const r = __lumina.logic().state.ex; return r && r.result; }, null, { timeout: 5000 }).catch(() => {});
    return page.evaluate(() => __lumina.logic().state.ex.result);
  };
  let sres = await save();
  ok(sres && sres.t === '4 saved' && !sres.bad, 'stale sidecar: result "4 saved"', sres);
  ok(lrRead('DSC01001.xmp') === newer1.replace('xmp:Rating="1"', 'xmp:Rating="3"'), 'stale sidecar: changed since the open → the other app\'s newer settings survive, only the rating differs', lrRead('DSC01001.xmp'));
  ok(!/\+0\.10/.test(lrRead('DSC01001.xmp')), 'stale sidecar: the text from the open is never written back');
  ok(fs.existsSync(lrFile('DSC01001.xmp.lumina-bak')) && lrRead('DSC01001.xmp.lumina-bak') === newer1, 'stale sidecar: .lumina-bak is the file as it was just before Lumina wrote');
  ok(/crs:Exposure2012="-0\.70"/.test(lrRead('DSC01002.xmp')) && /crs:Shadows2012="\+35"/.test(lrRead('DSC01002.xmp')) && /xmp:Rating="3"/.test(lrRead('DSC01002.xmp')), 'stale sidecar: made since the open → merged, not replaced by a fresh one', lrRead('DSC01002.xmp'));
  ok(fs.existsSync(lrFile('DSC01002.xmp.lumina-bak')) && lrRead('DSC01002.xmp.lumina-bak') === made2, 'stale sidecar: made since the open → kept as .lumina-bak');
  ok(/xmp:Rating="3"/.test(lrRead('DSC01003.xmp')) && !/Exposure2012/.test(lrRead('DSC01003.xmp')), 'stale sidecar: deleted since the open → a fresh sidecar, the deleted text does not come back', lrRead('DSC01003.xmp'));
  ok(lrRead('DSC01004.xmp') === atOpen['DSC01004.xmp'].replace('xmp:Rating="0"', 'xmp:Rating="3"'), 'stale sidecar: untouched since the open → merged as before', lrRead('DSC01004.xmp'));
  ok(await page.evaluate(() => { const l = __lumina.logic(), p = Object.values(l.data.byId).find(p => p.file === 'DSC01002.ARW'); return p.lrEd === true && /Shadows2012/.test(p.xmp || ''); }), 'stale sidecar: the page\'s photo carries the text on disk');
  ok(bridge.calls.includes('readSidecars') && bridge.calls.lastIndexOf('readSidecars') < bridge.calls.lastIndexOf('writeSidecars'), 'stale sidecar: the Mac reads the sidecars, then writes them');
  // The other app writes again in the instant between plumbing's re-read and the Mac's write: the Mac
  // leaves that file alone (it is no longer the base of the merge) and the result list says so.
  // Nothing is retried silently; the next Save reads it again.
  const racy = lrXmp('crs:Exposure2012="+2.00"', 1);
  let races = 0; bridge.beforeSidecar = dest => { if (path.basename(dest) === 'DSC01004.xmp') { fs.writeFileSync(dest, racy); races++; } };
  sres = await save();
  ok(sres && sres.t === '3 saved · 1 failed' && sres.bad && JSON.stringify(sres.errs) === JSON.stringify([{ name: 'DSC01004', reason: 'changed on disk' }]), 'stale sidecar: changed during Save → "DSC01004 · changed on disk" in the result list', sres);
  ok(races === 1 && lrRead('DSC01004.xmp') === racy, 'stale sidecar: changed during Save → the file is byte for byte the other app\'s', { races, text: lrRead('DSC01004.xmp') });
  bridge.beforeSidecar = null;
  sres = await save();
  ok(sres && sres.t === '4 saved' && !sres.bad, 'stale sidecar: the next Save reads it again', sres);
  ok(lrRead('DSC01004.xmp') === racy.replace('xmp:Rating="1"', 'xmp:Rating="3"'), 'stale sidecar: the next Save → the newest settings survive, rating set', lrRead('DSC01004.xmp'));
  await page.evaluate(() => __lumina.closeShoot()); await page.waitForTimeout(200);

  // Q4-F5: a sidecar that is there but is not UTF-8 text (Lightroom's settings in Latin-1, a UTF-16
  // file). The listing names it (unreadableXmp) instead of leaving it out, the page counts it with its
  // unreadable files, and Save leaves it byte for byte as it is: no fresh ratings-only sidecar over it.
  const odd = path.join(tmp, '2026-09-04');
  const latin1 = Buffer.from(lrXmp('crs:Exposure2012="+0.50" xmp:Label="café"', 2), 'latin1');      // é as the single byte 0xE9
  const utf16 = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(lrXmp('crs:Contrast2012="+15"', 4), 'utf16le')]);
  const plain = lrXmp('crs:Exposure2012="+0.25"', 1);
  makeShoot(odd, jpegs.slice(0, 4), { sidecars: { 'DSC01001.xmp': plain, 'DSC01002.xmp': latin1, 'DSC01003.XMP': utf16 } });
  const oddBytes = n => fs.readFileSync(path.join(odd, n));
  bridge.pending = odd; await page.evaluate(() => __lumina.openFolder());
  await loaded(page); await page.waitForTimeout(300);
  s = await S(page);
  ok(s.n === 4 && s.realInfo.n === 4 && s.realInfo.bad === 2, 'unreadable sidecar: 4 photos read, the 2 sidecars that are not text counted with the unreadable files', s.realInfo);
  const oddSeen = await page.evaluate(() => { const l = __lumina.logic(); return { failed: l._failed, photos: l.real.map(p => ({ name: p.name, xpath: p.xpath, xmp: p.xmp == null ? null : p.xmp.length, lrEd: !!p.lrEd })) }; });
  ok(JSON.stringify(oddSeen.failed) === JSON.stringify([{ name: 'DSC01002.xmp', reason: 'sidecar unreadable, not read' }, { name: 'DSC01003.XMP', reason: 'sidecar unreadable, not read' }]), 'unreadable sidecar: both named in the page\'s list', oddSeen.failed);
  ok(oddSeen.photos.find(p => p.name === 'DSC01002.ARW').xmp === null && oddSeen.photos.find(p => p.name === 'DSC01003.ARW').xpath === '2026-09-04/DSC01003.XMP' && oddSeen.photos.find(p => p.name === 'DSC01001.ARW').xmp === plain.length,
    'unreadable sidecar: no text reaches the page; the photo keeps the sidecar\'s own path (.XMP), so Save aims at that file', oddSeen.photos);
  await page.evaluate(() => { const l = __lumina.logic(); l.setState({ marks: Object.fromEntries(l.data.order.map(id => [id, 'keep'])) }); });
  sres = await save();
  ok(sres && sres.t === '2 saved · 2 failed' && sres.bad && JSON.stringify(sres.errs) === JSON.stringify([{ name: 'DSC01002', reason: 'unreadable' }, { name: 'DSC01003', reason: 'unreadable' }]),
    'unreadable sidecar: Save reports "DSC01002 · unreadable" and "DSC01003 · unreadable"', sres);
  ok(oddBytes('DSC01002.xmp').equals(latin1) && oddBytes('DSC01003.XMP').equals(utf16), 'unreadable sidecar: both files are byte for byte the other app\'s');
  const oddFiles = fs.readdirSync(odd).filter(n => /xmp/i.test(n)).sort();
  ok(JSON.stringify(oddFiles) === JSON.stringify(['DSC01001.xmp', 'DSC01001.xmp.lumina-bak', 'DSC01002.xmp', 'DSC01003.XMP', 'DSC01004.xmp']), 'unreadable sidecar: no backup made for them, no second sidecar beside the .XMP, the readable ones saved as usual', oddFiles);
  ok(fs.readFileSync(path.join(odd, 'DSC01001.xmp'), 'utf8') === plain.replace('xmp:Rating="1"', 'xmp:Rating="3"'), 'unreadable sidecar: the readable sidecar is merged as before');
  // The other app saves it again as UTF-8: the next Save reads it and merges the rating into it.
  const fixed = lrXmp('crs:Exposure2012="+0.50" xmp:Label="café"', 2);
  fs.writeFileSync(path.join(odd, 'DSC01002.xmp'), fixed);
  sres = await save();
  ok(sres && sres.t === '3 saved · 1 failed' && fs.readFileSync(path.join(odd, 'DSC01002.xmp'), 'utf8') === fixed.replace('xmp:Rating="2"', 'xmp:Rating="3"'), 'unreadable sidecar: once it is text again, the next Save merges into it', sres);
  await page.evaluate(() => __lumina.closeShoot()); await page.waitForTimeout(200);

  // S9: awkward folder and file names. Every path the page or plumbing puts into a URL (head, preview,
  // render, prefetch) or a message (near, canvasEnter, reveal, sidecars, session) must name the same
  // file. The stand-in decodes queries strictly (a '+' stays a '+'), so a URL built with URLSearchParams
  // fails here. NFD: 'é' as e + combining accent, as APFS can hand a name back.
  const NFD = 'Café', AWK = 'Shoot 2026 #1 & 50% (é) + more';
  const awk = path.join(tmp, AWK);
  makeShoot(awk, jpegs);
  const awkNames = { 'DSC01003.ARW': 'a+b=c?d&e#f 50%41.ARW', 'DSC01004.ARW': NFD + '.ARW', 'DSC01005.ARW': 'x %2B y.ARW' };
  for (const [a, b] of Object.entries(awkNames)) fs.renameSync(path.join(awk, a), path.join(awk, b));
  fs.renameSync(path.join(awk, 'sub'), path.join(awk, NFD + ' ?='));
  bridge.delayMs = 0; bridge.pending = awk; bridge.renders = []; bridge.revealed = []; bridge.nears = []; bridge.canvas.entered = [];
  bridge.prefetches = [];
  await page.evaluate(() => __lumina.openFolder());
  await loaded(page).catch(() => {}); await page.waitForTimeout(300);
  s = await S(page);
  ok(s.n === 12 && s.realInfo && s.realInfo.n === 12 && s.realInfo.bad === 0 && s.realInfo.name === AWK, 'awkward names: 12 photos read, 0 unreadable, folder name kept', s.realInfo);
  ok(bridge.calls.lastIndexOf('shootOpened') > bridge.calls.lastIndexOf('openFolder'), 'awkward names: shootOpened sent after the read');
  const urls = await page.evaluate(async () => {
    const out = [];
    for (const p of __lumina.logic().real) {
      const q = p.lg ? new URL(p.lg).searchParams : null, r = p.lg ? await fetch(p.lg) : null;
      out.push({ path: p.path, p: q && q.get('p'), plus: !!p.lg && /\+/.test(p.lg.split('?')[1]), status: r && r.status });
    }
    return out;
  });
  ok(urls.length === 12 && urls.every(u => u.p === u.path && !u.plus && u.status === 200), 'awkward names: every large-view URL names its file, %20 never +, and loads', urls.filter(u => !(u.p === u.path && !u.plus && u.status === 200)));
  const awkPaths = urls.map(u => u.path);
  for (const n of Object.values(awkNames).concat([NFD + ' ?=/DSC01011.ARW'])) ok(awkPaths.includes(AWK + '/' + n), 'awkward names: read ' + JSON.stringify(n), awkPaths);
  await key(page, 'p'); await page.waitForTimeout(600);                    // a keep: the page sends its warm-ahead list (BRIDGE-v0.03 §6)
  ok(bridge.prefetches.length &&bridge.prefetches.every(it => awkPaths.includes(it.p)), 'awkward names: prefetch items name read files', bridge.prefetches.slice(0, 3));
  // Edit preview URL (lumina://render) for the most awkward name, fetched as the page's <img> would.
  const relAwk = AWK + '/a+b=c?d&e#f 50%41.ARW', relNfd = AWK + '/' + NFD + '.ARW';
  const rv = await page.evaluate(async rel => { const u = lumina.preview(rel, 'ev:+0.20 con:+5', 900, 41); const r = await fetch(u); return { u, status: r.status }; }, relAwk);
  ok(rv.status === 200 && bridge.renders.some(r => r.rel === relAwk && r.look === 'ev:+0.20 con:+5 shp:40'), 'awkward names: lumina.preview URL reaches the file with its look', { rv, renders: bridge.renders.map(r => r.rel) });
  const nr = await page.evaluate(([a, b]) => lumina.near(a, b), [relAwk, relNfd]);
  ok(nr === 0.25 && bridge.nears.length === 1 && bridge.nears[0].a.p === relAwk && bridge.nears[0].b.p === relNfd, 'awkward names: near sends both paths unchanged', { nr, sent: bridge.nears });
  await page.evaluate(rel => lumina.reveal(rel), relNfd);
  ok(bridge.revealed[0] === relNfd, 'awkward names: reveal sends the path unchanged', bridge.revealed);
  const en = await page.evaluate(async rel => { await lumina.edit.enter(rel, ''); const st = lumina.edit.state(); lumina.edit.leave(); return st.rel; }, relAwk);
  const ent = bridge.canvas.entered.find(e => !e.leave);
  ok(en === relAwk && ent && ent.rel === relAwk && ent.preview && ent.preview.p === relAwk, 'awkward names: canvasEnter carries the path and its preview range unchanged', ent);
  // Keep all, Save: sidecars beside each RAW under its own name; the session keys by the same names.
  await page.evaluate(() => { const l = __lumina.logic(); l.setState({ marks: Object.fromEntries(l.data.order.map(id => [id, 'keep'])) }); });
  sres = await save();
  ok(sres && sres.t === '12 saved' && !sres.bad, 'awkward names: Save writes 12 sidecars', sres);
  for (const x of ['a+b=c?d&e#f 50%41.xmp', NFD + '.xmp', 'x %2B y.xmp', NFD + ' ?=/DSC01011.xmp']) ok(fs.existsSync(path.join(awk, x)) && /xmp:Rating="3"|<xmp:Rating>3</.test(fs.readFileSync(path.join(awk, x), 'utf8')), 'awkward names: sidecar ' + JSON.stringify(x), fs.readdirSync(awk));
  await page.waitForTimeout(2300);            // autosave
  const awkSaved = bridge.sessions['id-' + AWK] && JSON.parse(bridge.sessions['id-' + AWK]);
  ok(awkSaved && ['a+b=c?d&e#f 50%41.ARW', NFD + '.ARW', NFD + ' ?=/DSC01011.ARW'].every(k => awkSaved.marks[k] === 'keep'), 'awkward names: session marks keyed by the exact names', awkSaved && Object.keys(awkSaved.marks));
  await page.evaluate(() => __lumina.closeShoot()); await page.waitForTimeout(200);

  // Handoff v0.05. An ARW that can't be read stays as a grey tile (CHANGES-v0.05 B1); "Opening <name>…"
  // clears when the listing arrives (v0.04 A1); the read reports readEnd (BRIDGE-v0.03 §3); a capture-time
  // shift rides the session and is back on reopen (v0.04 B2); Esc on the opening line cancels the listing.
  const grey = path.join(tmp, 'Grey'); makeShoot(grey, jpegs);
  fs.writeFileSync(path.join(grey, 'DSC01003.ARW'), Buffer.from('not a raw file'));
  bridge.pending = grey;
  await page.evaluate(() => { window.luminaOpening({ name: 'Grey', onCard: false }); return __lumina.openFolder(); });
  await loaded(page); await page.waitForTimeout(300);
  s = await S(page);
  const gp = await page.evaluate(() => __lumina.logic().real.filter(p => p.unread).map(p => ({ name: p.name, nopv: p.nopv, path: p.path })));
  ok(s.realInfo.n === 12 && s.realInfo.nopic === 1 && JSON.stringify(gp) === JSON.stringify([{ name: 'DSC01003.ARW', nopv: true, path: 'Grey/DSC01003.ARW' }]),
    'grey tile: an unreadable ARW stays a photo (unread), counted without a picture', { info: s.realInfo, gp });
  ok(await page.evaluate(() => !__lumina.logic().state.opening), 'opening: cleared when the listing arrives');
  const rEnd = await page.evaluate(() => __lumina.events().filter(e => e.type === 'readEnd').pop());
  ok(rEnd && rEnd.detail.stay === false && rEnd.detail.photos === 12, 'readEnd: the read reports its end through lumina.emit', rEnd);
  await page.evaluate(() => { const f = window.luminaWorkingFiles; window.__wfPushed = []; window.luminaWorkingFiles = b => { window.__wfPushed.push(b); return f(b); }; });
  await page.evaluate(() => __lumina.logic().reshift([{ paths: null, sec: 3600, label: 'shifted 12 photos by +1:00:00' }], 'shifted 12 photos by +1:00:00'));
  await page.waitForTimeout(2300);            // autosave
  const gSaved = bridge.sessions['id-Grey'] && JSON.parse(bridge.sessions['id-Grey']);
  ok(gSaved && Array.isArray(gSaved.shifts) && gSaved.shifts.length === 1 && gSaved.shifts[0].sec === 3600, 'shift: saved with the session', gSaved && gSaved.shifts);
  ok(await page.evaluate(() => window.__wfPushed.includes(1234)), 'storage meter: a session write pushes luminaWorkingFiles(bytes)', await page.evaluate(() => window.__wfPushed));
  bridge.pending = grey; await page.evaluate(() => __lumina.openFolder()); await loaded(page); await page.waitForTimeout(300);
  ok(await page.evaluate(() => JSON.stringify(luminaState().shifts.map(x => x.sec)) === '[3600]'), 'shift: back on reopen', await page.evaluate(() => luminaState().shifts));
  ok(await page.evaluate(async () => (await lumina.notices()) === 'React 18.3.1 · MIT\n'), 'acknowledgements: lumina.notices() is the app\'s text');
  await page.evaluate(() => lumina.emit('openCancel', {})); await page.waitForTimeout(100);
  ok(bridge.cancels === 1, 'opening: Esc (openCancel) stops the listing', bridge.cancels);
  await page.evaluate(() => __lumina.closeShoot()); await page.waitForTimeout(200);

  ok(errors.length === 0, 'no page errors', errors);
  await ctx.close();
  await browser.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(fails ? fails + ' FAIL' : 'all ok');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
