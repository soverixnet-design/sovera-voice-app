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
  for(const m of state.messages){const row=document.createElement('div');row.className='msg'+(m.uid===state.uid?' me':'');row.innerHTML='<div class="mav">👤</div><div class="mb"><span class="mn">'+esc(m.name)+'</span><span class="mt">'+esc(m.text)+'</span></div>';row.onclick=()=>send('profile',{uid:m.uid});$('chat').append(row);}
  $('chat').scrollTop=$('chat').scrollHeight;
  if(state.sendPending===false&&state.messages.some(m=>m.uid===state.uid&&m.text===$('txt').value.trim())){$('txt').value='';$('txt').oninput();}
 }
 $('toast').textContent=state.error||'';$('toast').style.display=state.error?'block':'none';
}};
$('bg').onclick=e=>{if(e.target===$('bg'))close();};
$('min').onclick=()=>send('minimize');$('exit').onclick=()=>{sheet('<h3>রুম থেকে বের হবেন?</h3><div class="acts" id="exitActions"></div>');$('exitActions').append(button('🚪 বের হন','leave'));};
$('mic').onclick=()=>send('mic');$('bGift').onclick=()=>send('gifts');$('bMsg').onclick=()=>send('messages');$('bGame').onclick=()=>send('games');$('roomBtn').onclick=()=>send('settings');
$('bOwn').onclick=()=>{sheet('<h3>👑 রুম ম্যানেজমেন্ট</h3><div class="acts" id="ownerActions"></div>');$('ownerActions').append(button('⚙️ সেটিংস','settings'),button('🛡️ অ্যাডমিন','admins'));};
function sendText(){const text=$('txt').value.trim();if(text)send('send',{text});}
$('sendTxt').onclick=sendText;$('txt').onkeydown=e=>{if(e.key==='Enter')sendText();};
$('txt').oninput=()=>{$('sendTxt').style.display=$('txt').value.trim()?'grid':'none';};
$('emo').onclick=()=>{sheet('<h3>😊 ইমোজি</h3><div class="gifts" id="emojis"></div>');for(const emoji of ['😀','😂','😍','❤️','👍','👏','🎉','🔥']){const b=document.createElement('button');b.className='gf';b.textContent=emoji;b.onclick=()=>{$('txt').value+=emoji;$('txt').oninput();close();};$('emojis').append(b);}};
$('imgBtn').onclick=()=>send('photo');
if(window.visualViewport)visualViewport.addEventListener('resize',()=>{$('app').style.height=visualViewport.height+'px';});
