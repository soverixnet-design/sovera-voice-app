"""Same Food Wheel game/clock/result for every signed-in user, not 1v1."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, ProfileInput, create_app
from server.accounts.food_wheel import FoodWheel, FoodChoice

class WheelTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/'wheel.sqlite3'
        store=Profiles(self.path)
        self.names=('alice','bob','eve','dan','frank','mona')
        for uid in self.names:
            store.save(uid,ProfileInput(display_name='Name '+uid,country='BD',bio=''))
        self.now=[1000.]
        self.wheel=FoodWheel(self.path,clock=lambda:self.now[0],draw=lambda:0)

    def test_six_players_one_round_one_server_winner_and_bonus(self):
        users=self.names
        state=self.wheel.state('alice')
        self.assertEqual(state['phase'],'bet')
        self.assertEqual(state['round'],1)
        self.assertEqual(state['endsAt'],1020000)
        self.assertTrue(state['isDemo'])
        self.assertFalse(state['realCoinsEnabled'])
        self.assertIsNone(state['result'])
        for uid,item in zip(users,('chicken','fish','chicken','hotdog','chicken','steak')):
            result=self.wheel.choose(uid,FoodChoice(round=1,item=item))
            self.assertEqual(result['round'],1)
        self.assertEqual(self.wheel.state('eve')['players'],6)
        self.now[0]=1020.3
        views=[self.wheel.state(u) for u in users]
        self.assertTrue(all(v['phase']=='spin' for v in views))
        self.assertTrue(all(v['result']=='chicken' for v in views))
        self.assertTrue(all(v['visualIndex']==0 for v in views))
        self.assertTrue(all(v['endsAt']==1025000 for v in views))
        self.assertTrue(all(v['winnerCount']==3 for v in views))
        self.assertEqual([x['uid'] for x in views[0]['winners']],['alice','eve','frank'])
        self.assertTrue(views[0]['myWin'])
        self.assertFalse(views[1]['myWin'])
        self.now[0]=1025.1
        self.assertEqual(self.wheel.state('eve')['phase'],'result')
        self.assertEqual(self.wheel.state('eve')['endsAt'],1030000)
        self.now[0]=1030
        next_round=self.wheel.state('bob')
        self.assertEqual(next_round['round'],2)
        self.assertEqual(next_round['history'][0]['round'],1)
        self.assertEqual(next_round['history'][0]['result'],'chicken')
        fresh=FoodWheel(self.path,clock=lambda:self.now[0],draw=lambda:999)
        self.assertEqual(fresh.state('dan')['history'][0]['result'],'chicken')
        self.assertEqual(fresh.state('dan')['round'],2)

    def test_bonus_salad_uses_same_stored_visual_and_same_real_winners(self):
        self.wheel.draw=lambda:926 # salad starts at 926
        self.wheel.visual=lambda options:options[1]
        self.wheel.state('alice')
        self.wheel.choose('alice',FoodChoice(round=1,item='grapes'))
        self.wheel.choose('bob',FoodChoice(round=1,item='lettuce'))
        self.wheel.choose('eve',FoodChoice(round=1,item='fish'))
        self.now[0]=1020
        state=self.wheel.state('alice')
        self.assertEqual(state['result'],'salad')
        self.assertEqual(state['visualIndex'],5)
        self.assertEqual(state['winnerCount'],2)
        self.assertTrue(self.wheel.state('bob')['myWin'])
        self.assertFalse(self.wheel.state('eve')['myWin'])

    def test_duplicate_locked_late_and_spoofed_picks(self):
        self.wheel.state('alice')
        self.wheel.choose('alice',FoodChoice(round=1,item='chicken'))
        self.assertEqual(self.wheel.choose('alice',FoodChoice(round=1,item='chicken'))['players'],1)
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as changed:
            self.wheel.choose('alice',FoodChoice(round=1,item='fish'))
        self.assertEqual(changed.exception.status_code,409)
        self.now[0]=1020
        with self.assertRaises(HTTPException) as late:
            self.wheel.choose('bob',FoodChoice(round=1,item='steak'))
        self.assertEqual(late.exception.status_code,409)
        async def verify(token):
            if token not in self.names: raise ValueError('bad token')
            return token
        client=TestClient(create_app(Profiles(self.path),verify))
        endpoint='/sovera/account/wheel'
        self.assertEqual(client.get(endpoint+'/state').status_code,401)
        self.assertEqual(client.get(endpoint+'/state',headers={'Authorization':'Bearer fake'}).status_code,401)
        header={'Authorization':'Bearer dan'}
        self.assertEqual(client.get(endpoint+'/state',headers=header).status_code,200)
        for extra in ({'uid':'alice'},{'amount':500},{'coins':10000},{'result':'chicken'},{'diamond':1}):
            body={'round':client.get(endpoint+'/state',headers=header).json()['round'],
                  'item':'fish',**extra}
            self.assertEqual(client.post(endpoint+'/pick',json=body,headers=header).status_code,422)
        ok=client.post(endpoint+'/pick',json={'round':2,'item':'fish'},headers=header)
        self.assertEqual(ok.status_code,200)
        self.assertEqual(ok.json()['myPick'],'fish')
        other=client.get(endpoint+'/state',headers={'Authorization':'Bearer eve'}).json()
        self.assertIsNone(other['myPick'])
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM account_food_wheel_picks WHERE user_id=?',('dan',)).fetchone()[0],1)

if __name__=='__main__':
    unittest.main()
