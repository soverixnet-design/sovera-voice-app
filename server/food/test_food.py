import concurrent.futures
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from server.food.engine import Engine, Rejected, SLOTS
from server.food.app import create_app

class FoodTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.now=1000.;self.path=Path(self.tmp.name)/'food.db'
        self.e=Engine(self.path,lambda:self.now,can_autoplay=lambda uid:True)
        self.e.credit('alice',10000,'opening:alice')
        self.e.state('alice')
    def test_double_click_and_conflicting_key(self):
        with concurrent.futures.ThreadPoolExecutor(8) as pool:
            results=list(pool.map(lambda _:self.e.bet('alice',1,'chk',50,'same-key'),range(8)))
        self.assertTrue(all(r['balance']==9950 for r in results))
        with self.assertRaises(Rejected):self.e.bet('alice',1,'fish',50,'same-key')
    def test_overdraft_race(self):
        self.e.credit('bob',50,'opening:bob')
        def bet(i):
            try:self.e.bet('bob',1,'chk',50,str(i));return True
            except Rejected:return False
        with concurrent.futures.ThreadPoolExecutor(8) as pool:
            self.assertEqual(sum(pool.map(bet,range(8))),1)
        self.assertEqual(self.e.state('bob')['balance'],0)
    def test_close_settle_restart_and_replay(self):
        for slot in SLOTS:self.e.bet('alice',1,slot,50,'bet-'+slot)
        self.assertIsNone(self.e.state('alice')['seed'])
        self.now=1030
        s=self.e.state('alice');self.assertEqual(s['phase'],'spin')
        self.assertEqual(s['myWin'],50*SLOTS[s['slot']])
        with self.assertRaises(Rejected):self.e.bet('alice',1,'chk',50,'late')
        other=Engine(self.path,lambda:self.now)
        self.assertEqual(other.state('alice')['balance'],s['balance'])
        self.assertEqual(other.state('alice')['slot'],s['slot'])
        self.assertEqual(len(other.state('alice')['history']),1)
    def test_chip_validation(self):
        for amount in (-50,0,True,51,10000000000):
            with self.assertRaises(Rejected):self.e.bet('alice',1,'chk',amount,'bad')
    def test_autoplay_stops_without_funds(self):
        self.e.credit('bob',50,'opening:bob');self.e.autoplay('bob','chk',50,3)
        self.now=1043; self.e.state('bob')
        self.assertEqual(self.e.state('bob')['myBet'],50)
        self.e.autoplay('bob','fish',10000,3)
        self.now=1086;self.e.state('bob')
        self.assertEqual(self.e.state('bob')['myBet'],0)
    def test_config_snapshot_and_rtp(self):
        self.assertAlmostEqual(self.e.rtp(SLOTS),450/463)
        config={k:5 for k in SLOTS}
        self.e.configure(config)
        self.assertEqual(self.e.state('alice')['multipliers'],SLOTS)
        self.now=1043
        self.assertEqual(self.e.state('alice')['multipliers'],config)
    def test_autoplay_disabled_by_default(self):
        other=Engine(self.path,lambda:self.now)
        with self.assertRaises(Rejected):other.autoplay('alice','chk',50,1)
    def test_autoplay_rechecks_account_permission(self):
        self.e.autoplay('alice','chk',50,3)
        self.e.can_autoplay=lambda uid:False
        self.now=1043
        self.assertEqual(self.e.state('alice')['myBet'],0)
    def test_api_auth_and_owner(self):
        from fastapi import HTTPException
        async def verify(token):
            if token!='valid':raise HTTPException(401,'Invalid session')
            return 'alice'
        async def owner(uid):return False
        app=create_app(self.e,verify,owner)
        with TestClient(app) as client:
            self.assertEqual(client.get('/food/state').status_code,401)
            headers={'Authorization':'Bearer valid','Idempotency-Key':'api-bet'}
            self.assertEqual(client.post('/food/bet',headers=headers,json={'round':1,'slot':'chk','amount':50}).status_code,200)
            self.assertEqual(client.put('/food/admin/config',headers=headers,json=SLOTS).status_code,403)
            self.assertEqual(client.post('/food/bet',headers=headers,json={'round':1,'slot':'chk','amount':50,'user_id':'victim'}).status_code,422)
            with client.websocket_connect('/food/events') as ws:
                ws.send_json({'authorization':'Bearer valid'})
                state=ws.receive_json();self.assertEqual(state['event'],'state')
                self.assertEqual(state['data']['balance'],9950)

if __name__=='__main__':unittest.main()
