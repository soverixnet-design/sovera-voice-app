import assert from 'node:assert/strict';
let handler;let active=true;const used=new Set();let requests=[];
globalThis.Deno={env:{get:n=>n==='SUPABASE_URL'?'https://fixture.invalid':'fixture-signing-key-not-a-secret'},serve:f=>handler=f};
globalThis.fetch=async(url,opts)=>{
 const name=url.split('/').at(-1);const body=JSON.parse(opts.body);requests.push({name,body});
 let data;
 if(name==='sovera_admin_redeem'){if(used.has(body.p_hash))return Response.json({message:'Invalid or expired login code'},{status:400});used.add(body.p_hash);data='00000000-0000-4000-8000-000000000002';}
 else if(body.p_actor==='00000000-0000-4000-8000-000000000000'||!active)return Response.json({message:'Admin access revoked'},{status:400});
 else data=body.p_action==='session'?{role:'agent',permissions:['users.read','recharge.create'],profile:{uid:10000002}}:{users:2};
 return Response.json(data);
};
await import('../backend/gateway.ts');
const call=(data,token,origin='https://sovera-control.soverixnet.chatgpt.site')=>handler(new Request('https://fixture.invalid/functions/v1/sovera-admin',{method:'POST',headers:{origin,'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(data)}));
assert.equal((await call({action:'dashboard'})).status,401);
assert.equal((await call({action:'login',code:'short'})).status,400);
const login=await call({action:'login',code:'a'.repeat(64)});assert.equal(login.status,200);const {token}=await login.json();assert.ok(token);
assert.equal((await call({action:'login',code:'a'.repeat(64)})).status,401);
assert.equal((await call({action:'dashboard'},token)).status,200);
assert.equal(requests.at(-1).body.p_actor,'00000000-0000-4000-8000-000000000002');
assert.equal((await call({action:'dashboard'},token.slice(0,-4)+'fake')).status,401);
assert.equal((await call({action:'asset.upload',base64:'abc',mime:'image/png'},token)).status,403);
assert.equal((await call({action:'dashboard'},token,'https://evil.invalid')).status,403);
active=false;assert.equal((await call({action:'dashboard'},token)).status,401);
console.log('Gateway tests passed: signed sessions, tamper rejection, code replay, origin guard, asset permissions, live revocation');
