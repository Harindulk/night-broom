// policy: "aware" uses the on-screen key map, "naive" assumes default arrows
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
  const held=new Set(); let st; const shots=(process.env.SHOTS||'').split(',').filter(Boolean).map(Number); const out=process.env.OUT||'.';

  for(;;){
   st=await p.evaluate(()=>window.nb);
   while(shots.length&&st.t>=shots[0]){await p.screenshot({path:`${out}/t${shots.shift()}.png`});}
   if(st.state===2){ if(process.env.OUT){await p.waitForTimeout(1200); await p.screenshot({path:out+'/end.png'});} break;}
   const [wx,wy]=st.w; const haunted=st.map.some((d,k)=>d!==k);
   let tgt=null;
   const pool=(haunted&&st.pumpkins.length)?st.pumpkins:st.candies;
   for(const c of pool){const d=Math.hypot(c[0]-wx,c[1]-wy); if(!tgt||d<tgt.d) tgt={x:c[0],y:c[1],d};}
   let vx=tgt?(tgt.x-wx)/Math.max(tgt.d,1):0, vy=tgt?(tgt.y-wy)/Math.max(tgt.d,1):0;
   for(const bt of st.bats){const dx=wx-bt[0],dy=wy-bt[1],d=Math.hypot(dx,dy); if(d<55){vx+=dx/d*2.2*(55-d)/55*2; vy+=dy/d*2.2*(55-d)/55*2;}}
   const want=[]; if(vy<-0.3)want.push(0); if(vy>0.3)want.push(1); if(vx<-0.3)want.push(2); if(vx>0.3)want.push(3);
   const press=new Set();
   for(const d of want){ if(policy==='naive'){press.add(d);} else { const k=st.map.indexOf(d); if(k>=0) press.add(k);} }
   for(const k of [...held]) if(!press.has(k)){await p.keyboard.up(KN[k]);held.delete(k);}
   for(const k of press) if(!held.has(k)){await p.keyboard.down(KN[k]);held.add(k);}
   await p.waitForTimeout(40);
  }
  res.push({candy:st.candy,hearts:st.hearts,survived:+st.t.toFixed(1),dawn:st.t>=119});
  await p.close();
 }
 console.log(policy, JSON.stringify(res)); await b.close();
})();
