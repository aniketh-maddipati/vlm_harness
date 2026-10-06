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
// §9 begin (CHANGES-v0.02 §9 + v0.03 look string)
{ const tiff=E=>{ const out=new Uint8Array(4096), dv=new DataView(out.buffer); out[0]=out[1]=0x49; dv.setUint16(2,42,true); dv.setUint32(4,8,true); let end=8; const alloc=n=>{ const o=end; end+=n+(n&1); return o; };
    const ifd=L=>{ const off=alloc(2+L.length*12+4); dv.setUint16(off,L.length,true); L.forEach(([tag,type,v],i)=>{ const e=off+2+i*12; dv.setUint16(e,tag,true); dv.setUint16(e+2,type,true);
        if(v&&v.ifd){ dv.setUint32(e+4,1,true); dv.setUint32(e+8,ifd(v.ifd),true); return; }
        if(v instanceof Uint8Array){ dv.setUint32(e+4,v.length,true); if(v.length<=4) out.set(v,e+8); else { const p=alloc(v.length); out.set(v,p); dv.setUint32(e+8,p,true); } return; }
        const a=[].concat(v), sz=type===3?2:4; dv.setUint32(e+4,a.length,true); let p=e+8; if(a.length*sz>4){ p=alloc(a.length*sz); dv.setUint32(e+8,p,true); } a.forEach((x,k)=>sz===2?dv.setUint16(p+k*2,x,true):dv.setUint32(p+k*4,x,true)); });
      dv.setUint32(off+2+L.length*12,0,true); return off; };
    ifd(E); return out.slice(0,end); };
  const head=E=>LC.parseHead(tiff(E),1e6);
  const mn=seq=>{ const b=new Uint8Array(18), d=new DataView(b.buffer); d.setUint16(0,1,true); d.setUint16(2,0xB04A,true); d.setUint16(4,3,true); d.setUint32(6,1,true); d.setUint16(10,seq,true); return b; };
  eq('head under 8 bytes → null',LC.parseHead(new Uint8Array(7),7),null);
  { const m=head([[0x00FE,4,1],[0x0100,4,640],[0x0101,4,480],[0x0103,3,7],[0x0142,4,256],[0x0143,4,256],[0x0144,4,[10000,20000,30000,40000,50000,60000]],[0x0145,4,[5000,5000,5000,5000,5000,5000]]]);
    eq('tiled preview → pvParts',m&&m.pvParts&&{tiled:m.pvParts.tiled,n:m.pvParts.parts.length,w:m.pvParts.w,h:m.pvParts.h,preview:m.preview},{tiled:true,n:6,w:640,h:480,preview:null}); }
  { const m=head([[0x00FE,4,1],[0x0100,4,640],[0x0101,4,480],[0x0103,3,7],[0x0111,4,[10000,20000,30000]],[0x0116,4,160],[0x0117,4,[4000,4000,4000]]]);
    eq('multi-strip preview → pvParts',m&&m.pvParts&&{tiled:m.pvParts.tiled,n:m.pvParts.parts.length,rps:m.pvParts.rps},{tiled:false,n:3,rps:160}); }
  { const m=head([[0x00FE,4,1],[0x0100,4,160],[0x0101,4,120],[0x0102,3,[8,8,8]],[0x0103,3,1],[0x0106,3,2],[0x0111,4,10000],[0x0115,3,3],[0x0116,4,120],[0x0117,4,57600]]);
    eq('pixel-rgb-thumb → pvRGB',m&&m.pvRGB&&{w:m.pvRGB.w,h:m.pvRGB.h,spp:m.pvRGB.spp},{w:160,h:120,spp:3}); }
  { const m=head([[0x0110,2,new Uint8Array([73,76,67,69,0])],[0x8769,4,{ifd:[[0x927C,7,mn(3)]]}]]); eq('SONY-less MakerNote is read · frame 3 of 5 → seqImage 3',m&&m.seqImage,3); }
  { const m=head([[0x0110,2,new Uint8Array([73,76,67,69,0])],[0x8769,4,{ifd:[[0x927C,7,mn(0)]]}]]); eq('single shot → seqImage null',m&&m.seqImage,null); } }
{ const base=(i,o)=>({name:'DSC'+(10000+i)+'.ARW',path:'s/'+i,date:'2026:09:26 15:00:'+String(o.sec??i*3).padStart(2,'0'),exp:0.004,fl:50,ev:null,iso:100,lens:'FE 50',lum:0.5,focus:300,clip:0,portrait:false,src:'',lg:'',...o}), fl=(d,k)=>d.order.map(id=>d.byId[id][k]);
  eq('a single is never soft',fl(LC.buildShoot([base(0,{focus:5})],{}),'soft'),[false]);
  eq('burst frame under 0.45× its sharpest is soft',fl(LC.buildShoot([0,1,2].map(i=>base(i,{sec:0,seqImage:i+1,focus:[300,100,290][i]})),{}),'soft'),[false,true,false]);
  eq('a bracket is never blown',fl(LC.buildShoot([0,1,2].map(i=>base(i,{sec:0,releaseMode2:2,clip:[20,0,1][i]})),{}),'blown'),[false,false,false]);
  eq('single at 6 % clip, row median 1 % → blown',fl(LC.buildShoot([0,1,2,3,4].map(i=>base(i,{clip:i===4?6:1})),{}),'blown')[4],true);
  eq('single at 6 % clip, row median 4 % → not blown',fl(LC.buildShoot([0,1,2,3,4].map(i=>base(i,{clip:i===4?6:4})),{}),'blown')[4],false); }
{ const f=LC.freshXmp(3,'',null,'Lumina pass 2');
  eq('freshXmp writes dc:subject + lr:hierarchicalSubject',[f.includes('<dc:subject><rdf:Bag><rdf:li>Lumina pass 2</rdf:li>'),f.includes('<lr:hierarchicalSubject><rdf:Bag><rdf:li>Lumina|pass 2</rdf:li>')],[true,true]);
  const src='<x:xmpmeta><rdf:RDF><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:lr="http://ns.adobe.com/lightroom/1.0/" xmp:Rating="2"><dc:subject><rdf:Bag><rdf:li>Lumina pass 1</rdf:li><rdf:li>Family</rdf:li></rdf:Bag></dc:subject><lr:hierarchicalSubject><rdf:Bag><rdf:li>Lumina|pass 1</rdf:li><rdf:li>People|Family</rdf:li></rdf:Bag></lr:hierarchicalSubject></rdf:Description></rdf:RDF></x:xmpmeta>', m=LC.mergeXmp(src,3,null,'Lumina pass 3');
  eq('mergeXmp replaces the old Lumina pass keyword, keeps others',[m.includes('Lumina pass 3'),m.includes('Lumina pass 1'),m.includes('Family'),m.includes('Lumina|pass 3'),m.includes('Lumina|pass 1'),m.includes('People|Family')],[true,false,true,true,false,true]);
  const s=LC.mergeXmp('<x:xmpmeta><rdf:RDF><rdf:Description rdf:about="" xmp:Rating="1"/></rdf:RDF></x:xmpmeta>',2,null,'Lumina pass 2');
  eq('mergeXmp on a bare sidecar adds both bags',[s.includes('<rdf:li>Lumina pass 2</rdf:li>'),s.includes('<rdf:li>Lumina|pass 2</rdf:li>'),s.includes('xmp:Rating="2"')],[true,true,true]); }
{ const ex='ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0', srt=o=>JSON.stringify(Object.keys(o).sort().map(k=>[k,o[k]]));
  eq('look string: roadmap example parse → format is identical',LC.lookString(LC.parseLook(ex)),ex);
  const L={ev:0.35,wb:5600,tint:-4,crop:{x:0.1,y:0,w:0.8,h:1,ang:1.5,ratio:'4:5'},curve:[[0,0],[0.5,0.55],[1,1]],sat_red:-10,bw:true}, s=LC.lookString(L);
  eq('look string: Edit keys round-trip (crop, curve, sat_<colour>, bw)',srt(LC.parseLook(s)),srt(L)); eq('look string: parse → format → parse is stable',LC.lookString(LC.parseLook(s)),s);
  eq('look string: canonical order and signs',LC.lookString({sh:25,ev:-0.3,hl:0,wb:5200}),'ev:-0.30 wb:5200/ hl:0 sh:+25'); eq('as-shot look → empty string',LC.lookString({}),''); }
{ const b=(i,o)=>({name:'DSC'+(10000+i)+'.ARW',path:'s/DSC'+(10000+i)+'.ARW',date:'2026:09:26 15:'+String(10+i).padStart(2,'0')+':00',exp:0.004,fl:50,ev:null,iso:100,lens:'FE 50',lum:0.5,focus:300,clip:0,portrait:false,src:'',lg:'',...o});
  const d=LC.buildShoot([b(0,{}),b(1,{}),b(2,{date:'',unread:true,nopv:true,focus:0}),b(3,{}),b(4,{date:'2026:09:26 18:00:00'})],{});
  eq('no capture time → after the nearest lower file number, same row, never 00:00',d.M.map(m=>[m.time,m.fr.map(f=>f.file)]),[['15:10',['DSC10000.ARW','DSC10001.ARW','DSC10002.ARW','DSC10003.ARW']],['18:00',['DSC10004.ARW']]]);
  eq('unreadable photo is always a single',Object.values(d.G).filter(g=>g.frames.some(f=>f.unread)).map(g=>g.kind),['single']); }
// §9 end
process.exit(bad?1:0);
