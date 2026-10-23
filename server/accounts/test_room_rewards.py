import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from fastapi import HTTPException
from . import test_control
from .app import ProfileInput
from .rooms import Rooms,RoomInput
from .room_rewards import RoomRewards,Policy,week_start,WEEK

class RoomRewardTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    def prepare(self,count=5):
        self.service=RoomRewards(self.path)
        self.start=week_start(time.time())-WEEK
        self.room=Rooms(self.path).save('owner',RoomInput(name='Gift rewards'))['id']
        self.people=['giver'+str(i) for i in range(count)]
        for uid in self.people:self.profiles.save(uid,ProfileInput(display_name=uid,country='BD',bio=''))
        with self.control.db() as db:
            db.execute('DELETE FROM account_room_reward_policy')
            db.execute('INSERT INTO account_room_reward_policy VALUES(?,?)',(self.start,Policy().model_dump_json()))
            for uid in ['owner']+self.people:
                db.execute("INSERT OR IGNORE INTO account_wallet_links VALUES(?,?,1,'active')",(uid,'test-'+uid))
                db.execute("INSERT INTO account_wallet_ledger VALUES(?,?,1000000,0,'verified_import',1)",('opening-'+uid,uid))
            for i,uid in enumerate(self.people):
                req='gift-'+str(i)
                db.execute("INSERT INTO account_wallet_ledger VALUES(?,?,?,0,'gift',?)",('catalog:'+req,uid,-20000,self.start+10))
                db.execute('INSERT INTO account_gift_receipts VALUES(?,?,?,?,?,?,?,?)',(req,uid,'owner','gift','Gift',20000,self.room,self.start+10))
    def test_one_hundred_thousand_gifts_pays_owner_five_thousand_and_five_one_thousand_once(self):
        self.prepare()
        with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(lambda _:RoomRewards(self.path).tick(),range(2)))
        self.assertEqual(sum(results),6)
        self.assertEqual(self.service.tick(),0)
        detail=self.service.detail('owner',self.room)['history'][0]
        self.assertEqual(detail['gift_coins'],'100000');self.assertEqual(detail['reward_coins'],'10000')
        payouts={p['uid']:p['coins'] for p in detail['payouts']}
        self.assertEqual(payouts['owner'],'5000');self.assertTrue(all(payouts[uid]=='1000' for uid in self.people))
        with self.control.db() as db:
            self.assertEqual(db.execute("SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE reference LIKE 'room-reward:%'").fetchone()[0],10000)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM account_official_messages WHERE title='Weekly room reward'").fetchone()[0],6)
    def test_incomplete_top_five_does_not_mint_empty_slots(self):
        self.prepare(1);self.service.tick()
        detail=self.service.detail('owner',self.room)['history'][0]
        self.assertEqual(detail['reward_coins'],'2000');self.assertEqual(detail['unallocated_coins'],'800')
        self.assertEqual(sum(int(p['coins']) for p in detail['payouts']),1200)
    def test_policy_changes_next_week_without_rewriting_settled_rewards(self):
        self.prepare();self.service.tick()
        with self.assertRaises(HTTPException):self.service.save('alice',Policy(percent=20))
        result=self.service.save('owner',Policy(percent=20))
        self.assertEqual(result['effective_at'],week_start(time.time())+WEEK)
        self.assertEqual(self.service.detail('owner',self.room)['history'][0]['reward_coins'],'10000')
    def test_unverified_receipt_and_other_rooms_never_increase_pool(self):
        self.prepare(1)
        with self.control.db() as db:db.execute('INSERT INTO account_gift_receipts VALUES(?,?,?,?,?,?,?,?)',('fake','giver0','owner','gift','Fake',1000000,self.room,self.start+10))
        self.service.tick();self.assertEqual(self.service.detail('owner',self.room)['history'][0]['gift_coins'],'20000')
    def test_inactive_wallet_stays_pending_then_receives_once_when_active(self):
        self.prepare(1)
        with self.control.db() as db:db.execute("UPDATE account_wallet_links SET status='frozen' WHERE firebase_uid='giver0'")
        self.assertEqual(self.service.tick(),1)
        with self.control.db() as db:db.execute("UPDATE account_wallet_links SET status='active' WHERE firebase_uid='giver0'")
        self.assertEqual(self.service.tick(),1);self.assertEqual(self.service.tick(),0)
