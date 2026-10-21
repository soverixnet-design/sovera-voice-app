'use strict';
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let state={seats:[],people:[],messages:[]};
const send=(action,extra={})=>window.SoveraRoom?.postMessage(JSON.stringify({action,...extra}));
function close(){$('bg').classList.remove('on');}
function sheet(html){$('sheet').innerHTML='<div class="grab"></div>'+html;$('bg').classList.add('on');}
function button(label,action,extra={}){const b=document.createElement('button');b.className='act';b.textContent=label;b.onclick=()=>{close();send(action,extra);};return b;}
function seatMenu(i){
 const seat=state.seats[i];if(!seat)return;
 sheet('<h3>'+esc(seat.name||'সিট '+(i+1))+'</h3><div class="acts" id="seatActions"></div>');
 const a=$('seatActions');
 if(seat.uid)a.append(button('👤 প্রোফাইল','profile',{uid:seat.uid}));
 if(!seat.uid&&!seat.locked)a.append(button('🎤 সিটে বসুন','take',{seat:i}));
 if(seat.uid===state.uid){a.append(button(state.muted?'🎤 আনমিউট':'🔇 মিউট','mic'));a.append(button('⬇️ সিট ছাড়ুন','leaveSeat'));}
 if(state.role==='owner'||state.role==='admin')a.append(button('🔒 সিট ম্যানেজ করুন','seatMenu',{seat:i}));
 if(seat.uid)a.append(button('🎁 উপহার','gifts'));
}
function seatHTML(s,i,host){
 const locked=s.locked&&!s.uid,empty=!s.uid&&!locked;
 const url=typeof s.avatar==='string'&&s.avatar.startsWith('https://')?s.avatar:null;
 return '<button class="seat '+(locked?'lock':empty?'empty':'')+'" data-i="'+i+'"><div class="av"><div class="ring"></div><div class="face">'+(url?'<img alt="" style="width:100%;height:100%;object-fit:cover;border-radius:50%" src="'+esc(url)+'">':locked?'🔒':empty?'＋':'👤')+'</div><i class="wave"></i><i class="wave b"></i>'+(host?'<div class="crown">👑</div>':'')+(s.uid===state.uid&&state.muted?'<div class="badge">🔇</div>':'')+'</div><div class="nm">'+esc(s.name||(locked?'লক':'খালি'))+'</div>'+(host?'<div class="tag">হোস্ট সিট</div>':'')+'</button>';
}
window.SoveraLive={update(next){
 state=next;
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
 $('roomBtn').querySelector('small').textContent='লাইভ · '+(state.roomId||'');
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
 $('toast').textContent=state.error||'';$('toast').style.display=state.error?'block':'none';
}};
$('bg').onclick=e=>{if(e.target===$('bg'))close();};
$('min').onclick=()=>send('minimize');$('exit').onclick=()=>{sheet('<h3>রুম থেকে বের হবেন?</h3><div class="acts" id="exitActions"></div>');$('exitActions').append(button('🚪 বের হন','leave'));};
$('mic').onclick=()=>send('mic');$('bGift').onclick=()=>send('gifts');$('bMsg').onclick=()=>send('messages');$('bGame').onclick=()=>send('games');$('roomBtn').onclick=roomSettings;
$('bOwn').onclick=()=>{
 sheet('<h3>👑 রুম ম্যানেজমেন্ট</h3><div class="acts" id="ownerActions"></div>');
 const settings=button('⚙️ সেটিংস','settings');settings.onclick=roomSettings;
 $('ownerActions').append(settings,button('🔒 সব সিট লক','lockAll',{locked:true}),button('🔓 সব সিট আনলক','lockAll',{locked:false}));
 if(state.role==='owner'){const admins=button('🛡️ অ্যাডমিন','admins');admins.onclick=adminSheet;$('ownerActions').append(admins);}
};
function sendText(){const text=$('txt').value.trim();if(text)send('send',{text});}
$('sendTxt').onclick=sendText;$('txt').onkeydown=e=>{if(e.key==='Enter')sendText();};
$('txt').oninput=()=>{$('sendTxt').style.display=$('txt').value.trim()?'grid':'none';};
$('emo').onclick=()=>{sheet('<h3>😊 ইমোজি</h3><div class="gifts" id="emojis"></div>');for(const emoji of ['😀','😂','😍','❤️','👍','👏','🎉','🔥']){const b=document.createElement('button');b.className='gf';b.textContent=emoji;b.onclick=()=>{$('txt').value+=emoji;$('txt').oninput();close();};$('emojis').append(b);}};
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
