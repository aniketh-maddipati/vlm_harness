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
  await page.waitForTimeout(700);
  ok(bridge.canvas.entered[0] && bridge.canvas.entered[0].rel === rel0 && bridge.canvas.entered[0].model === 'ILCE-7M4' && bridge.canvas.entered[0].next && bridge.canvas.entered[0].preview && +bridge.canvas.entered[0].preview.l > 0,
    'edit: canvasEnter carries the photo, its body, its preview range and its neighbours', bridge.canvas.entered[0]);
  ok(bridge.canvas.layouts[0] && bridge.canvas.layouts[0].w === 900 && bridge.canvas.layouts[0].visible === true && bridge.canvas.layouts[0].dpr >= 1, 'edit: canvasLayout carries the rect, visibility and dpr', bridge.canvas.layouts[0]);
  ok(hooks.images.length === 1 && hooks.images[0].tier === 'base' && /\/render\/2026-09-01\/DSC01001\.ARW\?/.test(hooks.images[0].url), 'edit (image path): entering loads one full-quality image (an <img>, no CORS) and hands its URL to luminaEditImage', hooks.images);
  ok(bridge.renders.length >= 1 && bridge.renders[0].look === 'ev:+0.50' && bridge.renders[0].px === 900 && bridge.renders[0].decoder === 8, 'edit (image path): the render asks for the look at the canvas size with the canvas decoder', bridge.renders[0]);
  // A 2 s drag: 60 looks at ~25 ms, renders slower than that (60 ms): only the newest value is fetched,
  // at the small tier, one at a time; drag end brings one full-quality render of the last value.
  bridge.renders = []; bridge.renderDelayMs = 60;
  await page.waitForTimeout(2300);            // let the 2 s autosave flush what came before
  const savesBefore = bridge.saves || 0;
  const drag = await page.evaluate(async () => {
    window.__editImages = [];
    lumina.edit.dragStart();
    const l = __lumina.logic();
    for (let i = 1; i <= 60; i++) {
      const look = 'ev:' + (i / 100).toFixed(2);
      l.setState({ look: Object.assign({}, l.state.look, { [l.state.cur]: look }) });      // as the page's slider does
      lumina.edit.look(look, { drag: true }); await new Promise(r => setTimeout(r, 25));
    }
    const mid = lumina.edit.state();
    lumina.edit.dragEnd();
    await new Promise(r => setTimeout(r, 500));
    return { mid, end: lumina.edit.state(), images: window.__editImages.slice() };
  });
  const dragRenders = bridge.renders.filter(r => r.tier === 'small'), restRenders = bridge.renders.filter(r => r.tier === 'base');
  ok(dragRenders.length >= 8 && dragRenders.length <= 45, 'edit (image path): a 2 s drag of 60 values renders the newest value at most once per render, at the small tier', { small: dragRenders.length, total: bridge.renders.length });
  ok(dragRenders.every(r => r.px === Math.round(900)), 'edit (image path): small tier renders ask the canvas size with tier=small (the Mac quarters it)', dragRenders.slice(0, 2));
  ok(restRenders.length >= 1 && restRenders[restRenders.length - 1].look === 'ev:0.60', 'edit (image path): drag end renders the final value at full quality', restRenders);
  ok(drag.end.image.tier === 'base' && drag.end.image.shown === drag.end.seq && !drag.end.image.inFlight && !drag.end.image.pending, 'edit (image path): the last shown image is the newest seq at the base tier, nothing left in flight', drag.end.image);
  ok(drag.images.length && drag.images.every((im, i) => i === 0 || im.seq > drag.images[i - 1].seq), 'edit (image path): images reach the page in increasing seq only (latest wins)', drag.images.map(i => i.seq));
  ok(bridge.renders.every((r, i) => i === 0 || r.t >= bridge.renders[i - 1].t + 55), 'edit (image path): renders never overlap (one in flight)', bridge.renders.slice(0, 3).map(r => r.t));
  ok(drag.mid.dragging === true && drag.end.dragging === false && bridge.canvas.drags.join() === 'true,false,true,false', 'edit: drag(start/end) and dragStart / dragEnd reach the Mac', bridge.canvas.drags);
  ok((bridge.saves || 0) === savesBefore, 'edit: no session write during the drag (500 ms debounce)', { before: savesBefore, after: bridge.saves });
  await page.waitForTimeout(2600);
  ok((bridge.saves || 0) > savesBefore, 'edit: the session is written after the drag settles', { before: savesBefore, after: bridge.saves });
  // Keystroke: a full-quality render at once, no small tier. Loupe: reaches the Mac with its region.
  bridge.renders = []; bridge.renderDelayMs = 0;
  await page.evaluate(async () => { lumina.edit.look('ev:+1.00', { key: true }); lumina.edit.loupe(true, { x: 0.25, y: 0.25, w: 0.5, h: 0.5 }); await new Promise(r => setTimeout(r, 200)); });
  ok(bridge.renders.length === 1 && bridge.renders[0].tier === 'base' && bridge.renders[0].look === 'ev:+1.00', 'edit (image path): a keystroke renders once at full quality', bridge.renders);
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
  // Prompt 1 §7: writeInto(files, 'jpeg') renders natively with the body's pinned decoder.
  const jp = await page.evaluate(rel => __lumina.logic().writeInto([{ name: 'JPEG/DSC01001.jpg', look: { src: rel, look: 'ev:+0.50', px: 2048 } }], 'jpeg'), rel0);
  ok(jp && jp.n === 1 && jp.decoder === 'RAW 8' && bridge.jpegItems && bridge.jpegItems[0].look.model === 'ILCE-7M4' && bridge.jpegItems[0].look.px === 2048, 'edit: writeInto(files, "jpeg") reaches the Mac with the look, size and body; the result names the decoder', { jp, items: bridge.jpegItems });
  await page.evaluate(() => { lumina.edit.leave(); delete window.luminaEditImage; delete window.luminaEditFacts; });
  ok(bridge.canvas.entered.some(e => e.leave) && (await page.evaluate(() => lumina.edit.state().rel)) === null && bridge.canvas.layouts[bridge.canvas.layouts.length - 1].visible === false, 'edit: leave hides the canvas and tells the Mac');
  ok((await page.evaluate(() => { try { lumina.edit.look('ev:+0.10', { drag: true }); lumina.edit.dragEnd(); return true; } catch (e) { return String(e); } })) === true, 'edit: calls after leave are harmless no-ops');

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
