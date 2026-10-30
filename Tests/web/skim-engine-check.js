// The Skim web preview, checked inside whatever browser runs it (Tests/web/skim-engine.py loads this
// next to the page): WebKitGTK on Linux, Safari through safaridriver on a Mac. Everything here is
// plain page script, so both engines run exactly the same steps:
//   the Open screen draws; four H.264 clips (Tests/web/fixtures/skim-clips, a minute apart) handed to
//   the page's own file input are listed with their capture times, decoded (no clip unreadable) and
//   given lengths; K marks the clip on screen;
//   Export builds a Final Cut file the page checks as well formed; and no page error along the way.
// Returns {steps: [[ok, what], …], errors: [...]}.
window.__skimEngineCheck = async function (names) {
  const steps = [], ok = (c, what) => { steps.push([!!c, what]); return !!c; };
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const $ = sel => document.querySelector(sel), text = sel => ($(sel) && $(sel).textContent) || '';
  const until = async (fn, ms) => { const end = Date.now() + ms; while (Date.now() < end) { try { const v = fn(); if (v) return v; } catch (e) {} await wait(100); } return null; };
  const clock = () => { try { return JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0] || null; } catch (e) { return null; } };
  const run = async () => {
    if (!ok(await until(() => $('[data-lumina="drop"]'), 15000), 'the Open screen draws')) return;
    const files = await Promise.all(names.map(async (n, i) => new File([await (await fetch('clips/' + n)).blob()], n, {type: 'video/mp4', lastModified: Date.UTC(2026, 9, 1, 10, i)})));
    const dt = new DataTransfer(); files.forEach(f => dt.items.add(f));
    const input = $('input[type=file][accept]') || $('input[type=file]');
    if (!ok(input, 'the page has a file input')) return;
    input.files = dt.files; input.dispatchEvent(new Event('change', {bubbles: true}));
    const done = await until(() => { const c = clock(); return c && c.done != null && c; }, 60000);
    if (!ok(done, 'the clips are read to the end' + (done ? ' (' + done.done + ' ms)' : ', within 60 s'))) return;
    // The minimal page stays on Import with what came in under Included; Sort now opens the grid (as ⏎ does).
    { const b = $('[data-lumina="sort-now"]'); if (b) b.click(); await until(() => document.querySelectorAll('[data-gi]').length, 3000); }
    ok(done.n === names.length && document.querySelectorAll('[data-gi]').length === names.length, names.length + ' clips listed: ' + done.n + ' in the read, ' + document.querySelectorAll('[data-gi]').length + ' tiles');
    ok(done.unreadable === 0, 'every clip decoded (' + done.unreadable + ' unreadable)');
    // The time is on the tile, or (the wireframe's tiles: name, length, gamma on the frame) in the tile's accessible name.
    const times = [...document.querySelectorAll('[data-gi]')].map(t => ((t.innerText + ' ' + (t.getAttribute('aria-label') || '')).match(/\b\d{1,2}:\d\d\b/) || [''])[0]);
    ok(new Set(times.filter(Boolean)).size === names.length, 'each clip shows its own capture time: ' + times.join(', '));
    ok(/\b1 s\b/.test(document.body.innerText), 'clip lengths shown');
    const tile = $('[data-gi="0"]'); if (tile) tile.click(); await wait(300);
    const before = text('[data-lumina="counts"]');
    for (const type of ['keydown', 'keyup']) (document.activeElement || document).dispatchEvent(new KeyboardEvent(type, {key: 'k', bubbles: true, cancelable: true}));
    const after = await until(() => /^1 decided/.test(text('[data-lumina="counts"]')) && text('[data-lumina="counts"]'), 3000);
    ok(after, 'K marks the clip on screen: ' + (after || text('[data-lumina="counts"]') || before));
    const tab = [...document.querySelectorAll('[data-lumina="steps"] *')].filter(e => e.textContent.trim() === 'Export').pop();
    if (tab) tab.click();
    // Export is one page: the summary (and the file check) is folded under Summary, below the shortcuts.
    if (!await until(() => $('[data-lumina="export-summary"]'), 800)) {
      const fold = await until(() => $('[data-lumina="ws-sum"]'), 3000); if (fold && fold.getAttribute('aria-expanded') !== 'true') fold.click();
    }
    // The check runs after the summary draws ("Checking the file…"): wait for its verdict.
    const sum = await until(() => { const t = $('[data-lumina="export-summary"]') && text('[data-lumina="sum-check"]'); return t && !/^Checking/.test(t) && t; }, 15000) || text('[data-lumina="sum-check"]');
    ok(sum && /well formed/.test(sum) && /\.fcpxml/.test(text('[data-lumina="sum-file"]')), 'Export builds the Final Cut file: ' + (sum || 'no summary'));
  };
  try { await run(); } catch (e) { ok(false, 'the check threw: ' + (e && e.message || e)); }
  const errors = (window.__errors || []).slice(0, 10);
  ok(!errors.length, 'no page errors' + (errors.length ? ': ' + errors.join(' | ') : ''));
  return {steps, errors, ua: navigator.userAgent};
};
