// node lumina-core.test.mjs — checks a port (or this file) against the prototype's outputs.
import fs from 'node:fs'; import {createRequire} from 'node:module';
const LC=createRequire(import.meta.url)('./lumina-core.js'), fx=JSON.parse(fs.readFileSync(new URL('./lumina-core.fixtures.json',import.meta.url)));
let bad=0; const eq=(n,a,b)=>{ const ok=JSON.stringify(a)===JSON.stringify(b); if(!ok){ bad++; console.log('FAIL',n,'\n got ',JSON.stringify(a).slice(0,400),'\n want',JSON.stringify(b).slice(0,400)); } else console.log('ok  ',n); };
const d=LC.buildShoot(fx.buildShoot.input,{});
eq('buildShoot',{rows:d.M.map(m=>({time:m.time,groups:m.groups.map(g=>({kind:g.kind,files:g.frames.map(f=>f.file)}))})),flags:Object.values(d.byId).map(p=>({file:p.file,soft:!!p.soft,blown:p.blown,shake:p.shake,rank:p.rank})),keep:Object.keys(d.sugKeep).map(id=>d.byId[id].file)},fx.buildShoot.expect);
fx.mergeXmp.forEach((c,i)=>eq('mergeXmp '+i,LC.mergeXmp(c.src,c.rating,c.label),c.expect));
fx.freshXmp.forEach((c,i)=>eq('freshXmp '+i,LC.freshXmp(c.rating,c.label,c.dev),c.expect));
fx.hasDevelop.forEach((c,i)=>eq('hasDevelop '+i,LC.hasDevelop(c.src),c.expect));
fx.exportPlan.forEach((c,i)=>eq('exportPlan '+i,LC.exportPlan(c.target,c.shoot,c.items),c.expect));
eq('crc32',LC.crc32(new TextEncoder().encode(fx.crc32.input)),fx.crc32.expect);
process.exit(bad?1:0);
