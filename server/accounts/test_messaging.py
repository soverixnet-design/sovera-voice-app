import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path
from fastapi import HTTPException
from server.accounts.app import Profiles,create_app
from server.accounts.messaging import Messaging,SellerInput,MessageInput,NoticeInput,SellerTransferInput,ReadInput,SellerPackageInput
from server.accounts.control import Control,RechargeInput
from server.accounts.community import Publication

class MessagingTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory();self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/'db.sqlite3'
        profiles=Profiles(self.path)
        create_app(profiles,lambda x:x)
        self.service=Messaging(self.path)
        with sqlite3.connect(self.path) as db:
            for uid in ('owner','alice','bob','stranger'):
                db.execute('INSERT INTO account_profiles(firebase_uid,display_name,country,bio,avatar_url,updated_at) VALUES(?,?,?,?,?,?)',(uid,uid,'BD','',None,1))
            db.execute("INSERT INTO account_staff VALUES('owner','owner')")
            db.execute("INSERT INTO account_wallet_links VALUES('alice','old',1,'active')")
            db.execute("INSERT INTO account_wallet_ledger VALUES('initial','alice',100,0,'verified_import',1)")
    def test_approved_seller_real_balance_and_private_chat(self):
        self.assertEqual(self.service.sellers('bob'),[])
        with self.assertRaises(HTTPException):self.service.seller_save('bob',SellerInput(target_uid='alice',enabled=True))
        data=SellerInput(target_uid='alice',enabled=True)
        self.service.seller_save('owner',data);self.service.seller_save('owner',data)
        self.assertEqual(len(self.service.official_inbox('alice')),1)
        self.assertEqual(self.service.sellers('bob')[0]['coins'],'100')
        self.assertIsNone(self.service.role('alice'))
        msg=MessageInput(text='Hello seller',request_id=uuid.uuid4())
        self.service.send('bob','alice',msg);self.service.send('bob','alice',msg)
        self.assertEqual(len(self.service.thread('alice','bob')['items']),1)
        self.assertEqual(self.service.thread('stranger','bob')['items'],[])
        self.assertEqual(self.service.threads('alice')[0]['uid'],'bob')
        self.service.block('alice','bob',True)
        self.assertEqual(self.service.sellers('bob'),[])
        with self.assertRaises(HTTPException):self.service.send('bob','alice',MessageInput(text='blocked',request_id=uuid.uuid4()))
    def test_recharge_receipt_private_atomic_and_retry_safe(self):
        data=RechargeInput(target_uid='alice',amount=70,request_id=uuid.uuid4(),note='Thanks')
        control=Control(self.path)
        control.recharge('owner',data);control.recharge('owner',data)
        rows=self.service.official_inbox('alice')
        self.assertEqual(len(rows),1);self.assertIn('170',rows[0]['text'])
        self.assertEqual(self.service.official_inbox('bob'),[])
        self.service.publish('owner',Publication(title='Update',text='New app',section='notices',request_id=uuid.uuid4()))
        self.assertEqual(len(self.service.official_inbox('bob')),1)
        note=NoticeInput(target_uid='bob',title='Private',text='Only Bob',request_id=uuid.uuid4())
        self.service.notice('owner',note);self.service.notice('owner',note)
        self.assertEqual(len(self.service.official_inbox('bob')),2)
        self.assertFalse(any(r['text']=='Only Bob' for r in self.service.official_inbox('alice')))
        with self.assertRaises(HTTPException):self.service.notice('owner',note.model_copy(update={'text':'Changed'}))

    def test_seller_transfer_conserves_balance_and_retries(self):
        self.service.seller_save('owner',SellerInput(target_uid='alice',enabled=True))
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_wallet_links VALUES('bob','bob-native',1,'active')")
        data=SellerTransferInput(target_uid='bob',coins=70,request_id=uuid.uuid4())
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda _:self.service.transfer('alice',data),range(2)))
        self.assertTrue(all(r['saved'] for r in results))
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute('SELECT SUM(coin_delta) FROM account_wallet_ledger').fetchone()[0],100)
            self.assertEqual(db.execute("SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid='alice'").fetchone()[0],30)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM account_seller_transfers').fetchone()[0],1)
        self.assertEqual(len(self.service.official_inbox('bob')),1)
        with self.assertRaises(HTTPException):self.service.transfer('alice',data.model_copy(update={'coins':1}))
        with self.assertRaises(HTTPException):self.service.transfer('alice',data.model_copy(update={'request_id':uuid.uuid4()}))
        self.service.seller_save('owner',SellerInput(target_uid='alice',enabled=False))
        with self.assertRaises(HTTPException):self.service.transfer('alice',data.model_copy(update={'coins':1,'request_id':uuid.uuid4()}))

    def test_transfer_denies_frozen_and_non_seller(self):
        data=SellerTransferInput(target_uid='alice',coins=1,request_id=uuid.uuid4())
        with self.assertRaises(HTTPException):self.service.transfer('bob',data)
        self.service.seller_save('owner',SellerInput(target_uid='alice',enabled=True))
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_wallet_links VALUES('bob','bob-native',1,'frozen')")
        with self.assertRaises(HTTPException):self.service.transfer('alice',data.model_copy(update={'target_uid':'bob'}))
        with sqlite3.connect(self.path) as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM account_seller_transfers').fetchone()[0],0)

    def test_read_receipts_only_mark_visible_messages(self):
        one=self.service.send('bob','alice',MessageInput(text='First',request_id=uuid.uuid4()))['id']
        self.assertEqual(self.service.unread('alice')['messages'],1)
        self.assertEqual(self.service.threads('alice')[0]['unread'],1)
        self.service.mark_read('stranger',ReadInput(ids=['dm:'+str(one)]))
        self.assertEqual(self.service.unread('alice')['messages'],1)
        self.service.send('bob','alice',MessageInput(text='Later',request_id=uuid.uuid4()))
        self.service.mark_read('alice',ReadInput(ids=['dm:'+str(one)]))
        self.assertEqual(self.service.unread('alice')['messages'],1)
        self.service.notice('owner',NoticeInput(target_uid='alice',title='Receipt',text='Private',request_id=uuid.uuid4()))
        self.service.publish('owner',Publication(title='News',text='Everyone',section='notices',request_id=uuid.uuid4()))
        ids=[r['id'] for r in self.service.official_inbox('alice')]
        self.assertEqual(self.service.unread('alice')['official'],2)
        self.service.mark_read('alice',ReadInput(ids=ids))
        self.assertEqual(self.service.unread('alice')['official'],0)
        self.assertEqual(self.service.unread('bob')['official'],1)
        self.service.block('alice','bob',True)
        self.assertEqual(self.service.unread('alice')['messages'],0)

    def test_package_validates_asset_kind_and_approval_equips_once(self):
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_catalog VALUES('seller-frame','frame','Seller','media',0,1,0,1,0,0,1)")
        self.service.package('owner',SellerPackageInput(frame='seller-frame'))
        with self.assertRaises(HTTPException):self.service.package('bob',SellerPackageInput())
        with self.assertRaises(HTTPException):self.service.package('owner',SellerPackageInput(tag='seller-frame'))
        self.service.seller_save('owner',SellerInput(target_uid='alice',enabled=True))
        self.service.seller_save('owner',SellerInput(target_uid='alice',enabled=True))
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM account_asset_ownership WHERE uid='alice'").fetchone()[0],1)
            self.assertEqual(db.execute("SELECT item_id FROM account_asset_equipped WHERE uid='alice' AND kind='frame'").fetchone()[0],'seller-frame')
        from server.accounts.members import Members
        self.assertTrue(Members(self.path).profile('alice','alice')['is_coin_seller'])
        self.service.seller_save('owner',SellerInput(target_uid='alice',enabled=False))
        self.assertFalse(Members(self.path).profile('alice','alice')['is_coin_seller'])
