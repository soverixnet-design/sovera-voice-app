import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path
from fastapi import HTTPException
from server.accounts.app import Profiles,create_app
from server.accounts.messaging import Messaging,SellerInput,MessageInput,NoticeInput
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
