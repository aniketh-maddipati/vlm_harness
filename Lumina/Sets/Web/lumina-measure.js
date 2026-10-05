// Shared pixel measurements for Lumina Cull. No models, no verdicts.
// measure(img, M, {masks}) -> {sharp, sx, sy, hi, hiAll, lo, grid(8×8, 1 = sharpest cell), hash, aniso, motionDir, subj, peak?, clip?}
(function(){
  function measure(im, M, opt){ opt=opt||{}; const masks=opt.masks!==false;
    const W0=im.naturalWidth||im.width, H0=im.naturalHeight||im.height, sc=Math.min(1,M/Math.max(W0,H0)), W=Math.max(8,Math.round(W0*sc)), H=Math.max(8,Math.round(H0*sc));
    const cv=document.createElement('canvas'); cv.width=W; cv.height=H; const x=cv.getContext('2d',{willReadFrequently:true}); x.drawImage(im,0,0,W,H);
    const d=x.getImageData(0,0,W,H).data, N=W*H, L=new Float32Array(N), lap=new Float32Array(N);
    for(let i=0;i<N;i++) L[i]=0.2126*d[i*4]+0.7152*d[i*4+1]+0.0722*d[i*4+2];
    let sum=0,cnt=0,gx2=0,gy2=0;
    for(let y=1;y<H-1;y++) for(let q=1;q<W-1;q++){ const i=y*W+q, v=Math.abs(4*L[i]-L[i-1]-L[i+1]-L[i-W]-L[i+W]); lap[i]=v; sum+=v*v; cnt++; const dx=L[i+1]-L[i-1], dy=L[i+W]-L[i-W]; gx2+=dx*dx; gy2+=dy*dy; }
    const aniso=Math.abs(gx2-gy2)/Math.max(1,gx2+gy2), motionDir=gx2>gy2?'v':'h';
    const hist=new Uint32Array(256); for(let i=0;i<N;i++) hist[Math.min(255,lap[i]|0)]++; let acc=0,thr=255; for(let v=255;v>=0;v--){ acc+=hist[v]; if(acc>=N*0.03){ thr=v; break; } } thr=Math.max(thr,18);
    const G=8, cell=new Float32Array(G*G); let best=-1,bx=3,by=3;
    for(let gy=0;gy<G;gy++) for(let gx=0;gx<G;gx++){ const x0=Math.floor(gx*W/G),x1=Math.floor((gx+1)*W/G),y0=Math.floor(gy*H/G),y1=Math.floor((gy+1)*H/G); let t=0; for(let y=y0;y<y1;y++) for(let q=x0;q<x1;q++) t+=lap[y*W+q]; t/=Math.max(1,(x1-x0)*(y1-y0)); cell[gy*G+gx]=t; if(t>best){ best=t; bx=gx; by=gy; } }
    const thrC=best*0.45, seen=new Uint8Array(G*G), st=[by*G+bx]; seen[st[0]]=1; let x0=bx,x1=bx,y0=by,y1=by;
    while(st.length){ const k=st.pop(), cy=(k/G)|0, cx=k%G; x0=Math.min(x0,cx); x1=Math.max(x1,cx); y0=Math.min(y0,cy); y1=Math.max(y1,cy); [[cx+1,cy],[cx-1,cy],[cx,cy+1],[cx,cy-1]].forEach(([nx,ny])=>{ if(nx<0||ny<0||nx>=G||ny>=G) return; const nk=ny*G+nx; if(seen[nk]||cell[nk]<thrC) return; seen[nk]=1; st.push(nk); }); }
    const subj={x:x0/G*100,y:y0/G*100,w:(x1-x0+1)/G*100,h:(y1-y0+1)/G*100}, mean=sum/Math.max(1,cnt);
    let hi=0,lo=0,hiAll=0, peak='', clip='';
    if(masks){ const pk=x.createImageData(W,H), cl=x.createImageData(W,H), P=pk.data, C=cl.data;
      for(let i=0;i<N;i++){ const o=i*4; if(lap[i]>=thr){ P[o]=255; P[o+1]=36; P[o+2]=36; P[o+3]=255; } if(d[o]>=250||d[o+1]>=250||d[o+2]>=250){ hi++; if(d[o]>=250&&d[o+1]>=250&&d[o+2]>=250) hiAll++; C[o]=255; C[o+1]=36; C[o+2]=36; C[o+3]=235; } else if(L[i]<=6){ lo++; C[o]=36; C[o+1]=110; C[o+2]=255; C[o+3]=235; } }
      x.putImageData(pk,0,0); peak=cv.toDataURL('image/png'); x.putImageData(cl,0,0); clip=cv.toDataURL('image/png'); }
    else { for(let i=0;i<N;i++){ const o=i*4; if(d[o]>=250||d[o+1]>=250||d[o+2]>=250){ hi++; if(d[o]>=250&&d[o+1]>=250&&d[o+2]>=250) hiAll++; } else if(L[i]<=6) lo++; } }
    const hc=document.createElement('canvas'); hc.width=9; hc.height=8; const hx=hc.getContext('2d',{willReadFrequently:true}); hx.drawImage(im,0,0,9,8); const hd=hx.getImageData(0,0,9,8).data; let hash='';
    for(let y=0;y<8;y++) for(let q=0;q<8;q++){ const a=(y*9+q)*4; hash+=(hd[a]+hd[a+1]+hd[a+2])>(hd[a+4]+hd[a+5]+hd[a+6])?'1':'0'; }
    return {sharp:mean,sx:Math.round((bx+0.5)/G*100),sy:Math.round((by+0.5)/G*100),peak,clip,hi:hi/N*100,hiAll:hiAll/N*100,lo:lo/N*100,grid:Array.from(cell,v=>best>0?v/best:0),G,hash,aniso,motionDir,subj,W,H}; }
  // Current thresholds used by Cull v2's displays. Harness reports agreement at these and sweeps alternatives.
  const T={ softRel:0.30, motionSome:0.15, motionStreak:0.40, blownPct:0.5, crushedPct:2.0 };
  function motionClass(a){ const m=Math.max(0,(a.aniso-T.motionSome)/(T.motionStreak-T.motionSome+1e-9)); return m<=0?'steady':m<1?'some':'streaked'; }
  window.LuminaMeasure={measure,T,motionClass};
})();
