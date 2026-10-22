'use strict';
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let state={seats:[],people:[],messages:[]};
const send=(action,extra={})=>window.SoveraRoom?.postMessage(JSON.stringify({action,...extra}));
function close(){$('bg').classList.remove('on');giftOpen=false;}
function sheet(html){giftOpen=false;$('sheet').innerHTML='<div class="grab"></div>'+html;$('bg').classList.add('on');}
function button(label,action,extra={}){const b=document.createElement('button');b.className='act';b.textContent=label;b.onclick=()=>{close();send(action,extra);};return b;}
function seatMenu(i){
 const seat=state.seats[i];if(!seat)return;
 sheet('<h3>'+esc(seat.name||'সিট '+(i+1))+'</h3><div class="acts" id="seatActions"></div>');
 const a=$('seatActions');
 if(seat.uid)a.append(button('👤 প্রোফাইল','profile',{uid:seat.uid}));
 if(!seat.uid&&!seat.locked)a.append(button('🎤 সিটে বসুন','take',{seat:i}));
 if(seat.uid===state.uid){a.append(button(state.muted?'🎤 আনমিউট':'🔇 মিউট','mic'));a.append(button('⬇️ সিট ছাড়ুন','leaveSeat'));}

 if(seat.uid){const gift=button('🎁 উপহার','gifts');gift.onclick=()=>openGifts(seat.uid);a.append(gift);}
 if(state.role==='owner'||state.role==='admin'){
  if(!seat.uid&&!seat.locked){const invite=button('🎤 মাইকে আমন্ত্রণ','invite');invite.onclick=()=>inviteSheet(i);a.append(invite);}
  const lock=button(seat.locked?'🔓 সিট আনলক':'🔒 সিট লক','seatLock',{seat:i,locked:!seat.locked});a.append(lock);
  if(seat.uid&&seat.uid!==state.uid){
   const muted=(state.mutedUids||[]).includes(seat.uid);
   a.append(button(muted?'🔊 মিউট তুলে নিন':'🔇 মিউট', 'moderate',{kind:muted?'unmute':'mute',uid:seat.uid}),
    button('⬇️ মাইক থেকে নামান','moderate',{kind:'down',uid:seat.uid}),button('🚫 রুম থেকে বের করুন','moderate',{kind:'kick',uid:seat.uid}));
  }
 }
}
function inviteSheet(seat){
 sheet('<h3>🎤 মাইকে আমন্ত্রণ</h3><div class="acts" id="invitePeople"></div>');
 for(const p of state.people||[])if(p.uid!==state.uid&&!state.seats.some(s=>s.uid===p.uid))$('invitePeople').append(button(p.name||'রুম সদস্য','invite',{uid:p.uid,seat}));
}
function seatHTML(s,i,host){
 const locked=s.locked&&!s.uid,empty=!s.uid&&!locked;
 const asset=s.equipped?.frame;
 const frame=asset&&safeMedia(asset.url);
 const scale=Math.min(1,Math.max(.05,Number(asset?.avatar_scale)||.46));
 const canvas=frame?Math.min(2.4,.76/scale):1,faceSize=frame?canvas*scale:1;
 const x=Math.min(1-scale/2,Math.max(scale/2,Number(asset?.avatar_x)||.5)),y=Math.min(1-scale/2,Math.max(scale/2,Number(asset?.avatar_y)||.5));
 const faceStyle=frame?'style="inset:auto;width:'+(faceSize*100)+'%;height:'+(faceSize*100)+'%;left:'+((1-faceSize)*50)+'%;top:'+((1-faceSize)*50)+'%"':'';
 const frameHTML=frame?'<img class="equipped-frame" style="width:'+(canvas*100)+'%;height:'+(canvas*100)+'%;left:'+((.5-canvas*x)*100)+'%;top:'+((.5-canvas*y)*100)+'%" alt="" src="'+esc(frame)+'">':'';
 const url=typeof s.avatar==='string'&&s.avatar.startsWith('https://')?s.avatar:null;
 return '<button class="seat '+(locked?'lock':empty?'empty':s.speaking?'talk':'')+'" data-i="'+i+'"><div class="av"><div class="ring"></div><div class="face" '+faceStyle+'>'+(url?'<img alt="" style="width:100%;height:100%;object-fit:cover;border-radius:50%" src="'+esc(url)+'">':locked?'🔒':empty?'＋':'👤')+'</div>'+frameHTML+'<i class="wave"></i><i class="wave b"></i>'+(host?'<div class="crown">👑</div>':'')+((s.uid===state.uid&&state.muted)||(state.mutedUids||[]).includes(s.uid)?'<div class="badge">🔇</div>':'')+'</div><div class="nm">'+esc(s.name||(locked?'লক':'খালি'))+'</div>'+(host?'<div class="tag">হোস্ট সিট</div>':'')+'</button>';
}
window.SoveraLive={update(next){
 state=next;
 $('app').dataset.frame=state.seatStyle||'grad';
 $('rname').textContent=state.name||'';
 const themes={mid:['#171040','#0a0820','#8b5cf6','#ec4899'],gold:['#2e1f06','#0d0803','#f59e0b','#ef4444'],ocean:['#06284a','#030f20','#06b6d4','#3b82f6'],rose:['#3b0a2a','#14040f','#f43f5e','#f472b6'],forest:['#08301f','#03130c','#10b981','#84cc16'],sunset:['#3a1448','#150820','#fb923c','#e879f9']};
 const colors=themes[state.theme]||themes.mid;
 ['--bg1','--bg2','--a','--b'].forEach((k,i)=>$('app').style.setProperty(k,colors[i]));
 const background=typeof state.backgroundUrl==='string'&&state.backgroundUrl.startsWith('https://voice.soverixnet.com/sovera/account/room-photo/')?state.backgroundUrl:null;
 $('app').style.backgroundImage=background?'linear-gradient(rgba(5,3,20,.4),rgba(5,3,20,.82)),url('+JSON.stringify(background)+')':'';
 $('app').style.backgroundSize='cover';
 $('txt').disabled=state.chatEnabled===false;
 $('imgBtn').classList.toggle('locked',state.chatEnabled===false);
 const picture=typeof state.imageUrl==='string'&&state.imageUrl.startsWith('https://')?state.imageUrl:null;
 $('rav').replaceChildren();
 if(picture){const img=document.createElement('img');img.src=picture;img.alt='';img.style.cssText='width:100%;height:100%;object-fit:cover;border-radius:13px';$('rav').append(img);}else $('rav').textContent='🎙️';
 $('roomBtn').querySelector('small').textContent='লাইভ ভয়েস রুম';
 $('livePeople').textContent=String(state.people.length);
 $('liveWins').textContent=state.dailyWins??'—';
 $('mstat').textContent='🎤 '+state.seats.filter(s=>s.uid).length+'/'+state.seats.length;
 $('cstat').textContent='🪙 '+(state.coins??'—');
 $('cstat').onclick=()=>send('wallet');
 $('liveWins').parentElement.onclick=()=>send('ranking');
 $('lstat').textContent=state.connected?'সংযুক্ত':'সংযোগ হচ্ছে…';
 $('bOwn').style.display=state.role==='owner'||state.role==='admin'?'grid':'none';
 $('host').innerHTML=state.seats.length?seatHTML(state.seats[0],0,true):'';
 $('grid').className='grid'+(state.seats.length>13?' dense':'');
 $('grid').style.gridTemplateColumns='repeat('+(state.seats.length>17?5:4)+',1fr)';
 $('grid').innerHTML=state.seats.slice(1).map((s,i)=>seatHTML(s,i+1,false)).join('');
 document.querySelectorAll('.seat').forEach(b=>b.onclick=()=>seatMenu(Number(b.dataset.i)));
 $('mic').classList.toggle('off',state.muted);$('mic').textContent=state.muted?'🔇':'🎤';
 $('mic').setAttribute('aria-label',state.muted?'Unmute':'Mute');
 const signature=JSON.stringify(state.messages);
 if($('chat').dataset.signature!==signature){
  $('chat').dataset.signature=signature;$('chat').replaceChildren();
  for(const m of state.messages){const row=document.createElement('div');row.className='msg'+(m.uid===state.uid?' me':'');row.innerHTML='<div class="mav">👤</div><div class="mb"><span class="mn">'+esc(m.name)+'</span><span class="mt">'+esc(m.text)+'</span></div>';if(typeof m.image_url==='string'&&m.image_url.startsWith('https://voice.soverixnet.com/sovera/account/chat-photo/')){const image=document.createElement('img');image.src=m.image_url;image.className='mimg';image.alt='Room photo';image.onclick=e=>{e.stopPropagation();$('vimg').src=m.image_url;$('viewer').classList.add('on');};row.append(image);}row.onclick=()=>send('profile',{uid:m.uid});$('chat').append(row);}
  $('chat').scrollTop=$('chat').scrollHeight;
  if(state.sendPending===false&&state.messages.some(m=>m.uid===state.uid&&m.text===$('txt').value.trim())){$('txt').value='';$('txt').oninput();}
 }
 for(const invitation of state.invites||[]){
  const key='invite:'+invitation.id;
  if(!seenEffects.has(key)){seenEffects.add(key);sheet('<h3>🎤 মাইকে কথা বলার আমন্ত্রণ</h3><div class="acts" id="acceptInvite"></div>');$('acceptInvite').append(button('সিটে বসুন','take',{seat:invitation.seat}));}
 }
 for(const reaction of state.reactions||[]){
  const key='reaction:'+reaction.id;
  if(!seenEffects.has(key)){seenEffects.add(key);const index=state.seats.findIndex(s=>s.uid===reaction.uid);if(index>=0)seatEmoji(index,reaction.emoji);}
 }
 for(const event of state.events||[]){
  const key='gift:'+event.event_id;
  if(event.asset?.kind==='gift'&&!seenEffects.has(key)){seenEffects.add(key);flyGift(event);}
 }
 if(seenEffects.size>1000){const keep=[...seenEffects].slice(-500);seenEffects.clear();keep.forEach(k=>seenEffects.add(k));}
 if(giftOpen&&JSON.stringify([state.gifts,state.coins,state.giftLoading,state.giftPending,state.giftSending])!==giftSignature)renderGifts();
 $('toast').textContent=state.error||'';$('toast').style.display=state.error?'block':'none';
}};
$('bg').onclick=e=>{if(e.target===$('bg'))close();};
$('min').onclick=()=>send('minimize');$('exit').onclick=()=>{sheet('<h3>রুম থেকে বের হবেন?</h3><div class="acts" id="exitActions"></div>');$('exitActions').append(button('🚪 বের হন','leave'));};
$('mic').onclick=()=>send('mic');$('bGift').onclick=()=>openGifts();$('bMsg').onclick=()=>send('messages');$('bGame').onclick=()=>send('games');$('roomBtn').onclick=roomSettings;
$('bOwn').onclick=()=>ownerSheet();
function sendText(){const text=$('txt').value.trim();if(text)send('send',{text});}
$('sendTxt').onclick=sendText;$('txt').onkeydown=e=>{if(e.key==='Enter')sendText();};
$('txt').oninput=()=>{$('sendTxt').style.display=$('txt').value.trim()?'grid':'none';};
$('emo').onclick=()=>emojiSheet();
$('imgBtn').onclick=()=>send('photo');
if(window.visualViewport)visualViewport.addEventListener('resize',()=>{$('app').style.height=visualViewport.height+'px';});

function roomSettings(){
 if(state.role!=='owner'){sheet('<h3>'+esc(state.name)+'</h3><p>রুমের সেটিংস শুধু মালিক পরিবর্তন করতে পারেন।</p>');return;}
 sheet('<h3>⚙️ রুম সেটিংস</h3><div class="pic"><button class="act" id="changeCover">📷 রুমের ছবি</button><button class="act" id="changeBackground">🖼️ ব্যাকগ্রাউন্ড</button></div><label class="lbl">রুমের নাম</label><input class="field" id="editName" maxlength="40"><label class="lbl">সিট</label><select class="field" id="editSeats">'+[5,6,9,12,15].map(n=>'<option value="'+n+'">'+n+'</option>').join('')+'</select><label class="lbl">🎨 থিম</label><select class="field" id="editTheme">'+[['mid','মিডনাইট'],['gold','রয়্যাল গোল্ড'],['ocean','ওশান'],['rose','রোজ'],['forest','ফরেস্ট'],['sunset','সানসেট']].map(t=>'<option value="'+t[0]+'">'+t[1]+'</option>').join('')+'</select><label class="lbl"><input type="checkbox" id="editChat"> টেক্সট চ্যাট চালু</label><label class="lbl">ছবি পাঠাতে ন্যূনতম Wealth Level</label><input class="field" type="number" min="0" max="10000" id="editPhotoLevel"><div class="gbar"><button class="send" id="saveRoom">সংরক্ষণ করুন</button></div>');
 $('editName').value=state.name;$('editSeats').value=String(state.seats.length);$('editTheme').value=state.theme||'mid';$('editChat').checked=state.chatEnabled!==false;$('editPhotoLevel').value=String(state.photoLevel||0);
 $('changeCover').onclick=()=>send('roomPhoto');$('changeBackground').onclick=()=>send('roomBackground');
 $('saveRoom').onclick=()=>{send('saveSettings',{name:$('editName').value.trim(),seats:Number($('editSeats').value),theme:$('editTheme').value,chatEnabled:$('editChat').checked,photoLevel:Number($('editPhotoLevel').value)});close();};
}
function adminSheet(){
 if(state.role!=='owner')return;
 sheet('<h3>🛡️ রুম অ্যাডমিন</h3><div id="adminPeople"></div>');
 const people=new Map([...(state.people||[]),...(state.admins||[])].map(p=>[p.uid,p]));
 for(const [uid,p] of people){if(uid===state.uid)continue;const enabled=(state.admins||[]).some(a=>a.uid===uid);const b=button((enabled?'➖ ':'➕ ')+(p.name||uid),'setAdmin',{uid,enabled:!enabled});$('adminPeople').append(b);}
}
$('viewer').onclick=()=>$('viewer').classList.remove('on');

const seenEffects=new Set();
let giftOpen=false,giftSignature='',giftId=null,giftQuantity=1,giftRecipients=new Set(),emojiTab=0,settingsDraft=null;
function safeMedia(url){return typeof url==='string'&&/^https:\/\/voice\.soverixnet\.com\/sovera\/account\/media\/[a-f0-9]+$/.test(url)?url:null;}
function toast(text){$('toast').textContent=text;$('toast').style.display='block';}
function openGifts(uid){
 giftRecipients=new Set(uid?[uid]:[]);giftOpen=true;renderGifts();send('gifts');
}
function renderGifts(){
 const pending=state.giftPending;
 if(pending){giftId=pending.item_id;giftQuantity=pending.quantity||1;giftRecipients=new Set(pending.recipient_uids);}
 const gifts=state.gifts||[],people=state.people||[];
 if(!giftId&&gifts.length)giftId=gifts[0].id;
 const selected=gifts.find(g=>g.id===giftId),all=people.length>0&&people.every(p=>giftRecipients.has(p.uid));
 const locked=!!pending||!!state.giftSending;
 const artwork=g=>safeMedia(g.url)?'<img alt="" src="'+esc(g.url)+'" style="width:54px;height:54px;object-fit:contain">':'🎁';
 sheet('<h3>🎁 উপহার পাঠান <span style="margin-left:auto;font-size:12px;color:var(--gold)">🪙 '+esc(state.coins??'—')+'</span></h3><div class="lbl">কাকে পাঠাবেন</div><div class="chips">'+
 '<button class="chip '+(all?'sel':'')+'" id="giftAll"><div class="c">👥</div>সবাই</button>'+people.map(p=>'<button class="chip '+(giftRecipients.has(p.uid)?'sel':'')+'" data-recipient="'+esc(p.uid)+'"><div class="c">'+(p.avatar_url?'<img alt="" src="'+esc(p.avatar_url)+'" style="width:100%;height:100%;border-radius:50%;object-fit:cover">':'👤')+'</div>'+esc(p.name)+'</button>').join('')+
 '</div><div class="gifts">'+gifts.map(g=>'<button class="gf '+(g.id===giftId?'sel':'')+'" data-gift="'+esc(g.id)+'"><span>'+artwork(g)+'</span>'+esc(g.title)+'<small>🪙 '+esc(g.price)+'</small></button>').join('')+'</div>'+
 (!gifts.length?'<p>'+(state.giftLoading?'গিফট লোড হচ্ছে…':'কোনো প্রকাশিত গিফট নেই। অ্যাডমিন ক্যাটালগ থেকে যোগ করুন।')+'</p>':'')+
 '<div class="gbar"><div class="qty">'+[1,5,10].map(q=>'<button data-quantity="'+q+'" class="'+(q===giftQuantity?'sel':'')+'">×'+q+'</button>').join('')+'</div><button class="send" id="sendGift">'+(state.giftSending?'পাঠানো হচ্ছে…':pending?'একই গিফট আবার চেষ্টা করুন':'পাঠান 🚀')+'</button></div><div class="lbl">মোট: '+(selected?String(BigInt(selected.price)*BigInt(giftQuantity)*BigInt(giftRecipients.size)):'—')+' Coins</div>');
 giftOpen=true;giftSignature=JSON.stringify([state.gifts,state.coins,state.giftLoading,state.giftPending,state.giftSending]);
 $('giftAll').onclick=()=>{if(locked)return;giftRecipients=all?new Set():new Set(people.map(p=>p.uid));renderGifts();};
 document.querySelectorAll('[data-recipient]').forEach(b=>b.onclick=()=>{if(locked)return;const uid=b.dataset.recipient;if(giftRecipients.has(uid))giftRecipients.delete(uid);else giftRecipients.add(uid);renderGifts();});
 document.querySelectorAll('[data-gift]').forEach(b=>b.onclick=()=>{if(!locked){giftId=b.dataset.gift;renderGifts();}});
 document.querySelectorAll('[data-quantity]').forEach(b=>b.onclick=()=>{if(!locked){giftQuantity=Number(b.dataset.quantity);renderGifts();}});
 $('sendGift').disabled=state.giftSending||!selected||!giftRecipients.size||state.coins==null;
 $('sendGift').onclick=()=>{
  if(!selected||!giftRecipients.size)return;
  const cost=BigInt(selected.price)*BigInt(giftQuantity)*BigInt(giftRecipients.size);
  if(state.coins==null||BigInt(state.coins)<cost){toast('কয়েন যথেষ্ট নয়');return;}
  send('sendGift',{itemId:giftId,recipients:[...giftRecipients],quantity:giftQuantity,price:selected.price});
 };
}
const ER=[['😂','হাসি'],['😍','ভালোবাসা'],['😎','কুল'],['🔥','আগুন'],['👏','হাততালি'],['🎉','পার্টি'],['😭','কান্না'],['😡','রাগ'],['🥳','উৎসব'],['😘','চুমু'],['🤩','বাহ!'],['👍','দারুণ'],['🙏','ধন্যবাদ'],['💯','১০০'],['😴','ঘুম'],['💖','হৃদয়']];
function emojiSheet(){
 sheet('<h3>😊 ইমোজি বক্স</h3><div class="etabs"><button id="seatEmojiTab" class="'+(!emojiTab?'sel':'')+'">🎭 সিটে দেখান</button><button id="textEmojiTab" class="'+(emojiTab?'sel':'')+'">💬 মেসেজে</button></div><div class="lbl">'+(!emojiTab?'আপনার সিটে অ্যানিমেশনসহ দেখাবে':'মেসেজ বক্সে বসবে')+'</div><div class="gifts em">'+ER.map((e,i)=>'<button class="gf" data-emoji="'+i+'"><span>'+e[0]+'</span>'+e[1]+'</button>').join('')+'</div>');
 $('seatEmojiTab').onclick=()=>{emojiTab=0;emojiSheet();};$('textEmojiTab').onclick=()=>{emojiTab=1;emojiSheet();};
 document.querySelectorAll('[data-emoji]').forEach(b=>b.onclick=()=>{
  const e=ER[Number(b.dataset.emoji)][0];
  if(emojiTab){if(state.chatEnabled===false){toast('চ্যাট বন্ধ আছে');return;}$('txt').value+=e;$('txt').oninput();close();$('txt').focus();}
  else{if(!state.seats.some(s=>s.uid===state.uid)){toast('আগে একটি সিটে বসুন');return;}send('reaction',{emoji:e});close();}
 });
}
function seatElement(i){return document.querySelector('.seat[data-i="'+i+'"]');}
function seatEmoji(index,emoji){
 const seat=seatElement(index);if(!seat)return;
 const r=seat.querySelector('.face').getBoundingClientRect(),a=$('app').getBoundingClientRect(),el=document.createElement('div');
 el.className='g';el.textContent=emoji;el.style.fontSize='54px';$('fx').append(el);
 const x=r.left+r.width/2-a.left,y=r.top+r.height/2-a.top,T='translate('+x+'px,'+y+'px) translate(-50%,-50%) ';
 el.animate([{transform:T+'scale(.3)',opacity:0},{transform:T+'scale(1.2)',opacity:1,offset:.2},{transform:T+'rotate(-12deg)',opacity:1,offset:.55},{transform:T+'translateY(-28px) scale(.7)',opacity:0}],{duration:2600,fill:'both'}).onfinish=()=>el.remove();
}
function flyGift(event){
 const i=state.seats.findIndex(s=>s.uid===event.recipient_uid),target=i>=0?seatElement(i):null,src=safeMedia(event.asset?.url);
 if(!src)return;
 const a=$('app').getBoundingClientRect(),b=$('bGift').getBoundingClientRect(),t=target?.querySelector('.face')?.getBoundingClientRect();
 const endX=t?t.left+t.width/2-a.left:a.width/2,endY=t?t.top+t.height/2-a.top:a.height*.45;
 const image=document.createElement('img');image.src=src;image.alt='';image.className='gift-flight';$('fx').append(image);
 image.animate([{transform:'translate('+(b.left-a.left)+'px,'+(b.top-a.top)+'px) scale(.35)',opacity:0},{opacity:1,offset:.15},{transform:'translate('+(endX-42)+'px,'+(endY-42)+'px) scale(1.3)',opacity:1,offset:.75},{transform:'translate('+(endX-42)+'px,'+(endY-55)+'px) scale(.8)',opacity:0}],{duration:2200,fill:'both'}).onfinish=()=>image.remove();
}
function saveDraft(){if(state.role!=='owner')return;send('saveSettings',settingsDraft);close();}
function roomSettings(){
 if(state.role!=='owner'){sheet('<h3>'+esc(state.name)+'</h3><p>রুমের সেটিংস শুধু মালিক পরিবর্তন করতে পারেন।</p>');return;}
 settingsDraft={name:state.name,seats:state.seats.length,theme:state.theme||'mid',chatEnabled:state.chatEnabled!==false,photoLevel:state.photoLevel||0,seatStyle:state.seatStyle||'grad'};
 settingsSheet();
}
function settingsSheet(){
 sheet('<h3>⚙️ রুম সেটিংস</h3><div class="pic"><button class="act" id="changeCover">📷 রুমের ছবি</button><div style="flex:1"><div class="lbl">রুমের নাম</div><input class="field" id="editName" maxlength="40"></div></div><div class="row" id="themeSettings"><div>🎨 রুমের থিম<small>রঙ ও ব্যাকগ্রাউন্ড ছবি</small></div><span>›</span></div><div class="row" id="seatSettings"><div>🪑 সিট ব্যবস্থা<small>সিট সংখ্যা ও ফ্রেম স্টাইল</small></div><span>›</span></div><div class="gbar"><button class="send" id="saveRoom">সংরক্ষণ করুন</button></div>');
 $('editName').value=settingsDraft.name;$('editName').oninput=()=>settingsDraft.name=$('editName').value;
 $('changeCover').onclick=()=>send('roomPhoto');$('themeSettings').onclick=themeSheet;$('seatSettings').onclick=seatSettings;$('saveRoom').onclick=saveDraft;
}
function themeSheet(){
 const themes=[['mid','মিডনাইট','#6d28d9'],['gold','রয়্যাল গোল্ড','#b45309'],['ocean','ওশান','#0369a1'],['rose','রোজ','#be185d'],['forest','ফরেস্ট','#15803d'],['sunset','সানসেট','#ea580c']];
 sheet('<h3><button class="back" id="themeBack">‹</button>🎨 রুমের থিম</h3><div class="themes">'+themes.map(t=>'<button class="th '+(settingsDraft.theme===t[0]?'sel':'')+'" data-theme="'+t[0]+'" style="background:linear-gradient(160deg,'+t[2]+',#100a20)">'+t[1]+'</button>').join('')+'</div><button class="act" id="changeBackground">🖼️ গ্যালারি থেকে ব্যাকগ্রাউন্ড</button><button class="act" id="clearBackground">ছবি সরিয়ে থিমে ফিরুন</button><button class="send" id="saveTheme">সংরক্ষণ করুন</button>');
 $('themeBack').onclick=settingsSheet;document.querySelectorAll('[data-theme]').forEach(b=>b.onclick=()=>{settingsDraft.theme=b.dataset.theme;settingsDraft.clearBackground=true;themeSheet();});
 $('changeBackground').onclick=()=>send('roomBackground');$('clearBackground').onclick=()=>{settingsDraft.clearBackground=true;toast('সংরক্ষণ করলে ব্যাকগ্রাউন্ড সরবে');};$('saveTheme').onclick=saveDraft;
}
function seatSettings(){
 sheet('<h3><button class="back" id="seatBack">‹</button>🪑 সিট ব্যবস্থা</h3><div class="lbl">মোট সিট (হোস্টসহ)</div><div class="step"><button id="minusSeat">−</button><b>'+settingsDraft.seats+'</b><button id="plusSeat">+</button></div><div class="lbl">কমপক্ষে ৫টি, সর্বোচ্চ ২১টি</div><div class="fr">'+[['grad','রঙিন'],['gold','গোল্ড'],['neon','নিয়ন'],['sq','চৌকো']].map(f=>'<button data-style="'+f[0]+'" class="'+(settingsDraft.seatStyle===f[0]?'sel':'')+'"><div class="pv"></div>'+f[1]+'</button>').join('')+'</div><button class="send" id="saveSeats">সংরক্ষণ করুন</button>');
 $('seatBack').onclick=settingsSheet;$('minusSeat').onclick=()=>{settingsDraft.seats=Math.max(5,settingsDraft.seats-1);seatSettings();};$('plusSeat').onclick=()=>{settingsDraft.seats=Math.min(21,settingsDraft.seats+1);seatSettings();};
 document.querySelectorAll('[data-style]').forEach(b=>b.onclick=()=>{settingsDraft.seatStyle=b.dataset.style;seatSettings();});$('saveSeats').onclick=saveDraft;
}
function ownerSheet(){
 if(!['owner','admin'].includes(state.role))return;
 sheet('<h3>👑 মালিক ম্যানেজমেন্ট</h3><div class="row"><div>সবাইকে মিউট</div><button class="act" id="muteAll">🔇</button><button class="act" id="unmuteAll">🔊</button></div><div id="ownerRows"></div><div class="acts" id="ownerActions"></div>');
 $('muteAll').onclick=()=>send('moderate',{kind:'mute_all'});$('unmuteAll').onclick=()=>send('moderate',{kind:'unmute_all'});
 $('ownerActions').append(button('🔒 খালি সিট লক','lockAll',{locked:true}),button('🔓 সিট আনলক','lockAll',{locked:false}));
 const banned=button('🚫 ব্লক লিস্ট','banned');banned.onclick=bannedSheet;$('ownerActions').append(banned);
 if(state.role==='owner'){
  const settings=button('⚙️ রুম সেটিংস','settings');settings.onclick=roomSettings;
  const admins=button('🛡️ অ্যাডমিন','admins');admins.onclick=adminSheet;
  $('ownerActions').append(settings,admins);
  const row=document.createElement('div');row.className='row';row.innerHTML='<label>টেক্সট চ্যাট চালু <input type="checkbox" id="ownerChat"></label><label>ছবি পাঠাতে ন্যূনতম লেভেল<input class="field" type="number" id="ownerLevel" min="0" max="10000"></label><button class="send" id="ownerSave">সংরক্ষণ করুন</button>';$('ownerRows').append(row);
  $('ownerChat').checked=state.chatEnabled!==false;$('ownerLevel').value=state.photoLevel||0;
  $('ownerSave').onclick=()=>{send('saveSettings',{name:state.name,seats:state.seats.length,theme:state.theme||'mid',seatStyle:state.seatStyle||'grad',chatEnabled:$('ownerChat').checked,photoLevel:Number($('ownerLevel').value)});close();};
 }
}
function bannedSheet(){sheet('<h3>🚫 রুমের ব্লক লিস্ট</h3><div class="acts" id="blockedPeople"></div>');for(const p of state.banned||[])$('blockedPeople').append(button('আনব্লক · '+p.name,'moderate',{kind:'unban',uid:p.uid}));}
