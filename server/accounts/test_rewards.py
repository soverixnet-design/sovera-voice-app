import time
import uuid
import unittest
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
from fastapi import HTTPException
from . import test_control
from .test_catalog import CatalogTests
from .catalog import Catalog,GrantInput,SelectInput,BuyInput
from .control import RechargeInput
from .rewards import Rewards,CampaignInput,Prize

class RewardTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    login=test_control.ControlTests.login
    def test_room_and_cp_rankings_sum_confirmed_gifts_in_both_directions(self):
        from .rooms import Rooms,RoomInput
        rooms=Rooms(self.path);room=rooms.save('alice',RoomInput(name='Rank room'))['id']
        now=int(time.time())
        with self.control.db() as db:
            for sender,target,amount in [('alice','agent',10),('agent','alice',20),('alice','alice',5)]:
                db.execute('INSERT INTO account_gift_receipts VALUES(?,?,?,?,?,?,?,?)',(str(uuid.uuid4()),sender,target,'gift','Rose',amount,room,now))
        rewards=Rewards(self.path)
        cp=rewards.board('alice','cp','daily')
        self.assertEqual(cp['items'][0]['score'],'30')
        self.assertEqual(cp['mine']['rank'],1)
        self.assertEqual(rewards.board('agent','cp','daily')['mine']['score'],'30')
        board=rewards.board('alice','room','daily')
        self.assertEqual(board['items'][0]['score'],'35')
        self.assertEqual(board['items'][0]['room']['id'],room)
        with self.control.db() as db:db.execute("UPDATE account_gift_receipts SET created_at=?",(now-40*86400,))
        self.assertEqual(rewards.board('alice','cp','daily')['items'],[])

    def campaign(self,category='ranking',metric='rich',items=None,coins=50):
        self.start=int(time.time())+10;self.end=self.start+100
        p=CampaignInput(id=uuid.uuid4(),title='Weekly spotlight',category=category,metric=metric,starts_at=self.start,ends_at=self.end,threshold=20,prizes=[Prize(rank=1,coins=coins,item_ids=items or [],days=7)])
        self.rewards=Rewards(self.path);self.rewards.save('owner',p);return p
    def activity(self,uid,amount,kind='gift',created=None,diamonds=0):
        with self.control.db() as db:
            db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',(str(uuid.uuid4()),uid,amount,diamonds,kind,created or self.start+1))
    def test_ranking_finalization_claim_concurrency_and_official_receipt(self):
        p=self.campaign();self.activity('alice',-30);self.activity('agent',-25)
        self.activity('support',-999,'admin_adjust')
        self.activity('support',-999,created=self.end)
        with patch('server.accounts.rewards.time.time',return_value=self.end-1):
            with self.assertRaises(HTTPException):self.rewards.claim('alice',str(p.id))
        with patch('server.accounts.rewards.time.time',return_value=self.end+1):
            listing=self.rewards.listing('alice')['items'][0]
            self.assertEqual(listing['winners'][0]['uid'],'alice');self.assertTrue(listing['eligible'])
            with ThreadPoolExecutor(max_workers=4) as pool:receipts=list(pool.map(lambda _:self.rewards.claim('alice',str(p.id)),range(4)))
            self.assertEqual(sum(not r.get('duplicate') for r in receipts),1)
            self.assertFalse(self.rewards.listing('alice')['items'][0]['eligible'])
        with self.control.db() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM account_wallet_ledger WHERE reference LIKE 'reward:%'").fetchone()[0],1)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM account_official_messages WHERE title='Reward received'").fetchone()[0],1)
    def test_recharge_receipts_only_threshold_and_no_recursive_bonus(self):
        p=self.campaign('recharge','recharge');self.activity('alice',9999,'admin_adjust')
        with patch('server.accounts.rewards.time.time',return_value=self.start+1):
            with self.assertRaises(HTTPException):self.rewards.claim('alice',str(p.id))
            self.control.recharge('owner',RechargeInput(target_uid='alice',amount=20,note='real receipt',request_id=uuid.uuid4()))
            self.assertTrue(self.rewards.listing('alice')['items'][0]['eligible'])
            self.rewards.claim('alice',str(p.id))
            self.assertTrue(self.rewards.claim('alice',str(p.id))['duplicate'])
            board=self.rewards.board('alice','recharge','monthly')
            self.assertEqual(board['items'][0]['score'],'20')
        with self.assertRaises(HTTPException):self.rewards.save('agent',p)
    def test_expiring_prizes_preserve_permanent_ownership_and_allow_purchase(self):
        setup=CatalogTests();setup.path=self.path;setup.setup_catalog();item=setup.item(price=5);permanent=setup.item('medal',price=5)
        catalog=Catalog(self.path);catalog.grant('owner',GrantInput(target_uid='alice',item_id=permanent['id']))
        p=self.campaign(items=[item['id'],permanent['id']]);self.activity('alice',-30)
        with patch('server.accounts.rewards.time.time',return_value=self.end+1):self.rewards.claim('alice',str(p.id))
        catalog.select('alice',SelectInput(kind='frame',item_id=item['id']))
        with self.control.db() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM account_reward_asset_expiry').fetchone()[0],1)
            db.execute('UPDATE account_reward_asset_expiry SET expires_at=1')
        self.assertNotIn('frame',catalog.equipped(next_db:=self.open_db(),'alice'));next_db.close()
        self.assertIn(permanent['id'],catalog.listing('alice')['owned'])
        self.assertNotIn(item['id'],catalog.listing('alice')['owned'])
        with self.assertRaises(HTTPException):catalog.select('alice',SelectInput(kind='frame',item_id=item['id']))
        # Claim Coins cover original activity; purchase gives permanent ownership.
        catalog.transact('alice',BuyInput(item_id=item['id'],expected_price=5,request_id=uuid.uuid4()))
        with self.control.db() as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM account_reward_asset_expiry').fetchone()[0],0)
    def open_db(self):
        import sqlite3
        db=sqlite3.connect(self.path);db.row_factory=sqlite3.Row;return db
    def test_published_rules_are_immutable_and_cannot_cancel_started_campaign(self):
        p=self.campaign();changed=p.model_copy(update={'threshold':999})
        with self.assertRaises(HTTPException):self.rewards.save('owner',changed)
        with patch('server.accounts.rewards.time.time',return_value=self.start):
            with self.assertRaises(HTTPException):self.rewards.cancel('owner',str(p.id))
        self.rewards.cancel('owner',str(p.id))
        with self.assertRaises(HTTPException):self.rewards.claim('alice',str(p.id))
    def test_frozen_wallet_preserves_pending_reward_and_auth_is_required(self):
        p=self.campaign();self.activity('alice',-30)
        with self.control.db() as db:db.execute("UPDATE account_wallet_links SET status='frozen' WHERE firebase_uid='alice'")
        with patch('server.accounts.rewards.time.time',return_value=self.end+1):
            with self.assertRaises(HTTPException):self.rewards.claim('alice',str(p.id))
            self.assertTrue(self.rewards.listing('alice')['items'][0]['eligible'])
            with self.control.db() as db:db.execute("UPDATE account_wallet_links SET status='active' WHERE firebase_uid='alice'")
            self.assertTrue(self.rewards.claim('alice',str(p.id))['saved'])
        self.assertEqual(self.client.get('/sovera/account/rewards').status_code,401)
        self.assertEqual(self.client.post('/sovera/account/rewards/'+str(p.id)+'/claim',headers={'Authorization':'Bearer agent'}).status_code,409)

    def test_recurring_auto_rewards_are_once_only_and_can_stop_next_period(self):
        p=self.campaign();p=p.model_copy(update={'ends_at':self.start+86400,'repeat':'daily','auto_claim':True})
        # Replace only this not-yet-started fixture with the published repeating terms.
        with self.control.db() as db:db.execute('DELETE FROM account_reward_campaigns WHERE id=?',(str(p.id),))
        self.rewards.save('owner',p);self.activity('alice',-30)
        with patch('server.accounts.rewards.time.time',return_value=p.ends_at+1):
            self.assertEqual(self.rewards.tick(),1);self.assertEqual(self.rewards.tick(),0)
            with self.control.db() as db:
                rows=db.execute('SELECT * FROM account_reward_campaigns').fetchall();self.assertEqual(len(rows),2)
                following=next(r['id'] for r in rows if r['id']!=str(p.id))
            self.rewards.stop_repeat('owner',following)
        with patch('server.accounts.rewards.time.time',return_value=p.ends_at+86401):self.rewards.tick()
        with self.control.db() as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM account_reward_campaigns').fetchone()[0],2)
