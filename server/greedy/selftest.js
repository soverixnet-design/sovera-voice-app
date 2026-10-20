'use strict';
const assert=require('assert/strict'),fs=require('fs'),os=require('os'),path=require('path');
const http=require('http'),crypto=require('crypto'),{spawn,spawnSync}=require('child_process');
const root=path.resolve(process.argv[2]);
const Database=require(path.join(root,'node_modules/better-sqlite3'));
const WebSocket=require(path.join(root,'node_modules/ws'));
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'sovera-greedy-test-'));
const secret=crypto.randomBytes(32).toString('hex'),jwt=crypto.randomBytes(32).toString('hex');
const balances=new Map(),receipts=new Map();let drop=false,child;
const server=http.createServer(async(req,res)=>{
 let body='';for await(const chunk of req)body+=chunk;
 const stamp=req.headers['x-greedy-timestamp'];
 const expected=crypto.createHmac('sha256',secret).update(stamp+'.'+body).digest('hex');
 assert.equal(req.headers['x-greedy-signature'],expected);
 const p=JSON.parse(body),kind=req.url.split('/').pop(),key=p.txId;
 if(!balances.has(p.userId))balances.set(p.userId,10000);
 let reply;
 if(receipts.has(key))reply=receipts.get(key);
 else{
  let balance=balances.get(p.userId);reply={ok:true,balance};
  if(kind==='debit'){
   if(balance<p.amount)reply={ok:false,error:'INSUFFICIENT_BALANCE',balance};
   else{balance-=p.amount;balances.set(p.userId,balance);reply.balance=balance;}
  }else if(kind==='credit'){
   if(p.reason==='refund')assert(receipts.get(p.refundOf)?.ok);
   balance+=p.amount;balances.set(p.userId,balance);reply.balance=balance;
  }
  if(key)receipts.set(key,reply);
 }
 if(drop&&kind==='debit'){drop=false;req.socket.destroy();return;}
 res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(reply));
});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function freePort(){const s=http.createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));const p=s.address().port;await new Promise(r=>s.close(r));return p;}
async function main(){
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const walletUrl='http://127.0.0.1:'+server.address().port+'/sovera/account/internal/greedy-wallet';
 fs.cpSync(path.join(root,'src'),path.join(dir,'src'),{recursive:true});
 fs.symlinkSync(path.join(root,'node_modules'),path.join(dir,'node_modules'),'dir');
 const port=await freePort(),database=path.join(dir,'test.db');
 const env={...process.env,PORT:String(port),DB_FILE:database,WALLET_MODE:'http',WALLET_URL:walletUrl,
  WALLET_SECRET:secret,GAME_JWT_SECRET:jwt,DEMO_AUTH:'0',LOCAL_START_BALANCE:'0',CLIENT_DIR:'',
  BETTING_SECONDS:'2',SPIN_SECONDS:'1',RESULT_SECONDS:'1',W_SHRIMP:'1000',W_FISH:'0',W_CHICKEN:'0',W_STEAK:'0',W_CABBAGE:'0',W_CARROT:'0',W_CORN:'0',W_TOMATO:'0',W_SALAD:'0',W_PIZZA:'0',CHIPS:'1000,10000,100000,1000000',MIN_BET:'1000',MAX_BET_PER_ROUND:'1000000'};
 Object.assign(process.env,env);
 const wallet=require(path.join(dir,'src/wallet'));
 assert.equal(await wallet.debit({txId:'once',userId:'adapter',amount:1000}),9000);
 assert.equal(await wallet.debit({txId:'once',userId:'adapter',amount:1000}),9000);
 await assert.rejects(wallet.debit({txId:'once',userId:'adapter',amount:2000}),e=>e.code==='TX_CONFLICT');
 assert.equal(await wallet.credit({txId:'refund-once',userId:'adapter',amount:1000,reason:'refund',refundOf:'once'}),10000);
 assert.equal(await wallet.credit({txId:'win-test',userId:'adapter',amount:5000,reason:'win'}),15000);
 // HTTP response can be lost AFTER the trusted wallet commits its debit.
 drop=true;
 await assert.rejects(wallet.debit({txId:'crash',userId:'lost-response',amount:1000}),e=>e.retryable);
 assert.equal(balances.get('lost-response'),9000);
 await wallet.recover();
 assert.equal(balances.get('lost-response'),10000);
 await wallet.recover();assert.equal(balances.get('lost-response'),10000);
 const db=new Database(database);
 db.exec('CREATE TABLE IF NOT EXISTS bets(tx_id TEXT)');
 await wallet.debit({txId:'persisted',userId:'recorded',amount:1000});
 db.prepare('INSERT INTO bets VALUES(?)').run('persisted');
 await wallet.recover();assert.equal(balances.get('recorded'),9000);
 db.close();
 if(process.argv.includes('--wallet-only')){console.log('GREEDY_ADAPTER_TESTS_OK');return;}
 // Use a different DB for the untouched uploaded round engine.
 const gameEnv={...env,DB_FILE:path.join(dir,'engine.db')};
 child=spawn(process.execPath,[path.join(dir,'src/start.js')],{env:gameEnv,stdio:['ignore','ignore','pipe']});
 let logs='';child.stderr.on('data',b=>logs+=b.toString());
 let ready=false;
 for(let i=0;i<80;i++){
  try{const r=await fetch('http://127.0.0.1:'+port+'/health');const h=await r.json();if(h.ok&&h.walletMode==='http'){ready=true;break;}}catch{}
  if(child.exitCode!==null)break;await sleep(100);
 }
 assert(ready,'Original engine did not start: '+logs.slice(-1000));
 const head=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
 const now=Math.floor(Date.now()/1000);
 const payload=Buffer.from(JSON.stringify({uid:'round-player',name:'Integration test',iat:now,exp:now+120})).toString('base64url');
 const token=head+'.'+payload+'.'+crypto.createHmac('sha256',jwt).update(head+'.'+payload).digest('base64url');
 const messages=[],socket=new WebSocket('ws://127.0.0.1:'+port+'/ws?token='+token);
 socket.on('message',b=>{try{messages.push(JSON.parse(b.toString()));}catch{}});
 await new Promise((resolve,reject)=>{socket.once('open',resolve);socket.once('error',reject);setTimeout(()=>reject(Error('WebSocket timeout')),5000).unref();});
 let hello;
 for(let i=0;i<60;i++){hello=messages.find(m=>m.t==='hello');if(hello)break;await sleep(100);}
 assert(hello,'Original JWT authentication did not produce hello');
 // Read the public original round state; no client chooses a winner.
 const initial=hello.state;
 const round=initial.round??initial.id;
 assert(round!==undefined,'Unsupported public round state: '+JSON.stringify(initial));
 socket.send(JSON.stringify({t:'bet',round,itemId:0,amount:1000,reqId:'integration-bet'}));
 let ack,result;
 for(let i=0;i<200;i++){
  ack=messages.find(m=>m.t==='bet_ok');
  result=messages.find(m=>m.t==='result'&&m.you?.bet===1000);
  const error=messages.find(m=>m.t==='bet_err');
  if(error)throw Error('Original bet rejected: '+JSON.stringify(error));
  if(ack&&result)break;await sleep(100);
 }
 assert(ack,'No bet acknowledgement from original engine');
 assert(result,'Original engine did not settle a shared round');
 assert.equal(result.you.win,10000,'Forced isolated test winner was not paid correctly');
 for(let i=0;i<60&&balances.get('round-player')!==9000+result.you.win;i++)await sleep(100);
 assert.equal(balances.get('round-player'),9000+result.you.win,'Original result and trusted wallet differ');
 assert.equal([...receipts.keys()].filter(k=>k&&k.includes('round-player')&&!k.startsWith('win-')).length>=1,true);
 socket.close();child.kill('SIGTERM');await sleep(150);
 console.log('GREEDY_WALLET_AND_ROUND_TESTS_OK');
}
main().then(()=>process.exit(0)).catch(e=>{console.error(e.message);process.exitCode=1;}).finally(()=>{
 if(child)child.kill('SIGTERM');server.close();fs.rmSync(dir,{recursive:true,force:true});
});
