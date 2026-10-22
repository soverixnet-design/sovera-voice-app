
const {chromium}=require('playwright');
const {resolve}=require('node:path');
const assert=require('node:assert/strict');
const {mkdirSync}=require('node:fs');
(async()=>{
 const browser=await chromium.launch({headless:true});
 try{
  for(const [width,height] of [[320,640],[360,740],[390,844],[440,950],[520,1050],[844,390]]){
   const page=await browser.newPage({viewport:{width,height}});
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(()=>{window.sent=[];window.SoveraRoom={postMessage:x=>window.sent.push(JSON.parse(x))};});
   await page.goto('file://'+resolve('assets/room-design/interior.html'));
   const snapshot={uid:'alice',name:'Real room',imageUrl:'https://voice.soverixnet.com/sovera/account/room-photo/portrait',roomId:'long-private-uuid',people:[{uid:'alice',name:'Alice'},{uid:'bob',name:'Bob'}],seats:Array.from({length:21},(_,i)=>i===0?{uid:'alice',name:'Alice',speaking:true,equipped:{frame:{url:'https://voice.soverixnet.com/sovera/account/media/abcdef',avatar_scale:.46,avatar_x:.5,avatar_y:.5}}}:{uid:i===1?'bob':null,name:i===1?'Bob':null}),messages:[],coins:'1000',dailyWins:'50',role:'owner',connected:true,muted:false,gifts:[{id:'gift',title:'Rose',price:5}],reactions:[],events:[]};
   await page.evaluate(x=>window.SoveraLive.update(x),snapshot);
   const cover=await page.locator('#rav').boundingBox(),coverImage=await page.locator('#rav img').boundingBox();
   assert.equal(Math.round(cover.width),38);assert.equal(Math.round(cover.height),38);
   assert.equal(Math.round(coverImage.width),38);assert.equal(Math.round(coverImage.height),38);
   const geometry=await page.locator('.seat[data-i="0"]').evaluate(el=>{
    const av=el.querySelector('.av').getBoundingClientRect(),face=el.querySelector('.face').getBoundingClientRect(),frame=el.querySelector('.equipped-frame').getBoundingClientRect();
    return {av:av.width,face:face.width,frame:frame.width,faceX:face.x+face.width/2,frameX:frame.x+frame.width/2};
   });
   assert(geometry.frame>geometry.av*1.5);assert(geometry.face>=geometry.av*.7);assert(Math.abs(geometry.faceX-geometry.frameX)<1);
   await page.evaluate(()=>{window.effectAnimations=[];const original=Element.prototype.animate;Element.prototype.animate=function(frames,options){if(this.classList.contains('g')||this.classList.contains('gift-flight'))window.effectAnimations.push(frames);return original.call(this,frames,options);};});
   const center=await page.locator('.seat[data-i="0"] .face').evaluate(el=>{const r=el.getBoundingClientRect(),a=document.getElementById('app').getBoundingClientRect();return {x:r.left+r.width/2-a.left,y:r.top+r.height/2-a.top};});
   await page.evaluate(x=>window.SoveraLive.update({...x,reactions:[{id:100,uid:'alice',emoji:'😂'}],events:[{event_id:'test',recipient_uid:'alice',asset:{kind:'gift',url:'https://voice.soverixnet.com/sovera/account/media/abcdef'}}]}),snapshot);
   const effects=await page.evaluate(()=>window.effectAnimations);
   assert(effects[0][0].transform.startsWith('translate('+center.x+'px,'+center.y+'px)'));
   assert(effects[1][2].transform.startsWith('translate('+(center.x-42)+'px,'+(center.y-42)+'px)'));
   const box=await page.locator('#app').boundingBox();assert.equal(Math.round(box.width),width);assert.equal(Math.round(box.height),height);
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
   await page.locator('#bGift').click();await page.locator('#giftAll').click();await page.locator('[data-quantity="10"]').click();
   await page.locator('#sendGift').click();
   const gift=await page.evaluate(()=>window.sent.find(x=>x.action==='sendGift'));assert.equal(gift.quantity,10);assert.equal(gift.recipients.length,2);
   assert.equal(await page.locator('#cstat').innerText(),'🪙 1000');
   await page.evaluate(()=>document.getElementById('bg').classList.remove('on'));
   await page.locator('#emo').click();await page.locator('[data-emoji="0"]').click();
   assert.equal(await page.evaluate(()=>window.sent.at(-1).action),'reaction');
   assert.equal(await page.locator('.seat.talk').count(),1);
   assert.equal(await page.locator('#roomBtn small').innerText(),'লাইভ ভয়েস রুম');
   await page.locator('#bOwn').click();await page.locator('#muteAll').click();
   assert.equal(await page.evaluate(()=>window.sent.at(-1).kind),'mute_all');
   await page.locator('#roomBtn').click();await page.locator('#themeSettings').click();
   await page.locator('[data-theme="ocean"]').click();await page.locator('#changeBackground').click();
   assert.equal(await page.evaluate(()=>window.sent.at(-1).action),'roomBackground');
   assert.equal(await page.locator('#bg').evaluate(el=>el.classList.contains('on')),false);
   assert.deepEqual(errors,[]);
   await page.close();
  }
  mkdirSync('build/room-design/source-gifts',{recursive:true});
  const icons=[['rose','🌹'],['ring','💍'],['car','🚗'],['castle','🏰'],['lion','🦁'],['dragon','🐉'],['rocket','🚀'],['crown','👑']];
  const iconPage=await browser.newPage({viewport:{width:256,height:256},deviceScaleFactor:1});
  for(const [name,emoji] of icons){
   await iconPage.setContent('<html><body style="margin:0;background:transparent"><div style="width:256px;height:256px;display:grid;place-items:center;font:180px Noto Color Emoji,Apple Color Emoji,Segoe UI Emoji,sans-serif">'+emoji+'</div></body></html>');
   await iconPage.screenshot({path:'build/room-design/source-gifts/'+name+'.png',omitBackground:true});
  }
  await iconPage.close();
 }finally{await browser.close();}
 console.log('ROOM_VIEWPORT_AND_ACTIONS_OK');
})().catch(e=>{console.error(e);process.exit(1)});
