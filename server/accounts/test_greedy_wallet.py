import hashlib
import hmac
import json
import os
import sqlite3
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, create_app
from server.accounts.greedy_wallet import GreedyLedger

class GreedyWalletTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / 'wallet.db'
        async def verify(token):
            return 'alice'
        self.client = TestClient(create_app(Profiles(self.path), verify))
        self.ledger = GreedyLedger(self.path)
        with sqlite3.connect(self.path) as db:
            db.execute('INSERT INTO account_wallet_links VALUES(?,?,?,?)', ('alice', 'verified-legacy-id', 1, 'active'))
            db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)', ('import', 'alice', 100, 5, 'verified_import', 1))
        env = patch.dict(os.environ, {'SOVERA_GREEDY_ENABLED': '1', 'SOVERA_GREEDY_WALLET_VERIFIED': '1', 'SOVERA_GREEDY_WALLET_SECRET': 'x'*40})
        env.start()
        self.addCleanup(env.stop)

    def call(self, action, body, stamp=None, signature=None):
        raw = json.dumps(body)
        stamp = str(stamp or int(time.time()*1000))
        sig = hmac.new(b'x'*40, (stamp+'.'+raw).encode(), hashlib.sha256).hexdigest()
        return self.client.post('/sovera/account/internal/greedy-wallet/'+action, content=raw,
            headers={'x-greedy-timestamp': stamp, 'x-greedy-signature': sig if signature is None else signature})

    def test_signed_access_and_unknown_wallet(self):
        self.assertEqual(self.call('balance', {'userId': 'alice'}, signature='bad').status_code, 401)
        self.assertEqual(self.call('balance', {'userId': 'alice'}, stamp=1).status_code, 401)
        self.assertEqual(self.call('balance', {'userId': 'alice'}).json(), {'ok': True, 'balance': 100})
        self.assertEqual(self.call('balance', {'userId': 'bob'}).json()['error'], 'WALLET_NOT_VERIFIED')
        with patch.dict(os.environ, {'SOVERA_GREEDY_ENABLED': '0'}):
            self.assertEqual(self.call('balance', {'userId': 'alice'}).status_code, 503)

    def test_retry_persistence_conflict_and_exact_refund(self):
        debit = {'txId': 'bet1', 'userId': 'alice', 'amount': 70, 'roundId': 1}
        self.assertEqual(self.call('debit', debit).json()['balance'], 30)
        self.assertEqual(GreedyLedger(self.path).apply('debit', debit)['balance'], 30)
        self.assertEqual(self.call('debit', dict(debit, amount=1)).status_code, 409)
        refund = {'txId': 'ref1', 'userId': 'alice', 'amount': 70, 'reason': 'refund', 'refundOf': 'bet1'}
        self.assertEqual(self.call('credit', dict(refund, amount=71)).json()['error'], 'REFUND_DEBIT_MISMATCH')
        refund['txId'] = 'ref2'
        self.assertEqual(self.call('credit', refund).json()['balance'], 100)
        self.assertEqual(self.call('credit', refund).json()['balance'], 100)
        self.assertEqual(self.call('credit', dict(refund, txId='ref3')).json()['error'], 'ALREADY_REFUNDED')

    def test_concurrent_debits_cannot_overdraw(self):
        def debit(i):
            return self.ledger.apply('debit', {'txId': str(i), 'userId': 'alice', 'amount': 80})
        with ThreadPoolExecutor(max_workers=2) as pool:
            replies = list(pool.map(debit, range(2)))
        self.assertEqual(sum(r['ok'] for r in replies), 1)
        self.assertEqual(self.ledger.apply('balance', {'userId': 'alice'})['balance'], 20)

    def test_win_validation_and_frozen_account(self):
        win = {'txId': 'win1', 'userId': 'alice', 'amount': 50, 'reason': 'win'}
        self.assertEqual(self.call('credit', win).json()['balance'], 150)
        self.assertEqual(self.call('credit', dict(win, txId='bad', amount=True)).status_code, 400)
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE account_wallet_links SET status='frozen'")
        self.assertEqual(self.call('debit', {'txId': 'no', 'userId': 'alice', 'amount': 1}).json()['error'], 'WALLET_FROZEN')

if __name__ == '__main__':
    unittest.main()
