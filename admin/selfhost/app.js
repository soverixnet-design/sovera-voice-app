'use strict';
const root=document.getElementById('app');
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=value=>Number(value||0).toLocaleString('en-US');
const id=()=>crypto.randomUUID();
let identity=null,view='dashboard',users=[],rechargeRequest=null,publicationRequest=null;
const pendingKey=()=>`sovera.control.pending-recharge.${identity.uid}`;
function savePending(){try{if(rechargeRequest)sessionStorage.setItem(pendingKey(),JSON.stringify(rechargeRequest));else sessionStorage.removeItem(pendingKey());}catch{}}
const $=name=>document.getElementById(name);
async function api(path,method='GET',body){
 const response=await fetch('/sovera/control/'+path,{method,credentials:'same-origin',headers:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store'});
 const data=await response.json().catch(()=>({}));
 if(!response.ok){
  if(response.status===401){identity=null;login();}
  const error=Error(typeof data.detail==='string'?data.detail:'Request could not be completed.');error.status=response.status;throw error;
 }
 return data;
}
function login(message=''){
 root.innerHTML=`<main class="login"><div class="brand"><img class="brand-logo" src="/sovera-logo.png" alt="Sovera" width="72" height="72"><strong>Sovera Control</strong></div><h1>Your community workspace.</h1><p>Sign in with your assigned admin username and password.</p><form id="login"><label>Username<input id="username" autocomplete="username" minlength="3" maxlength="64" autocapitalize="none" spellcheck="false" required></label><label>Password<input id="password" type="password" autocomplete="current-password" maxlength="128" required></label><button id="submit" class="full">Sign in</button><p id="error" role="alert" class="error">${esc(message)}</p></form><p class="help">Only assigned staff can sign in. Contact the owner if you need to reset your password.</p></main>`;
 $('login').onsubmit=async event=>{event.preventDefault();$('submit').disabled=true;try{await api('password-login','POST',{username:$('username').value.trim(),password:$('password').value});await start();}catch(e){if($('error'))$('error').textContent=e.message;if($('submit'))$('submit').disabled=false;}};
}
const titles={dashboard:'Overview',users:'Members',recharge:'Recharge coins',staff:'Staff access',publications:'Notices & events',support:'Support inbox',history:'Recharge history',banners:'Home banners',frames:'Profile frames',entries:'Entry animations',gifts:'Animated gifts',medals:'Medals',tags:'Profile tags',roomframes:'Room frames'};
function available(){
 const role=identity.role;
 return ['dashboard',...(role!=='support'?['users']:[]),...(role==='owner'||role==='agent'?['recharge','history']:[]),...(role==='owner'?['staff']:[]),...(role==='owner'||role==='admin'?['banners','frames','entries','gifts','medals','tags','roomframes','publications']:[]),...(role!=='agent'?['support']:[])];
}
function shell(){
 root.innerHTML=`<div class="shell"><aside class="sidebar"><div class="brand"><img class="brand-logo" src="/sovera-logo.png" alt="Sovera" width="52" height="52"><strong>Sovera Control</strong><button id="menu-close" class="secondary mobile-menu" aria-label="Close navigation">×</button></div><nav class="nav" aria-label="Admin sections">${available().map(name=>`<button data-view="${name}" class="${view===name?'active':''}">${titles[name]}</button>`).join('')}</nav><div class="foot"><p>${esc(identity.name)} · ${esc(identity.role)}</p></div></aside><main class="main"><header class="topbar"><button id="menu-toggle" class="secondary mobile-menu" aria-label="Open navigation" aria-expanded="false">☰ Menu</button><div><small class="eyebrow">SOVERA / CONTROL</small><h1>${titles[view]}</h1></div><button id="logout" class="secondary">Sign out</button></header><p id="error" role="alert" class="error"></p><div id="panel">Loading…</div></main></div>`;
 root.querySelectorAll('[data-view]').forEach(button=>button.onclick=()=>{view=button.dataset.view;render();});
 $('menu-close').onclick=()=>root.querySelector('.shell').classList.remove('menu-open');
 $('menu-toggle').onclick=()=>{const opened=root.querySelector('.shell').classList.toggle('menu-open');$('menu-toggle').setAttribute('aria-expanded',String(opened));};
 $('logout').onclick=async()=>{try{await api('logout','POST',{});identity=null;login();}catch(e){$('error').textContent=e.message;}};
}
function table(headers,rows){return `<div class="table-wrap"><table><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table>${rows.length?'':'<p class="empty">No records yet.</p>'}</div>`;}
async function render(){
 shell();
 try{if(assetKinds[view])await assets();else await ({dashboard,members,recharge,staff,publications,support,history}[view==='users'?'members':view])();}
 catch(e){if($('error'))$('error').textContent=e.message;if($('panel')&&$('panel').textContent==='Loading…')$('panel').textContent='This section could not be loaded. Choose it again to retry.';}
}
function dashboard(){
 $('panel').innerHTML=`<div class="metrics">${[['Members',identity.users],['Saved rooms',identity.rooms],['Unanswered support',identity.open_tickets]].map(([name,value])=>`<section class="card metric"><small>${name}</small><div class="value">${num(value)}</div></section>`).join('')}</div><section class="card"><h2>Welcome, ${esc(identity.name)}</h2><p>Assigned role: ${esc(identity.role)}</p>${identity.quota_remaining===null?'':`<p>Recharge quota remaining: <b>${num(identity.quota_remaining)} Coins</b></p>`}<p class="help">Balances and records come from your Sovera server. Existing wallets must be reconciled before recharges or game spending can be enabled.</p></section>`;
}
async function members(){
 users=(await api('users')).items;
 $('panel').innerHTML='<section class="card"><label>Find by account ID, name or verified legacy reference<input id="search" type="search"></label><div id="results"></div><button id="more-members" class="secondary">Load more members</button></section>';
 const draw=()=>{
  const q=$('search').value.trim().toLowerCase();
  const rows=users.filter(u=>[u.uid,u.public_id,u.name,u.source_ref,u.country].some(v=>String(v??'').toLowerCase().includes(q)));
  $('results').innerHTML=table(['Member','Account ID','Country','Status / room','Role','Coins','Diamonds','Wallet','Details'],rows.map(u=>`<tr><td>${esc(u.name)}</td><td class="details">${u.public_id?'ID '+esc(u.public_id)+'<br>':''}${esc(u.uid)}</td><td>${esc(u.country)}</td><td>${u.last_seen>Date.now()/1000-90?'Online':'Offline'}<br>${esc(u.current_room||'—')}</td><td>${esc(u.role||'Member')}</td><td>${u.wallet_status?num(u.coins):'Not verified'}</td><td>${u.wallet_status?num(u.diamonds):'—'}</td><td>${esc(u.wallet_status||'Awaiting migration')}</td><td><button data-user-details="${esc(u.uid)}">View / assign assets</button></td></tr>`));
  root.querySelectorAll('[data-user-details]').forEach(b=>b.onclick=()=>userDetails(b.dataset.userDetails).catch(e=>{$('error').textContent=e.message;}));
 };
 let searchTimer;
 $('search').oninput=()=>{clearTimeout(searchTimer);const query=$('search').value.trim();searchTimer=setTimeout(async()=>{try{const data=await api('users?q='+encodeURIComponent(query));if(!$('search')||$('search').value.trim()!==query)return;users=data.items;draw();}catch(e){if($('error'))$('error').textContent=e.message;}},250);};
 $('more-members').onclick=async()=>{const query=$('search').value.trim();$('more-members').disabled=true;try{const data=await api('users?q='+encodeURIComponent(query)+'&offset='+users.length);if(!$('search')||$('search').value.trim()!==query)return;users.push(...data.items);draw();$('more-members').hidden=data.items.length<200;}catch(e){if($('error'))$('error').textContent=e.message;}finally{if($('more-members'))$('more-members').disabled=false;}};
 $('more-members').hidden=users.length<200;draw();
}
async function recharge(){
 users=(await api('users')).items;
 $('panel').innerHTML=`<section class="card"><h2>Recharge by account</h2><p>Select a member and verify their name and wallet before issuing coins.</p><form id="recharge"><label>Member<select id="target" required><option value="">Choose member</option>${users.map(u=>`<option value="${esc(u.uid)}">${esc(u.name)} · ${esc(u.public_id||u.source_ref||u.uid)}</option>`).join('')}</select></label><div id="target-info"></div><label>Coins<input id="amount" type="number" min="1" max="1000000000" step="1" required></label><label>Note<input id="note" maxlength="300"></label><button id="submit">Review recharge</button></form><div id="receipt" aria-live="polite"></div></section>`;
 $('target').onchange=()=>{
  const user=users.find(u=>u.uid===$('target').value);
  $('target-info').textContent=user?`${user.name} · ${user.wallet_status==='active'?num(user.coins)+' Coins':'Wallet not active or not migrated'}`:'';
 };
 if(rechargeRequest){$('target').value=rechargeRequest.target_uid;$('amount').value=rechargeRequest.amount;$('note').value=rechargeRequest.note;for(const field of ['target','amount','note'])$(field).disabled=true;$('submit').textContent='Retry same recharge';$('target').onchange();}
 $('recharge').onsubmit=async event=>{
  event.preventDefault();
  const target=users.find(u=>u.uid===$('target').value);
  if(!target||target.wallet_status!=='active'){$('error').textContent='This wallet must be verified and active first.';return;}
  const amount=Number($('amount').value);
  if(!Number.isSafeInteger(amount)||amount<1)return;
  if(!rechargeRequest&&!confirm(`Recharge ${num(amount)} Coins to ${target.name} (${target.uid})?`))return;
  rechargeRequest??={target_uid:target.uid,amount,note:$('note').value,request_id:id()};savePending();
  $('submit').disabled=true;
  for(const field of ['target','amount','note'])$(field).disabled=true;
  try{const result=await api('recharge','POST',rechargeRequest);rechargeRequest=null;savePending();if(!$('receipt'))return;$('receipt').innerHTML=`<div class="receipt"><strong>Recharge successful</strong><p>${esc(target.name)} received ${num(result.amount)} Coins.</p><p>Balance after this recharge: ${num(result.balance)} Coins</p><p class="details">Receipt: ${esc(result.request_id)}</p><button id="another">New recharge</button></div>`;$('another').onclick=recharge;}
  catch(e){$('error').textContent=e.message;$('submit').disabled=false;$('submit').textContent='Retry same recharge';}
 };
}
async function staff(){
 const rows=(await api('staff')).items;
 const people=(await api('users')).items;
 $('panel').innerHTML=`<section class="card"><h2>Assigned staff</h2>${table(['Account','Role','Quota','Issued'],rows.map(r=>`<tr><td class="details">${esc(r.uid)}</td><td>${esc(r.role)}</td><td>${r.quota===null?'—':num(r.quota)}</td><td>${r.used===null?'—':num(r.used)}</td></tr>`))}</section><section class="card space"><h2>Assign permissions</h2><form id="staff"><label>Member<select id="target" required>${people.filter(u=>u.uid!==identity.uid).map(u=>`<option value="${esc(u.uid)}">${esc(u.name)} · ${esc(u.uid)}</option>`).join('')}</select></label><label>Role<select id="role"><option value="support">Support replies only</option><option value="admin">Support and publications</option><option value="agent">Recharge within quota</option><option value="none">Revoke access</option></select></label><label>Total recharge quota<input id="quota" type="number" min="0" max="1000000000" value="0" required></label><p class="help">Quota is the lifetime total permitted for this agent; previously issued coins remain counted. Owner access can only be provisioned on the server console.</p><button id="submit">Save staff access</button></form></section>`;
 $('staff').onsubmit=async event=>{event.preventDefault();$('submit').disabled=true;try{await api('staff','POST',{target_uid:$('target').value,role:$('role').value,quota:Number($('quota').value)});await staff();}catch(e){$('error').textContent=e.message;$('submit').disabled=false;}};
}
function publications(){
 $('panel').innerHTML='<section class="card"><h2>Publish to the app</h2><form id="publication"><label>Section<select id="section"><option value="notices">Official notice</option><option value="events">Community event</option></select></label><label>Title<input id="title" maxlength="100" required></label><label>Details<textarea id="text" maxlength="1000" required></textarea></label><p class="help">Event announcements appear in the app. Automated prizes are a separate service.</p><button id="submit">Publish</button></form><p id="receipt" aria-live="polite"></p></section>';
 if(publicationRequest){for(const field of ['section','title','text']){$(field).value=publicationRequest[field];$(field).disabled=true;}$('submit').textContent='Retry same publication';}
 $('publication').onsubmit=async event=>{event.preventDefault();publicationRequest??={section:$('section').value,title:$('title').value,text:$('text').value,request_id:id()};$('submit').disabled=true;for(const field of ['section','title','text'])$(field).disabled=true;try{await api('publications','POST',publicationRequest);publicationRequest=null;publications();$('receipt').textContent='Published successfully.';}catch(e){$('error').textContent=e.message;$('submit').disabled=false;$('submit').textContent='Retry publication';}};
}
async function support(){
 const rows=(await api('support')).items;
 $('panel').innerHTML=`<section class="card"><h2>Support requests</h2>${rows.length?'':'<p>No requests yet.</p>'}${rows.map(t=>`<article class="ticket"><h3>${esc(t.name)}</h3><p>${esc(t.text)}</p><form data-ticket="${t.id}"><label>Your reply<textarea maxlength="1000" required>${esc(t.reply)}</textarea></label><button>Send reply</button></form></article>`).join('')}</section>`;
 root.querySelectorAll('[data-ticket]').forEach(form=>form.onsubmit=async event=>{event.preventDefault();const button=form.querySelector('button');button.disabled=true;try{await api('support/'+form.dataset.ticket,'PUT',{text:form.querySelector('textarea').value,request_id:id()});button.textContent='Reply saved';}catch(e){$('error').textContent=e.message;}finally{button.disabled=false;}});
}
async function history(){
 const rows=(await api('history')).items;
 $('panel').innerHTML=`<section class="card">${table(['Receipt','Account','Coins','Balance after','Note'],rows.map(r=>`<tr><td class="details">${esc(r.request_id)}</td><td class="details">${esc(r.target)}</td><td>${num(r.amount)}</td><td>${num(r.balance)}</td><td>${esc(r.note)}</td></tr>`))}</section>`;
}
async function start(){try{identity=await api('session');try{rechargeRequest=JSON.parse(sessionStorage.getItem(pendingKey())||'null');}catch{rechargeRequest=null;}if(!available().includes(view))view='dashboard';await render();}catch(e){login(e.message==='Sign in required'?'':e.message);}}
const assetKinds={banners:'banner',frames:'frame',entries:'entry',gifts:'gift',medals:'medal',tags:'tag',roomframes:'room_frame'};
let catalogRows=[],editingAsset=null,uploadedMedia=null;
const mediaPreview=key=>'/sovera/control/media/'+encodeURIComponent(key);
async function assets(){
 const kind=assetKinds[view];catalogRows=(await api('catalog')).items;editingAsset=null;uploadedMedia=null;
 const rows=catalogRows.filter(r=>r.kind===kind);
 $('panel').innerHTML=`<section class="card"><h2>${esc(titles[view])}</h2><p>Upload PNG, JPG, animated GIF or WebP from your gallery. Maximum 8 MB, 4096 px and 300 animation frames. Use a transparent image for frames.</p><button id="new-asset">Add new</button><div class="content-grid space">${rows.map(r=>`<article class="content-item"><img src="${mediaPreview(r.media_id)}" alt="${esc(r.title)}"><h3>${esc(r.title)}</h3><p>${num(r.price)} Coins · ${r.active?'Active':'Hidden'} · Order ${r.position}</p><button data-edit="${esc(r.id)}">Edit / preview</button><button class="secondary" data-toggle="${esc(r.id)}">${r.active?'Hide':'Publish'}</button></article>`).join('')}</div><p>${rows.length?'':'No items in this category yet.'}</p></section><div id="asset-editor"></div>`;
 $('new-asset').onclick=()=>assetEditor(kind);
 root.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>assetEditor(kind,catalogRows.find(r=>r.id===b.dataset.edit)));
 root.querySelectorAll('[data-toggle]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{const row=catalogRows.find(r=>r.id===b.dataset.toggle);await api('catalog','POST',itemPayload(row,{active:!row.active}));await assets();}catch(e){$('error').textContent=e.message;b.disabled=false;}});
}
function itemPayload(row,changes={}){const {id,kind,title,media_id,price,active,position,avatar_scale,avatar_x,avatar_y}=row;return {id,kind,title,media_id,price,active,position,avatar_scale,avatar_x,avatar_y,...changes};}
function assetEditor(kind,row){
 editingAsset=row??{id:id(),kind,title:'',media_id:'',price:0,active:true,position:0,avatar_scale:.46,avatar_x:.5,avatar_y:.5};uploadedMedia=null;
 $('asset-editor').innerHTML=`<section class="card"><h2>${row?'Edit':'New'} ${esc(kind.replaceAll('_',' '))}</h2><form id="asset-form"><label>Name<input id="asset-title" maxlength="80" value="${esc(editingAsset.title)}" required></label><label>Gallery image / animation<input id="asset-file" type="file" accept="image/png,image/jpeg,image/gif,image/webp"></label><div class="asset-preview fit-preview"><div id="fit-avatar" class="fit-avatar">USER</div><img id="fit-image" alt="Asset preview" ${editingAsset.media_id?`src="${mediaPreview(editingAsset.media_id)}"`:''}></div><p id="upload-info" class="help" aria-live="polite">${editingAsset.media_id?'Saved image loaded.':'Choose an image.'}</p><div class="cols"><label>Price in Coins (0 = free)<input id="asset-price" type="number" min="0" max="1000000000" value="${editingAsset.price}" required></label><label>Display order<input id="asset-order" type="number" min="0" max="10000" value="${editingAsset.position}" required></label></div>${kind==='gift'?'<p class="help">For paid gifts: each recipient receives Diamonds equal to the per-recipient Coin price. All wallets must be verified. Free gifts do not award Diamonds.</p>':''}<fieldset ${['frame','entry','room_frame'].includes(kind)?'':'hidden'}><legend>Avatar fit</legend><label>Avatar size<input id="fit-scale" type="range" min=".25" max=".8" step=".01" value="${editingAsset.avatar_scale}"></label><label>Horizontal center<input id="fit-x" type="range" min=".2" max=".8" step=".01" value="${editingAsset.avatar_x}"></label><label>Vertical center<input id="fit-y" type="range" min=".2" max=".8" step=".01" value="${editingAsset.avatar_y}"></label></fieldset><label class="check"><input id="asset-active" type="checkbox" ${editingAsset.active?'checked':''}>Show in app</label><button id="save-asset" class="space">Save and publish to app</button><p id="asset-message" role="status"></p></form></section>`;
 const fit=()=>{const avatar=$('fit-avatar'),scale=Number($('fit-scale').value),radius=scale/2;const center=value=>Math.max(radius,Math.min(1-radius,Number(value)));$('fit-x').value=center($('fit-x').value);$('fit-y').value=center($('fit-y').value);avatar.style.width=avatar.style.height=scale*100+'%';avatar.style.left=Number($('fit-x').value)*100+'%';avatar.style.top=Number($('fit-y').value)*100+'%';avatar.hidden=!['frame','entry','room_frame'].includes(kind);};
 for(const field of ['fit-scale','fit-x','fit-y'])$(field).oninput=fit;fit();
 $('asset-file').onchange=async()=>{
  const file=$('asset-file').files?.[0];if(!file)return;
  if(file.size>8*1024*1024){$('upload-info').textContent='Choose an image smaller than 8 MB.';return;}
  $('save-asset').disabled=true;$('upload-info').textContent='Uploading image…';uploadedMedia=null;
  try{
   const result=await fetch('/sovera/control/media',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/octet-stream'},body:file});
   const data=await result.json();if(!result.ok)throw Error(typeof data.detail==='string'?data.detail:'Upload failed');
   uploadedMedia=data.id;$('fit-image').src=mediaPreview(data.id);$('upload-info').textContent=`Uploaded ${data.width} × ${data.height} · ${data.frames} frame(s). Review fit, then save.`;
  }catch(e){$('upload-info').textContent=e.message;}finally{$('save-asset').disabled=false;}
 };
 $('asset-form').onsubmit=async event=>{
  event.preventDefault();const media=uploadedMedia||editingAsset.media_id;if(!media){$('asset-message').textContent='Upload an image first.';return;}
  $('save-asset').disabled=true;
  try{await api('catalog','POST',itemPayload(editingAsset,{title:$('asset-title').value,media_id:media,price:Number($('asset-price').value),position:Number($('asset-order').value),active:$('asset-active').checked,avatar_scale:Number($('fit-scale').value),avatar_x:Number($('fit-x').value),avatar_y:Number($('fit-y').value)}));await assets();$('error').textContent='Saved. The app loads published changes on refresh.';}
  catch(e){$('asset-message').textContent=e.message;$('save-asset').disabled=false;}
 };
 $('asset-editor').scrollIntoView({behavior:'smooth',block:'start'});
}
async function userDetails(uid){
 const data=await api('users/'+encodeURIComponent(uid)),p=data.profile;
 $('panel').innerHTML=`<section class="card"><button id="back-members" class="secondary">← Members</button><h2 class="space">${esc(p.display_name)}</h2><p class="details">Firebase ID: ${esc(p.firebase_uid)}</p><p>Country: ${esc(p.country)} · ${data.online?'Online':'Offline'}</p><p>Current room: ${esc(data.online?data.presence?.room_name||'—':'—')}</p><p>Bio: ${esc(p.bio||'—')}</p><p>Profile updated: ${new Date(p.updated_at*1000).toLocaleString()}</p><p>Wallet: ${esc(data.wallet?.status||'Awaiting verification')} · Legacy reference: ${esc(data.wallet?.source_ref||'—')}</p><p>Owned rooms: ${data.rooms.map(r=>esc(r.name)).join(', ')||'—'}</p><h3>Equipped assets</h3>${Object.entries(data.equipped).map(([k,r])=>`<span class="badge">${esc(k)}: ${esc(r.title)}</span>`).join(' ')||'<p>No assets equipped.</p>'}<div id="grant-editor"></div></section>`;
 $('back-members').onclick=members;
 if(identity.role==='owner'){
  const wear=(await api('catalog')).items.filter(r=>!['banner','gift'].includes(r.kind));
  $('grant-editor').innerHTML=`<h3 class="space">Assign frames, entries, medals and tags</h3><form id="asset-grant"><label>Asset<select id="grant-item" required>${wear.map(r=>`<option value="${esc(r.id)}">${esc(r.kind)} · ${esc(r.title)}${data.owned.includes(r.id)?' (owned)':''}</option>`).join('')}</select></label><label class="check"><input id="grant-equip" type="checkbox" checked>Equip immediately</label><label class="check"><input id="grant-revoke" type="checkbox">Revoke this asset</label><button id="grant-submit" class="space" ${wear.length?'':'disabled'}>Save assignment</button></form>`;
  $('asset-grant').onsubmit=async event=>{event.preventDefault();$('grant-submit').disabled=true;try{await api('catalog/grant','POST',{target_uid:uid,item_id:$('grant-item').value,equip:$('grant-equip').checked,revoke:$('grant-revoke').checked});await userDetails(uid);}catch(e){$('error').textContent=e.message;$('grant-submit').disabled=false;}};
 }
}

start();
