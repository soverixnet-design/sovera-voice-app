
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
   const snapshot={uid:'alice',name:'Real room',roomId:'long-private-uuid',people:[{uid:'alice',name:'Alice'},{uid:'bob',name:'Bob'}],seats:Array.from({length:21},(_,i)=>i===0?{uid:'alice',name:'Alice',speaking:true}:{uid:i===1?'bob':null,name:i===1?'Bob':null}),messages:[],coins:'1000',dailyWins:'50',role:'owner',connected:true,muted:false,gifts:[{id:'gift',title:'Rose',price:5}],reactions:[],events:[]};
   await page.evaluate(x=>window.SoveraLive.update(x),snapshot);
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
