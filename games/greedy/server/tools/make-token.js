'use strict';
// Usage: node tools/make-token.js <uid> [name] [hours]
// Creates the same JWT your app backend must create for each player.
const { signToken } = require('../src/auth');
const [uid = '1001', name = 'Test Player', hours = '12'] = process.argv.slice(2);
const token = signToken({ uid, name, avatar: '', exp: Math.floor(Date.now() / 1000) + Number(hours) * 3600 });
console.log(token);
