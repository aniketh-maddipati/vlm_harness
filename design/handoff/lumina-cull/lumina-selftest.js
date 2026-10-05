// Lumina self-test. Open the page with ?selftest (grammar + perf) or ?selftest&n=1000 (perf on 1,000 photos).
// Drives the page with real key events and reads window.luminaState(). Results appear in a panel and in window.luminaTestResults.
(function(){
  const box=document.createElement('div'); box.style.cssText='position:fixed;right:12px;bottom:46px;z-index:99;width:380px;max-height:70vh;overflow:auto;padding:12px 14px;border-radius:12px;background:#111;color:#EFECE6;font:12px -apple-system,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.6)';
  const head=document.createElement('div'); head.style.cssText='font-weight:700;margin-bottom:8px'; head.textContent='Lumina self-test · running…'; box.appendChild(head); document.body.appendChild(box);
  const rows=[]; const push=(n,ok,d)=>{ rows.push({n,ok,d:d||''}); const r=document.createElement('div'); r.style.cssText='display:grid;grid-template-columns:36px 1fr auto;gap:8px;padding:3px 0;border-top:1px solid #222'; r.innerHTML='<b style="color:'+(ok?'#9ED7B0':'#FFB4A2')+'">'+(ok?'pass':'fail')+'</b><span></span><span style="color:#96918A"></span>'; r.children[1].textContent=n; r.children[2].textContent=d||''; box.appendChild(r); };
  const w=()=>window, doc=()=>document, S=()=>window.luminaState(), wait=ms=>new Promise(r=>setTimeout(r,ms));
  const K=async(key,code,o={},ms=60)=>{ window.dispatchEvent(new KeyboardEvent('keydown',{key,code,bubbles:true,...o})); await wait(ms); };
  const U=async(key,code,ms=40)=>{ window.dispatchEvent(new KeyboardEvent('keyup',{key,code,bubbles:true})); await wait(ms); };
  const tap=async(key,code,o={})=>{ await K(key,code,o); await U(key,code); };
  const q=sel=>document.querySelector(sel), clickTile=async sel=>{ const n=q(sel); if(!n) return false; n.click(); await wait(120); return true; };
  const T=async(n,fn)=>{ try{ const r=await fn(); push(n,r===true||!!(r&&r.ok),r&&r.d); }catch(e){ push(n,false,String(e.message||e).slice(0,60)); } };
  const big=/[?&]n=\d+/.test(location.search);
  (async()=>{ let t0=Date.now(); while(typeof window.luminaState!=='function'&&Date.now()-t0<15000) await wait(100); await wait(400);
    if(!big){
      await T('page exposes luminaState',()=>typeof w().luminaState==='function');
      await T('⌘2 opens Cull',async()=>{ await tap('2','Digit2',{metaKey:true}); await wait(300); return S().view==='cull'; });
      await T('P keeps the photo under the cursor',async()=>{ await clickTile('[data-lumina=tile]'); const id=S().cur; await tap('p','KeyP'); return S().marks[id]==='keep'; });
      await T('P again un-keeps',async()=>{ await tap('ArrowLeft','ArrowLeft'); const id=S().cur; const was=S().marks[id]; await tap('p','KeyP'); return was==='keep'&&!S().marks[id]; });
      await T('R un-keeps (two states only)',async()=>{ const id=S().cur; await tap('p','KeyP'); await tap('ArrowLeft','ArrowLeft'); await tap('r','KeyR'); return !S().marks[id]&&!Object.values(S().marks).includes('out'); });
      await T('⇧R steps back and un-keeps',async()=>{ const id=S().cur; await tap('p','KeyP'); await tap('R','KeyR',{shiftKey:true}); return S().cur===id&&!S().marks[id]; });
      await T('1–5 change nothing',async()=>{ const u=S().undoDepth; await tap('3','Digit3'); return S().undoDepth===u; });
      await T('F held shows the focus overlay',async()=>{ await tap('ArrowRight','ArrowRight'); await tap(' ','Space'); await wait(250); await K('f','KeyF',{},250); const on=/red = sharp edges/.test(document.body.innerText); await U('f','KeyF'); await tap('Escape','Escape'); await wait(150); return on; });
      await T('Q undoes one step',async()=>{ const u=S().undoDepth; await tap('q','KeyQ'); return S().undoDepth===u-1; });
      await T('⇧→ opens a stack with a time axis',async()=>{ await clickTile('[data-lumina=stack]'); await tap('ArrowRight','ArrowRight',{shiftKey:true}); await wait(200); return !!q('[data-lumina=stack-axis]'); });
      await T('⇧→ steps frames inside the stack',async()=>{ const a=S().cur; await tap('ArrowRight','ArrowRight',{shiftKey:true}); return S().cur!==a&&!!q('[data-lumina=stack-axis]'); });
      await T('esc closes an open stack',async()=>{ await tap('Escape','Escape'); await wait(200); return !q('[data-lumina=stack-axis]'); });
      await T('→ on a closed stack walks into its frames',async()=>{ await clickTile('[data-lumina=stack]'); await tap('ArrowRight','ArrowRight'); await wait(150); return !!q('[data-lumina=stack-axis]'); });
      await T('→ past the last frame moves on and closes the stack',async()=>{ for(let i=0;i<60&&q('[data-lumina=stack-axis]');i++) await tap('ArrowRight','ArrowRight'); await wait(150); return !q('[data-lumina=stack-axis]'); });
      await T('⌥→ skips a closed stack',async()=>{ await clickTile('[data-lumina=stack]'); const a=S().cur; await tap('ArrowRight','ArrowRight',{altKey:true}); await wait(120); return S().cur!==a&&!q('[data-lumina=stack-axis]'); });
      await T('Space on a stack opens large at frame 1 with an axis',async()=>{ await clickTile('[data-lumina=stack]'); await K(' ','Space'); await U(' ','Space'); await wait(350); return !!q('[data-lumina=large]')&&!!q('[data-lumina=large-axis]'); });
      await T('large view: → walks through 40 photos without stopping',async()=>{ const seen=new Set(); for(let i=0;i<40;i++){ await tap('ArrowRight','ArrowRight'); seen.add(S().cur); } return {ok:seen.size>=38,d:seen.size+' distinct'}; });
      await T('esc closes large view',async()=>{ await tap('Escape','Escape'); await wait(300); return !q('[data-lumina=large]'); });
      await T('↓ marks the row seen',async()=>{ await tap('ArrowUp','ArrowUp'); const row=S().cur; await tap('ArrowDown','ArrowDown'); await wait(150); return [...doc().querySelectorAll('[data-lumina=row-progress]')].some(n=>/seen/.test(n.textContent)); });
      await T('⌘A previews keep-row, esc cancels',async()=>{ await K('a','KeyA',{metaKey:true}); const p=S().pending; await tap('Escape','Escape'); return p&&!S().pending; });
      await T('⌘, opens Settings, esc closes',async()=>{ await tap(',','Comma',{metaKey:true}); const o=!!q('[data-lumina=settings]'); await tap('Escape','Escape'); await wait(100); return o&&!q('[data-lumina=settings]'); });
      await T('⌘4 shows the Save bar with a count',async()=>{ await tap('4','Digit4',{metaKey:true}); await wait(300); const b=q('[data-lumina=handoff-primary]'); return {ok:!!b&&/Save \d+ pick/.test(b.textContent),d:b?b.textContent.trim():'none'}; });
      await T('⌘2 back to Cull',async()=>{ await tap('2','Digit2',{metaKey:true}); await wait(200); return S().view==='cull'; });
      await T('perf: → key to next frame (median of 40)',async()=>{ const ts=[]; for(let i=0;i<40;i++){ const t0=performance.now(); await K('ArrowRight','ArrowRight',{},0); await new Promise(r=>w().requestAnimationFrame(()=>r())); ts.push(performance.now()-t0); await U('ArrowRight','ArrowRight',0); } ts.sort((a,b)=>a-b); const m=ts[20]; return {ok:m<50,d:m.toFixed(1)+' ms'}; });
      await T('perf: open large view',async()=>{ const t0=performance.now(); await K(' ','Space',{},0); await new Promise(r=>w().requestAnimationFrame(()=>r())); const ms=performance.now()-t0; await U(' ','Space',0); await tap('Escape','Escape'); return {ok:ms<100,d:ms.toFixed(1)+' ms'}; });
  
    } else {
      await T('perf: ⌘2 to first tiles on screen',async()=>{ const t1=performance.now(); await tap('2','Digit2',{metaKey:true}); await new Promise(r=>requestAnimationFrame(()=>r())); const n=document.querySelectorAll('[data-tile]').length; return {ok:n>0,d:Math.round(performance.now()-t1)+' ms · '+S().undoDepth+' undo · '+n+' tiles'}; });
      await T('perf: ↓ ×30 on 1,000 photos (median)',async()=>{ const ts=[]; for(let i=0;i<30;i++){ const t1=performance.now(); await K('ArrowDown','ArrowDown',{},0); await new Promise(r=>requestAnimationFrame(()=>r())); ts.push(performance.now()-t1); await U('ArrowDown','ArrowDown',0); } ts.sort((a,b)=>a-b); return {ok:ts[15]<50,d:ts[15].toFixed(1)+' ms'}; });
      await T('perf: → ×40 on 1,000 photos (median)',async()=>{ const ts=[]; for(let i=0;i<40;i++){ const t1=performance.now(); await K('ArrowRight','ArrowRight',{},0); await new Promise(r=>requestAnimationFrame(()=>r())); ts.push(performance.now()-t1); await U('ArrowRight','ArrowRight',0); } ts.sort((a,b)=>a-b); return {ok:ts[20]<50,d:ts[20].toFixed(1)+' ms'}; });
    }
    const f=rows.filter(r=>!r.ok).length; head.textContent='Lumina self-test · '+(rows.length-f)+' passed · '+f+' failed'; window.luminaTestResults=rows;
  })();
})();
