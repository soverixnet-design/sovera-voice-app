"""Firebase signs in users; real Coins/Diamonds remain server-owned and private."""
import os
import sqlite3
import tempfile
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from fastapi.testclient import TestClient
from server.accounts.app import Profiles,create_app
from server.accounts.wallet import WalletStore

class ServerWalletTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/'profiles.sqlite3'
        store=Profiles(self.path)
        async def verify(token):
            if token not in ('alice','bob'):raise ValueError('Invalid token')
            return token
        self.client=TestClient(create_app(store,verify))
        self.wallet=WalletStore(self.path)
        self.a={'Authorization':'Bearer alice'}
        self.b={'Authorization':'Bearer bob'}

    def test_auth_and_unmigrated_balance_is_not_fabricated(self):
        self.assertEqual(self.client.get('/sovera/account/wallet').status_code,401)
        result=self.client.get('/sovera/account/wallet',headers=self.a)
        self.assertEqual(result.status_code,200)
        self.assertEqual(result.headers.get('cache-control'),'no-store')
        state=result.json()
        self.assertEqual(state['status'],'not_migrated')
        self.assertIsNone(state['coins'])
        self.assertIsNone(state['diamonds'])
        self.assertFalse(state['canSpend'])
        self.assertEqual(self.client.get('/sovera/account/wallet/history',
            headers=self.a).json()['entries'],[])
        self.assertEqual(self.client.post('/sovera/account/wallet',
            headers=self.a,json={'coins':999999}).status_code,405)

    def test_verified_server_migration_is_private_and_read_only(self):
        # This DB fixture stands for an externally reconciled migration.
        # The product has NO HTTP endpoint to perform it.
        with sqlite3.connect(self.path) as db:
            db.execute("""INSERT INTO account_wallet_links
                (firebase_uid,source_ref,verified_at,status)
                VALUES(?,?,?,?)""",('alice','legacy-proof-01',1000,'active'))
            db.execute("""INSERT INTO account_wallet_ledger
                (reference,firebase_uid,coin_delta,diamond_delta,kind,created_at)
                VALUES(?,?,?,?,?,?)""",('import-01','alice',400,70,'verified_import',1000))
            db.execute("""INSERT INTO account_wallet_ledger
                (reference,firebase_uid,coin_delta,diamond_delta,kind,created_at)
                VALUES(?,?,?,?,?,?)""",('gift-01','alice',-25,0,'gift',1001))
        mine=self.client.get('/sovera/account/wallet',headers=self.a).json()
        self.assertEqual((mine['coins'],mine['diamonds']),('375','70'))
        self.assertTrue(mine['verified'])
        self.assertFalse(mine['canSpend']) # no trusted betting settlement yet
        stranger=self.client.get('/sovera/account/wallet',headers=self.b).json()
        self.assertIsNone(stranger['coins'])
        self.assertEqual(stranger['status'],'not_migrated')
        history=self.client.get('/sovera/account/wallet/history',headers=self.a).json()['entries']
        self.assertEqual([r['reference'] for r in history],['gift-01','import-01'])
        self.assertEqual(self.client.get('/sovera/account/wallet/history',
            headers=self.b).json()['entries'],[])
        with sqlite3.connect(self.path) as db:
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("""INSERT INTO account_wallet_links VALUES(?,?,?,?)""",
                    ('bob','legacy-proof-01',1000,'active'))

    def test_paginated_history_same_timestamp_is_private_and_complete(self):
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_wallet_links VALUES(?,?,?,?)",
                ('alice','pagination-proof',1000,'active'))
            db.executemany("INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)",
                [(f'page-{i:03d}','alice',1,0,'recharge',1000) for i in range(37)])
        seen=[]
        params={'limit':10}
        while True:
            response=self.client.get('/sovera/account/wallet/history',
                headers=self.a,params=params)
            self.assertEqual(response.status_code,200)
            page=response.json()
            seen.extend(row['reference'] for row in page['entries'])
            if not page['has_more']:break
            last=page['entries'][-1]
            params.update(before_time=last['created_at'],before_ref=last['reference'])
        self.assertEqual(len(seen),37)
        self.assertEqual(len(set(seen)),37)
        self.assertEqual(seen,sorted(seen,reverse=True))
        self.assertEqual(self.client.get('/sovera/account/wallet/history',
            headers=self.b,params={'limit':10}).json()['entries'],[])
        self.assertEqual(self.client.get('/sovera/account/wallet/history',
            headers=self.a,params={'before_time':1000}).status_code,400)
        self.assertEqual(self.client.get('/sovera/account/wallet/history',
            headers=self.a,params={'limit':101}).status_code,422)

    def test_even_env_flags_cannot_enable_unreconciled_coin_game(self):
        from server.accounts.app import ProfileInput
        Profiles(self.path).save('alice',ProfileInput(
            display_name='Alice',country='BD',bio=''))
        env={'SOVERA_GREEDY_ENABLED':'1','SOVERA_GREEDY_WALLET_VERIFIED':'1',
            'SOVERA_GREEDY_JWT_SECRET':'s'*44,
            'SOVERA_GREEDY_PUBLIC_URL':'https://voice.soverixnet.com/greedy/'}
        with patch.dict(os.environ,env,clear=True):
            r=self.client.post('/sovera/account/greedy/access',headers=self.a)
        self.assertEqual(r.status_code,503)
        self.assertNotIn('token',r.json())

    def test_exchange_is_atomic_private_idempotent_and_uses_fixed_rate(self):
        from .wallet import ExchangeInput
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_wallet_links VALUES('alice','exchange-test',1000,'active')")
            db.execute("INSERT INTO account_wallet_ledger VALUES('exchange-opening','alice',20,500,'verified_import',1000)")
        request=ExchangeInput(diamonds=300,request_id=uuid.uuid4())
        with ThreadPoolExecutor(max_workers=4) as pool:
            results=list(pool.map(lambda _:self.wallet.exchange('alice',request),range(4)))
        self.assertTrue(all(r==results[0] for r in results))
        self.assertEqual(results[0]['coins_received'],'210')
        self.assertEqual((self.wallet.state('alice')['coins'],self.wallet.state('alice')['diamonds']),('230','200'))
        payload={'diamonds':300,'request_id':str(request.request_id)}
        url='/sovera/account/wallet/exchange'
        self.assertEqual(self.client.post(url,json=payload).status_code,401)
        self.assertEqual(self.client.post(url,headers=self.b,json=payload).status_code,409)
        self.assertEqual(self.client.post(url,headers=self.a,json={**payload,'diamonds':200}).status_code,409)
        self.assertEqual(self.client.post(url,headers=self.a,json={**payload,'uid':'bob'}).status_code,422)
        self.assertEqual(self.client.post(url,headers=self.a,json={'diamonds':True,'request_id':str(uuid.uuid4())}).status_code,422)
        self.assertEqual(self.client.post(url,headers=self.a,json={'diamonds':150,'request_id':str(uuid.uuid4())}).status_code,400)
        self.assertEqual(self.client.post(url,headers=self.a,json={'diamonds':300,'request_id':str(uuid.uuid4())}).status_code,409)
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE account_wallet_links SET status='frozen' WHERE firebase_uid='alice'")
        self.assertEqual(self.client.post(url,headers=self.a,json={'diamonds':100,'request_id':str(uuid.uuid4())}).status_code,409)

    def test_ledger_reconciliation_anomaly_fails_closed(self):
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_wallet_links VALUES(?,?,?,?)",
                       ('alice','ledger-test-1',1000,'frozen'))
            db.execute("""INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)""",
                       ('overdraw','alice',-10,0,'admin_adjust',1001))
        response=self.client.get('/sovera/account/wallet',headers=self.a)
        self.assertEqual(response.status_code,503)
        self.assertNotIn('coins',response.json())

if __name__=='__main__':unittest.main()
