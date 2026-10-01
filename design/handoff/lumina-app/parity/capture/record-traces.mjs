// Behaviour-trace recorder. Runs the scripted flows below against the prototype and records the app state after every action.
// The same flow scripts (flows.json) are replayed by the native XCTest (TraceReplayTests.swift), which compares state step by step.
// Used two ways:
//   1. Playwright:  node record-traces.mjs   (serves prototypes/, writes ../traces/*.json)
//   2. In a browser: paste recordAll into the console of a page that embeds the Workflow in an iframe.
export const FLOWS = {
  'cull-basics': { setup: 'copied', actions: ['r', 'r', 'r', 'x', 'ArrowLeft', 'r', 'Meta+z', 'Meta+z', 'Meta+Shift+z', 'u', 'ArrowDown', 'r', 'ArrowUp', 'x', 'ArrowRight', 'ArrowRight', 'Meta+z'] },
  'step-switching': { setup: 'kept6', actions: ['Meta+1', 'Meta+2', 'Meta+3', 'Meta+4', 'Meta+2', 'Meta+4', 'Meta+3', 'Meta+1', 'Meta+2'] },
  'enter-guards': { setup: 'fresh', actions: ['Enter', 'Enter', 'Enter', 'Enter', 'Enter', 'Enter', 'wait:2500', 'r', 'r', 'r', 'r', 'Meta+3', 'Enter', 'Enter', 'Enter', 'Enter', 'Enter', 'Enter', 'wait:1700', 'Enter'] },
  'edit-basics': { setup: 'kept6', actions: ['Meta+3', '.', '.', '.', 'BracketRight', '.', 'Meta+z', 'ArrowRight', 'ArrowLeft', 'Shift+.', '0', 'x', 'Meta+z', 'Equal', 'Meta+2', 'Meta+3'] },
  'edit-conflicts': { setup: 'kept6', actions: ['Meta+3', 'r', 't', 'c', 'x', 'a', '0', 'Escape', 'Shift+Slash', 'x', 'ArrowRight', 'Escape', 'z', 'h', 'Escape', 'Escape', 'v-hold', 'x', 'Escape', 'v-up'] },
  'save-flow': { setup: 'kept6', actions: ['Meta+4', 'click:save', 'Meta+s', 'click:fmt-jpeg', 'click:save', 'Meta+3', '.', 'Meta+s', 'Meta+s'] },
};

const KEYMAP = { '.': ['Period', '.'], ',': ['Comma', ','], 'BracketRight': ['BracketRight', ']'], 'BracketLeft': ['BracketLeft', '['], 'Equal': ['Equal', '='], 'Slash': ['Slash', '?'], 'Enter': ['Enter', 'Enter'], 'Escape': ['Escape', 'Escape'], 'ArrowLeft': ['ArrowLeft', 'ArrowLeft'], 'ArrowRight': ['ArrowRight', 'ArrowRight'], 'ArrowUp': ['ArrowUp', 'ArrowUp'], 'ArrowDown': ['ArrowDown', 'ArrowDown'] };

/** Runs in a page context. `w` is the Workflow window (iframe contentWindow or window). */
export async function recordFlow(w, name, flow, reload) {
  const wait = ms => new Promise(r => { const end = performance.now() + ms, ch = new MessageChannel(); ch.port1.onmessage = () => performance.now() >= end ? r() : ch.port2.postMessage(0); ch.port2.postMessage(0); });
  const ls = k => { try { return JSON.parse(w.localStorage.getItem(k) || 'null') || {}; } catch { return {}; } };
  const send = (spec, up) => { const parts = spec.split('+'), k = parts.pop(), m = new Set(parts); const [code, key] = KEYMAP[k] || (k.length === 1 ? [/[0-9]/.test(k) ? 'Digit' + k : 'Key' + k.toUpperCase(), m.has('Shift') && k === '.' ? '>' : k] : [k, k]);
    (w.document.activeElement || w.document.body).dispatchEvent(new w.KeyboardEvent(up ? 'keyup' : 'keydown', { code, key, bubbles: true, cancelable: true, metaKey: m.has('Meta'), shiftKey: m.has('Shift'), altKey: m.has('Alt') })); };
  const btn = re => [...w.document.querySelectorAll('[role="button"],[role="radio"]')].find(b => re.test((b.innerText || '').trim()));
  const snap = (action) => { const fl = (w.luminaFlow && w.luminaFlow()) || ls('lumina.flow.v1'), f = fl, s = (fl.step === 'edit' && w.luminaState && w.luminaState()) || {}, keep = (fl.step === 'edit' && s.keep) || fl.keep || ls('lumina.flow.edit.v1').keep || {}, d = w.document, t = d.body.innerText;
    const im = d.querySelector('[data-lumina-img]'), wr = im && im.parentElement && im.parentElement.parentElement, z = wr && /scale\(([\d.]+)\)/.exec(wr.style.transform || '');
    const overlay = /Trackpad/.test(t) ? 'help' : d.querySelector('[data-lumina="spectrum"]') ? 'variations' : /Cropping|Original\s*▾|Free\s*▾|Turn 90/.test(t) && /esc cancels/.test(t) ? 'crop' : ![...d.querySelectorAll('[role="slider"]')].some(x => x.getBoundingClientRect().width > 0) && f.step === 'edit' ? 'focus' : null;
    const cur = s.cur || f.cur || null;
    return { action, step: f.step || 'open', cur, kept: Object.values(keep).filter(v => v === true).length, out: Object.values(keep).filter(v => v === false).length, curDecision: cur in keep ? keep[cur] : null, look: f.step === 'edit' ? (s.look || {}) : undefined, zoom: z ? +(+z[1]).toFixed(2) : 1, overlay: f.step === 'edit' ? overlay : undefined, saved: f.saved ? { n: f.saved.n, ne: f.saved.ne, fmt: f.saved.fmt, again: !!f.saved.again, at: f.saved.sig ? f.saved.sig.length : 0 } : null }; };
  await reload(flow.setup);
  const out = [snap('(start)')];
  for (const a of flow.actions) {
    if (a.startsWith('wait:')) { await wait(+a.slice(5)); out.push(snap(a)); continue; }
    if (a === 'v-hold') { send('v'); await wait(400); out.push(snap(a)); continue; }
    if (a === 'v-up') { send('v', true); await wait(400); out.push(snap(a)); continue; }
    if (a === 'click:save') { const b = btn(/^(Save \d+ photos|Save again)/); b && b.click(); }
    else if (a === 'click:fmt-jpeg') { const b = btn(/^JPEG$/); b && b.click(); }
    else { send(a); send(a, true); }
    await wait(/Meta\+3/.test(a) ? 1300 : /Meta\+\d/.test(a) ? 600 : a === 'Enter' ? 120 : 220);
    out.push(snap(a));
  }
  return { flow: name, setup: flow.setup, steps: out };
}

// ---------- Playwright entry point
if (typeof process !== 'undefined' && process.argv[1] && process.argv[1].endsWith('record-traces.mjs')) {
  const { chromium } = await import('playwright'); const http = await import('node:http'); const fs = await import('node:fs/promises'); const path = await import('node:path');
  const PROTO = path.resolve(process.env.PROTO || '../../design_handoff_lumina_app/prototypes'), OUT = path.resolve('../traces');
  const srv = http.createServer(async (q, r) => { try { const p = path.join(PROTO, decodeURIComponent(new URL(q.url, 'http://x').pathname)); r.writeHead(200, { 'content-type': p.endsWith('.html') ? 'text/html' : 'text/javascript' }); r.end(await fs.readFile(p)); } catch { r.writeHead(404); r.end(); } }).listen(0);
  const WF = `http://127.0.0.1:${srv.address().port}/Lumina%20Workflow.dc.html`;
  const browser = await chromium.launch(); await fs.mkdir(OUT, { recursive: true });
  for (const [name, flow] of Object.entries(FLOWS)) {
    const page = await (await browser.newContext({ viewport: { width: 1100, height: 760 } })).newPage();
    await page.addScriptTag({ content: '' }).catch(() => {});
    await page.goto(WF);
    const trace = await page.evaluate(async ({ name, flow, src }) => {
      const mod = await import('data:text/javascript,' + encodeURIComponent(src));
      const reload = async setup => {
        Object.keys(localStorage).filter(k => k.startsWith('lumina.')).forEach(k => localStorage.removeItem(k)); localStorage.setItem('lumina.edit.intro.v1', '1');
        // setup runs in-page: start copy and wait, then keep 6 if asked
        const k = (code, key, o = {}) => window.dispatchEvent(new KeyboardEvent('keydown', { code, key, bubbles: true, ...o }));
        if (setup === 'fresh') return;
        k('Enter', 'Enter'); await new Promise(r => { const t = setInterval(() => { if ((JSON.parse(localStorage.getItem('lumina.flow.v1') || '{}').copied || 0) >= 117) { clearInterval(t); r(); } }, 50); });
        if (setup === 'kept6') for (let i = 0; i < 6; i++) { k('KeyR', 'r'); await new Promise(r => setTimeout(r, 50)); }
        await new Promise(r => setTimeout(r, 300));
      };
      return mod.recordFlow(window, name, flow, reload);
    }, { name, flow, src: await fs.readFile(new URL(import.meta.url), 'utf8') });
    await fs.writeFile(path.join(OUT, name + '.json'), JSON.stringify(trace, null, 1)); console.log('✓', name, trace.steps.length, 'steps');
    await page.context().close();
  }
  await browser.close(); srv.close();
}
