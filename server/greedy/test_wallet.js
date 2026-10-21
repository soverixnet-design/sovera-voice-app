'use strict';
const fs=require('fs'),os=require('os'),path=require('path'),{spawnSync}=require('child_process');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'greedy-fixture-'));
try{
 fs.mkdirSync(path.join(root,'src'));
 fs.symlinkSync(path.join(__dirname,'node_modules'),path.join(root,'node_modules'),'dir');
 fs.copyFileSync(path.join(__dirname,'wallet.js'),path.join(root,'src/wallet.js'));
 fs.writeFileSync(path.join(root,'src/config.js'),"module.exports={dbFile:process.env.DB_FILE,walletMode:process.env.WALLET_MODE,demoAuth:process.env.DEMO_AUTH==='1',jwtSecret:process.env.GAME_JWT_SECRET,walletSecret:process.env.WALLET_SECRET,walletUrl:process.env.WALLET_URL,walletTimeoutMs:1000};");
 const run=spawnSync(process.execPath,[path.join(__dirname,'selftest.js'),root,'--wallet-only'],{stdio:'inherit',timeout:30000});
 if(run.status!==0)process.exitCode=1;
}finally{fs.rmSync(root,{recursive:true,force:true});}
