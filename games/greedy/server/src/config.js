'use strict';
const fs = require('fs');
const path = require('path');

// Tiny .env loader (no dependency)
const envFile = path.join(__dirname, '..', '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}
const env = (k, d) => (process.env[k] !== undefined && process.env[k] !== '' ? process.env[k] : d);
const num = (k, d) => Number(env(k, d));

// Must match the client order: first 4 = right side (meat), last 4 = left side (veg).
// weight = relative chance (out of the total weight of every OUTCOME below).
const ITEMS = [
  { id: 'shrimp',  mult: 10, weight: num('W_SHRIMP', 96.94) },
  { id: 'fish',    mult: 15, weight: num('W_FISH', 63.96) },
  { id: 'chicken', mult: 25, weight: num('W_CHICKEN', 37.58) },
  { id: 'steak',   mult: 45, weight: num('W_STEAK', 19.99) },
  { id: 'cabbage', mult: 5,  weight: num('W_CABBAGE', 193.88) },
  { id: 'carrot',  mult: 5,  weight: num('W_CARROT', 193.88) },
  { id: 'corn',    mult: 5,  weight: num('W_CORN', 193.88) },
  { id: 'tomato',  mult: 5,  weight: num('W_TOMATO', 193.88) },
];
// Special outcomes: every item in `wins` pays at once (each at its own multiplier).
// Salad = all 4 vegetables, Pizza = all 4 meats. Total weight above = 1000, so 4 = 0.4 %.
const SPECIALS = [
  { id: 'salad', wins: [4, 5, 6, 7], weight: num('W_SALAD', 4) },
  { id: 'pizza', wins: [0, 1, 2, 3], weight: num('W_PIZZA', 2) },
];
// index 0..7 = single items, 8 = salad, 9 = pizza  (same as the client)
const OUTCOMES = ITEMS.map((it, i) => ({ id: it.id, wins: [i], weight: it.weight })).concat(SPECIALS);

module.exports = {
  port: num('PORT', 8080),
  dbFile: path.resolve(__dirname, '..', env('DB_FILE', './data/greedy.db')),
  bettingMs: num('BETTING_SECONDS', 30) * 1000,
  spinMs: num('SPIN_SECONDS', 6) * 1000,
  resultMs: num('RESULT_SECONDS', 5) * 1000,
  chips: env('CHIPS', '10,100,1000,5000,10000').split(',').map(Number),
  maxBetPerRound: num('MAX_BET_PER_ROUND', 1000000),
  minBet: num('MIN_BET', 10),
  jwtSecret: env('GAME_JWT_SECRET', 'change-me'),
  demoAuth: env('DEMO_AUTH', '0') === '1',
  walletMode: env('WALLET_MODE', 'local'),
  walletUrl: env('WALLET_URL', ''),
  walletSecret: env('WALLET_SECRET', 'change-me'),
  walletTimeoutMs: num('WALLET_TIMEOUT_MS', 5000),
  localStartBalance: num('LOCAL_START_BALANCE', 50000),
  adminKey: env('ADMIN_KEY', ''),
  clientDir: env('CLIENT_DIR', '') ? path.resolve(__dirname, '..', env('CLIENT_DIR', '')) : '',
  items: ITEMS,
  specials: SPECIALS,
  outcomes: OUTCOMES,
};
