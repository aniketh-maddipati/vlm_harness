// The hand kit (docs/editing/UX.md "The grammar", prompts/00c): the press-picks dispatch, the puck, detents and
// the haptic tick, pinch / rotate / pressure while pressed, chrome dim, hover handles, select-then-touch carry,
// the fan and the contact sheet. The real page with plumbing.js and the Node stand-in for SetsBridge (the image
// path), on 12 synthetic ARWs, in Chromium and in Playwright's WebKit (gesture events are WebKit's).
//   node Tests/web/edit-hand.mjs            (LUMINA_ENGINES=chromium,webkit)
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pw, open, makeJpegs, makeShoot, Bridge, deadline } from './lib.mjs';

deadline('edit-hand.mjs', 300);
const fails = [];
const ok = (c, m, extra) => { console.log((c ? 'ok   ' : 'FAIL ') + m + (extra !== undefined ? '  ' + JSON.stringify(extra) : '')); if (!c) fails.push(m); };
const engines = (process.env.LUMINA_ENGINES || 'chromium,webkit').split(',');

for (const eng of engines) {
  let browser;
  try { browser = await pw[eng].launch(); } catch (e) { if (eng === 'chromium') ok(false, eng + ': launches', String(e).slice(0, 120)); else console.log('SKIP ' + eng + ': not installed here (npx playwright install ' + eng + ')'); continue; }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lumina-hand-')), dir = path.join(tmp, '2026-09-01'), jpegs = await makeJpegs(browser, 12);
  makeShoot(dir, jpegs);
  const bridge = new Bridge(); bridge.renderJpeg = jpegs[3];
  const { ctx, page, errors } = await open(browser, bridge, { prefs: { rating: 4, adv: true, tsz: 1, enter: true, editIntro: true } });
  bridge.pending = dir; await page.evaluate(() => __lumina.openFolder());
  await page.waitForFunction(() => { const l = __lumina.logic(); return !!(l.real && l.real.length && !l.state.realLoad && l.state.realInfo); }, null, { timeout: 30000 });
  await page.evaluate(() => { const l = __lumina.logic(); l.setState({ marks: Object.fromEntries(l.data.order.map(id => [id, 'keep'])) }); });
  await page.waitForTimeout(200);
  await page.evaluate(() => { const l = __lumina.logic(); if (l.tourEnd) l.tourEnd(); l.setState({ gram: null }); l.setView('edit'); });
  await page.waitForFunction(() => window.luminaState && window.luminaState.__owner && window.luminaState.__owner.p(), null, { timeout: 15000 });
  await page.evaluate(() => { const E = window.luminaState.__owner, O = E.order(); E.goId(O[7].id); });
  await page.evaluate(() => { const E = window.luminaState.__owner; E.closeIntro(); });
  await page.waitForTimeout(600);
  const E = (f, a) => page.evaluate(([f, a]) => new Function('E', 'a', f)(window.luminaState.__owner, a), [String(f), a]);
  const st = () => E(`return { cur: E.state.cur, ev: E.val('ev'), vig: E.val('vig'), undo: E.state.undo.length, zm: E.state.zm, drag: E.state.dragging, hdrag: !!E.state.hdrag, pk: E.state.pk, hap: E._hapN || 0, footer: E.state.footer }`);
  const cv = await page.evaluate(() => { const r = document.querySelector('[data-lumina="canvas"]').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height, l: r.left, t: r.top }; });
  const tag = eng + ': ';

  // ——— dispatch: a press-drag at fit does Light (exposure until prompt 01), a click still zooms
  let s0 = await st();
  await page.mouse.move(cv.x, cv.y); await page.mouse.down();
  for (let i = 1; i <= 10; i++) await page.mouse.move(cv.x, cv.y - i * 8);
  let s1 = await st();
  ok(s1.hdrag && s1.pk && /Exposure/.test(s1.pk.label), tag + 'press-drag on the photo: the puck shows what was picked', s1.pk);
  ok(s1.ev > s0.ev + 0.3, tag + 'drag ↑ raises exposure', [s0.ev, s1.ev]);
  ok(/Exposure/.test(s1.footer), tag + 'the footer repeats it in words', s1.footer);
  const dim = await page.evaluate(() => getComputedStyle(document.querySelector('[data-screen-label="Controls"]')).opacity);
  await page.waitForTimeout(160);
  const dim2 = await page.evaluate(() => getComputedStyle(document.querySelector('[data-screen-label="Controls"]')).opacity);
  ok(+dim2 <= 0.41, tag + 'chrome dims to 40 % while dragging', [dim, dim2]);
  const puck = await page.evaluate(() => { const p = document.querySelector('[data-lumina="puck"]'); if (!p) return null; const ring = p.firstElementChild, r = ring.getBoundingClientRect(), cs = getComputedStyle(ring); return { w: r.width, h: r.height, bw: cs.borderTopWidth, num: getComputedStyle(p.children[1]).fontVariantNumeric, fs: getComputedStyle(p.children[1]).fontSize }; });
  ok(puck && puck.w === 28 && puck.bw === '1px' && /tabular-nums/.test(puck.num) && puck.fs === '12px', tag + 'the puck: a 1 px ring, 28 px, 12 px tabular figures', puck);
  await page.mouse.up(); await page.waitForTimeout(160);
  let s2 = await st();
  ok(!s2.hdrag && !s2.pk && s2.undo === s0.undo + 1, tag + 'release: puck gone, one undo step', s2);
  const und = await page.evaluate(() => getComputedStyle(document.querySelector('[data-screen-label="Controls"]')).opacity);
  ok(+und === 1, tag + 'chrome back to full after the drag', und);
  await E(`E.undo()`); await page.waitForTimeout(80);
  ok(Math.abs((await st()).ev - s0.ev) < 1e-6, tag + '⌘Z undoes the drag');
  await page.mouse.click(cv.x, cv.y); await page.waitForTimeout(260);
  ok((await st()).zm > 1.5, tag + 'a click (no move) still zooms to 1:1', (await st()).zm);
  // zoomed: a drag pans, not exposure
  const ev0 = (await st()).ev;
  await page.mouse.move(cv.x, cv.y); await page.mouse.down(); for (let i = 1; i <= 6; i++) await page.mouse.move(cv.x + i * 10, cv.y + i * 6); await page.mouse.up(); await page.waitForTimeout(80);
  ok((await st()).ev === ev0 && !(await st()).pk, tag + 'zoomed: a drag pans and leaves exposure alone');
  await page.keyboard.press('Escape'); await page.waitForTimeout(260);
  ok((await st()).zm === 1, tag + 'esc fits');
  // esc mid-drag cancels
  await page.mouse.move(cv.x, cv.y); await page.mouse.down(); for (let i = 1; i <= 6; i++) await page.mouse.move(cv.x, cv.y - i * 10);
  await page.keyboard.press('Escape'); await page.mouse.up(); await page.waitForTimeout(80);
  s2 = await st(); ok(s2.ev === s0.ev && s2.undo === s0.undo, tag + 'esc mid-drag cancels: value and undo as before', s2);

  // ——— detents: ev snaps at 0 on the way through, with one haptic tick; ⌥ drags through
  await E(`E.setVal('ev',0.3)`); await page.waitForTimeout(60);
  let h0 = (await st()).hap;
  await page.mouse.move(cv.x, cv.y); await page.mouse.down();
  const seen = [];
  for (let i = 1; i <= 16; i++) { await page.mouse.move(cv.x, cv.y + i * 4); seen.push((await st()).ev); }
  await page.mouse.up(); await page.waitForTimeout(60);
  const zeros = seen.filter(v => v === 0).length, h1 = (await st()).hap;
  ok(zeros >= 2, tag + 'detent: exposure rests at 0 for a few px', seen);
  ok(h1 - h0 >= 1 && h1 - h0 <= 2, tag + 'detent: a haptic tick on the way in (not one per move)', [h0, h1]);
  await E(`E.setVal('ev',0.3)`); await page.waitForTimeout(60);
  await page.keyboard.down('Alt'); await page.mouse.move(cv.x, cv.y); await page.mouse.down();
  const seenA = []; for (let i = 1; i <= 16; i++) { await page.mouse.move(cv.x, cv.y + i * 25); seenA.push((await st()).ev); }
  await page.mouse.up(); await page.keyboard.up('Alt'); await page.waitForTimeout(60);
  ok(seenA.filter(v => v === 0).length <= 1 && (await st()).hap === h1, tag + '⌥ drags through the detent, no tick', seenA);
  await E(`E.resetAll()`);

  // ——— pinch, rotate, pressure reach the drag only while pressed
  await E(`E.hand.register('probe', { pick: () => ({ slider: 'ev', label: 'Probe' }), drag: (t, d) => { (window.__hd = window.__hd || []).push({ pinch: d.pinch, rotate: d.rotate, pressure: d.pressure }); return { label: 'Probe', value: '1' }; } }); E.setState({ task: 'probe' })`);
  await page.waitForTimeout(60);
  await page.mouse.move(cv.x, cv.y); await page.mouse.down(); await page.mouse.move(cv.x, cv.y - 10);
  const zm0 = (await st()).zm;
  await page.evaluate(() => { const g = (t, o) => { const e = new Event(t, { bubbles: true, cancelable: true }); Object.assign(e, o); document.querySelector('[data-lumina="canvas"]').dispatchEvent(e); }; g('gesturestart', { scale: 1, rotation: 0 }); g('gesturechange', { scale: 1.5, rotation: 20 }); });
  await page.evaluate(() => { const e = new MouseEvent('webkitmouseforcechanged', { bubbles: true }); Object.defineProperty(e, 'webkitForce', { value: 2.4 }); document.querySelector('[data-lumina="canvas"]').dispatchEvent(e); });
  await page.evaluate(([x, y]) => document.querySelector('[data-lumina="canvas"]').dispatchEvent(new WheelEvent('wheel', { deltaY: -20, ctrlKey: true, clientX: x, clientY: y, bubbles: true, cancelable: true })), [cv.x, cv.y]);
  const hd = await page.evaluate(() => window.__hd.slice(-3));
  await page.mouse.up(); await page.waitForTimeout(60);
  ok(hd[0].pinch === 1.5 && hd[0].rotate === 20, tag + 'gesturechange while pressed: pinch 1.5, rotate 20° reach the drag', hd[0]);
  ok(Math.abs(hd[1].pressure - 0.8) < 1e-6, tag + 'Force Touch pressure reaches the drag', hd[1]);
  ok(hd[2].pinch > 1.5, tag + '⌃-wheel (Chromium pinch) while pressed: pinch grows', hd[2]);
  ok((await st()).zm === zm0, tag + 'and the photo did not zoom', (await st()).zm);
  await page.evaluate(() => { window.__hd = []; const g = (t, o) => { const e = new Event(t, { bubbles: true, cancelable: true }); Object.assign(e, o); document.querySelector('[data-lumina="canvas"]').dispatchEvent(e); }; g('gesturestart', { scale: 1 }); g('gesturechange', { scale: 1.6 }); });
  await page.waitForTimeout(80);
  ok((await page.evaluate(() => window.__hd.length)) === 0, tag + 'without a press, gestures reach no drag');
  await E(`E.setState({ task: undefined, zm: 1, zx: 0, zy: 0 }); E.resetAll()`); await page.waitForTimeout(150);
  // two-finger ↔ still moves photos when nothing is pressed
  const c0 = (await st()).cur;
  await page.evaluate(([x, y]) => { const el = document.querySelector('[data-lumina="canvas"]'); for (let i = 0; i < 3; i++) el.dispatchEvent(new WheelEvent('wheel', { deltaX: 30, clientX: x, clientY: y, bubbles: true, cancelable: true })); }, [cv.x, cv.y]);
  await page.waitForTimeout(100);
  ok((await st()).cur !== c0, tag + 'two-finger ↔ with nothing pressed: next photo');
  await E(`E.goId('${c0}')`); await page.waitForTimeout(200);

  // ——— hover handles: vignette corners show within 80 px only (Effects / Detail)
  await E(`E.setState({ sec: 'effects', param: 0 })`); await page.waitForTimeout(150);
  const ir = await page.evaluate(() => { const r = document.querySelector('[data-lumina-img]').parentElement.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; });
  await page.mouse.move(ir.l + ir.w / 2, ir.t + ir.h / 2); await page.waitForTimeout(80);
  ok((await page.locator('[data-lumina="handle"]').count()) === 0, tag + 'hover handles: none in the middle of the photo');
  await page.mouse.move(ir.l + 40, ir.t + 40); await page.waitForTimeout(80);
  ok((await page.locator('[data-lumina="handle"]').count()) === 1, tag + 'hover handles: the corner shows within 80 px');
  const v0 = (await st()).vig;
  await page.mouse.move(ir.l + 12, ir.t + 12); await page.mouse.down(); for (let i = 1; i <= 8; i++) await page.mouse.move(ir.l + 12 + i * 6, ir.t + 12 + i * 6); await page.mouse.up(); await page.waitForTimeout(80);
  ok((await st()).vig < v0 - 10, tag + 'vignette corner drag in: darker, through the dispatch', [v0, (await st()).vig]);
  await E(`E.resetAll(); E.setState({ sec: 'light', param: 0 })`); await page.waitForTimeout(100);

  // ——— ⌥-drag on a colour (Colour open) is still the colour drag
  await E(`E.setState({ sec: 'colour', param: 1, ccol: 'red' })`); await page.waitForTimeout(100);
  await page.keyboard.down('Alt'); await page.mouse.move(cv.x, cv.y); await page.mouse.down(); for (let i = 1; i <= 6; i++) await page.mouse.move(cv.x, cv.y - i * 6); await page.mouse.up(); await page.keyboard.up('Alt'); await page.waitForTimeout(80);
  const ck = await E(`const L = E.look(E.p()); return Object.keys(L).filter(k => /^sat_/.test(k)).map(k => [k, L[k]])`);
  ok(ck.length === 1 && ck[0][1] > 0, tag + '⌥-drag on the photo with Colour open: a colour\'s saturation', ck);
  await E(`E.resetAll(); E.setState({ sec: 'light', param: 0 })`);

  // ——— histogram zone drag through the same engine
  const hz = page.locator('[data-lumina="histogram"] [data-plot] > div[style*="ew-resize"]').nth(2);
  if (await hz.count()) {
    const b = await hz.boundingBox(); const e0 = (await st()).ev;
    await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down(); for (let i = 1; i <= 6; i++) await page.mouse.move(b.x + b.width / 2 + i * 10, b.y + b.height / 2); await page.mouse.up(); await page.waitForTimeout(80);
    ok((await st()).ev > e0, tag + 'histogram zone drag → exposure, through the engine', [e0, (await st()).ev]);
    await E(`E.resetAll()`);
  } else ok(false, tag + 'histogram zones present');

  // ——— crop through the dispatch: a corner drag still crops
  await page.keyboard.press('KeyC'); await page.waitForTimeout(250);
  const br = await page.locator('[data-h="br"]').boundingBox();
  await page.mouse.move(br.x + 9, br.y + 9); await page.mouse.down(); for (let i = 1; i <= 5; i++) await page.mouse.move(br.x + 9 - i * 20, br.y + 9 - i * 14); await page.mouse.up(); await page.waitForTimeout(80);
  const cd = await E(`return E.state.cd`);
  ok(cd && cd.ang !== 0, tag + 'crop: a drag on the turn arc straightens, through the dispatch', cd);
  await page.keyboard.press('KeyS'); await page.waitForTimeout(80);
  await page.mouse.move(cv.x - 200, cv.y); await page.mouse.down(); for (let i = 1; i <= 8; i++) await page.mouse.move(cv.x - 200 + i * 50, cv.y + i * 2); await page.mouse.up(); await page.waitForTimeout(80);
  const cd2 = await E(`return E.state.cd`);
  ok(cd2 && Math.abs(cd2.ang - cd.ang) > 1, tag + 'crop: S, then a drawn line straightens, through the dispatch', [cd.ang, cd2.ang]);
  await page.keyboard.press('Escape'); await page.waitForTimeout(120);

  // ——— select, then touch: ⇧-click two strip photos, drag, preview on them, release applies to all, one ⌘Z
  const strips = page.locator('[data-lumina="filmstrip"] [data-strip-cur]');
  const ids = await E(`const O = E.order(), i = E.oIdx(E.state.cur); return [O[i + 1].id, O[i + 2].id]`);
  const idx = await E(`const all = [...document.querySelectorAll('[data-lumina=filmstrip] [data-strip-cur]')]; const O = E.order(), i = E.oIdx(E.state.cur); return all.findIndex(el => el.getAttribute('data-strip-cur') === '1')`);
  await strips.nth(idx + 1).click({ modifiers: ['Shift'] }); await strips.nth(idx + 2).click({ modifiers: ['Shift'] }); await page.waitForTimeout(100);
  const sel = await E(`return E.selIds()`);
  ok(sel.length === 2, tag + '⇧-click selects photos in the filmstrip', sel);
  const u0 = (await st()).undo;
  await page.mouse.move(cv.x, cv.y); await page.mouse.down(); for (let i = 1; i <= 8; i++) await page.mouse.move(cv.x, cv.y - i * 9);
  await page.waitForTimeout(80);
  const live = await page.evaluate(() => ({ n: document.querySelectorAll('[data-lumina="carry-thumb"]').length, chip: (document.querySelector('[data-lumina="carry-n"]') || {}).textContent }));
  ok(live.n === 2 && /× 3/.test(live.chip || ''), tag + 'drag with a selection: previews on the selected thumbnails, × N by the puck', live);
  await page.mouse.up(); await page.waitForTimeout(120);
  const after = await E(`return { u: E.state.undo.length, a: ${JSON.stringify(ids)}.map(id => E.val('ev', E.data.byId[id])), me: E.val('ev') }`);
  ok(after.u === u0 + 1 && after.a.every(v => v > 0) && after.me > 0.2, tag + 'release: the move lands on every selected photo (shifted by each one\'s own Auto, as matchScene), one undo step', after);
  ok(/3 photos/.test((await st()).footer), tag + 'the footer says how many', (await st()).footer);
  await E(`E.undo()`); await page.waitForTimeout(80);
  const back = await E(`return ${JSON.stringify(ids)}.map(id => E.val('ev', E.data.byId[id])).concat([E.val('ev')])`);
  ok(back.every(v => v === 0), tag + 'one ⌘Z undoes all of them', back);

  // ——— Space: the contact sheet with a selection; a drag on one tile adjusts only that one
  const pre = await E(`return Object.fromEntries([E.state.cur, ...E.selIds()].map(id => [id, E.look(E.data.byId[id])]))`);
  await page.keyboard.press('Space'); await page.waitForTimeout(200);
  const tiles = await page.locator('[data-lumina="contact-sheet"] [data-sheet-tile]').count();
  ok(tiles === 3, tag + 'Space with a selection: the contact sheet, all three side by side', tiles);
  const t2 = page.locator('[data-lumina="contact-sheet"] [data-sheet-tile]').nth(2), tb = await t2.boundingBox(), tid = await t2.getAttribute('data-sheet-tile');
  await page.mouse.move(tb.x + tb.width / 2, tb.y + tb.height / 2); await page.mouse.down(); for (let i = 1; i <= 6; i++) await page.mouse.move(tb.x + tb.width / 2, tb.y + tb.height / 2 - i * 10); await page.mouse.up(); await page.waitForTimeout(100);
  const sh = await E(`return { cur: E.state.cur, evs: [E.state.cur, ...E.selIds()].map(id => [id, E.val('ev', E.data.byId[id])]) }`);
  ok(sh.cur === tid && sh.evs.filter(([id, v]) => v !== ((pre[id] || {}).ev || 0)).length === 1, tag + 'sheet: a drag on one tile adjusts only that one', [sh, pre]);
  await page.keyboard.press('Space'); await page.waitForTimeout(150);
  ok((await page.locator('[data-lumina="contact-sheet"]').count()) === 0, tag + 'Space again closes the sheet');
  await E(`E.resetAll(); E.setState({ sel: {} })`); await page.waitForTimeout(80);
  await page.keyboard.press('Space'); await page.waitForTimeout(150);
  ok((await page.locator('[data-lumina="contact-sheet"]').count()) === 0 && (await E(`return E.state.large`)), tag + 'Space with no selection: the large view as before');
  await page.keyboard.press('Space'); await page.waitForTimeout(150);

  // ——— the fan: hold L, move toward a tile, distance = strength, release applies; release at the centre cancels
  await E(`E.goId('${c0}'); E.resetAll()`); await page.waitForTimeout(200);
  await page.mouse.move(cv.x, cv.y); await page.waitForTimeout(50);
  const fu0 = (await st()).undo;
  await page.keyboard.down('KeyL'); await page.waitForTimeout(150);
  const nt = await page.locator('[data-lumina="fan"] [data-fan-tile]').count();
  ok(nt === 5, tag + 'hold L: five tiles fan out around the pointer', nt);
  await page.mouse.move(cv.x, cv.y - 60); await page.waitForTimeout(60);
  const half = await E(`return { s: E.state.fan.s, ev: E.val('ev') }`);
  await page.mouse.move(cv.x, cv.y - 104); await page.waitForTimeout(60);
  const full = await E(`return { s: E.state.fan.s, ev: E.val('ev') }`);
  ok(half.s > 0 && half.s < 1 && full.s === 1 && full.ev > half.ev && half.ev > 0, tag + 'fan: farther is stronger, previewed on the photo', [half, full]);
  await page.keyboard.up('KeyL'); await page.waitForTimeout(80);
  ok(!(await E(`return E.state.fan`)) && (await st()).ev === full.ev && (await st()).undo === fu0 + 1, tag + 'fan: release applies, one undo step', await st());
  await page.mouse.move(cv.x, cv.y); await page.keyboard.down('KeyL'); await page.waitForTimeout(80);
  await page.mouse.move(cv.x + 100, cv.y); await page.waitForTimeout(40); await page.mouse.move(cv.x + 4, cv.y + 3); await page.waitForTimeout(40);
  await page.keyboard.up('KeyL'); await page.waitForTimeout(80);
  ok((await st()).ev === full.ev && (await st()).undo === fu0 + 1 && JSON.stringify(await E(`return E.look(E.p())`)) === JSON.stringify({ ev: full.ev }), tag + 'fan: release at the centre cancels, nothing added to undo', await E(`return E.look(E.p())`));
  await page.keyboard.down('KeyL'); await page.waitForTimeout(60); await page.mouse.move(cv.x - 100, cv.y); await page.waitForTimeout(40); await page.keyboard.press('Escape'); await page.keyboard.up('KeyL'); await page.waitForTimeout(80);
  ok(JSON.stringify(await E(`return E.look(E.p())`)) === JSON.stringify({ ev: full.ev }), tag + 'fan: esc cancels');
  await E(`E.resetAll()`);

  // ——— the haptic op: each detent tick reaches the bridge (SetsBridge `haptic`)
  ok((bridge.haptics || []).length === h1 && (bridge.haptics || []).every(k => k === 'alignment'), tag + 'every detent tick is one `haptic` op (alignment)', [h1, bridge.haptics]);
  const thumbs = bridge.renders.filter(r => r.lane === 'thumb');
  ok(thumbs.length > 0 && thumbs.every(r => r.tier === 'small' || r.tier === 'base'), tag + 'carry previews, fan tiles and the sheet render through lumina://render lane=thumb', thumbs.length);
  ok(!errors.length, tag + 'no page errors', errors);
  await ctx.close(); await browser.close(); fs.rmSync(tmp, { recursive: true, force: true });
}
console.log(fails.length ? `\n${fails.length} failed` : '\nall ok');
process.exit(fails.length ? 1 : 0);
