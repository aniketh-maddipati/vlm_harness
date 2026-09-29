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
        else if(tag===0x9003&&!o.date) o.date=str(sp(),cnt); else if(tag===0x829A) o.exp=rat(g32(vo)); else if(tag===0x920A) o.fl=rat(g32(vo)); else if(tag===0x9204) o.ev=rat(g32(vo),true); else if(tag===0x8827) o.iso=val(); else if(tag===0xA434&&!o.lens) o.lens=str(sp(),cnt); else if(tag===0xA431&&!o.serial) o.serial=str(sp(),cnt); else if(tag===0x8822) o.program=val(); else if(tag===0xA403) o.wb=val(); else if(tag===0x9209) o.flash=val()&1; else if(tag===0x0112&&!o.orient) o.orient=val(); else if(tag===0x927C&&!o._mn) o._mn=[sp(),cnt]; else if(tag===0x829D&&!o.fnum) o.fnum=rat(g32(vo)); else if(tag===0x0110&&!o.model) o.model=str(sp(),cnt); else if(tag===0xA002&&!o.w) o.w=val(); else if(tag===0xA003&&!o.h) o.h=val(); }
      if(jo&&jl&&jo+jl<=size) jpgs.push([jo,jl]); subs.forEach(s=>walk(s,d+1)); walk(g32(off+2+n*12),d+1); };
    walk(g32(4),0); jpgs.sort((a,b)=>b[1]-a[1]); o.preview=jpgs[0]||null;
    o.bytes=size||null; ['fnum','model','w','h','lens','serial','program','wb','flash','ev'].forEach(k=>{ if(o[k]===undefined) o[k]=null; }); Object.assign(o,{releaseMode2:null,seqImage:null,seqLength:null,shotSincePower:null,focusMode:null,seqNumber:null}); if(o._mn) try{ sonyMN(u8,dv,le,o._mn[0],o); }catch(_){} delete o._mn; return o; }
// Sony MakerNote. Plain tags: 0xB049 ReleaseMode, 0xB04A SequenceNumber, 0x201B FocusMode. Enciphered 0x9400 (Tag9400c layout, bodies from ~2017):
// 0x09 ReleaseMode2, 0x0A ShotNumberSincePowerUp, 0x12 SequenceImageNumber, 0x1E SequenceLength. Anything that doesn't sanity-check stays null.
let _sonyDec=null;
function sonyMN(u8,dv,le,mo,o){ if(mo+14>u8.length||String.fromCharCode(...u8.subarray(mo,mo+4))!=='SONY') return; const ifd=mo+12, g16=p=>dv.getUint16(p,le), g32=p=>dv.getUint32(p,le), n=g16(ifd); if(!n||n>400||ifd+2+n*12>u8.length) return;
  for(let i=0;i<n;i++){ const e=ifd+2+i*12, tag=g16(e), type=g16(e+2), cnt=g32(e+4), vo=e+8, v16=()=>type===3?g16(vo):type===4?g32(vo):u8[vo];
    if(tag===0xB04A) o.seqNumber=v16(); else if(tag===0x201B) o.focusMode=u8[vo]; else if(tag===0x9400&&cnt>=0x20){ const p=g32(vo); if(p+0x20>u8.length) continue;
      if(!_sonyDec){ _sonyDec=new Uint8Array(256); for(let c=0;c<256;c++) _sonyDec[c]=c; for(let c=0;c<249;c++) _sonyDec[(c*c*c)%249]=c; }
      const d=Array.from(u8.subarray(p,p+0x20),x=>_sonyDec[x]), u32=k=>(le?d[k]|d[k+1]<<8|d[k+2]<<16|d[k+3]<<24:d[k]<<24|d[k+1]<<16|d[k+2]<<8|d[k+3])>>>0;
      if([0x23,0x24,0x26,0x28,0x31,0x32,0x33].includes(d[0])){ const si=u32(0x12), sl=d[0x1E], sp=u32(0x0A);
        o.releaseMode2=d[0x09]<64?d[0x09]:null; o.seqImage=si>0&&si<100000?si:null; o.seqLength=sl>0?sl:null; o.shotSincePower=sp>0&&sp<1e7?sp:null; } } }
  if(o.seqImage==null&&o.seqNumber!=null&&o.seqNumber<65535) o.seqImage=o.seqNumber||null; }

// Preview bitmap → mean luminance 0–1, Laplacian variance (focus), % clipped pixels.
function measure(bmp){ const W=bmp.width,H=bmp.height, c=document.createElement('canvas'); c.width=W; c.height=H; const x=c.getContext('2d',{willReadFrequently:true}); x.drawImage(bmp,0,0); const d=x.getImageData(0,0,W,H).data, g=new Float32Array(W*H); let sum=0,clip=0;
    for(let i=0,j=0;i<d.length;i+=4,j++){ const y=0.299*d[i]+0.587*d[i+1]+0.114*d[i+2]; g[j]=y; sum+=y; if(d[i]>=250&&d[i+1]>=250&&d[i+2]>=250) clip++; }
    let m=0,m2=0,k=0; for(let yy=1;yy<H-1;yy++) for(let xx=1;xx<W-1;xx++){ const j=yy*W+xx, l=4*g[j]-g[j-1]-g[j+1]-g[j-W]-g[j+W]; m+=l; m2+=l*l; k++; }
    const mean=m/k, hc=document.createElement('canvas'); hc.width=9; hc.height=8; const hx=hc.getContext('2d',{willReadFrequently:true}); hx.drawImage(bmp,0,0,9,8); const hd=hx.getImageData(0,0,9,8).data; let bits=''; for(let y=0;y<8;y++) for(let xx=0;xx<8;xx++){ const a=(y*9+xx)*4, b=a+4, la=hd[a]*.299+hd[a+1]*.587+hd[a+2]*.114, lb=hd[b]*.299+hd[b+1]*.587+hd[b+2]*.114; bits+=la>lb?'1':'0'; } let dh=''; for(let i=0;i<64;i+=4) dh+=parseInt(bits.slice(i,i+4),2).toString(16); const hist=new Array(16).fill(0); for(let j=0;j<g.length;j++) hist[Math.min(15,g[j]>>4)]++; for(let i=0;i<16;i++) hist[i]/=g.length; return {dhash:dh,hist,lum:sum/(W*H)/255, focus:m2/k-mean*mean, clip:100*clip/(W*H), canvas:c}; }

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

// Photos → rows (weighted change score, see rowScore; cuts[id]='row' | 'join' override), stacks
// (Sony SequenceImageNumber runs when present; else gap ≤ 2 s and dHash distance ≤ 6; dHash ≥ 28 always splits;
// no dHash: gap ≤ 1 s), brackets (ReleaseMode2 2/3, or 3+ frames spanning −/+ EV), cuts[id]=true|false stack override,
// flags (soft / blown / shake), ranks, suggested keeps, navigation nodes.
function buildShoot(list,cuts){ const light=h=>h<11?'morning':h<15?'midday':h<18?'afternoon':'evening';
    const ts=p=>{ const m=/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/.exec(p.date||''); return m?Date.UTC(+m[1],+m[2]-1,+m[3],+m[4],+m[5],+m[6]):0; };
    const fno=p=>{ const m=/(\d+)(?!.*\d)/.exec(p.name||p.path||''); return m?+m[1]:0; };
    const P=list.map(p=>({...p,t:ts(p)})).sort((a,b)=>a.t-b.t||String(a.serial||'').localeCompare(String(b.serial||''))||fno(a)-fno(b)||String(a.path).localeCompare(String(b.path)));
    const fs=P.map(p=>p.focus).slice().sort((a,b)=>a-b), pct=v=>{ let lo=0,hi=fs.length; while(lo<hi){ const m=(lo+hi)>>1; if(fs[m]<v) lo=m+1; else hi=m; } return Math.round(100*lo/Math.max(1,fs.length-1)); };
    const byId={}, G={}, M=[]; let cur=null, n=0;
    const gaps=[]; P.forEach((q,idx)=>{ const prev=P[idx-1], gap=prev?(q.t-prev.t)/1000:1e9; let rs=prev?rowScore(prev,q,gap,gaps):null; if(prev&&gap>2) gaps.push(gap); const rc=cuts['f'+n]; if(rs&&(rc==='row'||rc==='moved')) rs={start:true,reason:rc==='moved'?'you moved this':'you split here'}; else if(rs&&rc==='join') rs={start:false}; if(!cur||rs.start){ const d=new Date(q.t), hh=d.getUTCHours(); cur={hh,time:String(hh).padStart(2,'0')+':'+String(d.getUTCMinutes()).padStart(2,'0'),fr:[],reason:rs?rs.reason:''}; M.push(cur); }
      const id='f'+n, hh=new Date(q.t).getUTCHours(), fl=q.fl||0, shake=!!(q.exp&&fl&&q.exp>2/fl);
      const d2=new Date(q.t), p2=x=>String(x).padStart(2,'0');
      const p={exp:q.exp??null,iso:q.iso??null,model:q.model||null,fnum:q.fnum||null,pw:q.w||null,ph:q.h||null,bytes:q.bytes||null,seqLen:q.seqLength??null,evc:q.ev??null,sec:p2(d2.getUTCHours())+':'+p2(d2.getUTCMinutes())+':'+p2(d2.getUTCSeconds()),date10:d2.getUTCFullYear()+'-'+p2(d2.getUTCMonth()+1)+'-'+p2(d2.getUTCDate()),dark:!q.nopv&&q.lum!=null&&q.lum<0.08,nopv:!!q.nopv,path:q.path,lens:q.lens||null,serial:q.serial||null,program:q.program??null,wb:q.wb??null,flash:q.flash??null,dhash:q.dhash||null,hist:q.hist||null,id,n,jpg:!!q.jpg,mi:M.length-1,fileObj:q.fileObj,xpath:q.xpath,xmp:q.xmp||null,lrEd:!!q.lrEd,portrait:!!q.portrait,src:q.src,lg:q.lg,zsrc:q.lg,ev:0,time:cur.time,hh,light:light(hh),h:q.lum,sharp:pct(q.focus),focus:q.focus,fx:50,fy:50,seq:q.seqImage??null,rm2:q.releaseMode2??null,start:!prev||cur.fr.length===0||(()=>{ const sq=q.seqImage, ps=prev.seqImage; const h=prev.dhash&&q.dhash?ham(prev.dhash,q.dhash):null; if(h!=null&&h>=28) return true; if(sq!=null&&ps!=null) return !(sq===ps+1&&gap<=2); if(h!=null) return !(gap<=2&&h<=6); return gap>1; })(),bk:false,evs:q.ev,seed:0,sug:null,bl:0,clip:+q.clip.toFixed(1),blown:q.clip>2,shake,ss:q.exp?(q.exp>=1?q.exp.toFixed(1)+'s':'1/'+Math.round(1/q.exp)):'',fl:fl?Math.round(fl):0,file:q.name};
      byId[id]=p; cur.fr.push(p); n++; });
    // Manual moves (drag tiles onto a row header / a stack / between rows): cuts[id] = {to|stack|newAfter: anchor frame id}.
    const mv=Object.entries(cuts).filter(([,v])=>v&&typeof v==='object');
    if(mv.length){ const rowOf=new Map(); M.forEach(m=>m.fr.forEach(p=>rowOf.set(p.id,m))); const news=[];
      mv.forEach(([id,v])=>{ const p=byId[id], anc=byId[v.to||v.stack||v.newAfter]; if(!p||!anc||anc===p) return; const src=rowOf.get(id); let dst=rowOf.get(anc.id); if(!src||!dst) return;
        if(v.newAfter){ let nr=news.find(x=>x.after===dst); if(!nr){ nr={hh:p.hh,time:p.time,fr:[],reason:'you moved this',after:dst}; news.push(nr); } dst=nr; }
        if(dst!==src){ src.fr=src.fr.filter(x=>x!==p); dst.fr.push(p); rowOf.set(id,dst); p._moved=true; } if(v.stack) p._stackTo=anc.id; });
      news.forEach(nr=>{ M.splice(M.indexOf(nr.after)+1,0,nr); }); M.forEach(m=>{ m.fr.sort((a,b)=>a.n-b.n); if(m.fr[0]){ m.time=m.fr[0].time; m.hh=m.fr[0].hh; } });
      for(let i=M.length-1;i>=0;i--) if(!M[i].fr.length) M.splice(i,1); }
    M.forEach((m,mi)=>{ m.mi=mi; m.reason=m.reason||''; m.id='m'+mi; m.light=light(m.hh); m.fr.forEach(p=>{ p.mi=mi; });
      const gs=[], late=[]; m.fr.forEach((p,i)=>{ if(p._stackTo&&m.fr.some(x=>x.id===p._stackTo)){ late.push(p); return; } const cv=cuts[p.id], pv=m.fr[i-1];
        const st=!gs.length?true:typeof cv==='boolean'?cv:(p._moved||(pv&&pv._moved))?!(pv&&pv.n===p.n-1&&!p.start&&!!pv._moved===!!p._moved):p.start; if(st) gs.push([]); gs[gs.length-1].push(p); });
      late.forEach(p=>{ const g=gs.find(x=>x.some(f=>f.id===p._stackTo)); if(g){ g.push(p); g.sort((a,b)=>a.n-b.n); } else gs.push([p]); });
      let groups=gs.map(g=>{ const evs=g.map(f=>f.evs), br=g.length>=2&&g.every(f=>f.rm2===2||f.rm2===3)||g.length>=3&&evs.every(v=>v!=null)&&new Set(evs.map(v=>v.toFixed(1))).size===g.length&&Math.min(...evs)<0&&Math.max(...evs)>0;
        const kind=g.length<2?'single':br?'bracket':'burst'; g.forEach(f=>{ f.bk=kind==='bracket'; });
        if(kind==='burst'){ const mx=Math.max(...g.map(f=>f.focus)); g.forEach(f=>{ f.soft=f.focus<mx*0.45; f.slight=!f.soft&&f.focus<mx*0.7; }); } else g.forEach(f=>{ f.soft=f.sharp<12; f.slight=!f.soft&&f.sharp<25; });
        g.forEach(f=>{ if(f.nopv){ f.soft=false; f.slight=false; f.blown=false; f.shake=false; } f.peak=false; }); const pk=kind==='burst'?peakOf(g):null; if(pk) pk.peak=true;
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

// The look of an edit. Prototype applies this as a CSS filter; the app must apply the SAME maths
// to the RAW render (default settings) for 100% view and JPEG export, so export = what Edit showed.
// brightness(b) = multiply RGB by b · contrast(c) = (x-0.5)*c+0.5 · sepia/hue-rotate = CSS Filter Effects spec matrices.
// Input: {Exposure, Contrast, Highlights, Shadows, Temp}. Output: CSS filter string.
function editFilter(r){ if(!r) return 'none'; const E=r.Exposure||0,C=r.Contrast||0,Hi=r.Highlights||0,Sh=r.Shadows||0,T=r.Temp??6500, f=[];
    const b=Math.pow(2,E*0.6+Sh*0.002+Hi*0.0008), c=1+C/100-Sh*0.002; f.push('brightness('+(b*(1+(r._e||0))).toFixed(3)+')','contrast('+c.toFixed(3)+')');
    const dT=(T-6500)/1500; f.push(dT>0?'sepia('+Math.min(0.5,dT*0.45).toFixed(3)+')':'hue-rotate('+(dT*18).toFixed(1)+'deg)'); if(r._b) f.push('blur('+r._b+'px)'); return f.join(' '); }
// JPEG → the TIFF block inside its APP1 Exif segment (same layout parseHead reads). null if none.
function jpegTiff(u8){ if(u8[0]!==0xFF||u8[1]!==0xD8) return null; let p=2;
  while(p+4<u8.length){ if(u8[p]!==0xFF) return null; const mk=u8[p+1], len=(u8[p+2]<<8)|u8[p+3];
    if(mk===0xE1&&u8[p+4]===0x45&&u8[p+5]===0x78&&u8[p+6]===0x69&&u8[p+7]===0x66) return u8.subarray(p+10,p+2+len);
    if(mk===0xDA) return null; p+=2+len; } return null; }
// Motion peak inside a stack of ≥ 6: the frame at the maximum of the smoothed consecutive dHash distance,
// when that maximum is ≥ 2× the stack's median distance. null otherwise.
function peakOf(g){ if(g.length<6||!g.every(f=>f.dhash)) return null; const d=g.map((f,i)=>i?ham(g[i-1].dhash,f.dhash):0).slice(1), sm=d.map((v,i)=>0.5*v+0.25*(d[i-1]??v)+0.25*(d[i+1]??v));
  const med=d.slice().sort((a,b)=>a-b)[Math.floor(d.length/2)], mi=sm.indexOf(Math.max(...sm)); return sm[mi]>=2*Math.max(1,med)?g[mi+1]:null; }
function ham(a,b){ let d=0; for(let i=0;i<a.length&&i<b.length;i++){ let x=parseInt(a[i],16)^parseInt(b[i],16); while(x){ d+=x&1; x>>=1; } } return d; }
// Row boundary: weighted change score. Gap is scaled by the local shooting rate: median of the last 10 gaps between
// separate moments (gaps ≤ 2 s inside bursts are left out), never below 10 s, so a pause after a burst doesn't split the row.
function rowScore(a,b,gap,gaps){ const recent=gaps.slice(-10).slice().sort((x,y)=>x-y), med=recent.length?Math.max(10,recent[Math.floor(recent.length/2)]):30;
  const lensCh=!!(a.lens&&b.lens&&a.lens!==b.lens), flCh=!!(a.fl&&b.fl&&Math.max(a.fl,b.fl)/Math.min(a.fl,b.fl)>=1.5), flTxt=a.fl&&b.fl&&Math.round(a.fl)!==Math.round(b.fl)?Math.round(a.fl)+' → '+Math.round(b.fl)+' mm':'lens change';
  const parts=[[Math.min(1.2,(gap/med)/10),gap>=5400?Math.round(gap/3600)+' h gap':gap>=60?Math.round(gap/60)+' min gap':Math.round(gap)+' s gap'],
    [lensCh?0.6:flCh?0.5:0,flTxt],
    [a.portrait!=null&&b.portrait!=null&&!!a.portrait!==!!b.portrait?0.9:0,a.portrait?'portrait → landscape':'landscape → portrait'],
    [a.program!=null&&b.program!=null&&a.program!==b.program?0.3:0,'exposure mode change'],
    [a.wb!=null&&b.wb!=null&&a.wb!==b.wb?0.2:0,'white balance change'],
    [!a.flash&&b.flash?0.3:0,'flash on'],
    [a.iso&&b.iso&&Math.abs(Math.log2(b.iso/a.iso))>=2?0.3:0,'ISO '+a.iso+' → '+b.iso]];
  const score=parts.reduce((s,p)=>s+p[0],0), top=parts.slice().sort((x,y)=>y[0]-x[0])[0];
  return {start:gap>=600||(gap>5&&score>=1),reason:top[1],score}; }
// One undoable decision for a whole stack. group: {frames:[{id}]} or an id array. kept ids -> keep, the rest -> out.
// Flagged frames are untouched. Returns {marks, undo}; undo = {label, prev:{id: previous mark or null}}.
function sweep(marks,group,kept,flags){ const ids=Array.isArray(group)?group:group.frames.map(f=>f.id), m={...marks}, K=new Set(kept), prev={}; let k=0,x=0;
  ids.forEach(id=>{ if(flags&&flags[id]) return; const v=K.has(id)?'keep':'out'; prev[id]=marks[id]||null; m[id]=v; v==='keep'?k++:x++; });
  return {marks:m,undo:{label:'kept '+k+' · rejected '+x+' · Cull',prev,kept:k,rejected:x}}; }
// Row header double-click: every undecided, unflagged frame in the row → verb ('keep' | 'out').
function rowDone(marks,ids,verb,flags){ const m={...marks}, prev={}; let n=0; ids.forEach(id=>{ if(marks[id]||(flags&&flags[id])) return; prev[id]=null; m[id]=verb; n++; });
  return {marks:m,undo:{label:(verb==='keep'?'kept ':'rejected ')+n+' · row',prev}}; }
// Paint drag: ids → verb, flagged frames untouched.
function paint(marks,ids,verb,flags){ const m={...marks}, prev={}; let n=0; ids.forEach(id=>{ if(flags&&flags[id]||marks[id]===verb) return; prev[id]=marks[id]||null; m[id]=verb; n++; });
  return {marks:m,undo:{label:(verb==='keep'?'kept ':'rejected ')+n+' · painted',prev}}; }
function undoSweep(marks,undo){ const m={...marks}; Object.entries(undo.prev).forEach(([id,v])=>{ if(v==null) delete m[id]; else m[id]=v; }); return m; }
const LuminaCore={ham,peakOf,rowScore,sweep,undoSweep,rowDone,paint,jpegTiff,editFilter,parseHead,measure,crc32,zip,mergeXmp,freshXmp,hasDevelop,buildShoot,exportPlan};
g.LuminaCore=LuminaCore; if(typeof module!=='undefined'&&module.exports) module.exports=LuminaCore;
})(typeof window!=='undefined'?window:globalThis);
