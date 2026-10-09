// A small DOMParser for Node, enough to run the page's checkX outside a browser: elements, attributes and
// the handful of members checkX reads (documentElement, tagName, children, getAttribute). No package.
// Like a browser's, parseFromString never throws: text that is not well-formed gives a document whose
// root is <parsererror>. It is stricter than nothing and looser than a real XML parser; the browser run
// of the Export screen is what exercises the real one.
const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const NAME = /^[A-Za-z_:][\w:.-]*/;

class El {
  constructor(tagName){ this.tagName = tagName; this.attrs = {}; this.children = []; }
  getAttribute(n){ return Object.prototype.hasOwnProperty.call(this.attrs, n) ? this.attrs[n] : null; }
}

function text(s){
  if (s.includes('<')) throw new Error('< in text');
  return s.replace(/&(#x[0-9a-fA-F]+|#\d+|\w+);|&/g, (m, e) => {
    if (!e) throw new Error('bare &');
    if (e[0] === '#') return String.fromCodePoint(e[1] === 'x' ? parseInt(e.slice(2), 16) : +e.slice(1));
    if (!(e in ENT)) throw new Error('unknown entity ' + e);
    return ENT[e];
  });
}

function parse(src){
  let i = 0, root = null; const open = [];
  const fail = why => { throw new Error(why + ' at ' + i); };
  if (src.startsWith('<?xml')) { const e = src.indexOf('?>'); if (e < 0) fail('unclosed declaration'); i = e + 2; }
  while (i < src.length) {
    if (src[i] !== '<') {
      const e = src.indexOf('<', i), t = src.slice(i, e < 0 ? src.length : e);
      if (!open.length && t.trim()) fail('text outside the root');
      text(t); i = e < 0 ? src.length : e; continue;
    }
    if (src.startsWith('<!--', i)) { const e = src.indexOf('-->', i); if (e < 0) fail('unclosed comment'); i = e + 3; continue; }
    if (src.startsWith('<!DOCTYPE', i)) { if (root) fail('late doctype'); const e = src.indexOf('>', i); if (e < 0) fail('unclosed doctype'); i = e + 1; continue; }
    if (src[i + 1] === '/') {
      const m = NAME.exec(src.slice(i + 2)); if (!m) fail('bad closing tag');
      const top = open.pop(); if (!top || top.tagName !== m[0]) fail('closing tag does not match');
      i += 2 + m[0].length; while (/\s/.test(src[i])) i++;
      if (src[i] !== '>') fail('bad closing tag'); i++; continue;
    }
    const m = NAME.exec(src.slice(i + 1)); if (!m) fail('bad tag');
    if (root && !open.length) fail('a second root');
    const el = new El(m[0]); i += 1 + m[0].length;
    for (;;) {
      const ws = /^\s*/.exec(src.slice(i))[0].length; i += ws;
      if (src[i] === '>') { i++; (open.at(-1)?.children ?? []).push(el); if (!root) root = el; open.push(el); break; }
      if (src.startsWith('/>', i)) { i += 2; (open.at(-1)?.children ?? []).push(el); if (!root) root = el; break; }
      if (!ws) fail('attributes run together');
      const a = NAME.exec(src.slice(i)); if (!a) fail('bad attribute');
      i += a[0].length; if (src[i] !== '=') fail('attribute without a value'); i++;
      const q = src[i]; if (q !== '"' && q !== "'") fail('unquoted attribute');
      const e = src.indexOf(q, i + 1); if (e < 0) fail('unclosed attribute');
      if (a[0] in el.attrs) fail('attribute given twice');
      el.attrs[a[0]] = text(src.slice(i + 1, e)); i = e + 1;
    }
  }
  if (open.length) fail('unclosed <' + open.at(-1).tagName + '>');
  if (!root) fail('no root');
  return root;
}

export class MiniDOMParser {
  parseFromString(src){
    let root; try { root = parse(String(src)); } catch (e) { root = new El('parsererror'); root.why = e.message; }
    return { documentElement: root };
  }
}
