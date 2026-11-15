// policy: "aware" uses the on-screen key map, "naive" assumes default arrows,
// "human" models a first-timer: sees bats/candy/pumpkins ~250-350 ms late (tracks own witch live), learns a key's new mapping 1.0-1.5 s
// after it changes, steers with noise, dodges bats late/small, and waits ~1.5 s before chasing pumpkins
const {chromium}=require('playwright');
const policy=process.argv[2], runs=+process.argv[3]||1;
const KN=['ArrowUp','ArrowDown','ArrowLeft','ArrowRight'];
(async()=>{
 const b=await chromium.launch({args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const res=[];
 for(let r=0;r<runs;r++){
  const p=await b.newPage({viewport:{width:960,height:540}});
  await p.goto('http://localhost:'+(process.env.PORT||8765)+'/index.html?bot=1');
  await p.waitForFunction(()=>window.nb,null,{timeout:30000});
  await p.mouse.click(480,270); await p.waitForTimeout(800); if(process.env.OUT) await p.screenshot({path:process.env.OUT+'/title.png'}); await p.keyboard.press('ArrowRight');
  const held=new Set(); let st;
  const hist=[], lag=0.25+Math.random()*0.1, belief=[0,1,2,3], seen=[0,1,2,3], changedAt=[0,0,0,0], noticeIn=[0,0,0,0];
  let noise=0, noiseT=0; const pumpSeen=new Map(); const shots=(process.env.SHOTS||'').split(',').filter(Boolean).map(Number); const out=process.env.OUT||'.';

  let polls=0; for(;;){ polls++;
   st=await p.evaluate(()=>window.nb);
   while(shots.length&&st.t>=shots[0]){await p.screenshot({path:`${out}/t${shots.shift()}.png`});}
   if(st.state===2){ if(process.env.OUT){await p.waitForTimeout(1200); await p.screenshot({path:out+'/end.png'});} break;}
   let v=st;
   if(policy==='human'){
    hist.push(st); while(hist.length>1&&hist[1].t<=st.t-lag) hist.shift(); v=hist[0];  // act on the delayed frame
    for(let k=0;k<4;k++){
     if(st.map[k]!==seen[k]){seen[k]=st.map[k]; changedAt[k]=st.t; noticeIn[k]=1.0+Math.random()*0.5;}
     if(belief[k]!==seen[k]&&st.t-changedAt[k]>=noticeIn[k]) belief[k]=seen[k];
    }
    if(st.t>=noiseT){noise=(Math.random()-0.5)*1.4; noiseT=st.t+0.3+Math.random()*0.4;}  // +-40 deg drift
   }
   const [wx,wy]=st.w; const haunted=(policy==='human'?belief:v.map).some((d,k)=>d!==k);
   let tgt=null;
   let pumps=v.pumpkins;
   if(policy==='human'){ for(const q of pumps){const id=q.map(Math.round).join(); if(!pumpSeen.has(id)) pumpSeen.set(id,v.t);}
    pumps=pumps.filter(q=>v.t-pumpSeen.get(q.map(Math.round).join())>=1.5);}
   const pool=(haunted&&pumps.length)?pumps:v.candies;
   for(const c of pool){const d=Math.hypot(c[0]-wx,c[1]-wy); if(!tgt||d<tgt.d) tgt={x:c[0],y:c[1],d};}
   let vx=tgt?(tgt.x-wx)/Math.max(tgt.d,1):0, vy=tgt?(tgt.y-wy)/Math.max(tgt.d,1):0;
   if(policy==='human'){const c=Math.cos(noise),sn=Math.sin(noise); [vx,vy]=[vx*c-vy*sn,vx*sn+vy*c];}
   const R=policy==='human'?38:55, G=policy==='human'?2.2:4.4;
   for(const bt of v.bats){const dx=wx-bt[0],dy=wy-bt[1],d=Math.hypot(dx,dy); if(d<R){vx+=dx/d*G*(R-d)/R; vy+=dy/d*G*(R-d)/R;}}
   const want=[]; if(vy<-0.3)want.push(0); if(vy>0.3)want.push(1); if(vx<-0.3)want.push(2); if(vx>0.3)want.push(3);
   const press=new Set();
   for(const d of want){ if(policy==='naive'){press.add(d);} else { const k=(policy==='human'?belief:st.map).indexOf(d); if(k>=0) press.add(k);} }
   for(const k of [...held]) if(!press.has(k)){await p.keyboard.up(KN[k]);held.delete(k);}
   for(const k of press) if(!held.has(k)){await p.keyboard.down(KN[k]);held.add(k);}
   await p.waitForTimeout(40);
  }
  res.push({candy:st.candy,hearts:st.hearts,survived:+st.t.toFixed(1),dawn:st.t>=119,hz:+(polls/st.t).toFixed(1)});
  await p.close();
 }
 console.log(policy, JSON.stringify(res)); await b.close();
})();
