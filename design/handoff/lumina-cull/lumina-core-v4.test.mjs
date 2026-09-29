// node lumina-core-v4.test.mjs
import fs from 'node:fs'; import {createRequire} from 'node:module';
const LC=createRequire(import.meta.url)('./lumina-core-v4.js'), fx=JSON.parse(fs.readFileSync(new URL('./lumina-core-v4.fixtures.json',import.meta.url)));
let bad=0; const eq=(n,a,b)=>{ const ok=JSON.stringify(a)===JSON.stringify(b); console.log(ok?'ok  ':'FAIL',n); if(!ok){ bad++; console.log(' got ',JSON.stringify(a),'\n want',JSON.stringify(b)); } };
{ const r=LC.sweep(fx.sweep.premarked,fx.sweep.ids,fx.sweep.kept,{}), v=Object.values(r.marks);
  eq('sweep 31 · mark 2',{keep:v.filter(x=>x==='keep').length,out:v.filter(x=>x==='out').length,label:r.undo.label},fx.sweep.expect);
  eq('undo restores exactly',LC.undoSweep(r.marks,r.undo),fx.sweep.premarked);
  const fl=LC.sweep({},fx.sweep.ids,['f0'],{f1:true}); eq('flagged frame untouched by sweep',fl.marks.f1,undefined); }
const sum=d=>d.M.map(m=>m.fr.length+(m.reason?'('+m.reason+')':''));
for(const k of Object.keys(fx.rows)) eq('rows '+k,sum(LC.buildShoot(fx.rows[k].input,{})),fx.rows[k].expect);
const kinds=d=>d.M.flatMap(m=>m.groups.map(g=>g.kind+':'+g.frames.length));
eq('stacks from Sony sequence numbers',kinds(LC.buildShoot(fx.stacks.input,{})),fx.stacks.expect);
eq('α7 III whole seconds · 10 stays 10',kinds(LC.buildShoot(fx.a7iii.input,{})),fx.a7iii.expect);
eq('B splits a row',sum(LC.buildShoot(fx.split.input,fx.split.cutsRow)),fx.split.expectRow);
eq('⇧B merges rows',sum(LC.buildShoot(fx.split.input,fx.split.cutsJoin)),fx.split.expectJoin);
eq('burst then singles stays one row',sum(LC.buildShoot(fx.afterBurst.input,{})),fx.afterBurst.expect);
eq('drop onto a row header moves photos',sum(LC.buildShoot(fx.moves.input,fx.moves.to)),fx.moves.expectTo);
eq('drop between rows makes a row',sum(LC.buildShoot(fx.moves.input,fx.moves.newAfter)),fx.moves.expectNew);
eq('dragged boundary says you moved this',sum(LC.buildShoot(fx.moves.input,fx.moves.moved)),fx.moves.expectMoved);
eq('drop onto a stack merges',kinds(LC.buildShoot(fx.stacks.input,fx.stackMerge.cuts)),fx.stackMerge.expect);
{ const d=LC.buildShoot(fx.peak.input,{}), pk=Object.values(d.byId).find(f=>f.peak); eq('motion peak in a stack',pk&&pk.file,fx.peak.expect); }
{ const d=LC.buildShoot(fx.dark.input,{}); eq('dark flag under 8 %',d.order.map(id=>d.byId[id].dark),fx.dark.expect); }
{ const d=LC.buildShoot(fx.twoBody.input,{}); eq('two bodies: serial, then file number',d.order.map(id=>d.byId[id].file),fx.twoBody.expect); }
{ const r=LC.rowDone(fx.rowDone.marks,fx.rowDone.ids,'keep',fx.rowDone.flags); eq('row double-click keeps undecided, skips flagged',{marks:r.marks,label:r.undo.label},fx.rowDone.expect); eq('row undo restores',LC.undoSweep(r.marks,r.undo),fx.rowDone.marks); }
{ const r=LC.paint(fx.paint.marks,fx.paint.ids,fx.paint.verb,fx.paint.flags); eq('paint rejects, skips flagged',{marks:r.marks,label:r.undo.label},fx.paint.expect); eq('paint undo restores',LC.undoSweep(r.marks,r.undo),fx.paint.marks); }
process.exit(bad?1:0);
