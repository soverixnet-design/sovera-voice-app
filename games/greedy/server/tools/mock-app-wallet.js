'use strict';
/**
 * EXAMPLE of the wallet API that YOUR APP must provide (WALLET_MODE=http).
 * Run: WALLET_SECRET=xxx node tools/mock-app-wallet.js   (port 9090)
 * Then in the game server .env:  WALLET_MODE=http  WALLET_URL=http://127.0.0.1:9090
 * Replace the in-memory Maps with your real user table / coin ledger.
 */
const http = require('http');
const crypto = require('crypto');
const SECRET = process.env.WALLET_SECRET || 'change-me-shared-hmac-secret';
const PORT = Number(process.env.MOCK_PORT || 9090);

const balances = new Map();   // userId -> coins   (your users table)
const ledger = new Map();     // txId -> { userId, delta, balance }   (your coin transaction table, UNIQUE txId)
const bal = (u) => { if (!balances.has(u)) balances.set(u, 50000); return balances.get(u); };

function verify(req, body) {
  const ts = req.headers['x-greedy-timestamp'];
  const sig = String(req.headers['x-greedy-signature'] || '');
  if (!ts || Math.abs(Date.now() - Number(ts)) > 60000) return false;      // replay protection
  const expect = crypto.createHmac('sha256', SECRET).update(ts + '.' + body).digest('hex');
  return sig.length === expect.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expect));
}

function apply(txId, userId, delta) {
  if (ledger.has(txId)) return { ok: true, balance: ledger.get(txId).balance };   // idempotent
  const b = bal(userId);
  if (b + delta < 0) return { ok: false, error: 'INSUFFICIENT_BALANCE', balance: b };
  balances.set(userId, b + delta);
  ledger.set(txId, { userId, delta, balance: b + delta });
  return { ok: true, balance: b + delta };
}

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; if (body.length > 10000) req.destroy(); });
  req.on('end', () => {
    const out = (code, o) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (req.method !== 'POST') return out(405, { ok: false, error: 'METHOD' });
    if (!verify(req, body)) return out(401, { ok: false, error: 'BAD_SIGNATURE' });
    let p; try { p = JSON.parse(body); } catch (e) { return out(400, { ok: false, error: 'BAD_JSON' }); }
    const userId = String(p.userId || '');
    if (!userId) return out(400, { ok: false, error: 'NO_USER' });
    const amount = Math.floor(Number(p.amount));
    switch (req.url) {
      case '/balance': return out(200, { ok: true, balance: bal(userId) });
      case '/debit':
        if (!(amount > 0) || !p.txId) return out(400, { ok: false, error: 'BAD_INPUT' });
        return out(200, apply(p.txId, userId, -amount));
      case '/credit':
        if (!(amount > 0) || !p.txId) return out(400, { ok: false, error: 'BAD_INPUT' });
        // refund: only if the original debit really happened (and was not refunded before)
        if (p.reason === 'refund' && p.refundOf && !ledger.has(p.refundOf)) return out(200, { ok: true, balance: bal(userId) });
        return out(200, apply(p.txId, userId, amount));
      default: return out(404, { ok: false, error: 'NOT_FOUND' });
    }
  });
}).listen(PORT, () => console.log('Mock app wallet on :' + PORT));
