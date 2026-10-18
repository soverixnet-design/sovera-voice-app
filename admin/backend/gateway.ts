export {};
const origin = 'https://sovera-control.soverixnet.chatgpt.site';
const url = Deno.env.get('SUPABASE_URL')!;
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const enc = new TextEncoder();
const cors = {'Access-Control-Allow-Origin': origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
const json = (data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
const base64url = (b:Uint8Array)=>btoa(String.fromCharCode(...b)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const decode = (s:string)=>Uint8Array.from(atob(s.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));
const signing = crypto.subtle.importKey('raw',enc.encode(`sovera-admin-v1:${service}`),{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);
async function rpc(name:string,body:unknown){
 const r=await fetch(`${url}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
 const result=await r.json();if(!r.ok)throw new Error(result.message||'Server request failed');return result;
}
async function session(user:string){
 const p=base64url(enc.encode(JSON.stringify({user,exp:Math.floor(Date.now()/1000)+1800,nonce:crypto.randomUUID(),v:1})));
 const sig=await crypto.subtle.sign('HMAC',await signing,enc.encode(p));return `${p}.${base64url(new Uint8Array(sig))}`;
}
async function actor(req:Request){
 const token=req.headers.get('Authorization')?.replace(/^Bearer /,'')||'';
 const parts=token.split('.');if(parts.length!==2||token.length>2000)throw new Error('Session expired. Sign in again.');
 if(!await crypto.subtle.verify('HMAC',await signing,decode(parts[1]),enc.encode(parts[0])))throw new Error('Session expired. Sign in again.');
 const data=JSON.parse(new TextDecoder().decode(decode(parts[0])));
 const now=Math.floor(Date.now()/1000);if(data.v!==1||!data.exp||data.exp<=now||data.exp>now+1801||!/^[-a-f0-9]{36}$/.test(data.user))throw new Error('Session expired. Sign in again.');
 return data.user as string;
}
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return json({error:'Origin not allowed'},403);
 try{
  if(req.method==='GET'){
   let ready=false;try{await rpc('sovera_admin_run',{p_actor:'00000000-0000-4000-8000-000000000000',p_action:'session',p_data:{}});}catch(e){ready=e instanceof Error && e.message==='Admin access revoked';}
   return json({ready});
  }
  if(req.method!=='POST')return json({error:'Method not allowed'},405);
  if(Number(req.headers.get('content-length')||0)>15000000)return json({error:'Request too large'},413);
  const data=await req.json();
  if(data.action==='login'){
   const code=String(data.code||'').trim().toLowerCase();if(!/^[a-f0-9]{64}$/.test(code))return json({error:'Paste the complete one-time code from the Sovera app.'},400);
   const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(code))),x=>x.toString(16).padStart(2,'0')).join('');
   const user=await rpc('sovera_admin_redeem',{p_hash:hash});const identity=await rpc('sovera_admin_run',{p_actor:user,p_action:'session',p_data:{}});
   return json({token:await session(user),identity});
  }
  const user=await actor(req);
  if(data.action==='asset.upload'){
   const identity=await rpc('sovera_admin_run',{p_actor:user,p_action:'session',p_data:{}});
   if(identity.role!=='owner'&&!identity.permissions.some((p:string)=>p==='content.manage'||p==='events.manage'))return json({error:'Asset permission denied'},403);
   if(typeof data.base64!=='string'||data.base64.length>14000000)return json({error:'File too large'},400);
   const bytes=Uint8Array.from(atob(data.base64),c=>c.charCodeAt(0));
   const mime=String(data.mime);const ext:Record<string,string>={'image/png':'png','image/jpeg':'jpg','image/webp':'webp','video/mp4':'mp4','audio/mpeg':'mp3','audio/wav':'wav'};
   if(!ext[mime]||bytes.length>10485760||bytes.length<12)return json({error:'Use PNG, JPG, WebP, MP4, MP3 or WAV up to 10 MB.'},400);
   const head=new TextDecoder('latin1').decode(bytes.slice(0,12));
   const valid=mime==='image/png'?bytes[0]===137&&head.slice(1,4)==='PNG':mime==='image/jpeg'?bytes[0]===255&&bytes[1]===216:mime==='image/webp'?head.startsWith('RIFF')&&head.slice(8)==='WEBP':mime==='video/mp4'?head.slice(4,8)==='ftyp':mime==='audio/wav'?head.startsWith('RIFF')&&head.slice(8)==='WAVE':head.startsWith('ID3')||(bytes[0]===255&&(bytes[1]&224)===224);
   if(!valid)return json({error:'File format does not match its type'},400);
   const path=`${user}/${crypto.randomUUID()}.${ext[mime]}`;
   const uploaded=await fetch(`${url}/storage/v1/object/sovera-admin-assets/${path}`,{method:'POST',headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':mime},body:bytes});
   if(!uploaded.ok)return json({error:'Upload failed'},400);
   return json({url:`${url}/storage/v1/object/public/sovera-admin-assets/${path}`,mime});
  }
  const allowed=['session','dashboard','users','user','user.ban','user.vip','staff','staff.save','recharge','history','audit','rooms','room.save','content','content.save','support','support.reply','finance','sellers','seller.save','settings','settings.save','inventory','inventory.grant','inventory.revoke','moderation','report.resolve','moment.moderate','analytics','room.monitor'];
  if(!allowed.includes(data.action))return json({error:'Unknown action'},400);
  const result=await rpc('sovera_admin_run',{p_actor:user,p_action:data.action,p_data:data.payload||{}});return json({result});
 }catch(e){
  const message=e instanceof Error?e.message:'Request failed';const auth=/Session expired|Admin access revoked|Invalid or expired login code/.test(message);
  return json({error:message.length<300?message:'Request failed'},auth?401:400);
 }
});
