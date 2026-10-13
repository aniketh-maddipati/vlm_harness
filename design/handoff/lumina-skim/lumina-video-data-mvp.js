// FX5 sample shoot for Lumina Skim (MVP). A host app sets window.LuminaVideo (without __sample) and window.lumina.video before load.
(function(){
  function R(seed){var s=seed;return function(){s=(s*16807)%2147483647;return (s-1)/2147483646;};}
  function p2(n){return String(n).padStart(2,'0');}
  function iso(ms){var d=new Date(ms);return d.getFullYear()+'-'+p2(d.getMonth()+1)+'-'+p2(d.getDate())+'T'+p2(d.getHours())+':'+p2(d.getMinutes())+':'+p2(d.getSeconds());}
  // Metadata shaped after Visual Park's free "SONY FX5 Sample Pack" (9 clips, 5K S-Log3 + X-OCN RAW, sizes as listed).
  // Durations and times are estimated from the listed sizes; frames are placeholders until the real pack is opened.
  function fx5(){
    var L=[['FX5 24p OpenGate 01','MP4',24,6048,4032,492.6e6,'XAVC HS 5K · H.265','slog'],['FX5 24p OpenGate 02','MP4',24,6048,4032,1.91e9,'XAVC HS 5K · H.265','slog'],['FX5 60p','MP4',60,5120,2880,359.4e6,'XAVC HS 5K · H.265','slog'],['FX5 60p OpenGate 01','MP4',60,6048,4032,911.4e6,'XAVC HS 5K · H.265','slog'],['FX5 60p OpenGate 02','MP4',60,6048,4032,903.6e6,'XAVC HS 5K · H.265','slog'],['FX5 120p 01','MP4',120,5120,2880,2.11e9,'XAVC HS 5K · H.265','slog'],['FX5 120p 02','MP4',120,5120,2880,1.03e9,'XAVC HS 5K · H.265','slog'],['FX5 X-OCN 24p OpenGate','MXF',24,6048,4032,1.47e9,'X-OCN LT · RAW','raw'],['FX5 X-OCN 60p','MXF',60,5120,2880,3.82e9,'X-OCN LT · RAW','raw']];
    var r=R(41),t=new Date('2026-07-14T16:20:00').getTime(),clips=[];
    L.forEach(function(x,i){
      var mbps=x[7]==='raw'?(x[2]>30?1100:620):(x[2]===120?280:x[2]===60?200:140);
      var dur=Math.max(3,Math.round(x[5]*8/(mbps*1e6)));
      var f=x[7]==='raw'?{state:'unreliable'}:{ev:Math.round((r()-0.5)*16)/10,clip:i===5?2.4:Math.round(r()*8)/10,crush:Math.round(r()*40)/10,sharp:Math.round((0.48+r()*0.45)*100)/100,motion:i===3?'pan':null,bump:null,state:'ready'};
      if(f.state==='ready'){var sf=[];for(var j=0;j<8;j++)sf.push(Math.round(Math.min(0.98,f.sharp+r()*0.25)*100)/100);sf[3]=f.sharp;f.sharpF=sf;}
      var id='V'+String(i+1).padStart(4,'0');
      clips.push({id:id,name:x[0]+'.'+x[1],path:'/Volumes/FX5 Sample Pack/'+(x[7]==='raw'?'X-OCN RAW/':'S-Log3/')+x[0]+'.'+x[1],t:iso(t),dur:dur,fps:x[2],w:x[3],h:x[4],bytes:x[5],codec:x[6],
        profile:x[7]==='raw'?{gamma:null,primaries:null,source:'none'}:{gamma:'S-Log3',primaries:'S-Gamut3.Cine',source:'sidecar'},frames:[null,null,null,null,null,null,null,null],facts:f,dismissed:[],mark:null,look:{hue:[28,30,200,205,210,95,100,40,45][i]}});
      t+=(dur+(i===4?2700:i===6?1500:90+r()*240))*1000;
    });
    var gaps=[];for(var i=0;i<clips.length-1;i++){var a=clips[i],b=clips[i+1];gaps.push({after:a.id,s:Math.max(0,Math.round((new Date(b.t)-new Date(a.t))/1000-a.dur))});}
    return {__sample:true,shoot:{name:'FX5 Sample Pack',days:1,bytes:clips.reduce(function(s,c){return s+c.bytes;},0),free:null,rate:24,source:'Visual Park · SONY FX5 Sample Pack (free, non-commercial)'},clips:clips,gaps:gaps};
  }
  window.LuminaVideoSamples={fx5:fx5};
  if(!window.LuminaVideo) window.LuminaVideo=fx5();
  window.lumina=window.lumina||{};
  if(!window.lumina.video){var log=window.__luminaVideoCalls=[];var f=function(k){return function(){log.push([k].concat([].slice.call(arguments)));return Promise.resolve(true);};};
    window.lumina.video={mark:f('mark'),preview:f('preview'),handoff:f('handoff')};}
})();
