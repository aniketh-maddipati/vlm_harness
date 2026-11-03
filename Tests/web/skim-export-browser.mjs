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
  const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), ctx = await b.newContext({viewport:{width:1440, height:1000}}), errs = []; if (host) await ctx.grantPermissions(['clipboard-read', 'clipboard-write']);
  if (host) await ctx.addInitScript(() => {
    const ask = v => new Promise(r => setTimeout(() => r(v), 5)); window.__calls = [];
    let place = {ask:true, finalCut:true, clips:'/Users/sam/Desktop/dump'};
    window.lumina = {video:{
      exportPlace: () => ask(place),
      exportChoose: () => { place = {...place, ask:false, path:'/Users/sam/Movies/Exports', name:'Exports'}; return ask(place); },
      exportAsk: () => { place = {ask:true, finalCut:true, clips:place.clips}; return ask(place); },
      exportSave: (name, text, dir, note) => { window.__calls.push(['save', name, text, dir, note]); const f = dir || '/Users/sam/Movies/Exports', L = window.__led = window.__led || [];
        let nm = name; for (let k = 2; L.some(e => e.path === f + '/' + nm); k++) nm = name.replace(/(\.\w+)$/, ' ' + k + '$1');
        if (note) L.push({id:'e' + L.length, path:f + '/' + nm, name:nm, folder:f, kind:note.kind, at:Date.now() + L.length, bytes:text.length, clips:note.clips, opts:note.opts, state:'here', text});
        return ask({ok:true, path:f + '/' + nm, name:nm, folder:f}); },
      // Saved files: the stand-in keeps what exportSave noted, as skimExportsList / Trash / PutBack / Forget / Read do
      exportsList: () => ask((window.__led || []).map(({text, ...e}) => e)),
      exportsRead: id => ask(((window.__led || []).find(e => e.id === id) || {}).text || null),
      exportsTrash: id => { window.__calls.push(['ledTrash', id]); const e = (window.__led || []).find(x => x.id === id); if (e) e.state = 'trashed'; return ask({ok:!!e, why:''}); },
      exportsPutBack: id => { const e = (window.__led || []).find(x => x.id === id); if (e) e.state = 'here'; return ask({ok:!!e, why:''}); },
      exportsForget: id => { window.__led = (window.__led || []).filter(x => x.id !== id); return ask(true); },
      exportsReveal: id => { window.__calls.push(['ledReveal', id]); return ask({ok:true}); },
      exportsOpen: id => ask({ok:true, app:'Final Cut Pro'}),
      showInFinder: path => { window.__calls.push(['finder', path]); return ask(true); },
      showClips: paths => { window.__calls.push(['showClips', paths]); return ask(paths.length); },
      exportDefault: p => { place = {...place, ask:false, path:p, name:p.split('/').pop()}; return ask(place); },
      places: () => ask({saveTo:place.ask ? null : place.path, home:'/Users/sam',
        places:[{name:'dump', path:'/Users/sam/Desktop/dump', kind:'shoot', card:false}].concat(place.ask ? [] : [{name:place.name, path:place.path, kind:'saveTo', card:false}], window.__keptT7 ? [{name:'T7', path:'/Volumes/T7/', kind:'kept', card:false}] : []),
        drives:[{name:'Macintosh HD', path:'/', granted:false, card:false, readOnly:false, free:2e11}, {name:'T7', path:'/Volumes/T7', granted:true, card:false, readOnly:false, free:1.5e11}, {name:'SONY', path:'/Volumes/SONY', granted:false, card:true, readOnly:false, free:3e10}]}),
      dirList: (p, files) => { window.__calls.push(['list', p, !!files]); const D = window.__dirs = window.__dirs || {'/Volumes/T7':[{name:'Projects', path:'/Volumes/T7/Projects', dirs:true}], '/Volumes/T7/Projects':[],
        '/Users/sam/Desktop/dump':Array.from({length:8}, (_, i) => ({name:'C000' + (i + 1) + '.MP4', path:'/Users/sam/Desktop/dump/C000' + (i + 1) + '.MP4', file:true, bytes:2e6}))}; return ask(D[p] || []); },
      find: (q, seq) => { window.__calls.push(['find', q]); const D = window.__dirs || {}, fold = x => x.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase(), ws = fold(q).split(/\s+/).filter(Boolean), out = [], seen = new Set();
        const walk = (p, root, depth) => (D[p] || []).forEach(f => { if (f.file || seen.has(f.path)) return; seen.add(f.path); if (ws.every(w => fold(f.name).includes(w))) out.push({name:f.name, path:f.path, root, depth:depth + 1}); walk(f.path, root, depth + 1); });
        ['/Users/sam/Desktop/dump', '/Volumes/T7'].forEach(r => walk(r, r, 0));
        return new Promise(r => setTimeout(() => r({found:out, scanned:Object.keys(D).length, partial:false, seq}), 300)); },
      dirMake: (parent, name) => { window.__calls.push(['mkdir', parent, name]); const D = window.__dirs; const q = parent + '/' + name; (D[parent] = D[parent] || []).push({name, path:q, dirs:false}); D[q] = []; return ask({ok:true, path:q}); },
      placeAdd: () => ask(null), placeRemove: () => ask(null),
      dirSize: p => { window.__calls.push(['size', p]); const D = window.__dirs || {}, sum = q => (D[q] || []).reduce((a, f) => a + (f.file ? f.bytes : sum(f.path)), 0); return ask({bytes:sum(p), files:1, partial:false}); },
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
      exportCheck: text => { window.__calls.push(['check']); const m = [...text.matchAll(/src="file:\/\/([^"]+)"/g)].map(x => decodeURIComponent(x[1])), name = p => p.split('/').pop(); if (!window.__miss && m.length) window.__miss = name(m[0]); return ask({dtd:'ok', errors:[], unchecked:0, missing:m.filter(p => name(p) === window.__miss)}); },
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
  await p.evaluate(() => { const b = document.querySelector('[data-lumina="sort-now"]'); if (b) b.click(); }); await p.waitForTimeout(400);   // the minimal page stays on Import: Sort now
  // mark through the page's own keys: two selected, one maybe, two cut
  const clipsTab = p.locator('[data-lumina="levels"] [role=tab]').nth(1); if (await clipsTab.count()) { await clipsTab.click(); await p.waitForTimeout(200); } else { await p.click('[data-gi="0"]'); await p.waitForTimeout(200); }
  { const pre = await p.evaluate(() => { const t = [...document.querySelectorAll('[data-lumina="steps"] [role=tab]')].find(e => e.innerText.trim() === 'Export'); return [t && getComputedStyle(t).color, !!document.querySelector('[data-lumina="dock-export"]')]; });
    ok(pre[0] !== 'rgb(255, 210, 122)' && pre[1], (host ? 'app' : 'browser') + ': before anything is selected, Export is not gold and the dock\u2019s Export\u2026 is greyed (the wireframe): ' + JSON.stringify(pre)); }
  for (const k of ['k', 'ArrowRight', 'k', 'ArrowRight', 'm', 'ArrowRight', 'ArrowRight', 'c', 'ArrowRight', 'c']) { await p.keyboard.press(k); await p.waitForTimeout(80); }
  if (host) {
    // while you are still in Skim, Export gets ready (LOCAL-CHANGES 267): a moment after the last mark the app is asked for its folders and the file is checked
    await p.waitForTimeout(2800); const pre = await p.evaluate(() => window.__calls.map(c => c[0]));
    ok(pre.includes('check') && pre.includes('list'), 'app: Export is made ready in Skim, before it opens (the file checked, the folders read): ' + [...new Set(pre)].join(' '));
  }
  // LOCAL-CHANGES 279: Export is gold in the steps and has its own button at the end of the dock
  const gold = await p.evaluate(() => { const t = [...document.querySelectorAll('[data-lumina="steps"] [role=tab]')].find(e => e.innerText.trim() === 'Export'), b = document.querySelector('[data-lumina="dock-export"]'); return [t && getComputedStyle(t).color, b && getComputedStyle(b).backgroundColor, b && b.innerText.replace(/\s+/g, ' ').trim()]; });
  ok(gold[0] === 'rgb(255, 210, 122)' && gold[1] === 'rgb(255, 210, 122)' && /^Export\u2026? ⌘E \d+ clips?$/.test(gold[2]), (host ? 'app' : 'browser') + ': Export is gold in the steps and at the end of the dock: ' + JSON.stringify(gold));
  if (host) await p.click('[data-lumina="dock-export"]'); else await p.keyboard.press('Meta+Enter');
  await p.waitForTimeout(900);
  const text = sel => p.evaluate(s => document.querySelector(s)?.innerText || '', sel);
  ok(await p.$('[data-lumina="export-plan"]'), (host ? 'app' : 'browser') + ': the Export controls are there');
  if (shots) await p.screenshot({path:path.join(shots, (host ? 'app' : 'browser') + '-export.png'), fullPage:true});
  // LOCAL-CHANGES 290: three parts in order (anything to export, what Final Cut gets, the files)
  ok(await p.evaluate(() => { const y = s => document.querySelector('[data-lumina="' + s + '"]').getBoundingClientRect().top; return y('ex-part-ready') < y('ex-part-fcp') && y('ex-part-fcp') < y('ex-part-files') && y('ex-part-files') < y('ex-part-more'); })
    && /^3 clips to export/.test(await text('[data-lumina="ex-ready"]')), (host ? 'app' : 'browser') + ': Export reads in three parts: ' + await text('[data-lumina="ex-ready"]') + ' · ' + await text('[data-lumina="ex-ready-sub"]'));
  if (host) {
    // round 2, G1: each folder shown is added up in the background; Size sorts by it
    await p.waitForTimeout(400);
    const dumpSub = await text('[data-lumina="ws-row"][data-path="/Users/sam/Desktop/dump"]');
    await p.click('[data-lumina="ws-sort-size"]'); await p.waitForTimeout(150);
    ok(/shoot · 16(\.0)? MB/.test(dumpSub) && await p.getAttribute('[data-lumina="ws-sort-size"]', 'aria-pressed') === 'true' && (await p.evaluate(() => window.__calls.some(c => c[0] === 'size' && c[1] === '/Users/sam/Desktop/dump'))),
      'app: a folder shows its total size, and Size sorts by it: ' + dumpSub.replace(/\s+/g, ' '));
    await p.click('[data-lumina="ws-sort-size"]'); await p.waitForTimeout(100);
  }
  if (!host) {
    // Files is never blank in a browser: the folder the shoot came from, each clip with its mark, and a way to open another
    const clipRows = await p.$$eval('[data-lumina="ws-row"][data-kind="clip"]', es => es.map(e => e.innerText.replace(/\s+/g, ' ').trim()));
    ok(clipRows.length === 8 && clipRows.filter(t => /selected/.test(t)).length === 2 && clipRows.filter(t => /maybe/.test(t)).length === 1 && /this shoot/i.test(await text('[data-lumina="ws-tree"]')),
      'browser: Files lists the folder opened, every clip with its mark: ' + clipRows.slice(0, 3).join(' | '));
    ok(await p.$('[data-lumina="ws-conn-open"]') && !await p.$('[data-lumina="ws-find"]'), 'browser: Files offers Open another folder… and no search it could not run');
    const und = await p.$$eval('[data-lumina="ws-row"][data-kind="clip"]', es => es.filter(e => /undecided/.test(e.innerText)).map(e => e.getAttribute('data-path')));
    await p.click('[data-lumina="ws-row"][data-path="' + und[0] + '"]'); await p.keyboard.press('m'); await p.waitForTimeout(200);
    ok(/maybe/.test(await text('[data-lumina="ws-row"][data-path="' + und[0] + '"]')) && /^4 clips to export/.test(await text('[data-lumina="ex-ready"]')), 'browser: M on a clip in Files marks it, and part 1 counts it: ' + await text('[data-lumina="ex-ready"]'));
    await p.keyboard.press('Meta+z'); await p.waitForTimeout(200);
    if (shots) { await p.evaluate(() => document.querySelector('[data-lumina="ex-part-files"]').scrollIntoView()); await p.screenshot({path:path.join(shots, 'browser-files.png')}); await p.evaluate(() => { document.querySelector('[data-screen-label="Export"]').scrollTop = 0; }); }
    ok(/Your browser’s download folder/.test(await text('[data-lumina="export-dest"]')), 'browser: Save to names the download folder');
    ok(/^⌘⏎ downloads .+\.fcpxml\.$/.test(await text('[data-lumina="export-then"]')), 'browser: the plan line: ' + await text('[data-lumina="export-then"]'));
    await p.click('[data-lumina="ex-mem"]'); await p.waitForTimeout(200);
    ok(/clears .+ of working memory/.test(await text('[data-lumina="export-then"]')) || /down to the covers|Nothing is held/.test(await text('[data-lumina="export-after"]')), 'browser: Clear working memory joins the plan');
    await p.click('[data-lumina="download"]'); await p.waitForTimeout(600);
    const r = await text('[data-lumina="export-result"]');
    ok(/Downloaded .+\.fcpxml · 3 clips/.test(r) && /working memory/.test(r), 'browser: the result says what was done: ' + r.replace(/\n/g, ' | '));
    ok(await p.$('[data-lumina="export-close"]'), 'browser: Close this shoot is offered');
    // what Tests/web/skim-engine-check.js does to read the file check: Summary, below the shortcuts, unfolds it
    await p.click('[data-lumina="ws-sum"]'); await p.waitForTimeout(300);
    ok(/well formed/.test(await text('[data-lumina="sum-check"]')) && /\.fcpxml/.test(await text('[data-lumina="sum-file"]')), 'browser: Summary shows the file check: ' + await text('[data-lumina="sum-check"]'));
    if (shots) { await p.evaluate(() => { const e = document.querySelector('[data-screen-label="Export"]'); if (e) e.scrollTop = 0; }); await p.screenshot({path:path.join(shots, 'browser-done.png')}); }
  } else {
    ok(/Asks each time/.test(await text('[data-lumina="export-dest"]')), 'app: Save to starts on asking each time');
    await p.click('[data-lumina="dest-choose"]'); await p.waitForTimeout(300);
    ok(/~\/Movies\/Exports/.test(await text('[data-lumina="export-dest"]')) && await p.$('[data-lumina="dest-ask"]'), 'app: a folder chosen shows, with Ask each time');
    ok(await p.$('[data-lumina="ex-scope-maybes"][aria-checked="true"]') && !await p.$('[data-lumina="export-summary"]') && !await p.$('[data-lumina="ex-scenes"]'), 'app: quick export: clips as three choices, no summary, no Final Cut options');
    for (const id of ['ex-openfc', 'ex-trash', 'ex-mem']) await p.click('[data-lumina="' + id + '"]'), await p.waitForTimeout(150);
    await p.waitForTimeout(600);
    ok((await text('[data-lumina="sum-verify"]')).includes('missing on disk: ' + await p.evaluate(() => window.__miss)), 'app: the background check flags the missing clip file before saving: ' + await text('[data-lumina="sum-verify"]'));
    const plan = await text('[data-lumina="export-then"]');
    ok(/saves .+\.fcpxml to ~\/Movies\/Exports, opens it in Final Cut, moves 2 cut clips .+ to the Trash and clears .+ of working memory\./.test(plan) || /saves .+ to ~\/Movies\/Exports, opens it in Final Cut and moves 2 cut clips/.test(plan), 'app: the plan line: ' + plan);
    if (shots) await p.screenshot({path:path.join(shots, 'app-export-on.png'), fullPage:true});
    // one page: the shortcuts on top, the files and folders below; the tree, unfurled by a click and the arrows; a new folder; the Final Cut file dropped on it
    ok(await p.$('[data-lumina="export-top"] [data-lumina="export-plan"]') && await p.$('[data-lumina="workshop"]') && !await p.$('[data-lumina="export-workshop"]')
      && await p.evaluate(() => document.querySelector('[data-lumina="export-top"]').getBoundingClientRect().bottom <= document.querySelector('[data-lumina="workshop"]').getBoundingClientRect().top),
      'app: one Export page, the shortcuts above the files and folders');
    const rowsT = async () => (await p.$$eval('[data-lumina="ws-row"]', es => es.map(e => e.innerText.replace(/\s+/g, ' ').trim())));
    let rows = await rowsT();
    ok(rows.some(r => /dump/.test(r) && /selected/.test(r) === false && /2/.test(r)) && rows.some(r => /T7/.test(r) && /free/.test(r)) && rows.some(r => /SONY/.test(r) && /card/.test(r)) && rows.some(r => /Macintosh HD/.test(r)), 'app: the list has the shoot folder (with its marks), Save to and the drives: ' + rows.join(' | '));
    await p.click('[data-lumina="ws-opts"]'); await p.waitForTimeout(150);
    await p.click('[data-lumina="ex-scenes"]'); await p.waitForTimeout(150);
    // motion: a folder read ahead unfurls at once, its rows sliding in; furled, they fold up first; a fold closes the same way; none with Reduce motion
    const t7 = '[data-lumina="ws-row"][data-path="/Volumes/T7"]', anim = s => p.evaluate(q => [...document.querySelectorAll(q)].map(e => e.style.animation || ''), s);
    await p.click(t7); await p.waitForTimeout(60);
    let an = await anim('[data-lumina="ws-row"][data-path="/Volumes/T7/Projects"]');
    ok(an.length === 1 && /lmRowIn/.test(an[0]), 'app: a drive read ahead unfurls at once and its rows slide in: ' + JSON.stringify(an));
    await p.waitForTimeout(700); await p.click(t7); await p.waitForTimeout(40);
    an = await anim('[data-lumina="ws-row"][data-path="/Volumes/T7/Projects"]');
    ok(an.length === 1 && /lmRowOut/.test(an[0]), 'app: furled, its rows fold up before they go: ' + JSON.stringify(an));
    await p.waitForTimeout(300);
    ok(!await p.$('[data-lumina="ws-row"][data-path="/Volumes/T7/Projects"]') && await p.getAttribute(t7, 'aria-expanded') === 'false', 'app: then the drive is furled');
    await p.click('[data-lumina="ws-sum"]'); await p.waitForTimeout(250); await p.click('[data-lumina="ws-sum"]'); await p.waitForTimeout(40);
    an = await anim('[data-lumina="export-summary"]');
    ok(an.length === 1 && /lmFoldOut/.test(an[0]), 'app: a fold plays its way out: ' + JSON.stringify(an));
    await p.waitForTimeout(300); ok(!await p.$('[data-lumina="export-summary"]'), 'app: then it is closed');
    await p.emulateMedia({reducedMotion:'reduce'});
    await p.click('[data-lumina="ws-sum"]'); await p.waitForTimeout(150); await p.click('[data-lumina="ws-sum"]'); await p.waitForTimeout(40);
    ok(!await p.$('[data-lumina="export-summary"]'), 'app: with Reduce motion a fold closes at once');
    await p.emulateMedia({reducedMotion:'no-preference'});
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
    // the files and folders sit under the shortcuts: bring them up so the row and the bucket are both on screen for the drag
    await p.evaluate(() => document.querySelector('[data-lumina="workshop"]').scrollIntoView({block:'start'})); await p.waitForTimeout(100);
    await p.dragAndDrop('[data-lumina="ws-row"][data-path$="/' + undec[0] + '"]', '[data-lumina="ws-bucket-keep"]'); await p.waitForTimeout(250);
    ok((await marksOf([undec[0]]))[0].includes('selected') && /^Selected\s*3/.test((await text('[data-lumina="ws-bucket-keep"]')).trim()), 'app: a clip dropped on the Selected bucket is selected: ' + (await text('[data-lumina="ws-bucket-keep"]')).replace(/\s+/g, ' '));
    await p.keyboard.press('Meta+z'); await p.waitForTimeout(200);
    await p.click('[data-lumina="ws-bucket-cut"]'); await p.waitForTimeout(200);
    cr = await clipRows(); ok(cr.length === 2 && cr.every(r => /cut/.test(r)), 'app: clicking the Cut bucket lists only the cut clips: ' + cr.join(' | '));
    await p.click('[data-lumina="ws-bucket-cut"]'); await p.waitForTimeout(150);
    // one size, large: no S / M / L, every clip row 52 px with its picture; the rail beside the list is the list to scale
    const rowH = await p.$$eval('[data-lumina="ws-row"][data-kind="clip"]', es => es.map(e => Math.round(e.getBoundingClientRect().height)));
    ok(!await p.$('[data-lumina="ws-zoom"]') && rowH.length === 8 && rowH.every(h => h === 52), 'app: no row sizes; each clip row is large, with its picture: ' + rowH.join(','));
    await p.hover('[data-lumina="ws-tree"]'); await p.keyboard.down('Control'); await p.mouse.wheel(0, -60); await p.keyboard.up('Control'); await p.waitForTimeout(200);
    ok((await p.$$eval('[data-lumina="ws-row"][data-kind="clip"]', es => es.map(e => Math.round(e.getBoundingClientRect().height)))).every(h => h === 52), 'app: a pinch (⌃-wheel) leaves the rows as they are');
    // the rail: the row at a point on it, from the row's own place in the list
    const railAt = async pth => p.evaluate(q => { const t = document.querySelector('[data-lumina="ws-tree"]'), r = document.querySelector('[data-lumina="ws-row"][data-path="' + q + '"]'), m = document.querySelector('[data-lumina="ws-map"]').getBoundingClientRect();
      const y = r.getBoundingClientRect().top - t.getBoundingClientRect().top + t.scrollTop + r.offsetHeight / 2; return {x:m.left + m.width / 2, y:m.top + y / Math.max(t.scrollHeight, 1) * m.height}; }, pth);
    const c3 = '/Users/sam/Desktop/dump/' + undec[undec.length - 1], at3 = await railAt(c3);
    await p.mouse.move(at3.x, at3.y); await p.waitForTimeout(250);
    ok(new RegExp(undec[undec.length - 1].replace('.', '\\.')).test(await text('[data-lumina="ws-peek"]')), 'app: the pointer on the rail shows that clip\u2019s picture and name beside it: ' + (await text('[data-lumina="ws-peek"]')).replace(/\s+/g, ' '));
    if (shots) await p.screenshot({path:path.join(shots, 'app-workshop-clips.png'), fullPage:false});
    await p.mouse.down(); await p.mouse.up(); await p.waitForTimeout(250);
    ok(await p.$eval('[data-lumina="ws-row"][data-path="' + c3 + '"]', e => e.getAttribute('aria-selected')) === 'true', 'app: a click on the rail selects the row there');
    await p.keyboard.press('Home'); await p.waitForTimeout(150);
    const first = await p.$eval('[data-lumina="ws-row"][aria-selected="true"]', e => e.getAttribute('data-path'));
    await p.keyboard.press('End'); await p.waitForTimeout(150);
    const last = await p.$eval('[data-lumina="ws-row"][aria-selected="true"]', e => e.getAttribute('data-path'));
    ok(first === '/Users/sam/Desktop/dump' && last === '/Volumes/SONY', 'app: Home and End select the first and last rows: ' + first + ' · ' + last);
    await p.mouse.move(10, 10); await p.waitForTimeout(150);
    await p.click('[data-lumina="ws-row"][data-path="/Users/sam/Desktop/dump"]'); await p.click('[data-lumina="ws-row"][data-path="/Users/sam/Desktop/dump"]'); await p.waitForTimeout(200);
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
    await p.dragAndDrop('[data-lumina="ws-chip-fcp"]', '[data-lumina="ws-row"][data-path="/Volumes/SONY"]'); await p.waitForTimeout(250);
    ok(!/SONY/.test(await text('[data-lumina="ws-to-fcp"]')), 'app: a camera card takes no drop');
    await p.dragAndDrop('[data-lumina="ws-chip-fcp"]', '[data-lumina="ws-row"][data-path="' + made + '"]'); await p.waitForTimeout(300);
    ok(/Tuesday export/.test(await text('[data-lumina="ws-to-fcp"]')) && /Final Cut file/.test(await text('[data-lumina="ws-row"][data-path="' + made + '"]')), 'app: the Final Cut file dropped on the new folder goes there: ' + await text('[data-lumina="ws-to-fcp"]'));
    await p.dragAndDrop('[data-lumina="ws-chip-cut"]', '[data-lumina="ws-row"][data-path="/Volumes/T7"]'); await p.waitForTimeout(300);
    ok(/\/Volumes\/T7$/.test((await text('[data-lumina="ws-to-cut"]')).trim()), 'app: the cut list can go somewhere else: ' + await text('[data-lumina="ws-to-cut"]'));
    ok(/to \/Volumes\/T7\/Projects\/Tuesday export/.test(await text('[data-lumina="export-then"]')), 'app: the plan line names the folder: ' + await text('[data-lumina="export-then"]'));
    if (shots) await p.screenshot({path:path.join(shots, 'app-workshop.png'), fullPage:true});
    // Arrange: a clip dragged onto a folder waits as a draft; Sort by mark plans the rest; Review, ×, then ⌘⏎ applies
    const dumpP = '/Users/sam/Desktop/dump';
    await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '"]'); await p.waitForTimeout(300);
    cr = await clipRows(); const sel1 = 'C000' + (cr.findIndex(r => /selected/.test(r)) + 1) + '.MP4';
    await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '/' + sel1 + '"]'); await p.waitForTimeout(120);
    // large rows: bring the clip to the top so it and the folder are both on screen for the drag
    await p.evaluate(q => document.querySelector('[data-lumina="ws-row"][data-path="' + q + '"]').scrollIntoView({block:'start'}), dumpP + '/' + sel1); await p.waitForTimeout(100);
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
    ok(calls.map(c => c[0]).filter(c => !/check|list|mkdir|arrange|size/.test(c)).join(' ') === 'save save fcp trash', 'app: (cut list), save, then Final Cut, then the Trash: ' + calls.map(c => c[0]).join(' '));
    ok(r.includes('clip file missing on disk: ' + await p.evaluate(() => window.__miss)) && /missing on disk/.test(await text('[data-lumina="sum-verify"]')), 'app: a missing clip file is flagged in the result and the summary');
    ok(/Saved .+ in \/Volumes\/T7\/Projects\/Tuesday export/.test(r) && /Opened in Final Cut Pro/.test(r) && /Moved 2 cut clips/.test(r) && /working memory/.test(r), 'app: the result: ' + r.replace(/\n/g, ' | '));
    if (shots) { await p.evaluate(() => { const e = document.querySelector('[data-screen-label="Export"]'); if (e) e.scrollTop = 0; }); await p.screenshot({path:path.join(shots, 'app-done.png')}); }
    ok(/Tuesday export/.test(await text('[data-lumina="dest-line"]')) && await p.$('[data-lumina="dest-unpin"]'), 'app: Save to at the top shows the folder picked below');
    await p.click('[data-lumina="export-reveal"]'); await p.click('[data-lumina="export-putback"]'); await p.waitForTimeout(400);
    const c2 = await p.evaluate(() => window.__calls.map(c => c[0]).join(' '));
    ok(/reveal/.test(c2) && /putback/.test(c2) && /Put back 2 clips/.test(await text('[data-lumina="export-result"]')), 'app: Show in Finder and Put back answer from the result');
    // Undo: the run on the workshop's list puts its clips back, and their paths follow
    await p.click('[data-lumina="ws-run-undo-0"]'); await p.waitForTimeout(500);
    ok(/^Put back 2 clips/.test(await text('[data-lumina="ws-plan-say"]')) && /put back/.test(await text('[data-lumina="ws-plan-list"]')) && !await p.$('[data-lumina="ws-run-undo-0"]')
      && await p.$('[data-lumina="ws-row"][data-path="' + dumpP + '/' + sel1 + '"]'), 'app: Undo puts the run back, and the list says so: ' + await text('[data-lumina="ws-plan-say"]') + ' | ' + await text('[data-lumina="ws-plan-list"]') + ' | ' + (await rowsT()).join(' | '));
    // Read back: the file as Final Cut might return it, the two favorites rejected; the clip Arrange moved and put
    // back is found by its name
    const fb = path.join(T, 'from Final Cut.fcpxml'); fs.writeFileSync(fb, savedF[2].replace(/value="favorite"/g, 'value="reject"'));
    await p.setInputFiles('[data-lumina="ws-back"] input[type=file]', fb); await p.waitForTimeout(400);
    const bs = await text('[data-lumina="ws-back-say"]'), bl = await text('[data-lumina="ws-back-list"]');
    ok(/from Final Cut\.fcpxml: \d+ clips of this shoot\. 2 marks differ/.test(bs) && (bl.match(/selected\s*→\s*cut/g) || []).length === 2, 'app: Read back lists the marks the file changes, before anything changes: ' + bs + ' | ' + bl.replace(/\n/g, ' '));
    ok((await marksOf([sel1]))[0].includes('selected'), 'app: reading changes no mark');
    await p.click('[data-lumina="ws-back-use"]'); await p.waitForTimeout(300);
    ok((await marksOf([sel1]))[0].includes('cut') && /^Used 2 marks/.test(await text('[data-lumina="ws-back-say"]')), 'app: Use these marks sets them: ' + await text('[data-lumina="ws-back-say"]'));
    await p.keyboard.press('Meta+z'); await p.waitForTimeout(300);
    ok((await marksOf([sel1]))[0].includes('selected'), 'app: ⌘Z takes them back');
    await p.setInputFiles('[data-lumina="ws-back"] input[type=file]', {name:'notes.xml', mimeType:'text/xml', buffer:Buffer.from('<notes/>')}); await p.waitForTimeout(300);
    ok(/notes\.xml is not a Final Cut XML file/.test(await text('[data-lumina="ws-back-say"]')), 'app: another XML file is refused');
    // Saved files: the .fcpxml and the cut list Export saved, Current until a mark changes; a preview; Update saves beside it
    await p.evaluate(() => document.querySelector('[data-lumina="ws-led"]')?.scrollIntoView({block:'center'}));
    const led = async () => p.$$eval('[data-lumina="ws-led-row"]', es => es.map(e => e.getAttribute('data-state') + ' ' + e.innerText.replace(/\s+/g, ' ')));
    let lr = await led(); const old = lr.findIndex(r => /^old /.test(r) && /\.fcpxml/.test(r));
    // the .fcpxml points at Selected/, and Undo put the clips back since: it is out of date, and says why; the cut list is current
    ok(lr.length === 2 && old >= 0 && /Out of date · 2 clips moved/.test(lr[old]) && lr.some(r => /^cur .*cut clips\.txt/.test(r)) && /1 current · 1 out of date/.test(await text('[data-lumina="ws-led-sum"]')),
      'app: Saved files lists what Export saved: the cut list current, the .fcpxml out of date since Undo moved its clips back: ' + lr.join(' | '));
    await p.click('[data-lumina="ws-led-name-' + old + '"]'); await p.waitForTimeout(250);
    ok(/<fcpxml version=/.test(await text('[data-lumina="ws-led-text"]')), 'app: a click on its name previews the file');
    await p.click('[data-lumina="ws-led-finder-' + old + '"]'); await p.waitForTimeout(150);
    ok((await p.evaluate(() => window.__calls.some(c => c[0] === 'ledReveal'))) && /Finder has .+ selected/.test(await text('[data-lumina="ws-led-say"]')), 'app: Show in Finder answers from Saved files');
    await p.click('[data-lumina="ws-led-update-' + old + '"]'); await p.waitForTimeout(500);
    lr = await led();
    ok(lr.length === 3 && lr.some(r => /^replaced /.test(r)) && /Saved .+ 2\.fcpxml beside/.test(await text('[data-lumina="ws-led-say"]')), 'app: Update saves a new file beside it and the old one reads Replaced: ' + lr.join(' | '));
    const rep = lr.findIndex(r => /^replaced /.test(r));
    await p.click('[data-lumina="ws-led-trash-' + rep + '"]'); await p.waitForTimeout(400);
    lr = await led(); const tr = lr.findIndex(r => /^trash /.test(r));
    ok(tr >= 0 && await p.$('[data-lumina="ws-led-back-' + tr + '"]'), 'app: Move to Trash takes the replaced file, with Put back: ' + lr.join(' | '));
    // Show in Finder wherever you are: the bar, and ⌥⌘R on the row selected
    await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '"]'); await p.waitForTimeout(200);
    await p.click('[data-lumina="ws-row"][data-path="' + dumpP + '"]'); await p.waitForTimeout(200);
    ok(await p.$('[data-lumina="ws-finder"]'), 'app: the bar offers Show in Finder for the row selected');
    await p.keyboard.press('Alt+Meta+r'); await p.waitForTimeout(200);
    ok((await p.evaluate(() => window.__calls.filter(c => c[0] === 'finder').map(c => c[1]))).includes(dumpP), 'app: ⌥⌘R shows it in Finder');
    ok(/Give access/.test(await p.evaluate(() => document.querySelector('[data-lumina="ws-row"][data-path="/"]')?.title || '')) || /No access yet/.test(await p.evaluate(() => document.querySelector('[data-lumina="ws-row"][data-path="/"]')?.title || '')), 'app: a drive with no access says so in plain words');
    // Storage: memory, the cut clips with Delete in Finder…, and the drive
    await p.evaluate(() => document.querySelector('[data-lumina="ex-storage"]').scrollIntoView({block:'center'}));
    ok(/memory/i.test(await text('[data-lumina="sto-mem"]')) && /cut clip/.test(await text('[data-lumina="sto-cut"]')) && /T7 · 150\.0 GB free of 1000\.0 GB/.test(await text('[data-lumina="sto-drive"]')), 'app: Storage says what memory holds, the cut clips, and the drive: ' + [await text('[data-lumina="sto-mem"]'), await text('[data-lumina="sto-cut"]'), await text('[data-lumina="sto-drive"]')].join(' | ').replace(/\n/g, ' '));
    await p.click('[data-lumina="cut-finder"]'); await p.waitForTimeout(250);
    ok((await p.evaluate(() => window.__calls.some(c => c[0] === 'showClips' && c[1].length > 0))) && /Finder has .+ selected: press ⌘⌫ there/.test(await text('[data-lumina="cut-say"]')), 'app: Delete in Finder… selects the cut clips in Finder: ' + await text('[data-lumina="cut-say"]'));
    // round 2, F-1: each mark's clips in Finder, never marked included
    { const t = await p.$$eval('[data-lumina="ws-finder-marks"] button', es => es.map(e => e.getAttribute('data-lumina') + ' ' + e.innerText.trim()));
      const before = await p.evaluate(() => window.__calls.length); await p.click('[data-lumina="ws-finder-und"]'); await p.waitForTimeout(250);
      const got = await p.evaluate(n => window.__calls.slice(n).find(c => c[0] === 'showClips'), before);
      ok(t.some(x => /^ws-finder-und \d+ unmarked · /.test(x)) && t.some(x => /^ws-finder-keep \d+ selected · /.test(x)) && got && got[1].length >= 1 && /Finder has \d+ unmarked clips? selected/.test(await text('[data-lumina="ws-say"]')),
        'app: Show in Finder for each mark, unmarked too: ' + t.join(' | ') + ' → ' + await text('[data-lumina="ws-say"]')); }
    await p.click('[data-lumina="ex-preview"]'); await p.waitForTimeout(200);
    ok(/<fcpxml version=/.test(await text('[data-lumina="ex-preview-text"]')), 'app: Preview the file shows what ⌘⏎ saves');
    // Find a folder (LOCAL-CHANGES 268): a folder three levels down that nothing has read yet; ⌘F, type, the dots while the app
    // looks, the folder found with where it is, ⏎ shows it in the list with each folder above it unfurled; nothing found says so
    await p.evaluate(() => { const D = window.__dirs; D['/Volumes/T7'].push({name:'Archive', path:'/Volumes/T7/Archive', dirs:true}); D['/Volumes/T7/Archive'] = [{name:'2025', path:'/Volumes/T7/Archive/2025', dirs:true}];
      D['/Volumes/T7/Archive/2025'] = [{name:'Wedding Café', path:'/Volumes/T7/Archive/2025/Wedding Café', dirs:false}]; D['/Volumes/T7/Archive/2025/Wedding Café'] = []; });
    await p.click('[data-lumina="ws-tree"] [data-lumina="ws-row"]'); await p.keyboard.press('Meta+f'); await p.waitForTimeout(80);
    ok(await p.evaluate(() => document.activeElement && document.activeElement.getAttribute('data-lumina') === 'ws-find-q'), 'app: ⌘F goes to Find a folder');
    await p.keyboard.type('cafe wed'); await p.waitForTimeout(320);
    ok(await p.evaluate(() => getComputedStyle(document.querySelector('[data-lumina="ws-find-dots"]')).display !== 'none') && /Searching/.test(await text('[data-lumina="ws-find"]')), 'app: while the app looks, the dots and the line run: ' + await text('[data-lumina="ws-find-n"]'));
    await p.waitForTimeout(500);
    const fr = await p.$$eval('[data-lumina="ws-find-row"]', es => es.map(e => e.innerText.replace(/\s+/g, ' ').trim()));
    ok(fr.length === 1 && /Wedding Café/.test(fr[0]) && /\/Volumes\/T7\/Archive\/2025/.test(fr[0]) && /1 folder/.test(await text('[data-lumina="ws-find-n"]')), 'app: the folder is found, every word, accents aside, with where it is: ' + fr.join(' | '));
    await p.keyboard.press('Enter'); await p.waitForTimeout(500);
    const wc = '[data-lumina="ws-row"][data-path="/Volumes/T7/Archive/2025/Wedding Café"]';
    ok(await p.$(wc + '[aria-selected="true"]') && await p.getAttribute('[data-lumina="ws-row"][data-path="/Volumes/T7/Archive/2025"]', 'aria-expanded') === 'true' && !await p.$('[data-lumina="ws-find-list"]'),
      'app: ⏎ shows it in the list, each folder above it unfurled, selected');
    await p.fill('[data-lumina="ws-find-q"]', 'zzqx'); await p.waitForTimeout(700);
    ok(/No folder named “zzqx”/.test(await text('[data-lumina="ws-find-say"]')), 'app: nothing found says so: ' + await text('[data-lumina="ws-find-say"]'));
    await p.keyboard.press('Escape'); await p.waitForTimeout(200); await p.keyboard.press('Escape'); await p.waitForTimeout(200);
    ok(await p.inputValue('[data-lumina="ws-find-q"]') === '' && !await p.$('[data-lumina="ws-find-list"]'), 'app: Escape closes the list, then clears the search');
    ok(await p.$('[data-lumina="ws-load"]'), 'app: the list has its reading line');
    // LOCAL-CHANGES 269: a drive given access at its top is listed once, under Drives, with what the folder was
    await p.evaluate(() => { window.__keptT7 = true; window.dispatchEvent(new Event('focus')); }); await p.waitForTimeout(400);
    const t7rows = await p.$$eval('[data-lumina="ws-row"]', es => es.filter(e => /^\/Volumes\/T7\/?$/.test(e.getAttribute('data-path'))).length);
    ok(t7rows === 1, 'app: the T7, given access at its top, is listed once (as a drive), not again under Folders: ' + t7rows);
    // its menu: a right-click, every thing that can be done with it
    await p.click('[data-lumina="ws-row"][data-path="/Volumes/T7"]', {button:'right'}); await p.waitForTimeout(500);
    const menu = (await p.$$eval('[data-lumina="ws-menu"] [role=menuitem]', es => es.map(e => e.innerText.replace(/\s+/g, ' ').trim()))).join(' | ');
    ok(/Expand everything inside/.test(menu) && /Show in Finder/.test(menu) && /Copy path/.test(menu) && /Remove access/.test(menu) && /New folder inside/.test(menu), 'app: a right-click opens the row’s menu: ' + menu);
    await p.keyboard.press('Escape'); await p.waitForTimeout(250);
    ok(!await p.$('[data-lumina="ws-menu"]'), 'app: esc closes the menu');
    await p.click('[data-lumina="ws-row"][data-path="/Volumes/T7"]', {button:'right'}); await p.waitForTimeout(450);
    await p.click('[data-lumina="ws-menu-all"]'); await p.waitForTimeout(700);
    const deep = '[data-lumina="ws-row"][data-path="/Volumes/T7/Archive/2025/Wedding Café"]';
    ok(await p.$(deep) && await p.$('[data-lumina="ws-row"][data-path="/Volumes/T7/Projects"]'), 'app: Expand everything inside shows the folders levels down');
    await p.click(deep); await p.waitForTimeout(200);
    const crumbs = (await p.$$eval('[data-lumina="ws-path"] button', es => es.map(e => e.innerText.trim()))).join(' › ');
    ok(crumbs === 'T7 › Archive › 2025 › Wedding Café', 'app: the path bar shows where the selected folder is: ' + crumbs);
    await p.click('[data-lumina="ws-path-1"]'); await p.waitForTimeout(200);
    ok(await p.getAttribute('[data-lumina="ws-row"][data-path="/Volumes/T7/Archive"]', 'aria-selected') === 'true', 'app: a folder in the path bar selects it');
    await p.keyboard.press('Meta+ArrowUp'); await p.waitForTimeout(200);
    ok(await p.getAttribute('[data-lumina="ws-row"][data-path="/Volumes/T7"]', 'aria-selected') === 'true', 'app: ⌘↑ goes to the folder above');
    await p.keyboard.press('Alt+Meta+KeyC'); await p.waitForTimeout(200);
    ok(/Copied ~?\/?Volumes\/T7|Copied \/Volumes\/T7/.test(await text('[data-lumina="ws-say"]')) && await p.evaluate(() => navigator.clipboard.readText()) === '/Volumes/T7', 'app: ⌥⌘C copies the path: ' + await text('[data-lumina="ws-say"]'));
    await p.keyboard.press('Alt+ArrowLeft'); await p.waitForTimeout(500);
    ok(!await p.$('[data-lumina="ws-row"][data-path="/Volumes/T7/Projects"]') && await p.getAttribute('[data-lumina="ws-row"][data-path="/Volumes/T7"]', 'aria-expanded') === 'false', 'app: ⌥← furls the folder and everything open inside it');
    // the menu from the keyboard: ⇧F10, ↓ and ⏎
    await p.keyboard.press('Shift+F10'); await p.waitForTimeout(450);
    ok(await p.$('[data-lumina="ws-menu"]'), 'app: ⇧F10 opens the menu of the selected row');
    await p.keyboard.press('ArrowDown'); await p.keyboard.press('Enter'); await p.waitForTimeout(500);
    ok(!await p.$('[data-lumina="ws-menu"]') && await p.getAttribute('[data-lumina="ws-row"][data-path="/Volumes/T7"]', 'aria-expanded') === 'true', 'app: ↓ ⏎ in the menu runs its first item (Expand)');
    // the options: Clips as three cards with their counts, Then as switches with what each does
    const sc = (await p.$$eval('[data-lumina="export-scope"] [role=radio]', es => es.map(e => e.innerText.replace(/\s+/g, ' ').trim()))).join(' | ');
    ok(/Selected \d+ clips?/.test(sc) && /Everything 8 clips/.test(sc), 'app: Clips, three cards each with its count: ' + sc);
    ok(/Moves|cut clip|No cut clips/.test(await text('[data-lumina="ex-trash"]')) && /working memory/.test(await text('[data-lumina="ex-mem"]')), 'app: each Then switch says what it does: ' + (await text('[data-lumina="ex-mem"]')).replace(/\s+/g, ' '));
  }
  ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
  await b.close();
}
await run(false); await run(true);
fs.rmSync(T, {recursive:true, force:true});
console.log(fails ? fails + ' FAIL' : 'all ok'); process.exit(fails ? 1 : 0);
