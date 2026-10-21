'use strict';
const assert=require('assert/strict');
const apply=require('./limits');
const config={maxBetPerRound:1000000,minBet:1000,chips:[1000,1000000],items:[{mult:10},{mult:15},{mult:25},{mult:45}]};
const limit=apply(config);
assert(limit>111111111);
assert(Number.isSafeInteger(limit*45));
assert.equal(config.maxBetPerRound,limit);
assert(config.chips.includes(1234567));
assert(!config.chips.includes(1.5));
assert(!config.chips.includes(NaN));
const hello=apply.withBalanceChip({balance:111111111,config:{chips:config.chips}},config);
assert(hello.config.chips.includes(111111111));
assert.deepEqual([...config.chips],[1000,1000000]); // Other users never see this user's balance chip.
assert.throws(()=>apply({items:[{mult:Infinity}]}));
console.log('BALANCE_LIMIT_POLICY_OK');
