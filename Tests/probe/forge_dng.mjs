// Writes the synthetic phone-DNG fixtures (Tests/web/dng-fixtures.mjs) into a folder, for the probe's fixture root.
// Only under ~/LuminaEvidence or the system temp folder (symlinks resolved); never replaces a file.
//
//   node Tests/probe/forge_dng.mjs <dir>       e.g. ~/LuminaEvidence/fixtures/dng
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fixtures } from '../web/dng-fixtures.mjs';

const fail = msg => { console.error('forge_dng: ' + msg); process.exit(2); };
const arg = process.argv[2];
if (!arg) fail('usage: node Tests/probe/forge_dng.mjs <dir under ~/LuminaEvidence or the temp folder>');

// The real path of `p`, resolving symlinks in the part that exists so far.
const real = p => { let head = path.resolve(p); const tail = []; while (!fs.existsSync(head)) { tail.unshift(path.basename(head)); const up = path.dirname(head); if (up === head) break; head = up; } return path.join(fs.realpathSync(head), ...tail); };
const roots = [path.join(os.homedir(), 'LuminaEvidence'), os.tmpdir()].map(real);
const dir = real(arg);
if (!roots.some(r => dir.startsWith(r + path.sep))) fail(`refusing ${dir}: not under ${roots.join(' or ')}`);

fs.mkdirSync(dir, { recursive: true });
let total = 0;
for (const f of fixtures()) {
  const p = path.join(dir, f.name);
  try { fs.writeFileSync(p, f.bytes, { flag: 'wx' }); } catch (e) { if (e.code === 'EEXIST') fail(`${p} exists, not replacing it`); throw e; }
  total += f.bytes.length; console.log(`${String(f.bytes.length).padStart(8)}  ${f.name}  (${f.id})`);
}
console.log(`${String(total).padStart(8)}  total, ${dir}`);
