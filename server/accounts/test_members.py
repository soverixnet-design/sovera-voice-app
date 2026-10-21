import sqlite3
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from fastapi import HTTPException
from .test_control import ControlTests
from .members import Members,Adjustment,BanInput,AgencyInput

class MemberTests(unittest.TestCase):
    setUp=ControlTests.setUp
    def test_ids_are_unique_persistent_and_searchable(self):
        first=self.profiles.get('owner')['public_id']
        self.assertTrue(first.isdigit())
        with ThreadPoolExecutor(max_workers=4) as pool:values=list(pool.map(lambda _:self.profiles.get('owner')['public_id'],range(8)))
        self.assertEqual(set(values),{first})
        self.assertNotEqual(first,self.profiles.get('support')['public_id'])
        self.assertEqual(self.control.users('owner',first)[0]['uid'],'owner')
    def test_real_follows_visits_and_public_privacy(self):
        s=Members(self.path)
        s.follow_user('owner','alice',True);s.follow_user('owner','alice',True)
        s.follow_user('alice','owner',True)
        s.profile('owner','alice',True);s.profile('owner','alice',True)
        p=s.profile('alice','alice')
        self.assertEqual((p['followers'],p['following'],p['friends'],p['visitors']),(1,1,1,1))
        self.assertNotIn('coins',p);self.assertNotIn('birthday',p)
        s.follow_user('owner','alice',False)
        self.assertEqual(s.profile('alice','alice')['followers'],0)
        s.block('alice','owner',True)
        with self.assertRaises(HTTPException):s.follow_user('owner','alice',True)
    def test_coin_adjustment_no_overdraft_and_retry_safety(self):
        s=Members(self.path);data=Adjustment(amount=-7,note='Correction',request_id=uuid.uuid4())
        with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(lambda _:s.adjust('owner','alice',data),range(2)))
        with sqlite3.connect(self.path) as db:self.assertEqual(db.execute("SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid='alice'").fetchone()[0],3)
        with self.assertRaises(HTTPException):s.adjust('owner','alice',Adjustment(amount=-4,note='Too much',request_id=uuid.uuid4()))
        with self.assertRaises(HTTPException):s.adjust('agent','alice',Adjustment(amount=10,note='No access',request_id=uuid.uuid4()))
        self.assertEqual(s.history('owner','alice')['ledger'][0]['coin_delta'],-7)
    def test_ban_enforced_on_authenticated_api_without_deleting_wallet(self):
        s=Members(self.path)
        with self.assertRaises(HTTPException):s.ban('agent','alice',BanInput(enabled=True))
        s.ban('owner','alice',BanInput(enabled=True,reason='Review'))
        auth={'Authorization':'Bearer alice'}
        self.assertEqual(self.client.get('/sovera/account',headers=auth).status_code,403)
        self.assertEqual(self.client.post('/sovera/account/greedy/access',headers=auth).status_code,403)
        s.ban('owner','alice',BanInput(enabled=False))
        self.assertEqual(self.client.get('/sovera/account',headers=auth).status_code,200)
        with self.assertRaises(HTTPException):s.ban('owner','owner',BanInput(enabled=True))
    def test_agency_manager_approval_is_not_global_admin_or_wallet_access(self):
        s=Members(self.path);key=uuid.uuid4()
        s.agency_save('owner',AgencyInput(id=key,name='Sovera Team',manager='agent'))
        s.agency_join('alice',str(key))
        self.assertEqual(s.agency_roster('agent',str(key))[0]['status'],'pending')
        with self.assertRaises(HTTPException):s.agency_join('support',str(key),'alice')
        s.agency_join('agent',str(key),'alice')
        self.assertEqual(s.agencies('alice')[0]['membership'],'active')
        self.assertIsNone(s.role('alice'))
        s.agency_join('agent',str(key),'alice',False)
        self.assertIsNone(s.agencies('alice')[0]['membership'])
