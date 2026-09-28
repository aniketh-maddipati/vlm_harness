// Lumina core: pure logic shared by the design prototype and the app. No UI.
// Browser-only: measure() needs a canvas, zip() returns a Blob. Edit here; the prototype loads this file.
(function(g){
let _crcT=null;

// Sony ARW (TIFF) header → capture time, exposure, focal length, EV comp, ISO, orientation,
// and the largest embedded JPEG preview [offset, length].
function parseHead(u8,size){ const dv=new DataView(u8.buffer,u8.byteOffset,u8.byteLength), le=u8[0]===0x49&&u8[1]===0x49; if(!le&&!(u8[0]===0x4d&&u8[1]===0x4d)) return null;
    const g16=o=>dv.getUint16(o,le), g32=o=>dv.getUint32(o,le), in_=o=>o>=0&&o+4<=u8.length; const seen=new Set(), jpgs=[], o={};
    const str=(p,n)=>{ let s=''; for(let i=0;i<n&&p+i<u8.length;i++){ const c=u8[p+i]; if(!c) break; s+=String.fromCharCode(c); } return s.trim(); };
    const rat=(p,signed)=>in_(p+4)?(signed?dv.getInt32(p,le)/dv.getInt32(p+4,le):g32(p)/g32(p+4)):null;
    const walk=(off,d)=>{ if(!off||seen.has(off)||d>6||off+2>u8.length) return; seen.add(off); const n=g16(off); if(n===0||n>1000||off+2+n*12+4>u8.length) return; let jo=0,jl=0; const subs=[];
      for(let i=0;i<n;i++){ const e=off+2+i*12, tag=g16(e), type=g16(e+2), cnt=g32(e+4), vo=e+8, val=()=>(type===3&&cnt===1)?g16(vo):g32(vo), sp=()=>cnt>4?g32(vo):vo;
        if(tag===0x0201) jo=val(); else if(tag===0x0202) jl=val(); else if(tag===0x8769) subs.push(val());
        else if(tag===0x9003&&!o.date) o.date=str(sp(),cnt); else if(tag===0x829A) o.exp=rat(g32(vo)); else if(tag===0x920A) o.fl=rat(g32(vo)); else if(tag===0x9204) o.ev=rat(g32(vo),true); else if(tag===0x8827) o.iso=val(); else if(tag===0x0112&&!o.orient) o.orient=val(); }
      if(jo&&jl&&jo+jl<=size) jpgs.push([jo,jl]); subs.forEach(s=>walk(s,d+1)); walk(g32(off+2+n*12),d+1); };
    walk(g32(4),0); jpgs.sort((a,b)=>b[1]-a[1]); o.preview=jpgs[0]||null; return o; }

// Preview bitmap → mean luminance 0–1, Laplacian variance (focus), % clipped pixels.
function measure(bmp){ const W=bmp.width,H=bmp.height, c=document.createElement('canvas'); c.width=W; c.height=H; const x=c.getContext('2d',{willReadFrequently:true}); x.drawImage(bmp,0,0); const d=x.getImageData(0,0,W,H).data, g=new Float32Array(W*H); let sum=0,clip=0;
    for(let i=0,j=0;i<d.length;i+=4,j++){ const y=0.299*d[i]+0.587*d[i+1]+0.114*d[i+2]; g[j]=y; sum+=y; if(d[i]>=250&&d[i+1]>=250&&d[i+2]>=250) clip++; }
    let m=0,m2=0,k=0; for(let yy=1;yy<H-1;yy++) for(let xx=1;xx<W-1;xx++){ const j=yy*W+xx, l=4*g[j]-g[j-1]-g[j+1]-g[j-W]-g[j+W]; m+=l; m2+=l*l; k++; }
    const mean=m/k; return {lum:sum/(W*H)/255, focus:m2/k-mean*mean, clip:100*clip/(W*H), canvas:c}; }

function crc32(u8){ let T=_crcT; if(!T){ T=new Uint32Array(256); for(let n=0;n<256;n++){ let c=n; for(let k=0;k<8;k++) c=c&1?0xEDB88320^(c>>>1):c>>>1; T[n]=c>>>0; } _crcT=T; } let c=0xFFFFFFFF; for(let i=0;i<u8.length;i++) c=T[(c^u8[i])&0xFF]^(c>>>8); return (c^0xFFFFFFFF)>>>0; }

// Stored (uncompressed) zip. files: [{name, data:Uint8Array}]
function zip(files){ const enc=new TextEncoder(), parts=[], cen=[]; let off=0;
    for(const f of files){ const nm=enc.encode(f.name), crc=crc32(f.data), sz=f.data.length, h=new DataView(new ArrayBuffer(30));
      h.setUint32(0,0x04034b50,true); h.setUint16(4,20,true); h.setUint16(12,0x21,true); h.setUint32(14,crc,true); h.setUint32(18,sz,true); h.setUint32(22,sz,true); h.setUint16(26,nm.length,true); parts.push(new Uint8Array(h.buffer),nm,f.data);
      const c=new DataView(new ArrayBuffer(46)); c.setUint32(0,0x02014b50,true); c.setUint16(4,20,true); c.setUint16(6,20,true); c.setUint16(14,0x21,true); c.setUint32(16,crc,true); c.setUint32(20,sz,true); c.setUint32(24,sz,true); c.setUint16(28,nm.length,true); c.setUint32(42,off,true); cen.push(new Uint8Array(c.buffer),nm); off+=30+nm.length+sz; }
    const cs=cen.reduce((a,b)=>a+b.length,0), e=new DataView(new ArrayBuffer(22)); e.setUint32(0,0x06054b50,true); e.setUint16(8,files.length,true); e.setUint16(10,files.length,true); e.setUint32(12,cs,true); e.setUint32(16,off,true);
    return new Blob([...parts,...cen,new Uint8Array(e.buffer)],{type:'application/zip'}); }

// Set rating + label in an existing XMP; everything else (Lightroom edits) untouched.
function mergeXmp(src,rating,final){ let x=src; const setA=(name,val)=>{ const re=new RegExp('(<(?:[\\w-]+:)?'+name.replace(':','\\:')+'>)[^<]*(</)'), ra=new RegExp(name.replace(':','\\:')+'\\s*=\\s*"[^"]*"');
      if(ra.test(x)) x=x.replace(ra,name+'="'+val+'"'); else if(re.test(x)) x=x.replace(re,'$1'+val+'$2'); else x=x.replace(/<rdf:Description\b/,m=>m+' '+name+'="'+val+'"'); };
    const d=/<rdf:Description\b[^>]*>/.exec(x); if(d&&!/xmlns:xmp\s*=/.test(x)) x=x.replace(/<rdf:Description\b/,m=>m+' xmlns:xmp="http://ns.adobe.com/xap/1.0/"');
    setA('xmp:Rating',rating); if(final) setA('xmp:Label',final); return x; }

// Photos → rows (gap > 90 s), groups (< 1 s apart; bracket = 3+ frames spanning −/+ EV),
// flags (soft / blown / shake), ranks, suggested keeps, navigation nodes.
function buildShoot(list,cuts){ const light=h=>h<11?'morning':h<15?'midday':h<18?'afternoon':'evening';
    const ts=p=>{ const m=/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/.exec(p.date||''); return m?Date.UTC(+m[1],+m[2]-1,+m[3],+m[4],+m[5],+m[6]):0; };
    const P=list.map(p=>({...p,t:ts(p)})).sort((a,b)=>a.t-b.t||a.path.localeCompare(b.path));
    const fs=P.map(p=>p.focus).slice().sort((a,b)=>a-b), pct=v=>{ let lo=0,hi=fs.length; while(lo<hi){ const m=(lo+hi)>>1; if(fs[m]<v) lo=m+1; else hi=m; } return Math.round(100*lo/Math.max(1,fs.length-1)); };
    const byId={}, G={}, M=[]; let cur=null, n=0;
    P.forEach((q,idx)=>{ const prev=P[idx-1], gap=prev?(q.t-prev.t)/1000:1e9; if(!cur||gap>90){ const d=new Date(q.t), hh=d.getUTCHours(); cur={hh,time:String(hh).padStart(2,'0')+':'+String(d.getUTCMinutes()).padStart(2,'0'),fr:[]}; M.push(cur); }
      const id='f'+n, hh=new Date(q.t).getUTCHours(), fl=q.fl||0, shake=!!(q.exp&&fl&&q.exp>2/fl);
      const p={id,n,mi:M.length-1,fileObj:q.fileObj,xpath:q.xpath,xmp:q.xmp||null,lrEd:!!q.lrEd,portrait:!!q.portrait,src:q.src,lg:q.lg,zsrc:q.lg,ev:0,time:cur.time,hh,light:light(hh),h:q.lum,sharp:pct(q.focus),focus:q.focus,fx:50,fy:50,start:!prev||gap>1||cur.fr.length===0,bk:false,evs:q.ev,seed:0,sug:null,bl:0,clip:+q.clip.toFixed(1),blown:q.clip>2,shake,ss:q.exp?(q.exp>=1?q.exp.toFixed(1)+'s':'1/'+Math.round(1/q.exp)):'',fl:fl?Math.round(fl):0,file:q.name};
      byId[id]=p; cur.fr.push(p); n++; });
    M.forEach((m,mi)=>{ m.mi=mi; m.id='m'+mi; m.light=light(m.hh);
      const gs=[]; m.fr.forEach((p,i)=>{ const st=i===0?true:(cuts[p.id]!=null?cuts[p.id]:p.start); if(st) gs.push([]); gs[gs.length-1].push(p); });
      let groups=gs.map(g=>{ const evs=g.map(f=>f.evs), br=g.length>=3&&evs.every(v=>v!=null)&&new Set(evs.map(v=>v.toFixed(1))).size===g.length&&Math.min(...evs)<0&&Math.max(...evs)>0;
        const kind=g.length<2?'single':br?'bracket':'burst'; g.forEach(f=>{ f.bk=kind==='bracket'; });
        if(kind==='burst'){ const mx=Math.max(...g.map(f=>f.focus)); g.forEach(f=>{ f.soft=f.focus<mx*0.45; f.slight=!f.soft&&f.focus<mx*0.7; }); } else g.forEach(f=>{ f.soft=f.sharp<12; f.slight=!f.soft&&f.sharp<25; });
        const ranked=kind==='bracket'?[...g]:[...g].sort((a,b)=>b.focus-a.focus); ranked.forEach((f,r)=>{ f.rank=r+1; f.bn=g.length; f.kind=kind; }); const gid='g'+g[0].n; g.forEach(f=>f.gid=gid); return G[gid]={gid,frames:g,ranked,kind}; });
      const subs=[]; groups.forEach(g=>{ if(g.kind==='single'){ const L=subs[subs.length-1]; if(L&&L.kind==='singles') L.frames.push(g.frames[0]); else subs.push({kind:'singles',frames:[g.frames[0]]}); } else subs.push({kind:g.kind,gid:g.gid,frames:g.frames}); });
      subs.forEach(sb=>{ sb.id=sb.gid||('r'+sb.frames[0].id); sb.ids=sb.frames.map(f=>f.id); }); m.groups=groups; m.subs=subs; m.time=m.time; });
    const R=M.map(m=>({id:m.id,m,groups:m.groups.map(x=>x.frames.length<2?{frames:x.frames}:{burst:true,bracket:x.kind==='bracket',frames:x.frames})}));
    R.forEach(r=>r.ids=r.m.subs.flatMap(x=>x.ids));
    const N=[], sub={}, sugKeep={}; R.forEach(r=>{ N.push({id:r.id,type:'moment',mi:r.m.mi,ids:r.ids}); r.m.subs.forEach(sb=>{ N.push({id:sb.id,type:'sub',mi:r.m.mi,ids:sb.ids,kind:sb.kind}); sb.ids.forEach(i=>sub[i]=sb.id); }); });
    Object.values(G).forEach(g=>{ if(g.kind==='bracket') g.frames.forEach(f=>sugKeep[f.id]=true); else if(g.kind==='burst'){ const k=g.ranked.find(f=>!f.blown&&!f.shake&&!f.soft)||g.ranked[0]; sugKeep[k.id]=true; } else { const f=g.frames[0]; if(!f.soft&&!f.blown&&!f.shake) sugKeep[f.id]=true; } });
    return {M,G,R,byId,N,sub,sugKeep,order:R.flatMap(r=>r.ids)}; }

// New sidecar. dev = {Exposure, Contrast, Highlights, Shadows, Temp} or null for ratings only.
function freshXmp(rating,label,dev){
  let a='xmp:Rating="'+rating+'"'+(label?' xmp:Label="'+label+'"':'');
  if(dev){ const f=(v,d=2)=>(v>=0?'+':'')+(+v).toFixed(d); a+=' crs:Version="15.0" crs:ProcessVersion="11.0" crs:HasSettings="True" crs:Exposure2012="'+f(dev.Exposure||0)+'" crs:Contrast2012="'+f(dev.Contrast||0,0)+'" crs:Highlights2012="'+f(dev.Highlights||0,0)+'" crs:Shadows2012="'+f(dev.Shadows||0,0)+'"'+(dev.Temp?' crs:WhiteBalance="Custom" crs:Temperature="'+Math.round(dev.Temp)+'" crs:Tint="+0"':''); }
  return '<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>\n<x:xmpmeta xmlns:x="adobe:ns:meta/">\n <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" '+a+'/>\n </rdf:RDF>\n</x:xmpmeta>\n<?xpacket end="w"?>\n'; }

// Existing sidecar already has develop settings (edited in Lightroom / Camera Raw)?
function hasDevelop(x){ return !!(x&&(/crs:HasSettings\s*=\s*"True"/i.test(x)||/<crs:HasSettings>True</i.test(x)||/crs:(Exposure2012|Temperature|Contrast2012|Highlights2012|Shadows2012)/.test(x))); }

// Export folder layout. target: 'lr' | 'c1' | 'raw' | 'jpg' | 'both'.
// items: [{file:'DSC01234.ARW', xmp:'DSC01234.xmp' (original case kept), rel:'sub/DSC01234.xmp'}]
function exportPlan(target,shoot,items){
  if(target==='lr'||target==='c1') return items.map(it=>({path:it.rel||it.xmp,kind:'xmp'}));
  const out=[], raw=target==='both'?shoot+'/RAW/':shoot+'/', jpg=target==='both'?shoot+'/JPEG/':shoot+'/';
  if(target==='raw'||target==='both') items.forEach(it=>{ out.push({path:raw+it.file,kind:'raw'}); out.push({path:raw+it.xmp,kind:'xmp'}); });
  if(target==='jpg'||target==='both') items.forEach(it=>out.push({path:jpg+it.file.replace(/\.[^.]+$/,'')+'.jpg',kind:'jpg'}));
  return out; }

const LuminaCore={parseHead,measure,crc32,zip,mergeXmp,freshXmp,hasDevelop,buildShoot,exportPlan};
g.LuminaCore=LuminaCore; if(typeof module!=='undefined'&&module.exports) module.exports=LuminaCore;
})(typeof window!=='undefined'?window:globalThis);
