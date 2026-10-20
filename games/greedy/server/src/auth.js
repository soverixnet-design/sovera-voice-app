'use strict';
const crypto = require('crypto');
const cfg = require('./config');

const b64url = (buf) => Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const fromB64url = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

/** Create an HS256 JWT (used by tools/make-token.js and tests; your app backend does the same). */
function signToken(payload, secret = cfg.jwtSecret) {
  const head = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify(payload));
  const sig = b64url(crypto.createHmac('sha256', secret).update(head + '.' + body).digest());
  return `${head}.${body}.${sig}`;
}

/** Verify an HS256 JWT issued by your app backend. Returns {id,name,avatar} or null. */
function verifyToken(token) {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [head, body, sig] = parts;
  let header;
  try { header = JSON.parse(fromB64url(head).toString()); } catch (e) { return null; }
  if (header.alg !== 'HS256') return null;
  const expect = crypto.createHmac('sha256', cfg.jwtSecret).update(head + '.' + body).digest();
  const got = fromB64url(sig);
  if (got.length !== expect.length || !crypto.timingSafeEqual(got, expect)) return null;
  let p;
  try { p = JSON.parse(fromB64url(body).toString()); } catch (e) { return null; }
  if (p.exp && Date.now() / 1000 > p.exp) return null;
  const id = String(p.uid || p.sub || '');
  if (!id) return null;
  return { id, name: String(p.name || 'Player').slice(0, 40), avatar: String(p.avatar || '').slice(0, 500) };
}

module.exports = { signToken, verifyToken };
