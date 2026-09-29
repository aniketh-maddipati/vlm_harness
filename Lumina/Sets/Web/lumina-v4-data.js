// Lumina v4-beta page data: the grammar (shown verbatim in the ? sheet), the browser-only sample shoot,
// value formatters, and the "this shoot" facts. No UI.
(function(g){
const GRAMMAR = `LUMINA CULL GRAMMAR
Rule: the cursor acts on the unit under it. It is the only selection. P or R keeps. ⇧ works inside a stack.
Unit = a photo, or a closed stack (burst/bracket). Every decision is one undo step and reports in the footer.

MOVE
←→            next / previous photo · on a stack: through its frames, then on · hold repeats
⇧←→           same, and stops at the ends of a stack
↑↓            row above / below, same column
⌥←→           skip a whole stack or run of singles
⌘←→           previous / next row
⌥↑↓           previous / next group in a row not yet seen
⏎             closed stack: open at the first frame · open stack: done, move on · photo: next unseen row
esc           close the stack

DECIDE (the unit under the cursor)
P / R         keep / un-keep (right or left hand) · closed stack: sharpest · bracket: all · T also works
F             flag for later (not saved while flagged)
P R F         in an open stack or large view: the frame shown
⌘A            keep every photo in this row · 600 ms preview · esc cancels · one undo
⇧P / ⇧R       stack (open or closed): keep the sharpest only · bracket: all
⇧F            stack (open or closed): flag all · again: unflag
Q / ⌘Z        undo
X U L G 1–5   not used · the footer names the right key
⇪ Caps Lock   auto-advance off while on

SEEN
a row is marked seen when the cursor leaves it
⇧U            rows not yet seen only

VIEW
Space         hold: large view while held · tap: toggle · a stack opens at its first frame · ←→ within the stack, else the row
Z hold        100% · in a stack the same region on every frame · drag moves it
time axis     large view and open stacks · capture time per frame · gold: sharpest · ≈: estimated
− +           tile size: small / medium / large, scaled to the window
B / ⇧B        split / merge here (row or stack)
H             hide key bar · ?  all keys
Tab           move between buttons · ⏎ or Space presses the focused one · esc returns to the grid

CLICK
click                         focus · the Keep button on the focused photo keeps / un-keeps
click row header              focus the row
double-click photo or stack   large view · double-click again closes
double-click stack badge      keep sharpest
double-click row header       keep every photo in the row · ⇧ clears the row · one step

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
⌘,            keeper rating (1–5★, default 3) · auto-advance · arrows enter stacks · tile size

STEPS
⌘1 Open · ⌘2 Cull · ⌘3 Save · ⌘O open a folder or card · ⌘R Show in Finder (Cull: the photo · Save: the folder)
Open: ↑↓ choose · ⏎ open
Save: ⌘⏎ save keepers · one sidecar per keeper, read by Lightroom Classic and Capture One (⏎ alone does not save)`;

const FAQ=[["Using Lumina",[["What does Lumina do?","It opens a card or folder of Sony RAW files, groups them into rows and stacks, lets you mark keepers with P, and writes an .xmp sidecar for each keeper so Lightroom Classic or Capture One can pick up the rating."],["Which cameras and files are supported?","Sony ARW. Other RAW formats are skipped and listed after import. JPEG and HEIF files without a matching RAW are skipped because Lightroom does not read sidecars for JPEG."],["How are rows made?","A new row starts after a long time gap for that shoot (compared with the last 10 gaps, at least 10 seconds), or when the lens, focal length, orientation, shooting mode, white balance, flash or ISO changes. You can split or merge with B and ⇧B."],["How are stacks made?","Frames from the camera's continuous drive sequence form a stack. Without sequence data, frames taken within 2 seconds that look alike form a stack. A large change between frames starts a new one."],["How is the sharpest frame chosen?","By the amount of edge detail in the preview image stored inside each RAW. It is a starting point. Check it in large view with Z for 100%."],["Can I undo?","Yes. Q or ⌘Z undoes one step at a time. The undo history resets when you close the shoot."],["What happens if I shot with two cameras?","Photos are sorted by capture time, so rows only line up if both camera clocks were set to the same time."]]],["Your files",[["Does Lumina change my RAW files?","No. RAW files are never modified, moved or deleted."],["What does Save write?","One small .xmp file next to each keeper, with the same name as the RAW. It sets the rating to 3★. Photos you did not keep get nothing."],["What if a photo already has a sidecar?","Only the rating is updated. Edits and other metadata stay. The previous file is kept as .xmp.lumina-bak."],["Why 3★ and not a Lightroom pick flag?","Lightroom stores pick flags in its catalog, not in sidecar files. A rating is the part of a sidecar Lightroom reads, so keepers are easy to filter."],["Can I cull straight from the card?","Yes. The card is read only. Sidecars cannot be written to a card, so copy the folder to your Mac before you save. Your decisions carry over when you open the copy."],["How do I get the keepers into Lightroom Classic?","Import the folder. For photos already in your catalog, select them and choose Metadata → Read Metadata from Files."],["And Capture One?","Import the folder. The ratings come with the sidecars."]]],["Privacy and security",[["Does Lumina use AI?","Not in this version. There is no AI model and no online service. Lumina uses plain image measurements (edge detail, brightness and a small fingerprint to compare frames) that run on your Mac. You make every decision."],["Will Lumina add editing or AI features?","Later versions may add editing and AI features, based on what users ask for. Any AI feature will be optional and will say clearly what it does and whether anything leaves your Mac."],["Are my photos uploaded anywhere?","No. Files are read on your Mac and are not sent to a server."],["Are my photos used to train anything?","No."],["Where are my decisions stored?","On your Mac, in Lumina's app data. In the browser version they are stored in that browser only."],["How do I remove Lumina's data?","Use Remove Lumina's working files at the bottom of Handoff. It deletes saved sessions and cached previews. Your RAW files and sidecars are not affected."],["Why does macOS ask for access?","macOS asks before any app reads a removable drive or protected folder. Lumina needs read access to open the card. You can change this in System Settings → Privacy & Security → Files and Folders."],["Why did Chrome ask to upload files?","That is how Chrome words folder access for web pages. The browser version opens the files on your Mac and does not send them anywhere. The Mac app does not show this prompt."]]],["Contact",[["How do I report a problem or ask a question?","DM Aniketh Maddipati (@aniketh745) on X."],["Can I suggest a feature?","Yes. DM Aniketh Maddipati (@aniketh745) on X. Feedback decides what comes next."]]]];

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
  const A={model:'ILCE-7M4',serial:'5021473'}, Bd={model:'ILCE-7M3',serial:'4418260'};
  const rows=[
    {gap:0,lens:'FE 24mm F1.4 GM',fl:24,f:2,iso:200,u:['s','s','s','b8']},
    {gap:720,lens:'FE 24mm F1.4 GM',fl:24,f:2,iso:200,u:['b31','s','s','s','s','s','s']},
    {gap:80,lens:'FE 85mm F1.4 GM',fl:85,f:2,iso:200,u:['s','s','b5','s']},
    {gap:40,lens:'FE 85mm F1.4 GM',fl:85,f:2.8,iso:200,pt:true,u:['s','s','s','s','k3']},
    {gap:1500,lens:'FE 85mm F1.4 GM',fl:85,f:4,iso:100,two:true,u:['b12','s','s','s','s','s']},
    {gap:900,lens:'FE 24mm F1.4 GM',fl:24,f:1.4,iso:400,u:['s','s','b6','s']},
    {gap:3900,lens:'FE 24mm F1.4 GM',fl:24,f:1.4,iso:3200,u:['b6','s','s','s']},
    {gap:1200,lens:'FE 24mm F1.4 GM',fl:24,f:1.4,iso:3200,u:['s','s','b4']}];
  const ds=s=>{ const d=new Date(s*1000); return d.getUTCFullYear()+':'+p2(d.getUTCMonth()+1)+':'+p2(d.getUTCDate())+' '+p2(d.getUTCHours())+':'+p2(d.getUTCMinutes())+':'+p2(d.getUTCSeconds()); };
  rows.forEach((r,ri)=>{ t+=r.gap; r.u.forEach((u,ui)=>{ const kind=u[0], cnt=kind==='s'?1:+u.slice(1); seed++; if(ui) t+=kind==='s'?20:12; const H=kind==='b'&&cnt>=6?hashes(cnt,Math.floor(cnt*0.55)):null;
    for(let j=0;j<cnt;j++){ const pt=!!r.pt&&kind!=='k', w=pt?240:360+(j%4)*6, h=pt?360:240, lw=pt?1067:1600+(j%4)*24, lh=pt?1600:1067, body=r.two&&kind==='s'&&n%2?Bd:A;
      const focus=kind==='b'?(j===(seed*7)%cnt?420:200+((j*53+seed*31)%180)):kind==='k'?300:[340,90,260,300,380,70,310][(n+ri)%7], blown=kind==='s'&&(n*43+11)%100<9, shake=kind==='s'&&!blown&&(n*29+5)%100<10, dark=kind==='s'&&ri===5&&ui===1, nopv=kind==='s'&&ri===6&&ui===2;
      out.push({name:'DSC0'+(3100+n)+'.ARW',path:'Untitled/DCIM/100MSDCF/DSC0'+(3100+n)+'.ARW',date:ds(t+(kind==='b'?Math.floor(j/10):kind==='k'?j:0)),exp:shake?1/15:[1/250,1/500,1/1000][n%3],fl:r.fl,fnum:r.f,ev:kind==='k'?[-1,0,1][j]:[0,0.7,-0.3,0][n%4],iso:r.iso,lens:r.lens,model:body.model,serial:body.serial,
        w:pt?4672:7008,h:pt?7008:4672,bytes:33.1e6+(n%7)*0.4e6,lum:dark?0.05:0.5,focus:nopv?0:focus,clip:blown?3.2:0,portrait:pt,nopv,dhash:H?H[j]:null,
        seqImage:kind==='b'?j+1:null,seqLength:kind==='b'?cnt:null,releaseMode2:kind==='k'?2:kind==='b'?1:null,src:nopv?'':'https://picsum.photos/seed/lumina'+(180+seed)+'/'+w+'/'+h,lg:nopv?'':'https://picsum.photos/seed/lumina'+(180+seed)+'/'+lw+'/'+lh});
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

// n photos for performance runs: the sample repeated with each copy shifted 3 h later
function sampleN(n){ const base=sample(), out=[]; let k=0; while(out.length<n){ const off=k*10800; base.forEach(p=>{ if(out.length>=n) return; const m=/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(p.date); const t=Date.UTC(+m[1],+m[2]-1,+m[3],+m[4],+m[5],+m[6])/1000+off, dd=new Date(t*1000), ds=dd.getUTCFullYear()+':'+p2(dd.getUTCMonth()+1)+':'+p2(dd.getUTCDate())+' '+p2(dd.getUTCHours())+':'+p2(dd.getUTCMinutes())+':'+p2(dd.getUTCSeconds()); const nm='DSC'+String(10000+out.length).slice(1)+'.ARW'; out.push({...p,name:nm,path:'Untitled/DCIM/100MSDCF/'+nm,date:ds}); }); k++; } return out; }
g.LuminaV4={GRAMMAR,grammarSections,fmt,sample,sampleN,SHOOTS,facts,FAQ};
})(typeof window!=='undefined'?window:globalThis);
