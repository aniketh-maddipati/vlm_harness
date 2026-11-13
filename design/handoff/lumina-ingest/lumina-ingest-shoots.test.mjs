// node lumina-ingest-shoots.test.mjs: shoots proposed from gaps, corrected by hand, and the folder pattern.
import { createRequire } from 'module';
import assert from 'assert/strict';
const require = createRequire(import.meta.url);
const K = require('./lumina-ingest-shoots.js');

const H = 3600e3, at = (y, mo, d, h, mi = 0) => new Date(y, mo - 1, d, h, mi).getTime();
let n = 0; const shot = (t, body = 'A7M3', src = 'Card') => ({ id: 'p' + String(++n).padStart(3, '0'), t, body, src });
const run = (t0, count, stepMin, body, src) => Array.from({ length: count }, (_, i) => shot(t0 + i * stepMin * 60e3, body, src));
const shape = (shoots) => shoots.map((s) => s.parts.map((p) => p.ids.length));

// A three-day trip, one camera: nights split the days into parts, the trip stays one shoot.
const trip = [...run(at(2026, 10, 28, 9), 5, 30), ...run(at(2026, 10, 29, 8), 4, 45), ...run(at(2026, 10, 30, 7), 3, 60)];
assert.deepEqual(shape(K.propose(trip)), [[5, 4, 3]], 'one shoot holding its three days');

// Four days later: another shoot.
const later = run(at(2026, 11, 3, 14), 6, 10);
assert.deepEqual(shape(K.propose([...later, ...trip])), [[5, 4, 3], [6]], 'a gap of 36 h or more starts a new shoot; order is by time');

// 3 h apart on one camera: the same part. 3 h apart with another camera, or another card: a new part.
const am = run(at(2026, 10, 28, 9), 3, 5);
assert.deepEqual(shape(K.propose([...am, ...run(at(2026, 10, 28, 12, 30), 3, 5)])), [[6]], '3 h, same camera: one part');
assert.deepEqual(shape(K.propose([...am, ...run(at(2026, 10, 28, 12, 30), 3, 5, 'A7S3')])), [[3, 3]], '3 h and another camera: a new part');
assert.deepEqual(shape(K.propose([...am, ...run(at(2026, 10, 28, 12, 30), 3, 5, 'A7M3', 'Card 2')])), [[3, 3]], '3 h and another card: a new part');
assert.deepEqual(shape(K.propose([...am, ...run(at(2026, 10, 28, 10), 3, 5, 'A7S3')])), [[6]], 'two cameras shooting together: one part');
assert.deepEqual(shape(K.propose([...am, ...run(at(2026, 10, 28, 16), 3, 5)])), [[3, 3]], '6 h or more: a new part whatever the camera');

// By hand: split here (a part becomes the start of a new shoot), and it is undone by taking the id out.
let s = K.propose(trip);
const day2 = s[0].parts[1].start;
const cut = new Set([day2]);
s = K.propose(trip, { cut });
assert.deepEqual(shape(s), [[5], [4, 3]], 'split at day 2');
assert.equal(s[1].cut, true); assert.equal(s[1].start, day2);
cut.delete(day2);
assert.deepEqual(shape(K.propose(trip, { cut })), [[5, 4, 3]], 'undone');

// By hand: merge with next, and undone.
const both = [...trip, ...later];
s = K.propose(both);
const join = new Set([s[1].start]);
s = K.propose(both, { join });
assert.deepEqual(shape(s), [[5, 4, 3, 6]], 'merged with the next');
assert.deepEqual(s[0].joined, [...join]);
join.clear();
assert.deepEqual(shape(K.propose(both, { join })), [[5, 4, 3], [6]], 'undone');
// a merge and a split together; ids that are not there change nothing
assert.deepEqual(shape(K.propose(both, { join: new Set([K.propose(both)[1].start, 'nope']), cut: new Set([day2]) })), [[5], [4, 3, 6]]);
// every id is in exactly one shoot, in time order
s = K.propose(both);
assert.equal(s.flatMap((x) => x.ids).length, both.length);
assert.deepEqual(s.flatMap((x) => x.parts.flatMap((p) => p.ids)), s.flatMap((x) => x.ids));
assert.deepEqual(K.propose([]), []);

// Names.
assert.equal(K.draftName(at(2026, 10, 28, 9), at(2026, 10, 28, 17)), 'Oct 28, 2026');
assert.equal(K.draftName(at(2026, 10, 28, 9), at(2026, 10, 30, 17)), 'Oct 28 – 30, 2026');
assert.equal(K.draftName(at(2026, 10, 30, 9), at(2026, 11, 2, 17)), 'Oct 30 – Nov 2, 2026');

// The pattern.
const v = { t: at(2026, 10, 29, 8), start: at(2026, 10, 28, 9), shoot: 'Death Valley', kind: 'Photos', camera: 'ILCE-7M3' };
assert.equal(K.folder(null, v), '2026-10-29', 'no pattern: the plain dated folder');
assert.equal(K.folder('', v), '2026-10-29');
assert.equal(K.folder('{year}/{start} {shoot}/{kind}', v), '2026/2026-10-28 Death Valley/Photos');
assert.equal(K.folder('{year}/{month}/{date}/{camera}', v), '2026/10/2026-10-29/ILCE-7M3');
assert.equal(K.folder('{ Shoot }/{DATE}', v), 'Death Valley/2026-10-29', 'tokens in any case, spaces inside the braces');
assert.equal(K.folder('{year}/{shoot}', { ...v, shoot: '' }), '2026', 'an empty name leaves its folder out');
assert.equal(K.folder('{shoot}/{camera}', { ...v, shoot: '', camera: '' }), '2026-10-29', 'nothing left: the plain dated folder');
assert.equal(K.folder('{year}/{shoot}', { ...v, t: null }), 'No date');
assert.equal(K.folder('{year}/{nope}', v), '2026-10-29', 'a pattern that does not check is not used');
assert.equal(K.check('{year}/{nope}').ok, false); assert.deepEqual(K.check('{year}/{nope}').unknown, ['nope']);
assert.equal(K.check('Photos').ok, false, 'no token: every file would land in one folder');
assert.equal(K.check('{year').ok, false);
assert.equal(K.check(' {date} {shoot} ').pattern, '{date} {shoot}');

// Whatever the names hold, the folder stays inside the library and is one safeFolder takes.
const mirror = (f) => { const p = f.split('/').filter(Boolean); return p.length > 0 && !p.some((x) => x === '..' || x === '.' || x.startsWith('.')); };
const nasty = ['../../etc', '..', '.hidden', '/abs/path', 'a/b\\c', 'x: y', ' . . ', '\u0000\n', '...', 'ok', '', '~', 'a'.repeat(300), '{year}', '-rf'];
for (const shoot of nasty) for (const camera of nasty) for (const p of ['{shoot}/{camera}', '{year}/{shoot} {camera}', '../{shoot}/./{camera}', '.{shoot}/{date}', '/{shoot}//{kind}/', '{shoot}']) {
  const f = K.folder(p, { ...v, shoot, camera });
  assert.ok(mirror(f), `${JSON.stringify(p)} with ${JSON.stringify(shoot)} / ${JSON.stringify(camera)} → ${JSON.stringify(f)}`);
  assert.ok(!f.startsWith('/') && !f.includes('\\') && !f.includes(':') && !/\/\/|^\.|\/\./.test(f), f);
  assert.ok(f.split('/').every((x) => x.length <= 200));
}
assert.equal(K.folder('{shoot}', { ...v, shoot: '../../etc' }), '-..-etc'.replace(/^[.\s-]+/, ''), 'slashes become dashes, leading dots go');
console.log('ok   shoots from gaps, splits and merges by hand, undo, names, the folder pattern (' + nasty.length * nasty.length * 6 + ' hostile folders stay inside)');
console.log('all passed');
