'use strict';
/**
 * Wallet adapter.
 *  - local: coins stored in this server's SQLite (for testing / if the game owns the coins)
 *  - http : coins stored in YOUR app. This server calls your wallet API:
 *
 *      POST {WALLET_URL}/balance  { userId }                                   -> { ok, balance }
 *      POST {WALLET_URL}/debit    { txId, userId, amount, roundId, itemId }    -> { ok, balance } | { ok:false, error:'INSUFFICIENT_BALANCE', balance }
 *      POST {WALLET_URL}/credit   { txId, userId, amount, roundId, reason, refundOf? } -> { ok, balance }
 *
 *    Every request has headers:
 *      X-Greedy-Timestamp: <unix ms>
 *      X-Greedy-Signature: hex( HMAC_SHA256(WALLET_SECRET, timestamp + "." + rawBody) )
 *    Your API MUST be idempotent on txId (same txId twice = do it once, return same result).
 *    For reason "refund" with refundOf: only credit if that debit txId was actually applied.
 */
const crypto = require('crypto');
const cfg = require('./config');
const db = require('./db');

class WalletError extends Error {
  constructor(code, balance, retryable = false) { super(code); this.code = code; this.balance = balance; this.retryable = retryable; }
}

/* ---------------- local ---------------- */
const q = {
  get: db.prepare('SELECT balance FROM local_wallets WHERE user_id = ?'),
  ins: db.prepare('INSERT OR IGNORE INTO local_wallets(user_id, balance) VALUES (?, ?)'),
  set: db.prepare('UPDATE local_wallets SET balance = ? WHERE user_id = ?'),
  tx: db.prepare('SELECT * FROM local_wallet_tx WHERE tx_id = ?'),
  addTx: db.prepare('INSERT INTO local_wallet_tx(tx_id,user_id,delta,balance_after,created_at) VALUES (?,?,?,?,?)'),
};
function localEnsure(userId) { q.ins.run(userId, cfg.localStartBalance); return q.get.get(userId).balance; }
const localApply = db.transaction((txId, userId, delta) => {
  const prev = q.tx.get(txId);
  if (prev) return prev.balance_after;                 // idempotent
  const bal = localEnsure(userId);
  if (bal + delta < 0) throw new WalletError('INSUFFICIENT_BALANCE', bal);
  q.set.run(bal + delta, userId);
  q.addTx.run(txId, userId, delta, bal + delta, Date.now());
  return bal + delta;
});
const local = {
  async balance(userId) { return localEnsure(userId); },
  async debit({ txId, userId, amount }) { return localApply(txId, userId, -amount); },
  async credit({ txId, userId, amount, refundOf }) {
    if (refundOf && !q.tx.get(refundOf)) return localEnsure(userId); // original debit never applied
    return localApply(txId, userId, amount);
  },
  // test helper
  async topup(userId, amount) { return localApply('topup-' + userId + '-' + Date.now() + '-' + Math.random(), userId, amount); },
};

/* ---------------- http ---------------- */
async function call(pathname, payload) {
  const body = JSON.stringify(payload);
  const ts = String(Date.now());
  const sig = crypto.createHmac('sha256', cfg.walletSecret).update(ts + '.' + body).digest('hex');
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), cfg.walletTimeoutMs);
  let res, data;
  try {
    res = await fetch(cfg.walletUrl.replace(/\/$/, '') + pathname, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Greedy-Timestamp': ts, 'X-Greedy-Signature': sig },
      body,
      signal: ctrl.signal,
    });
    data = await res.json().catch(() => ({}));
  } catch (e) {
    throw new WalletError('WALLET_UNREACHABLE', undefined, true);
  } finally { clearTimeout(timer); }
  if (res.status >= 500) throw new WalletError('WALLET_ERROR', undefined, true);
  if (!data.ok) throw new WalletError(data.error || 'WALLET_REJECTED', data.balance, false);
  return Number(data.balance);
}
const http = {
  async balance(userId) { return call('/balance', { userId }); },
  async debit(p) { return call('/debit', p); },
  async credit(p) { return call('/credit', p); },
};

const impl = cfg.walletMode === 'http' ? http : local;
module.exports = { ...impl, WalletError, mode: cfg.walletMode, localTopup: local.topup };
