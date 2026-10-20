'use strict';
const crypto=require('crypto');
const Database=require('better-sqlite3');
const cfg=require('./config');
if(cfg.walletMode!=='http'||cfg.demoAuth||String(cfg.jwtSecret).length<32||
 String(cfg.walletSecret).length<32||!/^http:\/\/127\.0\.0\.1:\d+\/sovera\/account\/internal\/greedy-wallet\/?$/.test(cfg.walletUrl))
 throw Error('Verified loopback wallet and non-demo authentication required');
class WalletError extends Error{
 constructor(code,balance,retryable=false){super(code);this.code=code;this.balance=balance;this.retryable=retryable;}
}
const journal=new Database(cfg.dbFile+'.wallet-journal');
journal.pragma('journal_mode = WAL');journal.pragma('synchronous = FULL');
journal.exec("CREATE TABLE IF NOT EXISTS debit_intents(tx TEXT PRIMARY KEY,body TEXT NOT NULL,status TEXT NOT NULL)");
function canonical(action,p){
 const d={userId:p.userId};
 if(typeof d.userId!=='string'||!d.userId||d.userId.length>128)throw new WalletError('INVALID_USER');
 if(action!=='balance'){
  if(typeof p.txId!=='string'||!p.txId||p.txId.length>200||!Number.isSafeInteger(p.amount)||p.amount<=0)throw new WalletError('INVALID_TRANSFER');
  Object.assign(d,{txId:p.txId,amount:p.amount});
  if(action==='credit'){
   if(!['win','refund'].includes(p.reason))throw new WalletError('INVALID_REASON');
   d.reason=p.reason;
   if(p.reason==='refund'){
    if(typeof p.refundOf!=='string'||!p.refundOf)throw new WalletError('INVALID_REFUND');
    d.refundOf=p.refundOf;
   }
  }
 }
 return d;
}
async function call(action,p){
 const data=canonical(action,p),body=JSON.stringify(data),ts=String(Date.now());
 const signature=crypto.createHmac('sha256',cfg.walletSecret).update(ts+'.'+body).digest('hex');
 const controller=new AbortController();
 const timeout=setTimeout(()=>controller.abort(),Math.min(15000,Math.max(500,Number(cfg.walletTimeoutMs)||5000)));
 try{
  const response=await fetch(cfg.walletUrl.replace(/\/$/,'')+'/'+action,{
   method:'POST',headers:{'Content-Type':'application/json','X-Greedy-Timestamp':ts,'X-Greedy-Signature':signature},body,signal:controller.signal});
  let reply;try{reply=await response.json();}catch{throw new WalletError('INVALID_WALLET_REPLY',undefined,true);}
  if(response.status>=500)throw new WalletError('WALLET_UNAVAILABLE',undefined,true);
  if(!response.ok)throw new WalletError('WALLET_AUTH_OR_REQUEST_REJECTED',undefined,true);
  if(reply.ok!==true)throw new WalletError(reply.error||'WALLET_REJECTED',reply.balance,false);
  if(!Number.isSafeInteger(reply.balance)||reply.balance<0)throw new WalletError('INVALID_BALANCE',undefined,true);
  return reply.balance;
 }catch(e){if(e instanceof WalletError)throw e;throw new WalletError('WALLET_UNREACHABLE',undefined,true);}
 finally{clearTimeout(timeout);}
}
async function debit(input){
 const p=canonical('debit',input),body=JSON.stringify(p);
 const prior=journal.prepare('SELECT * FROM debit_intents WHERE tx=?').get(p.txId);
 if(prior&&prior.body!==body)throw new WalletError('TX_CONFLICT');
 if(prior?.status==='refunded')throw new WalletError('DEBIT_ALREADY_REFUNDED');
 journal.prepare("INSERT OR IGNORE INTO debit_intents VALUES(?,?,'pending')").run(p.txId,body);
 try{
  const balance=await call('debit',p);
  journal.prepare("UPDATE debit_intents SET status='applied' WHERE tx=?").run(p.txId);
  return balance;
 }catch(e){
  if(!e.retryable)journal.prepare("UPDATE debit_intents SET status='rejected' WHERE tx=?").run(p.txId);
  throw e;
 }
}
async function recover(){
 const game=new Database(cfg.dbFile);
 game.pragma('busy_timeout = 10000');
 try{
  const hasBets=game.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='bets'").get();
  if(hasBets&&!game.prepare('PRAGMA table_info(bets)').all().some(c=>c.name==='tx_id'))throw Error('Unsupported original bet schema');
  for(const row of journal.prepare("SELECT * FROM debit_intents WHERE status IN ('pending','applied')").all()){
   if(hasBets&&game.prepare('SELECT 1 FROM bets WHERE tx_id=?').get(row.tx)){
    journal.prepare("UPDATE debit_intents SET status='linked' WHERE tx=?").run(row.tx);continue;
   }
   const p=JSON.parse(row.body);
   try{await call('debit',p);}catch(e){if(e.retryable)throw e;
    journal.prepare("UPDATE debit_intents SET status='rejected' WHERE tx=?").run(row.tx);continue;}
   // Match the original engine refund ID so its durable payout retry agrees.
   try{await call('credit',{userId:p.userId,txId:'refund-'+p.txId,amount:p.amount,reason:'refund',refundOf:p.txId});}
   catch(e){if(e.code!=='ALREADY_REFUNDED')throw e;}
   journal.prepare("UPDATE debit_intents SET status='refunded' WHERE tx=?").run(row.tx);
  }
 }finally{game.close();}
}
module.exports={mode:'http',WalletError,balance:userId=>call('balance',{userId}),debit,
 credit:p=>call('credit',p),recover,
 localTopup(){throw new WalletError('LOCAL_COINS_DISABLED');}};
