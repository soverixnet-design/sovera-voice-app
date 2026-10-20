'use strict';
(async()=>{
 require('./limits')(require('./config'));
 await require('./wallet').recover();
 require('./server');
})().catch(()=>{console.error('Greedy startup reconciliation failed; game remains closed');process.exit(1);});
