import os
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from fastapi.testclient import TestClient
from server.accounts.app import Profiles,create_app
from server.accounts.wallet import WalletStore

class AutoWalletTests(unittest.TestCase):
    def test_automatic_real_zero_wallet_no_reset_and_authenticated_game(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'db.sqlite3'
            async def verify(token):
                if token not in ('new','old'):raise ValueError()
                return token
            client=TestClient(create_app(Profiles(path),verify))
            env={'SOVERA_AUTO_WALLETS':'1','SOVERA_GREEDY_ENABLED':'1','SOVERA_GREEDY_WALLET_VERIFIED':'1','SOVERA_GREEDY_WALLET_SECRET':'a'*40,'SOVERA_GREEDY_JWT_SECRET':'b'*40,'SOVERA_GREEDY_PUBLIC_URL':'https://voice.soverixnet.com/greedy/'}
            with patch.dict(os.environ,env):
                self.assertEqual(client.post('/sovera/account/greedy/access').status_code,401)
                auth={'Authorization':'Bearer new'}
                response=client.post('/sovera/account/greedy/access',headers=auth)
                self.assertEqual(response.status_code,200)
                wallet=client.get('/sovera/account/wallet',headers=auth).json()
                self.assertEqual(wallet['coins'],'0');self.assertTrue(wallet['canSpend'])
                store=WalletStore(path)
                with ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(store.provision,['new']*8))
                with sqlite3.connect(path) as db:
                    self.assertEqual(db.execute("SELECT count(*) FROM account_wallet_links WHERE firebase_uid='new'").fetchone()[0],1)
                    db.execute("INSERT INTO account_wallet_ledger VALUES('recharge-1','new',700,0,'recharge',1)")
                store.provision('new');self.assertEqual(store.state('new')['coins'],'700')
                with sqlite3.connect(path) as db:db.execute("UPDATE account_wallet_links SET status='frozen' WHERE firebase_uid='new'")
                store.provision('new');self.assertEqual(store.state('new')['status'],'frozen')
                self.assertEqual(client.post('/sovera/account/greedy/access',headers=auth).status_code,503)
