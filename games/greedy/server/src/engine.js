'use strict';
/**
 * Round engine — the single source of truth.
 *   betting (BETTING_SECONDS) -> spinning (SPIN_SECONDS) -> result (RESULT_SECONDS) -> next round
 * Fairness: at round start we publish hash = sha256(seed). The result is derived from
 * HMAC_SHA256(seed, roundId). After the round the seed is revealed so anyone can verify.
 */
const crypto = require('crypto');
const cfg = require('./config');
const db = require('./db');
const wallet = require('./wallet');

const N = cfg.items.length;
const OUT = cfg.outcomes;
const TOTAL_W = OUT.reduce((a, o) => a + o.weight, 0);
// coins won by a bet array for outcome o (Salad / Pizza pay several items at once)
const winOf = (o, arr) => (arr ? OUT[o].wins.reduce((a, w) => a + arr[w] * cfg.items[w].mult, 0) : 0);
const idxOf = (id) => cfg.items.findIndex((it) => it.id === id);

/* ---------------- statements ---------------- */
const S = {
  maxRound: db.prepare('SELECT MAX(id) AS m FROM rounds'),
  insRound: db.prepare('INSERT INTO rounds(id, seed, hash, started_at) VALUES (?,?,?,?)'),
  closeRound: db.prepare('UPDATE rounds SET result_index=?, result_id=?, closed_at=?, total_bet=?, total_win=?, status=? WHERE id=?'),
  insBet: db.prepare('INSERT INTO bets(tx_id, round_id, user_id, item_id, amount, created_at) VALUES (?,?,?,?,?,?)'),
  insPayout: db.prepare('INSERT OR IGNORE INTO payouts(tx_id, round_id, user_id, bet, win, status, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)'),
  payoutDone: db.prepare("UPDATE payouts SET status='done', updated_at=? WHERE tx_id=?"),
  payoutFail: db.prepare('UPDATE payouts SET attempts=attempts+1, last_error=?, updated_at=? WHERE tx_id=?'),
  pending: db.prepare("SELECT * FROM payouts WHERE status='pending' AND attempts < 200 ORDER BY created_at LIMIT 50"),
  history: db.prepare("SELECT id AS round, result_id AS itemId FROM rounds WHERE status='settled' ORDER BY id DESC LIMIT ?"),
  records: db.prepare(`SELECT p.round_id AS round, r.result_id AS itemId, p.bet, CASE WHEN p.tx_id LIKE 'refund-%' THEN 0 ELSE p.win END AS win
                       FROM payouts p JOIN rounds r ON r.id = p.round_id
                       WHERE p.user_id = ? AND p.tx_id LIKE 'win-%' ORDER BY p.round_id DESC LIMIT ?`),
  roundById: db.prepare('SELECT * FROM rounds WHERE id = ?'),
  unsettled: db.prepare("SELECT id FROM rounds WHERE status='betting'"),
  betsOfRound: db.prepare('SELECT user_id, tx_id, amount FROM bets WHERE round_id = ?'),
  upUser: db.prepare('INSERT INTO users(id,name,avatar,updated_at) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, avatar=excluded.avatar, updated_at=excluded.updated_at'),
  userName: db.prepare('SELECT name, avatar FROM users WHERE id = ?'),
  stats: db.prepare(`SELECT COUNT(*) AS rounds, COALESCE(SUM(total_bet),0) AS bet, COALESCE(SUM(total_win),0) AS win FROM rounds WHERE status='settled' AND started_at >= ?`),
};

/* ---------------- state ---------------- */
let round = null;              // current round
const users = new Map();       // userId -> { id, name, avatar, sockets:Set, balance, queue:Promise }
let send = () => {};           // (userId|null, msg) injected by server.js (null = broadcast)
let totalsDirty = false;

function pickResult(seed, roundId) {
  const h = crypto.createHmac('sha256', seed).update(String(roundId)).digest('hex');
  const x = parseInt(h.slice(0, 13), 16) / Math.pow(2, 52);
  let r = x * TOTAL_W;
  for (let i = 0; i < OUT.length; i++) { r -= OUT[i].weight; if (r < 0) return i; }
  return OUT.length - 1;
}

function publicState() {
  return {
    round: round.id, phase: round.phase, endsAt: round.endsAt, serverTime: Date.now(), hash: round.hash,
    totals: round.totals, online: onlineCount(),
    resultIndex: round.phase === 'betting' ? null : round.resultIndex,
    resultId: round.phase === 'betting' ? null : OUT[round.resultIndex].id,
  };
}
const onlineCount = () => { let n = 0; for (const u of users.values()) if (u.sockets.size) n++; return n; };

/* ---------------- lifecycle ---------------- */
function startRound() {
  const id = (S.maxRound.get().m || 1000) + 1;
  const seed = crypto.randomBytes(32).toString('hex');
  const hash = crypto.createHash('sha256').update(seed).digest('hex');
  S.insRound.run(id, seed, hash, Date.now());
  round = {
    id, seed, hash, phase: 'betting', startedAt: Date.now(), endsAt: Date.now() + cfg.bettingMs,
    totals: new Array(N).fill(0), bets: new Map(), betCount: new Map(), pendingDebits: 0, resultIndex: null, top: [],
  };
  send(null, { t: 'state', ...publicState() });
  setTimeout(closeBetting, cfg.bettingMs);
}

async function closeBetting() {
  const r = round;
  r.phase = 'spinning';
  r.resultIndex = pickResult(r.seed, r.id);
  r.endsAt = Date.now() + cfg.spinMs;
  send(null, { t: 'spin', round: r.id, resultIndex: r.resultIndex, resultId: OUT[r.resultIndex].id, endsAt: r.endsAt, serverTime: Date.now(), totals: r.totals });

  // wait for bets that are still being debited (max wallet timeout)
  const waitUntil = Date.now() + cfg.walletTimeoutMs + 500;
  while (r.pendingDebits > 0 && Date.now() < waitUntil) await new Promise((ok) => setTimeout(ok, 50));

  settle(r);
  setTimeout(() => showResult(r), Math.max(0, r.endsAt - Date.now()));
}

function settle(r) {
  const it = OUT[r.resultIndex];
  let totalBet = 0, totalWin = 0;
  const now = Date.now();
  const winners = [];
  const tx = db.transaction(() => {
    for (const [uid, arr] of r.bets) {
      const bet = arr.reduce((a, b) => a + b, 0);
      const win = winOf(r.resultIndex, arr);
      totalBet += bet; totalWin += win;
      S.insPayout.run(`win-${r.id}-${uid}`, r.id, uid, bet, win, win > 0 ? 'pending' : 'none', now, now);
      if (win > 0) winners.push({ uid, win });
    }
    S.closeRound.run(r.resultIndex, it.id, now, totalBet, totalWin, 'settled', r.id);
  });
  tx();
  r.top = winners.sort((a, b) => b.win - a.win).slice(0, 3).map((w) => {
    const u = users.get(w.uid) || S.userName.get(w.uid) || {};
    return { name: u.name || 'Player', avatar: u.avatar || '', win: w.win, userId: w.uid };
  });
  // pay winners now (spin animation hides the latency); failures are retried by the worker
  for (const w of winners) payOne({ tx_id: `win-${r.id}-${w.uid}`, user_id: w.uid, win: w.win, round_id: r.id });
}

async function payOne(p) {
  const refundOf = p.tx_id.startsWith('refund-') ? p.tx_id.slice(7) : undefined;
  try {
    const bal = await wallet.credit({ txId: p.tx_id, userId: p.user_id, amount: p.win, roundId: p.round_id, reason: refundOf ? 'refund' : 'win', refundOf });
    S.payoutDone.run(Date.now(), p.tx_id);
    const u = users.get(p.user_id);
    if (u) { u.balance = bal; send(p.user_id, { t: 'balance', balance: bal }); }
  } catch (e) {
    S.payoutFail.run(String(e.code || e.message), Date.now(), p.tx_id);
  }
}

function showResult(r) {
  r.phase = 'result';
  r.endsAt = Date.now() + cfg.resultMs;
  const it = OUT[r.resultIndex];
  const base = { t: 'result', round: r.id, resultIndex: r.resultIndex, resultId: it.id, wins: it.wins.map((w) => cfg.items[w].id), seed: r.seed, hash: r.hash, top: r.top, endsAt: r.endsAt, serverTime: Date.now() };
  for (const u of users.values()) {
    if (!u.sockets.size) continue;
    const arr = r.bets.get(u.id);
    const bet = arr ? arr.reduce((a, b) => a + b, 0) : 0;
    const win = winOf(r.resultIndex, arr);
    send(u.id, { ...base, you: { bet, win, balance: u.balance } });
  }
  setTimeout(startRound, cfg.resultMs);
}

/* ---------------- bets ---------------- */
function placeBet(userId, { itemId, amount, reqId, round: clientRound }) {
  const u = users.get(userId);
  if (!u) return;
  // serialize per user so balance checks don't race
  u.queue = u.queue.then(() => doBet(u, itemId, Math.floor(Number(amount)), reqId, clientRound)).catch(() => {});
}

async function doBet(u, itemId, amount, reqId, clientRound) {
  const r = round;
  const err = (code, extra = {}) => send(u.id, { t: 'bet_err', reqId, code, ...extra });
  if (clientRound && clientRound !== r.id) return err('ROUND_CHANGED');
  if (r.phase !== 'betting' || Date.now() > r.endsAt - 250) return err('BETTING_CLOSED');
  const idx = idxOf(itemId);
  if (idx < 0) return err('BAD_ITEM');
  if (!Number.isFinite(amount) || amount < cfg.minBet || !cfg.chips.includes(amount)) return err('BAD_AMOUNT');
  const mine = r.bets.get(u.id) || new Array(N).fill(0);
  if (mine.reduce((a, b) => a + b, 0) + amount > cfg.maxBetPerRound) return err('MAX_BET');

  const n = (r.betCount.get(u.id) || 0) + 1;
  r.betCount.set(u.id, n);
  const txId = `bet-${r.id}-${u.id}-${n}`;
  r.pendingDebits++;
  let bal;
  try {
    try { bal = await wallet.debit({ txId, userId: u.id, amount, roundId: r.id, itemId }); }
    catch (e) { if (!e.retryable) throw e; bal = await wallet.debit({ txId, userId: u.id, amount, roundId: r.id, itemId }); }
  } catch (e) {
    r.pendingDebits--;
    if (e.retryable) { // unknown state: queue a safe refund (only applied if the debit really happened)
      const now = Date.now();
      S.insPayout.run(`refund-${txId}`, r.id, u.id, amount, amount, 'pending', now, now);
    }
    if (e.balance !== undefined) { u.balance = e.balance; }
    return err(e.code || 'WALLET_ERROR', { balance: u.balance });
  }
  r.pendingDebits--;
  if (r.bets.has(u.id) === false) r.bets.set(u.id, mine);
  if (round !== r || !S.roundById.get(r.id) || S.roundById.get(r.id).status !== 'betting') {
    // round already settled while wallet was slow -> refund
    const now = Date.now();
    S.insPayout.run(`refund-${txId}`, r.id, u.id, amount, amount, 'pending', now, now);
    u.balance = bal;
    return err('BETTING_CLOSED', { balance: bal });
  }
  S.insBet.run(txId, r.id, u.id, itemId, amount, Date.now());
  mine[idx] += amount;
  r.totals[idx] += amount;
  totalsDirty = true;
  u.balance = bal;
  send(u.id, { t: 'bet_ok', reqId, round: r.id, itemId, amount, myBets: mine, balance: bal });
}

/* ---------------- users ---------------- */
async function join(user, socket) {
  let u = users.get(user.id);
  if (!u) { u = { ...user, sockets: new Set(), balance: 0, queue: Promise.resolve() }; users.set(user.id, u); }
  u.name = user.name; u.avatar = user.avatar;
  u.sockets.add(socket);
  S.upUser.run(u.id, u.name, u.avatar, Date.now());
  try { u.balance = await wallet.balance(u.id); } catch (e) { /* keep last known */ }
  const mine = round.bets.get(u.id) || new Array(N).fill(0);
  return {
    t: 'hello',
    user: { id: u.id, name: u.name, avatar: u.avatar },
    balance: u.balance,
    config: { items: cfg.items.map(({ id, mult }) => ({ id, mult })), specials: cfg.specials.map(({ id, wins }) => ({ id, wins })), chips: cfg.chips, maxBetPerRound: cfg.maxBetPerRound, bettingMs: cfg.bettingMs, spinMs: cfg.spinMs, resultMs: cfg.resultMs },
    state: publicState(),
    myBets: mine,
    history: S.history.all(50),
  };
}
function leave(userId, socket) {
  const u = users.get(userId);
  if (!u) return;
  u.sockets.delete(socket);
}
async function refreshBalance(userId) {
  const u = users.get(userId);
  if (!u) return;
  try { u.balance = await wallet.balance(userId); send(userId, { t: 'balance', balance: u.balance }); } catch (e) {}
}
const records = (userId, limit = 50) => S.records.all(userId, limit);
const history = (limit = 50) => S.history.all(limit);

/* ---------------- background ---------------- */
setInterval(() => {
  if (!round || !totalsDirty) return;
  totalsDirty = false;
  send(null, { t: 'totals', round: round.id, totals: round.totals, online: onlineCount() });
}, 500);
setInterval(() => { for (const p of S.pending.all()) payOne(p); }, 10000);

function recoverCrashedRounds() {
  // Rounds that never settled (server crashed mid-round): refund every bet.
  for (const { id } of S.unsettled.all()) {
    const now = Date.now();
    db.transaction(() => {
      for (const b of S.betsOfRound.all(id)) S.insPayout.run(`refund-${b.tx_id}`, id, b.user_id, b.amount, b.amount, 'pending', now, now);
      db.prepare("UPDATE rounds SET status='void', closed_at=? WHERE id=?").run(now, id);
    })();
  }
}

function start(sender) {
  send = sender;
  recoverCrashedRounds();
  startRound();
}

function verifyRound(id) {
  const r = S.roundById.get(id);
  if (!r) return null;
  const settled = r.status === 'settled';
  return {
    round: r.id, hash: r.hash, seed: settled ? r.seed : null, resultId: r.result_id, status: r.status,
    howToVerify: 'sha256(seed) must equal hash; result = weighted pick of HMAC_SHA256(key=seed, msg=roundId) first 13 hex chars / 2^52',
    check: settled ? { hashOk: crypto.createHash('sha256').update(r.seed).digest('hex') === r.hash, recomputed: OUT[pickResult(r.seed, r.id)].id } : null,
  };
}
function stats(sinceMs) { const s = S.stats.get(sinceMs); return { ...s, houseProfit: s.bet - s.win, rtp: s.bet ? +(s.win / s.bet).toFixed(4) : null, online: onlineCount(), pendingPayouts: S.pending.all().length }; }

function odds() {
  const sumW = TOTAL_W;
  const list = OUT.map((o) => ({ id: o.id, chance: +(o.weight / sumW * 100).toFixed(3) + '%' }));
  // average return for one coin spread evenly-weighted is not meaningful; report per-item RTP
  const rtp = cfg.items.map((it, i) => ({ id: it.id, mult: it.mult, rtp: +(OUT.reduce((a, o) => a + (o.wins.includes(i) ? o.weight : 0), 0) / sumW * it.mult * 100).toFixed(2) + '%' }));
  return { outcomes: list, itemRtp: rtp };
}

module.exports = { odds, start, join, leave, placeBet, refreshBalance, records, history, verifyRound, stats, pickResult };
