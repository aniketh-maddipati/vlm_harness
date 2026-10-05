// Lumina v4-beta page data: the grammar (shown verbatim in the ? sheet), the browser-only sample shoot,
// value formatters, and the "this shoot" facts. No UI.
(function(g){
const GRAMMAR = `LUMINA PICK GRAMMAR
Rule: arrows say where, ⏎ says yes, R says no. The cursor acts on the unit under it. ⇧ works inside a stack.
Unit = a photo, or a closed stack (burst/bracket). Three states: undecided, kept (⏎), removed (R). Every decision is one undo step and reports in the footer.

MOVE
←→            next / previous photo · on a stack: through its frames, then on · hold repeats
⇧←→           same, and stops at the ends of a stack
↑↓            row above / below, same column · on a stack: ↓ opens, ↑ closes
⌥←→           skip a whole stack or run of singles
⌘←→           previous / next row
⌥↑↓           previous / next group in a row not yet seen
⏎             photo: keep, next · closed stack: open · open frame: keep, next frame · after the last frame the stack closes
⇧⏎            next row not yet seen
esc           close the stack

DECIDE (the unit under the cursor)
K             same as ⏎
R             remove · closed stack: removes every frame
K R F         in an open stack or large view: the frame shown
⌘A            keep every photo in this row · 600 ms preview · esc cancels · one undo
⇧K / ⇧R       stack (open or closed): keep every frame / remove every frame
⇧F            stack (open or closed): flag all · again: unflag
Q / ⌘Z        undo · ⇧Q / ⇧⌘Z redo · the key bar shows how many steps each way
⌥⌘⌫          start over · press twice · clears every keep and remove for this shoot · one undo step
U L G 1–5     not used · the footer names the right key
⇪ Caps Lock   auto-advance off while on

SEEN · PASSES
a row is marked seen when the cursor leaves it
⇧U            rows not yet seen only
⇧P            pass 2: picks only · R narrows, removed photos leave the view · ⇧P returns to all photos
picks tray  along the bottom in pass 1 · every pick in time order · click one to jump · Y hides

VIEW
Space         hold: large view while held · tap: toggle · a stack opens at its first frame · ←→ within the stack, else the row
Z hold        100% · in a stack the same region on every frame · drag moves it
time axis     large view and open stacks · capture time per frame · gold: most detail · ≈: estimated
− +           tile size: small / medium / large, scaled to the window
B / ⇧B        split / merge here (row or stack)
H             hide key bar · ?  all keys
Tab           move between buttons · ⏎ or Space presses the focused one · esc returns to the grid

CLICK
click                         focus · the Keep button on the focused photo keeps / un-keeps
click row header              focus the row
double-click photo or stack   large view · double-click again closes
double-click stack badge      open the stack
double-click row header       focus the row · ⌘A keeps every photo in it

DRAG
hold P or R + drag    paint keep across tiles · esc cancels · one step
row header ↑↓         move the boundary a group at a time · onto the previous header merges
stack edge → / ←      open / close the stack

DROP
tiles → row header    move those photos to that row · onto a stack merges · between rows splits
tiles → outside       drags the RAW files (copies) to Finder, Lightroom, Capture One, Mail

TRACKPAD
two-finger ↕          scroll
two-finger ↔          in an open stack or large view: scrub frames
pinch                 tile size, centred on the cursor
force click / 3-tap   large view while held
⌥ + two-finger ↔      previous / next group
(no decisions by gesture · rotate and pinch in large view ignored)

SETTINGS
⌘,            pick rating (1–5★, default 3) · auto-advance · arrows enter stacks · tile size

STEPS
⌘1 Open · ⌘2 Pick · ⌘3 Edit · ⌘4 Save · ⌘O open a folder or card · ⌘R Show in Finder (Pick: the photo · Save: the folder)
Open: ↑↓ choose · ⏎ open
Save: ⌘⏎ save picks · one sidecar per pick, read by Lightroom Classic and Capture One (⏎ alone does not save)
Guards: with undecided photos left, ⌘⏎ asks once · opening another card with unsaved picks asks once · esc stays`;

const FAQ=[["Using Lumina",[["What does Lumina do?","It opens RAW photos from a card, a folder or your phone. Pick the ones you want with ⏎ (or set some aside with R), edit them, then Save. For ARW, Save writes an .xmp sidecar for each pick so Lightroom Classic or Capture One picks up the rating."],["Which files are supported?","RAW only: Sony ARW and DNG, including iPhone ProRAW and Android RAW. JPEG and HEIC are not supported yet. Other RAW formats are skipped and listed after import. A JPEG or HEIC with a RAW of the same name is skipped quietly. One without a RAW is skipped and counted."],["What is a shoot?","A named set of photos from one or more places: a card, folders, your phone. Name it in the top bar. Files stay where they are; Lumina keeps a record of them."],["How do I add more photos to a shoot?","⌘O inside a shoot, the + next to the shoot name, holding ⇧, or drop files on the window. Photos already in the shoot are skipped by camera, capture time and size."],["How do I add photos from my phone?","Open → Add from phone. iPhone: AirDrop the photos with Share → Options → All Photos Data turned on, or in Photos on your Mac use File → Export → Export Unmodified Original. Android: plug in, choose File transfer, copy the .dng files from DCIM → Camera with OpenMTP. Then drop them on the page, or turn on Watch Downloads."],["Why did my iPhone photos arrive as HEIC?","AirDrop sends a compressed copy unless All Photos Data is on. In Share, tap Options, turn it on, and send again. Lumina only adds the RAW."],["What if I've seen these photos before?","Lumina remembers each decision by photo, not by folder. If a photo turns up again in another shoot, your earlier pick or remove comes back, and a note names the shoot it came from."],["How are rows made?","A new row starts after a long time gap for that shoot (compared with the last 10 gaps, at least 10 seconds), or when the lens, focal length, orientation, shooting mode, white balance, flash or ISO changes. You can split or merge with B and ⇧B."],["How are stacks made?","Frames from the camera's continuous drive sequence form a stack. Without sequence data, frames taken within 2 seconds that look alike form a stack. A large change between frames starts a new one. ↓ or ⏎ opens a stack, ↑ closes it."],["What happens if I shot with two cameras?","Photos are sorted by capture time. When you add photos from a second camera whose clock is off, Lumina shows the offset it found and lets you shift them into line. Files are not changed."],["What is edge detail?","How much edge detail the embedded preview has, scaled so the frame with the most detail in the stack (or row) is 100. It is a measurement, not a verdict. Hold F in the big view to see the edges, Z for 100%."],["What are the F, E, M and B overlays?","In the big view, hold F for sharp edges (red), E for clipped highlights (red) and blocked shadows (blue), M for motion streaking, B for the focus point. Inside an open stack, F and E tint every frame so you can compare."],["Can I undo or start over?","⌘Z undoes one step at a time; ⇧⌘Z redoes. ⌥⌘⌫ pressed twice clears every decision for the shoot as one undo step."]]],["Your files",[["Does Lumina change my RAW files?","No. RAW and DNG files are never modified, moved or deleted. Nothing is ever written to a card."],["What does Save write?","For ARW: one small .xmp file next to each pick, with the rating set in Settings (⌘,, default 3★). For DNG, including phone photos: picks are copied into a Picks folder, because Lightroom ignores sidecars for DNG. Photos you didn't pick get nothing."],["What if a photo already has a sidecar?","Only the rating is updated. Edits and other metadata stay. The previous file is kept as .xmp.lumina-bak."],["Why a rating and not a Lightroom pick flag?","Lightroom keeps pick flags in its catalog, not in sidecar files. A rating is the part of a sidecar Lightroom reads, so picks arrive as a rating you can filter on."],["What if I save with photos still undecided?","Lumina tells you how many are undecided and asks once; ⌘⏎ again saves anyway."],["What are working files?","Previews and progress Lumina keeps so it stays fast: big-view previews, this card's picks, earlier cards, the recent list. Click the squares in the top bar to see what each uses, clear any of them, or set a limit (200 MB, 1 GB, 5 GB or none). When the limit is reached, the oldest previews and earlier cards go first. Your RAWs, .xmp ratings and this card's picks are never removed."],["Who makes Lumina?","Aniketh Maddipati. Bugs and feedback: anikethcov@gmail.com. Also on LinkedIn (linkedin.com/in/anikethmaddipati) and X (@aniketh745)."],["What if a drive or folder is disconnected?","The shoot keeps its photos and your decisions. The source shows Reconnect; plug the drive back in or point to where it moved."],["Which browsers work?","Chrome and Comet support everything. Firefox and Safari can open and pick photos, but can't watch Downloads, and Save downloads a zip instead of writing next to your RAWs. The Mac app needs no browser."],["Does anything leave my Mac?","No. Nothing is uploaded, no account is needed, and all measuring happens on your Mac."]]]];

// Sections for the sheet: [{h, lines:[[key, desc]]}]
function grammarSections(){ const out=[]; let cur=null; GRAMMAR.split('\n').forEach((l,i)=>{ if(i===0) return; if(!l.trim()){ cur=null; return; }
  if(/^[A-Z]{3,}/.test(l)&&!/\s{2,}/.test(l)){ cur={h:l,lines:[]}; out.push(cur); return; }
  if(!cur){ cur={h:'',lines:[]}; out.push(cur); } const m=/^(\S.*?)\s{2,}(.*)$/.exec(l); cur.lines.push(m?[m[1],m[2]]:['',l]); }); return out; }

const p2=x=>String(x).padStart(2,'0');
const fmt={
  exp:v=>!v?'':v>=1?(+v.toFixed(1))+' s':'1/'+Math.round(1/v),
  f:v=>v?'f/'+(+v.toFixed(1)):'',
  iso:v=>v?'ISO '+v:'',
  fl:v=>v?Math.round(v)+' mm':'',
  ev:v=>v==null?'':v===0?'0':(v>0?'+':'−')+(+Math.abs(v).toFixed(1)),
  mb:b=>b?(b/1e6).toFixed(1)+' MB':'',
  gb:b=>b>=1e9?(b/1e9).toFixed(1)+' GB':Math.round((b||0)/1e6)+' MB',
  base:n=>(n||'').replace(/\.[^.]+$/,'')
};

// dHash sequence with one motion spike (for the sample's peak marker)
function hashes(n,spikeAt){ const B=new Set(), out=[]; let pos=0; const hx=()=>{ let s=''; for(let i=0;i<16;i++){ let v=0; for(let b=0;b<4;b++) if(B.has(i*4+b)) v|=1<<b; s+=v.toString(16); } return s; };
  for(let j=0;j<n;j++){ if(j){ const k=j===spikeAt?14:2; for(let q=0;q<k;q++){ const b=(pos++*7)%64; B.has(b)?B.delete(b):B.add(b); } } out.push(hx()); } return out; }

// Browser-only sample: facts like a real card, placeholder images, no captions.
function sample(){ const out=[]; let t=Date.UTC(2026,8,28,9,12,0)/1000, n=0, seed=0;
  const A={model:'ILCE-7M4',serial:'5021473',make:'SONY'}, Bd={model:'ILCE-7M3',serial:'4418260',make:'SONY'}, Ph={model:'iPhone 15 Pro',serial:null,make:'Apple'};
  const rows=[
    {gap:0,lens:'FE 24mm F1.4 GM',fl:24,f:2,iso:200,u:['s','s','s','b8']},
    {gap:720,lens:'FE 24mm F1.4 GM',fl:24,f:2,iso:200,u:['b31','s','s','s','s','s','s']},
    {gap:80,lens:'FE 85mm F1.4 GM',fl:85,f:2,iso:200,u:['s','s','b5','s']},
    {gap:40,lens:'FE 85mm F1.4 GM',fl:85,f:2.8,iso:200,pt:true,u:['s','s','s','s','k3']},
    {gap:1500,lens:'FE 85mm F1.4 GM',fl:85,f:4,iso:100,two:true,u:['b12','s','s','s','s','s']},
    {gap:900,lens:'FE 24mm F1.4 GM',fl:24,f:1.4,iso:400,u:['s','s','b6','s']},
    {gap:3900,lens:'FE 24mm F1.4 GM',fl:24,f:1.4,iso:3200,u:['b6','s','s','s']},
    {gap:1200,lens:'FE 24mm F1.4 GM',fl:24,f:1.4,iso:3200,u:['s','s','b4']},
    {gap:900,lens:'1× camera',fl:24,f:1.8,iso:80,ph:true,u:['s','s','s']}];
  const ds=s=>{ const d=new Date(s*1000); return d.getUTCFullYear()+':'+p2(d.getUTCMonth()+1)+':'+p2(d.getUTCDate())+' '+p2(d.getUTCHours())+':'+p2(d.getUTCMinutes())+':'+p2(d.getUTCSeconds()); };
  rows.forEach((r,ri)=>{ t+=r.gap; r.u.forEach((u,ui)=>{ const kind=u[0], cnt=kind==='s'?1:+u.slice(1); seed++; if(ui) t+=kind==='s'?20:12; const H=kind==='b'&&cnt>=6?hashes(cnt,Math.floor(cnt*0.55)):null;
    for(let j=0;j<cnt;j++){ const pt=!!r.pt&&kind!=='k', w=pt?240:360+(j%4)*6, h=pt?360:240, lw=pt?1067:1600+(j%4)*24, lh=pt?1600:1067, body=r.ph?Ph:r.two&&kind==='s'&&n%2?Bd:A, nm=r.ph?'IMG_'+(4100+n)+'.DNG':'DSC0'+(3100+n)+'.ARW';
      const focus=kind==='b'?(j===(seed*7)%cnt?420:200+((j*53+seed*31)%180)):kind==='k'?300:[340,90,260,300,380,70,310][(n+ri)%7], blown=kind==='s'&&(n*43+11)%100<9, shake=kind==='s'&&!blown&&(n*29+5)%100<10, dark=kind==='s'&&ri===5&&ui===1, nopv=kind==='s'&&ri===6&&ui===2;
      out.push({name:nm,path:'Untitled/DCIM/'+(r.ph?'100APPLE/':'100MSDCF/')+nm,make:body.make,date:ds(t+(kind==='b'?Math.floor(j/10):kind==='k'?j:0)),exp:shake?1/15:[1/250,1/500,1/1000][n%3],fl:r.fl,fnum:r.f,ev:kind==='k'?[-1,0,1][j]:[0,0.7,-0.3,0][n%4],iso:r.iso,lens:r.lens,model:body.model,serial:body.serial,
        w:pt?4672:7008,h:pt?7008:4672,bytes:33.1e6+(n%7)*0.4e6,lum:dark?0.05:0.5,focus:nopv?0:focus,clip:blown?3.2:0,portrait:pt,nopv,dhash:H?H[j]:null,
        focusLoc:nopv?null:(kind==='b'?{x:0.36+((j*7)%5)*0.012,y:0.42,w:0.14,h:0.2}:(n%3)?{x:[0.3,0.55,0.42][n%3],y:[0.38,0.3,0.5][(n+ri)%3],w:pt?0.3:0.16,h:pt?0.18:0.24}:null),seqImage:kind==='b'?j+1:null,seqLength:kind==='b'?cnt:null,releaseMode2:kind==='k'?2:kind==='b'?1:null,src:nopv?'':SIMG(seed),lg:nopv?'':SIMG(seed)});
      n++; } }); t+=20; });
  return out; }

const SHOOTS=[
  {d:'2026-08-30',n:341,dec:341,kp:52,last:'DSC04118',where:'/Volumes/T7/Photos/2026-08-30'},
  {d:'2026-08-12',n:44,dec:18,kp:6,last:'DSC03902',where:'~/Pictures/2026-08-12'},
  {d:'2026-07-04',n:512,dec:412,kp:38,last:'DSC03311',where:'/Volumes/T7/Photos/2026-07-04'}];

// "this shoot" facts for the ? sheet
function facts(data,failed){ const P=data.order.map(id=>data.byId[id]); if(!P.length) return [['photos','0']];
  const cnt=(k)=>{ const m=new Map(); P.forEach(p=>{ const v=k(p); if(v) m.set(v,(m.get(v)||0)+1); }); return [...m.entries()].sort((a,b)=>b[1]-a[1]); };
  const rows=data.R.map(r=>r.ids.length).sort((a,b)=>a-b), st=Object.values(data.G).filter(x=>x.kind!=='single'), big=st.reduce((m,x)=>x.frames.length>m?x.frames.length:m,0), t=P.map(p=>p.date10+' '+(p.sec||'').slice(0,5)).sort();
  const out=[['photos',P.length+' · '+data.R.length+' rows · '+st.length+' stacks']];
  cnt(p=>(p.model||'body ?')+' · '+(p.serial||'no serial')).forEach(([k,v])=>out.push(['body',k+' · '+v]));
  cnt(p=>p.lens).forEach(([k,v])=>out.push(['lens',k+' · '+v]));
  out.push(['dates',t[0]+' → '+t[t.length-1]]);
  out.push(['per row','min '+rows[0]+' · median '+rows[Math.floor(rows.length/2)]+' · max '+rows[rows.length-1]]);
  out.push(['largest stack',String(big)]);
  const ns=P.filter(p=>p.seq==null).length, np=P.filter(p=>p.nopv).length, nf=(failed||[]).length; if(np) out.push(['no preview',String(np)]); if(nf) out.push(['unreadable',String(nf)]); (failed||[]).slice(0,12).forEach(f=>out.push(['',f.name+' · '+f.reason]));
  return out; }

// Sample shoot images ship with the app (no network).
const SAMPLE_IMGS=["DSC06175.jpg","DSC06176.jpg","DSC06178.jpg","DSC06180.jpg","DSC06181.jpg","DSC06182.jpg","DSC06183.jpg","DSC06184.jpg","DSC06982.jpg","DSC06986.jpg","DSC06987.jpg","DSC06988.jpg","DSC06989.jpg","DSC06992.jpg","DSC06996.jpg","DSC06997.jpg","DSC07001.jpg","DSC07026.jpg","DSC07027.jpg","DSC07029.jpg","DSC07039.jpg","DSC07052.jpg","DSC07054.jpg","DSC07055.jpg","DSC07056.jpg","DSC07057.jpg","DSC07174.jpg","DSC07177.jpg","DSC07178.jpg","DSC07181.jpg","DSC07182.jpg","DSC07185.jpg","DSC07189.jpg","DSC07191.jpg","DSC07194.jpg","DSC07195.jpg","DSC07196-2.jpg","DSC07196.jpg","DSC07198.jpg","DSC07199.jpg","DSC07200.jpg","DSC07203.jpg","DSC07207.jpg","DSC07211.jpg","DSC07214.jpg","DSC07215.jpg","DSC07216.jpg","DSC07220.jpg","DSC07225.jpg","DSC07227.jpg","DSC07228.jpg","DSC07229.jpg","DSC07230.jpg","DSC07233.jpg","DSC07235.jpg","DSC07249.jpg","DSC07252.jpg","DSC07254.jpg","DSC07256.jpg","DSC07257.jpg","DSC07258.jpg","DSC07259-2.jpg","DSC07259.jpg","DSC07260.jpg","DSC07261.jpg","DSC07262.jpg","DSC07265.jpg","DSC07267.jpg","DSC07268.jpg","DSC07284.jpg","DSC07289.jpg","DSC07292.jpg","DSC07295.jpg","DSC07296.jpg","DSC07299.jpg","DSC07300.jpg","DSC07310.jpg","DSC07315.jpg","DSC07317.jpg","DSC07320.jpg","DSC07325.jpg","DSC07329.jpg","DSC07331.jpg","DSC07342.jpg","media-1789969373326-qife.jpeg","photos-1790028451788-gtsa.jpg","photos-1790028452061-wq0k.jpg","photos-1790531781942-7nv3.jpg","photos-1790531782130-nffo.jpg","photos-1790531782704-g465.jpg","photos-1790531782902-a2dl.jpg","photos-1790531783025-5823.jpg","photos-1790531783173-eioa.jpg","photos-1790531784110-t6j2.jpg","photos-1790531784279-5mpg.jpg"];
function SIMG(k){ return './uploads/'+SAMPLE_IMGS[((k%SAMPLE_IMGS.length)+SAMPLE_IMGS.length)%SAMPLE_IMGS.length]; }
// n photos for a varied stress shoot: long bursts, brackets, two bodies, portraits, dark/blown singles, idle gaps
function sampleBig(n){ const out=[]; let t=Date.UTC(2026,8,28,7,40,0)/1000, k=0, seed=900; const A={model:'ILCE-7M4',serial:'5021473'}, Bd={model:'ILCE-1',serial:'7710022'}; const lenses=[['FE 24mm F1.4 GM',24,1.4],['FE 35mm F1.4 GM',35,1.8],['FE 85mm F1.4 GM',85,2],['FE 70-200mm F2.8 GM II',135,2.8],['FE 70-200mm F2.8 GM II',200,2.8]];
  const ds=s=>{ const d=new Date(s*1000); return d.getUTCFullYear()+':'+p2(d.getUTCMonth()+1)+':'+p2(d.getUTCDate())+' '+p2(d.getUTCHours())+':'+p2(d.getUTCMinutes())+':'+p2(d.getUTCSeconds()); };
  let ri=0; while(out.length<n){ const L=lenses[(ri*3)%lenses.length], gap=[40,90,600,1800,15,120,3600,300][ri%8]; t+=gap; const units=3+(ri*7)%9; for(let u=0;u<units&&out.length<n;u++){ const r=(ri*13+u*5)%20, kind=r<9?'s':r<16?'b':r<18?'k':'B', cnt=kind==='s'?1:kind==='k'?3:kind==='B'?30+(ri%4)*20:4+(r%7); seed++; if(u) t+=kind==='s'?12+(u%5)*6:8; const pt=(ri+u)%6===0&&kind==='s';
    for(let j=0;j<cnt&&out.length<n;j++){ const body=(ri%5===2&&kind==='s'&&k%2)?Bd:A, w=pt?240:360, h=pt?360:240, lw=pt?1067:1600, lh=pt?1600:1067, focus=kind==='b'||kind==='B'?(j===(seed*7)%cnt?420:160+((j*53+seed*31)%220)):kind==='k'?300:[340,90,260,300,380,70,310][(k+ri)%7], blown=kind==='s'&&(k*43+11)%100<8, shake=kind==='s'&&!blown&&(k*29+5)%100<9, dark=kind==='s'&&(k*17)%100<4, nopv=kind==='s'&&(k*31)%500===7;
      out.push({name:'DSC'+String(10000+k).slice(1)+'.ARW',path:'Untitled/DCIM/100MSDCF/DSC'+String(10000+k).slice(1)+'.ARW',date:ds(t+(kind==='b'||kind==='B'?Math.floor(j/10):kind==='k'?j:0)),exp:shake?1/15:[1/250,1/500,1/1000,1/125][k%4],fl:L[1],fnum:L[2],ev:kind==='k'?[-1,0,1][j]:[0,0.7,-0.3,0][k%4],iso:[100,200,400,800,3200][ri%5],lens:L[0],model:body.model,serial:body.serial,w:pt?4672:7008,h:pt?7008:4672,bytes:33.1e6+(k%7)*0.4e6,lum:dark?0.05:0.5,focus:nopv?0:focus,clip:blown?3.2:0,portrait:pt,nopv,dhash:null,focusLoc:nopv?null:{x:0.3+((k*7)%5)*0.08,y:0.35+((k*3)%3)*0.1,w:pt?0.3:0.16,h:pt?0.18:0.24},seqImage:kind==='b'||kind==='B'?j+1:null,seqLength:kind==='b'||kind==='B'?cnt:null,releaseMode2:kind==='k'?2:(kind==='b'||kind==='B')?1:null,src:nopv?'':SIMG(seed),lg:nopv?'':SIMG(seed)}); k++; } } t+=30; ri++; }
  return out; }
// n photos for performance runs: the sample repeated with each copy shifted 3 h later
function sampleN(n){ const base=sample(), out=[]; let k=0; while(out.length<n){ const off=k*10800; base.forEach(p=>{ if(out.length>=n) return; const m=/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(p.date); const t=Date.UTC(+m[1],+m[2]-1,+m[3],+m[4],+m[5],+m[6])/1000+off, dd=new Date(t*1000), ds=dd.getUTCFullYear()+':'+p2(dd.getUTCMonth()+1)+':'+p2(dd.getUTCDate())+' '+p2(dd.getUTCHours())+':'+p2(dd.getUTCMinutes())+':'+p2(dd.getUTCSeconds()); const nm='DSC'+String(10000+out.length).slice(1)+'.ARW'; out.push({...p,name:nm,path:'Untitled/DCIM/100MSDCF/'+nm,date:ds}); }); k++; } return out; }
g.LuminaV4={GRAMMAR,grammarSections,fmt,sample,sampleN,sampleBig,SHOOTS,facts,FAQ};
})(typeof window!=='undefined'?window:globalThis);
