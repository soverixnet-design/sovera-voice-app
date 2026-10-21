'use strict';
// Remove the former product cap; retain exact arithmetic for possible payouts.
// The trusted wallet checks every debit against the actual remaining balance.
module.exports=function applyBalanceLimits(cfg){
 const multipliers=cfg.items.map(item=>Number(item.mult));
 if(!multipliers.length||multipliers.some(n=>!Number.isSafeInteger(n)||n<1))
  throw Error('Invalid game multipliers');
 cfg.maxBetPerRound=Math.floor(Number.MAX_SAFE_INTEGER/Math.max(...multipliers));
 if(Array.isArray(cfg.chips)){
  Object.defineProperty(cfg.chips,'includes',{value:amount=>
   Number.isSafeInteger(amount)&&amount>=cfg.minBet&&amount<=cfg.maxBetPerRound});
 }
 return cfg.maxBetPerRound;
};
module.exports.withBalanceChip=function(hello,cfg){
 if(!hello?.config||!Number.isSafeInteger(hello.balance))return hello;
 const chips=[...new Set([...cfg.chips,10000000,100000000,hello.balance])]
  .filter(n=>Number.isSafeInteger(n)&&n>=cfg.minBet&&n<=cfg.maxBetPerRound);
 return {...hello,config:{...hello.config,chips}};
};
