"""Shared game results: all clients see the same round, result and real winners."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from fastapi import HTTPException
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, ProfileInput, create_app
from server.accounts.global_games import ColorPick, GlobalColors

class GlobalColorsTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/'game.sqlite3'
        store=Profiles(self.path)
        for uid,name in [('alice','Shakil'),('bob','Friend'),('eve','Guest')]:
            store.save(uid,ProfileInput(display_name=name,country='BD',bio=''))
        self.now=[1000.]
        self.game=GlobalColors(self.path,clock=lambda:self.now[0],draw=lambda:'red')

    def test_one_global_clock_result_and_winners_on_every_device(self):
        a=self.game.state('alice')
        b=self.game.state('bob')
        self.assertEqual(a['round'],b['round'])
        self.assertEqual(a['phase_ends_ms'],b['phase_ends_ms'])
        self.assertEqual(a['phase'],'pick')
        self.assertEqual(a['result'],None)
        self.assertEqual(a['server_now_ms'],1000000)
        for uid,choice in [('alice','red'),('bob','blue'),('eve','red')]:
            self.game.pick(uid,ColorPick(round=1,choice=choice))
        self.assertEqual(self.game.state('bob')['pick_count'],3)
        self.now[0]=1024.9
        self.assertEqual(self.game.state('alice')['result'],None)
        self.now[0]=1025.1
        views=[self.game.state(uid) for uid in ['alice','bob','eve']]
        for view in views:
            self.assertEqual(view['round'],1)
            self.assertEqual(view['phase'],'reveal')
            self.assertEqual(view['result'],'red')
            self.assertEqual(view['winner_count'],2)
            self.assertEqual({w['uid'] for w in view['winners']},{'alice','eve'})
            self.assertEqual(view['history'][0]['result'],'red')
            self.assertEqual(view['history'][0]['winner_count'],2)
        self.assertTrue(views[0]['my_win'])
        self.assertFalse(views[1]['my_win'])
        self.now[0]=1036
        self.assertEqual(self.game.state('bob')['phase'],'break')
        self.now[0]=1040.1
        after=self.game.state('eve')
        self.assertEqual(after['round'],2)
        self.assertEqual(after['phase'],'pick')
        self.assertIsNone(after['result'])
        self.assertEqual(after['history'][0]['round'],1)
        self.assertEqual(after['history'][0]['winner_count'],2)
        restart=GlobalColors(self.path,clock=lambda:self.now[0],draw=lambda:'gold')
        self.assertEqual(restart.state('bob')['round'],2)
        self.assertEqual(restart.state('bob')['history'][0]['result'],'red')

    def test_idempotency_changing_picks_and_stale_rounds(self):
        before=self.game.pick('alice',ColorPick(round=1,choice='red'))
        self.assertEqual(before['my_pick'],'red')
        self.assertEqual(self.game.pick('alice',ColorPick(round=1,choice='red'))['pick_count'],1)
        with self.assertRaises(HTTPException) as rejected:
            self.game.pick('alice',ColorPick(round=1,choice='blue'))
        self.assertEqual(rejected.exception.status_code,409)
        self.now[0]=1027
        with self.assertRaises(HTTPException) as closed:
            self.game.pick('bob',ColorPick(round=1,choice='green'))
        self.assertEqual(closed.exception.status_code,409)
        self.now[0]=1040
        after=self.game.pick('alice',ColorPick(round=1,choice='red'))
        self.assertEqual(after['round'],2)
        self.assertIsNone(after['my_pick'])
        with sqlite3.connect(self.path) as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM account_global_color_picks').fetchone()[0],1)
            self.assertEqual(conn.execute('SELECT count(*) FROM account_global_color_rounds').fetchone()[0],2)

    def test_draw_is_once_after_close_and_winners_may_be_zero(self):
        draws=[]
        self.game.draw=lambda: draws.append('gold') or 'gold'
        self.game.pick('alice',ColorPick(round=1,choice='red'))
        self.now[0]=1030
        self.assertEqual(self.game.state('alice')['result'],'gold')
        self.assertEqual(self.game.state('bob')['winner_count'],0)
        self.assertEqual(self.game.state('eve')['winners'],[])
        self.assertEqual(draws,['gold'])

    def test_http_authentication_and_no_coins_or_user_spoofing(self):
        async def verify(token):
            if token not in ('alice','bob'):
                raise ValueError('Invalid login')
            return token
        client=TestClient(create_app(Profiles(self.path),verify))
        uri='/sovera/account/games/colors'
        headers={'Authorization':'Bearer alice'}
        self.assertEqual(client.get(uri).status_code,401)
        self.assertEqual(client.get(uri,headers={'Authorization':'Bearer forged'}).status_code,401)
        s=client.get(uri,headers=headers).json()
        self.assertEqual(s['round'],client.get(uri,headers={'Authorization':'Bearer bob'}).json()['round'])
        self.assertTrue(client.get('/sovera/account/health').json()['global_color_game'])
        self.assertFalse(client.get('/sovera/account/health').json()['wallet'])
        bad=client.post(uri+'/pick',json={'round':s['round'],'choice':'red','coins':999999},headers=headers)
        self.assertEqual(bad.status_code,422)
        forged=client.post(uri+'/pick',json={'round':s['round'],'choice':'red','uid':'bob'},headers=headers)
        self.assertEqual(forged.status_code,422)
        allowed=client.post(uri+'/pick',json={'round':s['round'],'choice':'red'},headers=headers)
        self.assertEqual(allowed.status_code,200)
        self.assertEqual(allowed.json()['my_pick'],'red')
        self.assertEqual(client.get(uri,headers={'Authorization':'Bearer bob'}).json()['my_pick'],None)
        with sqlite3.connect(self.path) as conn:
            self.assertFalse(any('wallet' in row[0] for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%wallet%'")))

if __name__=='__main__':
    unittest.main()
