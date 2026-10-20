'use strict';
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const cfg = require('./config');

fs.mkdirSync(path.dirname(cfg.dbFile), { recursive: true });
const db = new Database(cfg.dbFile);
db.pragma('journal_mode = WAL');
db.pragma('synchronous = NORMAL');

db.exec(`
CREATE TABLE IF NOT EXISTS rounds (
  id INTEGER PRIMARY KEY,
  seed TEXT NOT NULL,
  hash TEXT NOT NULL,
  result_index INTEGER,
  result_id TEXT,
  started_at INTEGER NOT NULL,
  closed_at INTEGER,
  total_bet INTEGER DEFAULT 0,
  total_win INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'betting'          -- betting | settled
);
CREATE TABLE IF NOT EXISTS bets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tx_id TEXT UNIQUE NOT NULL,
  round_id INTEGER NOT NULL,
  user_id TEXT NOT NULL,
  item_id TEXT NOT NULL,
  amount INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS bets_round ON bets(round_id);
CREATE INDEX IF NOT EXISTS bets_user ON bets(user_id, round_id);
CREATE TABLE IF NOT EXISTS payouts (
  tx_id TEXT PRIMARY KEY,
  round_id INTEGER NOT NULL,
  user_id TEXT NOT NULL,
  bet INTEGER NOT NULL,
  win INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',        -- pending | done | none
  attempts INTEGER DEFAULT 0,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS payouts_user ON payouts(user_id, round_id);
CREATE INDEX IF NOT EXISTS payouts_status ON payouts(status);
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT,
  avatar TEXT,
  updated_at INTEGER
);
CREATE TABLE IF NOT EXISTS local_wallets (       -- used only in WALLET_MODE=local
  user_id TEXT PRIMARY KEY,
  balance INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS local_wallet_tx (
  tx_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  delta INTEGER NOT NULL,
  balance_after INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
`);

module.exports = db;
