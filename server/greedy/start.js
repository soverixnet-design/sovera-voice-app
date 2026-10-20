'use strict';
(async()=>{
 const limits=require('./limits'),cfg=require('./config');
 limits(cfg);
 await require('./wallet').recover();
 const engine=require('./engine'),join=engine.join;
 engine.join=async(...args)=>limits.withBalanceChip(await join(...args),cfg);
 require('./server');
})().catch(()=>{console.error('Greedy startup reconciliation failed; game remains closed');process.exit(1);});
