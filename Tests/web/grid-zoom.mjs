// Grid zoom steps: pinching in (⌃-wheel in Chromium) walks the tile sizes up to one photo per row,
// and one more pinch in opens the photo the grid is on. ⌘= does the same at the last step.
//   node Tests/web/grid-zoom.mjs
import fs from 'fs'; import os from 'os'; import path from 'path';
import { pw, open, LOGIC, deadline, makeBigJpegs, makeBigShoot, Bridge } from './lib.mjs';

deadline('grid-zoom.mjs', 360);
const fails = [];
const ok = (c, m, extra) => { console.log((c ? 'ok   ' : 'FAIL ') + m + (extra !== undefined ? '  ' + JSON.stringify(extra) : '')); if (!c) fails.push(m); };

const browser = await pw.chromium.launch();
for (const size of [[1440, 900], [1920, 1080], [900, 700]]) {
  const { ctx, page, errors } = await open(browser, null, { app: false, size });
  await page.evaluate(`window.__l = ${LOGIC}`);
  await page.evaluate(() => __l().setView('cull')); await page.waitForTimeout(400);
  const st = () => page.evaluate(() => { const l = __l(), L = l.layout(); return { tsz: l.state.tsz, max: l.tszMax(), TW: L.TW, per: L.per, one: !!L.oneRow, avail: l.tileAvail(), large: !!l.state.large, cur: l.state.cur, view: l.state.view }; });
  const s0 = await st();
  ok(s0.view === 'cull', size + ': opens on Cull', s0);
  // the same path a trackpad pinch takes (WebKit gesture events and Chromium's ⌃-wheel both end here)
  const pinch = async () => { await page.evaluate(() => __l().gesture('magnify', { delta: 0.12 })); await page.waitForTimeout(40); };
  const seen = [];
  let s = s0;
  for (let i = 0; i < 40 && !s.large; i++) { await pinch(); s = await st(); if (!s.large) seen.push([s.tsz, s.TW, s.per]); }
  const pers = seen.map(x => x[2]);
  ok(pers.every((p, i) => i === 0 || p <= pers[i - 1]), size + ': each pinch in shows as many or fewer per row', seen);
  const atMax = seen.filter(x => x[0] === s.max).length;
  ok(atMax >= 3, size + ': at one per row it takes more pinching before the photo opens', atMax);
  const last = seen[seen.length - 1];
  ok(last && last[2] === 1 && last[0] === s.max, size + ': the last grid step is one per row', last);
  ok(seen.filter(x => x[2] > 1).length >= 4, size + ': several steps before one per row', seen.length);
  ok(s.large, size + ': pinching in past one per row opens the photo', s);
  // the photo it opened is the one the grid was on
  ok(s.cur === s0.cur, size + ': opened on the current photo', [s0.cur, s.cur]);
  // a slow pinch out zooms the photo out but stays in the large view
  await page.evaluate(() => __l().gesture('magnify', { delta: -0.1 })); await page.waitForTimeout(400);
  await page.evaluate(() => __l().gesture('magnify', { delta: -0.1 })); await page.waitForTimeout(400);
  s = await st();
  ok(s.large, size + ': a slow pinch out stays on the photo', s);
  await page.evaluate(() => __l().setState({ zl: 1, zx: 0, zy: 0, zoom: false })); await page.waitForTimeout(100);
  // a quick pinch out goes back to the grid
  await page.evaluate(() => { const l = __l(); l.gesture('magnify', { delta: -0.15 }); l.gesture('magnify', { delta: -0.12 }); l.gesture('magnify', { delta: -0.12 }); }); await page.waitForTimeout(150);
  s = await st();
  ok(!s.large && s.tsz === s.max, size + ': a quick pinch out goes back to the grid at one per row', s);
  await page.evaluate(() => __l().gesture('magnify', { delta: 0.12 })); await page.waitForTimeout(150);
  s = await st();
  ok(!s.large, size + ': one small pinch in at one per row stays in the grid', s);
  await page.waitForTimeout(600);
  for (let i = 0; i < 6 && !s.large; i++) { await pinch(); s = await st(); }
  ok(s.large, size + ': and pinching in further opens it', s);
  await page.evaluate(() => __l().setState({ large: false, zoom: false })); await page.waitForTimeout(150);
  s = await st();
  ok(!s.large && s.tsz === s.max, size + ': back in the grid at one per row', s);
  await page.keyboard.press('Escape'); await page.waitForTimeout(80);
  await page.keyboard.press('Equal'); await page.waitForTimeout(80);
  s = await st();
  ok(s.large, size + ': = at one per row opens the photo too', s);
  await page.evaluate(() => __l().setState({ large: false, zoom: false })); await page.waitForTimeout(150);
  await page.keyboard.press('Minus'); await page.waitForTimeout(80);
  s = await st();
  ok(!s.one && s.per >= 2 && s.tsz === s.max - 1, size + ': − steps back to two or more per row', s);
  // 0 and the Reset zoom button take the grid back to the size it started at; 0 takes the large view back to Fit
  ok(await page.locator('[data-lumina="zoom-reset"]').isVisible(), size + ': zoomed in, the grid shows Reset zoom', s);
  await page.locator('[data-lumina="zoom-reset"]').click(); await page.waitForTimeout(150);
  s = await st();
  ok(s.tsz === s0.tsz && !(await page.locator('[data-lumina="zoom-reset"]').count()), size + ': Reset zoom goes back to the starting size and hides', s);
  await page.evaluate(() => __l().setState({ tsz: 9 })); await page.waitForTimeout(100);
  await page.keyboard.press('Digit0'); await page.waitForTimeout(150);
  s = await st();
  ok(s.tsz === s0.tsz, size + ': 0 does the same', s);
  await page.evaluate(() => { const l = __l(); l.setState({ large: true }); }); await page.waitForTimeout(300);
  await page.evaluate(() => { const l = __l(); for (let i = 0; i < 5; i++) l.gesture('magnify', { delta: 0.15 }); }); await page.waitForTimeout(200);
  const zIn = await page.evaluate(() => __l().state.zl);
  const cols = await page.evaluate(() => { const c = document.querySelector('[data-lumina="large-check"]'); return c ? getComputedStyle(c).opacity : null; });
  ok(cols === null || cols === '1', size + ': zoomed in, the photo info stays on screen', { zIn, cols });
  await page.keyboard.press('Digit0'); await page.waitForTimeout(300);
  const zl = await page.evaluate(() => [__l().state.zl, __l().state.zoom, __l().state.large]);
  ok(zIn > 1.2 && zl[0] === 1 && !zl[1] && zl[2], size + ': 0 in the large view goes back to Fit', { zIn, zl });
  await page.evaluate(() => __l().setState({ large: false, zoom: false })); await page.waitForTimeout(100);
  ok(!errors.length, size + ': no page errors', errors);
  await ctx.close();
}
// Sharp at every grid step (app mode, Retina): a tile shown wider than its thumbnail covers takes the
// photo's embedded preview (plumbing's srcPx), so below one per row no tile's picture is magnified.
{
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lumina-gz-')), dir = path.join(tmp, 'Shoot');
  makeBigShoot(dir, await makeBigJpegs(browser, 6), 30);
  for (const size of [[1440, 900], [2560, 1440]]) {
    const bridge = new Bridge();
    const { ctx, page, errors } = await open(browser, bridge, { size, scale: 2, prefs: { tsz: 1 } });
    bridge.pending = dir; await page.evaluate(() => __lumina.openFolder());
    await page.waitForFunction(() => { const l = __lumina.logic(); return l.real && l.real.length && !l.state.realLoad; }, null, { timeout: 60000 });
    await page.evaluate(() => __lumina.logic().setView('cull')); await page.waitForTimeout(400);
    const steps = [];
    for (let i = 0; i < 30; i++) {
      const r = await page.evaluate(async () => { const l = __lumina.logic(), L = l.layout();
        const shown = () => [...document.querySelectorAll('[data-tile] img')].filter(im => { const b = im.getBoundingClientRect(); return b.width > 20 && b.bottom > 0 && b.top < innerHeight; });
        for (let t = 0; t < 40 && shown().some(im => !im.complete || !im.naturalWidth); t++) await new Promise(r => setTimeout(r, 50));
        const up = shown().map(im => { const b = im.getBoundingClientRect(); return Math.max(b.width * devicePixelRatio / im.naturalWidth, b.height * devicePixelRatio / im.naturalHeight); });
        return { tsz: l.state.tsz, TW: L.TW, per: L.per, large: !!l.state.large, up: up.length ? +Math.max(...up).toFixed(2) : null }; });
      if (r.large) break;
      if (!steps.length || steps[steps.length - 1].tsz !== r.tsz) steps.push(r);
      await page.evaluate(() => __lumina.logic().gesture('magnify', { delta: 0.12 })); await page.waitForTimeout(350);
    }
    const soft = steps.filter(x => x.per > 1 && !(x.up <= 1.01));
    ok(steps.length >= 4 && !soft.length, size + ' @2x app: below one per row no tile is magnified', soft.length ? soft : steps.map(x => x.TW + ':' + x.up).join(' '));
    ok(!errors.length, size + ' @2x app: no page errors', errors);
    await ctx.close();
  }
  fs.rmSync(tmp, { recursive: true, force: true });
}
await browser.close();
console.log(fails.length ? fails.length + ' failed' : 'all ok');
process.exit(fails.length ? 1 : 0);
