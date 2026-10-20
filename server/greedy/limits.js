'use strict';
// Remove the former product cap; retain exact arithmetic for possible payouts.
// The trusted wallet checks every debit against the actual remaining balance.
module.exports=function applyBalanceLimits(cfg){
 const multipliers=cfg.items.map(item=>Number(item.mult));
 if(!multipliers.length||multipliers.some(n=>!Number.isSafeInteger(n)||n<1))
  throw Error('Invalid game multipliers');
 cfg.maxBetPerRound=Math.floor(Number.MAX_SAFE_INTEGER/Math.max(...multipliers));
 return cfg.maxBetPerRound;
};
