// The Skim page's grid layout maths (canvas plan 1.2), runnable outside a browser.
//
// The page is the one implementation; this reads the static lay* functions out of it, the same way
// skim-export.mjs reads buildX, and hangs them on a bare Component so they can call each other.
//
//   node --test Tests/web/skim-layout.test.mjs
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

export const NAMES = ['layGeo', 'laySceneGeo', 'layClips', 'layScenes', 'layout', 'layHit'];

export function loadLayout(pagePath = PAGE){
  const src = fs.readFileSync(pagePath, 'utf8');
  const Component = {}, sources = {};
  for (const name of NAMES){
    const m = src.match(new RegExp('\\n  static ' + name + '\\(([^)]*)\\) \\{'));
    if (!m) throw new Error('layout function not found: ' + name);
    const body = extractMethod(src, name, 'static ' + name + '(' + m[1] + ') {').replace(/^static /, 'function ');
    sources[name] = body;
    Component[name] = new Function('Component', 'return ' + body)(Component);
  }
  return { Component, sources };
}

/** A shoot of n clips cut into scenes of uneven size, as [{i, n}], the shape the page hands layClips. */
export function groupsOf(n, scenes, seed = 7){
  let s = seed >>> 0; const rnd = () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
  const w = Array.from({length:scenes}, () => 0.2 + rnd()), tot = w.reduce((a, b) => a + b, 0);
  const out = w.map((x, i) => ({i, n:Math.max(1, Math.floor(x / tot * n))}));
  let left = n - out.reduce((a, g) => a + g.n, 0);
  for (let i = 0; left !== 0; i = (i + 1) % scenes){ if (left > 0){ out[i].n++; left--; } else if (out[i].n > 1){ out[i].n--; left++; } }
  return out;
}
