// A folder of n synthetic ARWs with camera-sized, detailed previews (bursts, stacks, rows), for the
// scroll probe on a machine without a card (CI's macOS runner). No personal data.
//
//   node Tests/web/make-shoot.mjs <dir> [n=775]
import path from 'path';
import { pw, makeBigJpegs, makeBigShoot, deadline } from './lib.mjs';

deadline('make-shoot.mjs', 300);

const dir = path.resolve(process.argv[2] || 'scroll-shoot'), n = +(process.argv[3] || 775);
const b = await pw.chromium.launch();
const jpegs = await makeBigJpegs(b, 24);
await b.close();
makeBigShoot(dir, jpegs, n);
console.log(`${n} ARWs in ${dir}`);
