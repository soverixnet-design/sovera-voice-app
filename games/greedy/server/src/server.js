'use strict';
/**
 * Greedy game server: HTTP (static client + small API) and WebSocket (/ws) on one port.
 *   ws://HOST:PORT/ws?token=<JWT from your app>
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const cfg = require('./config');
const engine = require('./engine');
const wallet = require('./wallet');
const { verifyToken } = require('./auth');

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.json': 'application/json', '.ico': 'image/x-icon', '.mp3': 'audio/mpeg' };
const json = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(obj)); };

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname.replace(/\/+$/, '') || '/';
  try {
    if (p === '/health') return json(res, 200, { ok: true, time: Date.now(), walletMode: wallet.mode });
    if (p === '/api/history') return json(res, 200, { list: engine.history(Math.min(100, Number(url.searchParams.get('limit')) || 50)) });
    if (p === '/api/odds') return json(res, 200, engine.odds());
    let m;
    if ((m = p.match(/^\/api\/round\/(\d+)$/))) { const v = engine.verifyRound(Number(m[1])); return json(res, v ? 200 : 404, v || { error: 'NOT_FOUND' }); }
    if (p.startsWith('/api/admin/')) {
      if (!cfg.adminKey || url.searchParams.get('key') !== cfg.adminKey) return json(res, 403, { error: 'FORBIDDEN' });
      if (p === '/api/admin/stats') {
        const since = Number(url.searchParams.get('since')) || new Date().setHours(0, 0, 0, 0);
        return json(res, 200, engine.stats(since));
      }
      if (p === '/api/admin/topup') {
        if (wallet.mode !== 'local') return json(res, 400, { error: 'ONLY_LOCAL_MODE' });
        const uid = url.searchParams.get('uid'); const amt = Math.floor(Number(url.searchParams.get('amount')));
        if (!uid || !(amt > 0)) return json(res, 400, { error: 'BAD_INPUT' });
        const bal = await wallet.localTopup(uid, amt);
        engine.refreshBalance(uid);
        return json(res, 200, { ok: true, balance: bal });
      }
      return json(res, 404, { error: 'NOT_FOUND' });
    }
    // static client
    if (!cfg.clientDir) return json(res, 404, { error: 'NOT_FOUND' });
    const file = path.normalize(path.join(cfg.clientDir, p === '/' ? 'index.html' : decodeURIComponent(p)));
    if (!file.startsWith(cfg.clientDir)) return json(res, 403, { error: 'FORBIDDEN' });
    fs.readFile(file, (err, buf) => {
      if (err) return json(res, 404, { error: 'NOT_FOUND' });
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(buf);
    });
  } catch (e) {
    console.error(e);
    json(res, 500, { error: 'SERVER_ERROR' });
  }
});

/* ---------------- WebSocket ---------------- */
const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 4096 });
const socketsOf = new Map(); // userId -> Set<ws>

function send(userId, msg) {
  const data = JSON.stringify(msg);
  if (userId === null) { for (const c of wss.clients) if (c.readyState === 1 && c.userId) c.send(data); return; }
  const set = socketsOf.get(userId);
  if (set) for (const c of set) if (c.readyState === 1) c.send(data);
}

function authenticate(req) {
  const url = new URL(req.url, 'http://x');
  const token = url.searchParams.get('token');
  if (token) return verifyToken(token);
  if (cfg.demoAuth && url.searchParams.get('demo') === '1') {
    const visitor = String(req.headers['x-visitor-id'] || '').slice(0, 64);
    const uid = (visitor || String(url.searchParams.get('uid') || '').slice(0, 64) || 'guest-' + Math.random().toString(36).slice(2, 10)).replace(/[^\w-]/g, '');
    return { id: 'demo-' + uid, name: String(url.searchParams.get('name') || 'Guest').slice(0, 40), avatar: '' };
  }
  return null;
}

wss.on('connection', async (ws, req) => {
  const user = authenticate(req);
  if (!user) { ws.close(4001, 'AUTH_FAILED'); return; }
  ws.userId = null; // not part of broadcast until hello is sent
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  if (!socketsOf.has(user.id)) socketsOf.set(user.id, new Set());
  socketsOf.get(user.id).add(ws);

  // rate limit: max 20 msgs / second
  let bucket = 20, last = Date.now();
  ws.on('message', (raw) => {
    const n = Date.now(); bucket = Math.min(20, bucket + ((n - last) / 1000) * 20); last = n;
    if (bucket < 1) return; bucket--;
    let m; try { m = JSON.parse(raw); } catch (e) { return; }
    if (!m || typeof m !== 'object') return;
    if (m.t === 'bet') engine.placeBet(user.id, m);
    else if (m.t === 'records') send(user.id, { t: 'records', list: engine.records(user.id, 50) });
    else if (m.t === 'balance') engine.refreshBalance(user.id);
    else if (m.t === 'ping') ws.send(JSON.stringify({ t: 'pong', serverTime: Date.now() }));
  });
  ws.on('close', () => {
    const set = socketsOf.get(user.id);
    if (set) { set.delete(ws); if (!set.size) socketsOf.delete(user.id); }
    engine.leave(user.id, ws);
  });

  try {
    const hello = await engine.join(user, ws);
    if (ws.readyState !== 1) return;
    ws.send(JSON.stringify(hello));
    ws.userId = user.id;
    send(user.id, { t: 'records', list: engine.records(user.id, 50) });
  } catch (e) {
    console.error('join failed', e);
    ws.close(1011, 'JOIN_FAILED');
  }
});

setInterval(() => {
  for (const ws of wss.clients) { if (!ws.isAlive) { ws.terminate(); continue; } ws.isAlive = false; ws.ping(); }
}, 25000);

engine.start(send);
server.listen(cfg.port, '0.0.0.0', () => {
  console.log(`Greedy server on :${cfg.port}  wallet=${wallet.mode}  demoAuth=${cfg.demoAuth}  client=${cfg.clientDir || '-'}`);
});
process.on('unhandledRejection', (e) => console.error('unhandledRejection', e));
