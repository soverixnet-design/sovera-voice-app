import json
import sqlite3
import unittest
from .test_greedy_wallet import GreedyWalletTests
from .app import ProfileInput
from .broadcasts import Broadcasts

class BroadcastTests(unittest.TestCase):
    setUp=GreedyWalletTests.setUp
    def test_only_settled_wins_are_public_and_retry_is_not_duplicated(self):
        from .app import Profiles
        Profiles(self.path).save('alice',ProfileInput(display_name='Alice',country='BD',avatar_url='https://example.com/a.webp'))
        self.assertEqual(self.client.get('/sovera/account/broadcasts').status_code,401)
        # The fixture verifier ignores tokens; absence still must be rejected.
        with sqlite3.connect(self.path) as db:
            db.execute('INSERT INTO account_wallet_imports VALUES(?,?,?,?,?,?,?,?,?)',('old','alice','10000001','snapshot','a'*64,100,5,'proof',1))
        win={'txId':'won-round','userId':'alice','amount':500,'reason':'win'}
        self.ledger.apply('credit',win);self.ledger.apply('credit',win)
        rows=Broadcasts(self.path).read()['items']
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]['coins'],'500')
        self.assertEqual(rows[0]['winner']['public_id'],'10000001')
        self.assertNotIn('balance',json.dumps(rows))
        self.assertNotIn('firebase_uid',json.dumps(rows))
        self.assertEqual(Broadcasts(self.path).read(rows[0]['id'])['items'],[])
        self.ledger.apply('debit',{'txId':'bet','userId':'alice','amount':10})
        self.ledger.apply('credit',{'txId':'refund','userId':'alice','amount':10,'reason':'refund','refundOf':'bet'})
        self.assertEqual(len(Broadcasts(self.path).read()['items']),1)
