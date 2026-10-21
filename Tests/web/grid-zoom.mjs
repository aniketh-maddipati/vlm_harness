// Grid zoom steps: pinching in (⌃-wheel in Chromium) walks the tile sizes up to one photo per row,
// and one more pinch in opens the photo the grid is on. ⌘= does the same at the last step.
//   node Tests/web/grid-zoom.mjs
import { pw, open, LOGIC, deadline } from './lib.mjs';

deadline('grid-zoom.mjs', 240);
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
  ok(!errors.length, size + ': no page errors', errors);
  await ctx.close();
}
await browser.close();
console.log(fails.length ? fails.length + ' failed' : 'all ok');
process.exit(fails.length ? 1 : 0);
