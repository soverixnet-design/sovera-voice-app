import copy
import hashlib
import json
import sqlite3
import unittest
from concurrent.futures import ThreadPoolExecutor
from . import test_control
from .import_legacy_wallet import import_wallet,validate,ImportRejected
from .wallet import WalletStore

def manifest(**changes):
    data={'version':1,'source_project':'rfrmcmeyamndghtiheci',
      'legacy_user_id':'00000000-0000-4000-8000-000000000123',
      'snapshot_id':'00000000-0000-4000-8000-000000000456',
      'public_id':'10000099','wallet_status':'frozen','frozen_at':'2026-01-02T00:00:00+00:00',
      'coins':'120','diamonds':'5','entries':[
        {'id':'00000000-0000-4000-8000-000000000789','user_id':'00000000-0000-4000-8000-000000000123',
         'coin_delta':120,'diamond_delta':5,'created_at':'2026-01-01T00:00:00+00:00'}]}
    data.update(changes)
    raw=json.dumps(data,sort_keys=True)
    return {'payload':raw,'sha256':hashlib.sha256(raw.encode()).hexdigest()}

class LegacyWalletTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    def test_preview_then_exact_import_restores_public_id_and_wallet(self):
        proof=manifest()
        preview=import_wallet(self.path,proof,owner=True)
        self.assertFalse(preview['saved'])
        self.assertFalse(WalletStore(self.path).state('owner')['verified'])
        saved=import_wallet(self.path,proof,owner=True,apply=True)
        self.assertTrue(saved['saved'])
        state=WalletStore(self.path).state('owner')
        self.assertEqual((state['coins'],state['diamonds']),('120','5'))
        self.assertTrue(state['verified']);self.assertTrue(state['canPurchase']);self.assertTrue(state['canGift'])
        self.assertFalse(state['canSpend'])
        self.assertEqual(self.profiles.get('owner')['public_id'],'10000099')
        self.assertEqual([r['uid'] for r in self.control.users('owner','10000099')],['owner'])
        self.assertTrue(self.client.get('/sovera/account/health').json()['wallet'])
    def test_retry_preserves_later_recharges_and_does_not_duplicate_import(self):
        proof=manifest();import_wallet(self.path,proof,owner=True,apply=True)
        with self.control.db() as db:db.execute("INSERT INTO account_wallet_ledger VALUES('later-recharge','owner',17,0,'recharge',1800000000)")
        again=import_wallet(self.path,proof,owner=True,apply=True)
        self.assertTrue(again['duplicate']);self.assertEqual(again['coins'],'137')
        with self.control.db() as db:self.assertEqual(db.execute("SELECT COUNT(*) FROM account_wallet_ledger WHERE firebase_uid='owner' AND kind='verified_import'").fetchone()[0],1)
    def test_bad_snapshots_and_tampering_are_rejected(self):
        proof=manifest();proof['payload']+=' '
        with self.assertRaises(ImportRejected):validate(proof)
        for changes in ({'coins':'121'},{'wallet_status':'active'},{'diamonds':True}):
            with self.assertRaises(ImportRejected):validate(manifest(**changes))
        data=json.loads(manifest()['payload']);data['entries'][0]['user_id']='00000000-0000-4000-8000-000000000999'
        with self.assertRaises(ImportRejected):validate(manifest(entries=data['entries']))
        data=json.loads(manifest()['payload']);data['entries']*=2
        with self.assertRaises(ImportRejected):validate(manifest(entries=data['entries']))
    def test_existing_wallet_and_conflicting_mapping_are_not_overwritten(self):
        with self.assertRaises(ImportRejected):import_wallet(self.path,manifest(),target_uid='alice',apply=True)
        self.assertEqual(WalletStore(self.path).state('alice')['coins'],'10')
        import_wallet(self.path,manifest(),owner=True,apply=True)
        with self.assertRaises(ImportRejected):import_wallet(self.path,manifest(coins='120',public_id='10000100'),owner=True,apply=True)
        with self.assertRaises(ImportRejected):import_wallet(self.path,manifest(),target_uid='support',apply=True)
        self.assertEqual(WalletStore(self.path).state('owner')['coins'],'120')
    def test_concurrent_retries_and_frozen_local_wallet_remain_safe(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda _:import_wallet(self.path,manifest(),owner=True,apply=True),range(2)))
        self.assertEqual(sum(r['duplicate'] for r in results),1)
        with self.control.db() as db:db.execute("UPDATE account_wallet_links SET status='frozen' WHERE firebase_uid='owner'")
        import_wallet(self.path,manifest(),owner=True,apply=True)
        state=WalletStore(self.path).state('owner')
        self.assertEqual(state['status'],'frozen');self.assertFalse(state['canPurchase'])
    def test_missing_import_history_fails_reconciliation_and_zero_snapshot_is_real(self):
        import_wallet(self.path,manifest(),owner=True,apply=True)
        with self.control.db() as db:db.execute("DELETE FROM account_wallet_ledger WHERE firebase_uid='owner'")
        with self.assertRaises(ImportRejected):import_wallet(self.path,manifest(),owner=True,apply=True)
        zero=manifest(legacy_user_id='00000000-0000-4000-8000-000000000999',snapshot_id='00000000-0000-4000-8000-000000000998',public_id='10000101',coins='0',diamonds='0',entries=[])
        import_wallet(self.path,zero,target_uid='support',apply=True)
        state=WalletStore(self.path).state('support')
        self.assertTrue(state['verified']);self.assertEqual(state['coins'],'0')

if __name__=='__main__':unittest.main()
