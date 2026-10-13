// Export in a real browser: the web preview build in headless Chromium over clips made here with ffmpeg, as the
// browser runs it and as the Mac app runs it (a stand-in for the skimExport* and skimTrash* bridge ops).
// Bounded (LUMINA_WEB_LIMIT, 240 s). Screenshots go to SKIM_SHOTS when it is set.
//   1. The browser: Save to names its download folder, the plan line says what ⌘⏎ does, the result says it was done.
//   2. The app: Save to shows the folder, the switches change the file, ⌘⏎ saves, opens in Final Cut, moves the cut
//      clips and clears working memory, each said in the result; Put back and Show in Finder answer from there.
//
//   node Tests/web/skim-export-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-export-browser', 240);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-export-')), page = path.join(T, 'preview.html'), shots = process.env.SKIM_SHOTS;
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
const dir = path.join(T, 'dump'); fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 8; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 31, '-c:v', 'libvpx-vp9', '-b:v', '200k', '-deadline', 'realtime', '-cpu-used', '8', path.join(dir, 'C' + String(i).padStart(4, '0') + '.MP4')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
async function run(host) {
  const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), ctx = await b.newContext({viewport:{width:1440, height:1000}}), errs = [];
  if (host) await ctx.addInitScript(() => {
    const ask = v => new Promise(r => setTimeout(() => r(v), 5)); window.__calls = [];
    let place = {ask:true, finalCut:true, clips:'/Users/sam/Desktop/dump'};
    window.lumina = {video:{
      exportPlace: () => ask(place),
      exportChoose: () => { place = {...place, ask:false, path:'/Users/sam/Movies/Exports', name:'Exports'}; return ask(place); },
      exportAsk: () => { place = {ask:true, finalCut:true, clips:place.clips}; return ask(place); },
      exportSave: (name, text, dir) => { window.__calls.push(['save', name, text, dir]); const f = dir || '/Users/sam/Movies/Exports'; return ask({ok:true, path:f + '/' + name, name, folder:f}); },
      exportDefault: p => { place = {...place, ask:false, path:p, name:p.split('/').pop()}; return ask(place); },
      places: () => ask({saveTo:place.ask ? null : place.path, home:'/Users/sam',
        places:[{name:'dump', path:'/Users/sam/Desktop/dump', kind:'shoot', card:false}].concat(place.ask ? [] : [{name:place.name, path:place.path, kind:'saveTo', card:false}]),
        drives:[{name:'Macintosh HD', path:'/', granted:false, card:false, readOnly:false, free:2e11}, {name:'T7', path:'/Volumes/T7', granted:true, card:false, readOnly:false, free:1.5e11}, {name:'SONY', path:'/Volumes/SONY', granted:false, card:true, readOnly:false, free:3e10}]}),
      dirList: (p, files) => { window.__calls.push(['list', p, !!files]); const D = window.__dirs = window.__dirs || {'/Volumes/T7':[{name:'Projects', path:'/Volumes/T7/Projects', dirs:true}], '/Volumes/T7/Projects':[],
        '/Users/sam/Desktop/dump':Array.from({length:8}, (_, i) => ({name:'C000' + (i + 1) + '.MP4', path:'/Users/sam/Desktop/dump/C000' + (i + 1) + '.MP4', file:true, bytes:2e6}))}; return ask(D[p] || []); },
      dirMake: (parent, name) => { window.__calls.push(['mkdir', parent, name]); const D = window.__dirs; const q = parent + '/' + name; (D[parent] = D[parent] || []).push({name, path:q, dirs:false}); D[q] = []; return ask({ok:true, path:q}); },
      placeAdd: () => ask(null), placeRemove: () => ask(null),
      // Arrange: the stand-in moves the listed entries between folders, as skimArrangeApply / Undo do on disk
      arrangeApply: (shoot, moves) => { window.__calls.push(['arrange', moves.length]); const D = window.__dirs, at = q => q.slice(0, q.lastIndexOf('/'));
        const out = moves.map(m => { const L = D[at(m.from)] || [], i = L.findIndex(f => f.path === m.from); if (i < 0) return {from:m.from, to:'', ok:false, why:'not there any more'};
          if (!D[m.dir]) { D[m.dir] = []; (D[at(m.dir)] = D[at(m.dir)] || []).push({name:m.dir.split('/').pop(), path:m.dir, dirs:false}); }
          const [f] = L.splice(i, 1), to = m.dir + '/' + f.name; D[m.dir].push({...f, path:to}); return {from:m.from, to, ok:true, why:''}; });
        const run = {id:'r' + (window.__runs || []).length, shoot, at:Date.now(), clips:out.filter(o => o.ok).length, bytes:2e6 * out.filter(o => o.ok).length, undone:false, moves:out};
        window.__runs = [run].concat(window.__runs || []); return ask({run:run.id, moves:out}); },
      arrangeUndo: id => { window.__calls.push(['undo', id]); const D = window.__dirs, at = q => q.slice(0, q.lastIndexOf('/')), r = (window.__runs || []).find(x => x.id === id); if (!r || r.undone) return ask([]);
        r.undone = true; return ask(r.moves.filter(m => m.ok).map(m => { const L = D[at(m.to)], i = L.findIndex(f => f.path === m.to), [f] = L.splice(i, 1); D[at(m.from)].push({...f, path:m.from}); return {from:m.from, to:m.to, ok:true, why:''}; })); },
      arrangeList: () => ask((window.__runs || []).map(({moves, ...x}) => x)),
      exportCheck: text => { window.__calls.push(['check']); const m = [...text.matchAll(/src="file:\/\/([^"]+)"/g)].map(x => decodeURIComponent(x[1])); return ask({dtd:'ok', errors:[], unchecked:0, missing:m.filter(p => /C0002/.test(p))}); },
      exportReveal: p => { window.__calls.push(['reveal', p]); return ask(true); },
      openInFinalCut: p => { window.__calls.push(['fcp', p]); return ask({ok:true, app:'Final Cut Pro'}); },
      drive: () => ask({name:'T7', total:1e12, free:150e9, readOnly:false, card:false, trash:0}),
      trashList: () => ask(JSON.parse(localStorage.getItem('fake-trash') || '[]')),
      trashMove: (sh, paths) => { window.__calls.push(['trash', paths]); const out = paths.map(p => ({rel:p, ok:true, bytes:1e9, why:''})); localStorage.setItem('fake-trash', JSON.stringify(out)); return ask(out); },
      trashPutBack: () => { const t = JSON.parse(localStorage.getItem('fake-trash') || '[]'); localStorage.setItem('fake-trash', '[]'); window.__calls.push(['putback', t.length]); return ask(t); }}};
  });
  const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + page); await p.waitForTimeout(1000);
  await p.setInputFiles('input[type=file]', dir);
  for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
  // mark through the page's own keys: two selected, one maybe, two cut
  const clipsTab = p.locator('[data-lumina="levels"] [role=tab]').nth(1); if (await clipsTab.count()) { await clipsTab.click(); await p.waitForTimeout(200); } else { await p.click('[data-gi="0"]'); await p.waitForTimeout(200); }
  for (const k of ['k', 'ArrowRight', 'k', 'ArrowRight', 'm', 'ArrowRight', 'ArrowRight', 'c', 'ArrowRight', 'c']) { await p.keyboard.press(k); await p.waitForTimeout(80); }
  await p.keyboard.press('Meta+Enter'); await p.waitForTimeout(900);
  const text = sel => p.evaluate(s => document.querySelector(s)?.innerText || '', sel);
  ok(await p.$('[data-lumina="export-plan"]'), (host ? 'app' : 'browser') + ': the Export controls are there');
  if (shots) await p.screenshot({path:path.join(shots, (host ? 'app' : 'browser') + '-export.png'), fullPage:true});
  if (!host) {
    ok(/Your browser’s download folder/.test(await text('[data-lumina="export-dest"]')), 'browser: Save to names the download folder');
    ok(/^⌘⏎ downloads .+\.fcpxml\.$/.test(await text('[data-lumina="export-then"]')), 'browser: the plan line: ' + await text('[data-lumina="export-then"]'));
    await p.click('[data-lumina="ex-mem"]'); await p.waitForTimeout(200);
    ok(/clears .+ of working memory/.test(await text('[data-lumina="export-then"]')) || /down to the covers|Nothing is held/.test(await text('[data-lumina="export-after"]')), 'browser: Clear working memory joins the plan');
    await p.click('[data-lumina="download"]'); await p.waitForTimeout(600);
    const r = await text('[data-lumina="export-result"]');
    ok(/Downloaded .+\.fcpxml · 3 clips/.test(r) && /working memory/.test(r), 'browser: the result says what was done: ' + r.replace(/\n/g, ' | '));
    ok(await p.$('[data-lumina="export-close"]'), 'browser: Close this shoot is offered');
    // what Tests/web/skim-engine-check.js does to read the file check: W opens the workshop, Summary unfolds it
    await p.keyboard.press('w'); await p.waitForTimeout(300); await p.click('[data-lumina="ws-sum"]'); await p.waitForTimeout(300);
    ok(/well formed/.test(await text('[data-lumina="sum-check"]')) && /\.fcpxml/.test(await text('[data-lumina="sum-file"]')), 'browser: the workshop\u2019s Summary shows the file check: ' + await text('[data-lumina="sum-check"]'));
    await p.keyboard.press('Escape'); await p.waitForTimeout(200);
    if (shots) { await p.evaluate(() => { const e = document.querySelector('[data-screen-label="Export"]'); if (e) e.scrollTop = 0; }); await p.screenshot({path:path.join(shots, 'browser-done.png')}); }
  } else {
    ok(/Asks each time/.test(await text('[data-lumina="export-dest"]')), 'app: Save to starts on asking each time');
    await p.click('[data-lumina="dest-choose"]'); await p.waitForTimeout(300);
    ok(/~\/Movies\/Exports/.test(await text('[data-lumina="export-dest"]')) && await p.$('[data-lumina="dest-ask"]'), 'app: a folder chosen shows, with Ask each time');
    ok(await p.$('[data-lumina="ex-scope-maybes"][aria-checked="true"]') && !await p.$('[data-lumina="export-summary"]') && !await p.$('[data-lumina="ex-scenes"]'), 'app: quick export: clips as three choices, no summary, no Final Cut options');
    for (const id of ['ex-openfc', 'ex-trash', 'ex-mem']) await p.click('[data-lumina="' + id + '"]'), await p.waitForTimeout(150);
    await p.waitForTimeout(600);
    ok(/missing on disk: C0002/.test(await text('[data-lumina="sum-verify"]')), 'app: the background check flags the missing clip file before saving: ' + await text('[data-lumina="sum-verify"]'));
    const plan = await text('[data-lumina="export-then"]');
    ok(/saves .+\.fcpxml to ~\/Movies\/Exports, opens it in Final Cut, moves 2 cut clips .+ to the Trash and clears .+ of working memory\./.test(plan) || /saves .+ to ~\/Movies\/Exports, opens it in Final Cut and moves 2 cut clips/.test(plan), 'app: the plan line: ' + plan);
    if (shots) await p.screenshot({path:path.join(shots, 'app-export-on.png'), fullPage:true});
    // the workshop: W opens it; the tree, unfurled by a click and the arrows; a new folder; the Final Cut file dropped on it
    await p.keyboard.press('w'); await p.waitForTimeout(400);
    ok(await p.$('[data-lumina="workshop"]') && /Export workshop/.test(await text('[data-screen-label="Export"]')), 'app: W opens the workshop');
    const rowsT = async () => (await p.$$eval('[data-lumina="ws-row"]', es => es.map(e => e.innerText.replace(/\s+/g, ' ').trim())));
    let rows = await rowsT();
    ok(rows.some(r => /dump/.test(r) && /selected/.test(r) === false && /2/.test(r)) && rows.some(r => /T7/.test(r) && /free/.test(r)) && rows.some(r => /SONY/.test(r) && /card/.test(r)) && rows.some(r => /Macintosh HD/.test(r)), 'app: the list has the shoot folder (with its marks), Save to and the drives: ' + rows.join(' | '));
    await p.click('[data-lumina="ws-opts"]'); await p.waitForTimeout(150);
    await p.click('[data-lumina="ex-scenes"]'); await p.waitForTimeout(150);
    // the shoot's folder: each clip file with its mark; drag select, K M C, ⌘Z, and clips dropped on a bucket
    await p.click('[data-lumina="ws-row"][data-path="/Users/sam/Desktop/dump"]'); await p.waitForTimeout(300);
    const clipRows = async () => p.$$eval('[data-lumina="ws-row"][data-kind="clip"]', es => es.map(e => e.innerText.replace(/\s+/g, ' ').trim()));
    let cr = await clipRows();
    ok(cr.length === 8 && cr.filter(r => /selected/.test(r)).length === 2 && cr.filter(r => /cut/.test(r)).length === 2 && cr.filter(r => /maybe/.test(r)).length === 1, 'app: unfurling the shoot folder lists each clip with its mark: ' + cr.join(' | '));
    const box = async (a, b) => { const r1 = await p.locator('[data-lumina="ws-row"][data-path$="' + a + '"]').boundingBox(), r2 = await p.locator('[data-lumina="ws-row"][data-path$="' + b + '"]').boundingBox();
      await p.mouse.move(r1.x + r1.width - 30, r1.y + 4); await p.mouse.down(); await p.mouse.move(r1.x + r1.width - 40, r1.y + 20, {steps:4}); await p.mouse.move(r2.x + r2.width - 40, r2.y + r2.height - 4, {steps:6}); await p.mouse.up(); await p.waitForTimeout(150); };
    const marksOf = async names => p.evaluate(ns => ns.map(n => document.querySelector('[data-lumina="ws-row"][data-path$="/' + n + '"]').innerText.replace(/\s+/g, ' ')), names);
    const undec = cr.map((r, i) => /undecided/.test(r) ? 'C000' + (i + 1) + '.MP4' : '').filter(Boolean);
    await box(undec[0], undec[undec.length - 1]);
    const picked = await p.$$eval('[data-lumina="ws-row"][aria-selected="true"]', es => es.length);
    ok(picked >= 2 && /clips/.test(await text('[data-lumina="ws-bar"]')), 'app: a drag over the rows selects them: ' + picked + ' · ' + await text('[data-lumina="ws-bar"]'));
    await p.keyboard.press('m'); await p.waitForTimeout(200);
    ok((await marksOf([undec[0]]))[0].includes('maybe'), 'app: M marks the selected clips maybe');
    await p.keyboard.press('Meta+z'); await p.waitForTimeout(200);
    ok((await marksOf([undec[0]]))[0].includes('undecided'), 'app: ⌘Z takes it back');
    await p.click('[data-lumina="ws-row"][data-path$="/' + undec[0] + '"]'); await p.waitForTimeout(150);
    await p.dragAndDrop('[data-lumina="ws-row"][data-path$="/' + undec[0] + '"]', '[data-lumina="ws-bucket-keep"]'); await p.waitForTimeout(250);
    ok((await marksOf([undec[0]]))[0].includes('selected') && /^Selected\s*3/.test((await text('[data-lumina="ws-bucket-keep"]')).trim()), 'app: a clip dropped on the Selected bucket is selected: ' + (await text('[data-lumina="ws-bucket-keep"]')).replace(/\s+/g, ' '));
    await p.keyboard.press('Meta+z'); await p.waitForTimeout(200);
    await p.click('[data-lumina="ws-bucket-cut"]'); await p.waitForTimeout(200);
    cr = await clipRows(); ok(cr.length === 2 && cr.every(r => /cut/.test(r)), 'app: clicking the Cut bucket lists only the cut clips: ' + cr.join(' | '));
    await p.click('[data-lumina="ws-bucket-cut"]'); await p.waitForTimeout(150);
    await p.hover('[data-lumina="ws-tree"]'); await p.keyboard.down('Control'); await p.mouse.wheel(0, -60); await p.keyboard.up('Control'); await p.waitForTimeout(200);
    ok(await p.$('[data-lumina="ws-z-2"][aria-checked="true"]'), 'app: a pinch (⌃-wheel) makes the rows large, with each clip\u2019s picture');
    if (shots) await p.screenshot({path:path.join(shots, 'app-workshop-clips.png'), fullPage:false});
    await p.click('[data-lumina="ws-z-1"]'); await p.click('[data-lumina="ws-row"][data-path="/Users/sam/Desktop/dump"]'); await p.click('[data-lumina="ws-row"][data-path="/Users/sam/Desktop/dump"]'); await p.waitForTimeout(200);
    await p.click('[data-lumina="ws-row"][data-path="/Volumes/T7"]'); await p.waitForTimeout(300);
    ok(await p.$('[data-lumina="ws-row"][data-path="/Volumes/T7/Projects"]') && await p.$eval('[data-lumina="ws-row"][data-path="/Volumes/T7"]', e => e.getAttribute('aria-expanded')) === 'true', 'app: a click unfurls a drive');
    await p.keyboard.press('ArrowDown'); await p.waitForTimeout(100); await p.keyboard.press('ArrowRight'); await p.waitForTimeout(300);
    ok(/Empty/.test(await text('[data-lumina="ws-tree"]')) && await p.$eval('[data-lumina="ws-row"][data-path="/Volumes/T7/Projects"]', e => e.getAttribute('aria-selected')) === 'true', 'app: ↓ and → select and unfurl the next folder');
    await p.keyboard.press('n'); await p.waitForTimeout(200);
    ok(await p.$('[data-lumina="ws-new-name"]'), 'app: N asks for a folder name');
    await p.fill('[data-lumina="ws-new-name"]', 'Tuesday export'); await p.keyboard.press('Enter'); await p.waitForTimeout(400);
    const made = '/Volumes/T7/Projects/Tuesday export';
    ok(await p.$('[data-lumina="ws-row"][data-path="' + made + '"][aria-selected="true"]') && /Made .+Tuesday export/.test(await text('[data-lumina="ws-say"]')), 'app: the new folder is made, listed and selected');
    await p.keyboard.press('ArrowLeft'); await p.keyboard.press('ArrowLeft'); await p.waitForTimeout(250);
    ok(!await p.$('[data-lumina="ws-row"][data-path="' + made + '"]'), 'app: ← goes out to the parent and furls it');
    await p.keyboard.press('ArrowRight'); await p.waitForTimeout(250);
    await p.dragAndDrop('[data-lumina="ws-file-fcp"]', '[data-lumina="ws-row"][data-path="/Volumes/SONY"]'); await p.waitForTimeout(250);
    ok(!/SONY/.test(await text('[data-lumina="ws-to-fcp"]')), 'app: a camera card takes no drop');
    await p.dragAndDrop('[data-lumina="ws-file-fcp"]', '[data-lumina="ws-row"][data-path="' + made + '"]'); await p.waitForTimeout(300);
    ok(/Tuesday export/.test(await text('[data-lumina="ws-to-fcp"]')) && /Final Cut file/.test(await text('[data-lumina="ws-row"][data-path="' + made + '"]')), 'app: the Final Cut file dropped on the new folder goes there: ' + await text('[data-lumina="ws-to-fcp"]'));
    await p.dragAndDrop('[data-lumina="ws-file-cut"]', '[data-lumina="ws-row"][data-path="/Volumes/T7"]'); await p.waitForTimeout(300);
    ok(/\/Volumes\/T7$/.test((await text('[data-lumina="ws-to-cut"]')).trim()), 'app: the cut list can go somewhere else: ' + await text('[data-lumina="ws-to-cut"]'));
    ok(/to \/Volumes\/T7\/Projects\/Tuesday export/.test(await text('[data-lumina="export-then"]')), 'app: the plan line names the folder: ' + await text('[data-lumina="export-then"]'));
    if (shots) await p.screenshot({path:path.join(shots, 'app-workshop.png'), fullPage:true});
    // Arrange: a clip dragged onto a folder waits as a draft; Sort by mark plans the rest; Review, ×, then ⌘⏎ applies
    const dumpP = '/Users/sam/Desktop/dump';
    await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '"]'); await p.waitForTimeout(300);
    cr = await clipRows(); const sel1 = 'C000' + (cr.findIndex(r => /selected/.test(r)) + 1) + '.MP4';
    await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '/' + sel1 + '"]'); await p.waitForTimeout(120);
    await p.dragAndDrop('[data-lumina="ws-row"][data-path="' + dumpP + '/' + sel1 + '"]', '[data-lumina="ws-row"][data-path="' + made + '"]'); await p.waitForTimeout(300);
    ok(/^1 move waiting/.test(await text('[data-lumina="ws-plan-say"]')) && await p.$('[data-lumina="ws-row"][data-path="' + made + '/' + sel1 + '"][data-kind="clip"]')
      && /→ Tuesday export/.test(await text('[data-lumina="ws-row"][data-path="' + dumpP + '/' + sel1 + '"]')) && !(await p.evaluate(() => window.__calls.some(c => c[0] === 'arrange'))),
      'app: a clip dropped on a folder waits there as a draft, its old row says where it goes, nothing moves: ' + await text('[data-lumina="ws-plan-say"]'));
    await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '"]'); await p.waitForTimeout(150);
    if (await p.$eval('[data-lumina="ws-row"][data-path="' + dumpP + '"]', e => e.getAttribute('aria-expanded')) !== 'true') { await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '"]'); await p.waitForTimeout(150); }
    await p.click('[data-lumina="ws-sort"]'); await p.waitForTimeout(300);
    ok(/^3 moves waiting/.test(await text('[data-lumina="ws-plan-say"]')) && /new/.test(await text('[data-lumina="ws-row"][data-path="' + dumpP + '/Selected"]')) && await p.$('[data-lumina="ws-row"][data-path="' + dumpP + '/Maybe"]')
      && await p.$('[data-lumina="ws-row"][data-path="' + dumpP + '/Selected/' + sel1 + '"]') && !await p.$('[data-lumina="ws-row"][data-path="' + made + '/' + sel1 + '"]'),
      'app: Sort by mark plans Selected and Maybe folders, shown as new, with the clips inside; the earlier move is replaced: ' + await text('[data-lumina="ws-plan-say"]'));
    await p.click('[data-lumina="ws-plan-review"]'); await p.waitForTimeout(150);
    const lst = await text('[data-lumina="ws-plan-list"]');
    ok((lst.match(/→/g) || []).length === 3 && /dump → .*dump\/Maybe/.test(lst), 'app: Review lists every move, old folder → new: ' + lst.replace(/\n/g, ' | '));
    await p.click('[data-lumina="ws-plan-x-2"]'); await p.waitForTimeout(150);
    ok(/^2 moves waiting/.test(await text('[data-lumina="ws-plan-say"]')), 'app: × leaves one clip where it is');
    if (shots) await p.screenshot({path:path.join(shots, 'app-arrange-draft.png'), fullPage:false});
    await p.keyboard.press('Meta+Enter'); await p.waitForTimeout(600);
    const ac = await p.evaluate(() => window.__calls.filter(c => c[0] === 'arrange' || c[0] === 'save'));
    ok(ac.length === 1 && ac[0][1] === 2 && /^Moved 2 clips .+ into 1 folder/.test(await text('[data-lumina="ws-plan-say"]')) && await p.$('[data-lumina="ws-run-undo-0"]'),
      'app: ⌘⏎ with moves waiting applies them (and saves nothing): ' + await text('[data-lumina="ws-plan-say"]'));
    ok(await p.$('[data-lumina="ws-row"][data-path="' + dumpP + '/Selected/' + sel1 + '"][data-kind="clip"]') && !await p.$('[data-lumina="ws-row"][data-path="' + dumpP + '/' + sel1 + '"]'), 'app: the tree reads the folders again: the clip is in Selected now');
    if (shots) await p.screenshot({path:path.join(shots, 'app-arrange-done.png'), fullPage:false});
    await p.click('[data-lumina="cut-save"]'); await p.waitForTimeout(300);
    await p.keyboard.press('Meta+Enter'); await p.waitForTimeout(900);
    const calls = await p.evaluate(() => window.__calls), r = await text('[data-lumina="export-result"]');
    const saved = calls.find(c => c[0] === 'save');
    const savedF = calls.filter(c => c[0] === 'save' && /\.fcpxml$/.test(c[1])).pop(), savedT = calls.find(c => c[0] === 'save' && /cut clips\.txt$/.test(c[1]));
    ok(savedF && /<keyword [^>]*value="[^"]*Scene 1/.test(savedF[2]) && /file:\/\/\/Users\/sam\/Desktop\/dump\//.test(savedF[2]), 'app: the file has scene keywords and points at the folder the app read');
    ok(savedF && savedF[3] === made && savedT && savedT[3] === '/Volumes/T7', 'app: each file is saved in the folder it was dropped on');
    ok(savedF && savedF[2].includes('file:///Users/sam/Desktop/dump/Selected/' + sel1), 'app: the Final Cut file points at the clips where Arrange moved them');
    ok(calls.map(c => c[0]).filter(c => !/check|list|mkdir|arrange/.test(c)).join(' ') === 'save save fcp trash', 'app: (cut list), save, then Final Cut, then the Trash: ' + calls.map(c => c[0]).join(' '));
    ok(/clip file missing on disk: C0002\.MP4/.test(r) && /missing on disk/.test(await text('[data-lumina="sum-verify"]')), 'app: a missing clip file is flagged in the result and the summary');
    ok(/Saved .+ in \/Volumes\/T7\/Projects\/Tuesday export/.test(r) && /Opened in Final Cut Pro/.test(r) && /Moved 2 cut clips/.test(r) && /working memory/.test(r), 'app: the result: ' + r.replace(/\n/g, ' | '));
    if (shots) { await p.evaluate(() => { const e = document.querySelector('[data-screen-label="Export"]'); if (e) e.scrollTop = 0; }); await p.screenshot({path:path.join(shots, 'app-done.png')}); }
    await p.keyboard.press('Escape'); await p.waitForTimeout(300);
    ok(/Tuesday export/.test(await text('[data-lumina="dest-line"]')) && await p.$('[data-lumina="dest-unpin"]'), 'app: esc goes back to the quick export, which shows the folder the workshop picked');
    await p.click('[data-lumina="export-reveal"]'); await p.click('[data-lumina="export-putback"]'); await p.waitForTimeout(400);
    const c2 = await p.evaluate(() => window.__calls.map(c => c[0]).join(' '));
    ok(/reveal/.test(c2) && /putback/.test(c2) && /Put back 2 clips/.test(await text('[data-lumina="export-result"]')), 'app: Show in Finder and Put back answer from the result');
    // Undo: the run on the workshop's list puts its clips back, and their paths follow
    await p.keyboard.press('w'); await p.waitForTimeout(400); await p.click('[data-lumina="ws-run-undo-0"]'); await p.waitForTimeout(500);
    ok(/^Put back 2 clips/.test(await text('[data-lumina="ws-plan-say"]')) && /put back/.test(await text('[data-lumina="ws-plan-list"]')) && !await p.$('[data-lumina="ws-run-undo-0"]')
      && await p.$('[data-lumina="ws-row"][data-path="' + dumpP + '/' + sel1 + '"]'), 'app: Undo puts the run back, and the list says so: ' + await text('[data-lumina="ws-plan-say"]') + ' | ' + await text('[data-lumina="ws-plan-list"]') + ' | ' + (await rowsT()).join(' | '));
  }
  ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
  await b.close();
}
await run(false); await run(true);
fs.rmSync(T, {recursive:true, force:true});
console.log(fails ? fails + ' FAIL' : 'all ok'); process.exit(fails ? 1 : 0);
