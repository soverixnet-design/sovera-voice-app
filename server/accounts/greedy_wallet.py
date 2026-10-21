"""Signed, idempotent Greedy adapter for the existing verified account ledger."""
import asyncio
import hashlib
import hmac
import json
import os
import re
import sqlite3
import time
from fastapi import HTTPException, Request

from .broadcasts import initialize, person, emit

MAX_COINS = 9007199254740991

def configured():
    return (os.getenv('SOVERA_GREEDY_ENABLED') == '1'
            and os.getenv('SOVERA_GREEDY_WALLET_VERIFIED') == '1'
            and len(os.getenv('SOVERA_GREEDY_WALLET_SECRET', '')) >= 32)

class GreedyLedger:
    def __init__(self, path):
        self.path = str(path)
        with sqlite3.connect(self.path) as db:
            initialize(db)
            db.executescript('''
                CREATE TABLE IF NOT EXISTS account_greedy_requests(
                  tx_id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL,
                  response TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS account_greedy_refunds(
                  debit_id TEXT PRIMARY KEY, refund_id TEXT NOT NULL UNIQUE);
            ''')

    def apply(self, action, data):
        uid = data.get('userId')
        if not isinstance(uid, str) or not 1 <= len(uid) <= 128:
            raise HTTPException(400, 'Invalid userId')
        tx = data.get('txId')
        amount = data.get('amount')
        if action != 'balance':
            if not isinstance(tx, str) or not 1 <= len(tx) <= 200:
                raise HTTPException(400, 'Invalid txId')
            if type(amount) is not int or not 1 <= amount <= MAX_COINS:
                raise HTTPException(400, 'Invalid amount')
            if action == 'credit' and data.get('reason') not in ('win', 'refund'):
                raise HTTPException(400, 'Invalid credit reason')
        fingerprint = json.dumps([action, data], sort_keys=True, separators=(',', ':'))
        with sqlite3.connect(self.path, timeout=10) as db:
            db.execute('BEGIN IMMEDIATE')
            # Retry returns the original result, including rejected debits.
            if action != 'balance':
                previous = db.execute('SELECT fingerprint,response FROM account_greedy_requests WHERE tx_id=?', (tx,)).fetchone()
                if previous:
                    if previous[0] != fingerprint:
                        raise HTTPException(409, 'Transaction payload conflict')
                    return json.loads(previous[1])
            if action=='debit' and db.execute("SELECT 1 FROM sqlite_master WHERE name='account_bans'").fetchone() and db.execute('SELECT 1 FROM account_bans WHERE uid=?',(uid,)).fetchone():return {'ok':False,'error':'ACCOUNT_BANNED'}
            link = db.execute('SELECT status FROM account_wallet_links WHERE firebase_uid=?', (uid,)).fetchone()
            if not link:
                return {'ok': False, 'error': 'WALLET_NOT_VERIFIED'}
            coins, diamonds = db.execute('SELECT COALESCE(SUM(coin_delta),0),COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?', (uid,)).fetchone()
            if not 0 <= coins <= MAX_COINS or diamonds < 0:
                raise HTTPException(503, 'Wallet reconciliation required')
            if link[0] != 'active':
                return {'ok': False, 'error': 'WALLET_FROZEN', 'balance': coins}
            if action == 'balance':
                return {'ok': True, 'balance': coins}
            result = {'ok': True, 'balance': coins}
            delta = -amount if action == 'debit' else amount
            kind = 'game_debit' if action == 'debit' else 'game_win'
            if action == 'credit' and data['reason'] == 'refund':
                debit = data.get('refundOf')
                if not isinstance(debit, str) or not debit:
                    raise HTTPException(400, 'refundOf required')
                original = db.execute('SELECT firebase_uid,coin_delta,kind FROM account_wallet_ledger WHERE reference=?', ('greedy:' + debit,)).fetchone()
                if original != (uid, -amount, 'game_debit'):
                    result = {'ok': False, 'error': 'REFUND_DEBIT_MISMATCH', 'balance': coins}
                elif db.execute('SELECT 1 FROM account_greedy_refunds WHERE debit_id=?', (debit,)).fetchone():
                    result = {'ok': False, 'error': 'ALREADY_REFUNDED', 'balance': coins}
                kind = 'refund'
            if result['ok'] and not 0 <= coins + delta <= MAX_COINS:
                result = {'ok': False, 'error': 'INSUFFICIENT_BALANCE' if delta < 0 else 'BALANCE_LIMIT', 'balance': coins}
            if result['ok']:
                if kind == 'refund':
                    db.execute('INSERT INTO account_greedy_refunds VALUES(?,?)', (data['refundOf'], tx))
                db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)', ('greedy:' + tx, uid, delta, 0, kind, int(time.time())))
                result['balance'] = coins + delta
                if kind == 'game_win':
                    winner=person(db,uid)
                    if winner is not None: emit(db,'greedy:'+tx,'win',{'winner':winner,'game':'Greedy Wheel','coins':str(amount)})
            db.execute('INSERT INTO account_greedy_requests VALUES(?,?,?)', (tx, fingerprint, json.dumps(result)))
            return result

def attach_greedy_wallet(app, wallets):
    ledger = GreedyLedger(wallets.database_path)

    @app.post('/sovera/account/internal/greedy-wallet/{action}')
    async def transfer(action: str, request: Request):
        if action not in ('balance', 'debit', 'credit'):
            raise HTTPException(404)
        if not configured():
            raise HTTPException(503, 'Game wallet is not configured')
        raw = await request.body()
        stamp = request.headers.get('x-greedy-timestamp', '')
        signature = request.headers.get('x-greedy-signature', '')
        if not stamp.isdecimal() or len(stamp) > 16 or abs(int(stamp) - int(time.time() * 1000)) > 30000:
            raise HTTPException(401, 'Invalid wallet signature')
        expected = hmac.new(os.environ['SOVERA_GREEDY_WALLET_SECRET'].encode(), stamp.encode() + b'.' + raw, hashlib.sha256).hexdigest()
        if not re.fullmatch(r'[0-9a-f]{64}', signature) or not hmac.compare_digest(expected, signature):
            raise HTTPException(401, 'Invalid wallet signature')
        try:
            data = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            raise HTTPException(400, 'Invalid JSON') from None
        if not isinstance(data, dict):
            raise HTTPException(400, 'Invalid payload')
        return await asyncio.to_thread(ledger.apply, action, data)
