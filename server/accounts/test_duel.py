"""API tests for the room XO duel and authoritative turn validation."""
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, create_app

class DuelTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        async def verify(token):
            if token not in ('alice','bob','eve'):
                raise ValueError('Invalid session')
            return token
        self.client=TestClient(create_app(Profiles(Path(temp.name)/'account.sqlite3'),verify))
        self.people={'alice':{'Authorization':'Bearer alice'},
                     'bob':{'Authorization':'Bearer bob'},
                     'eve':{'Authorization':'Bearer eve'}}
        for uid in self.people:
            self.client.put('/sovera/account',
                json={'display_name':uid,'country':'BD','bio':''},
                headers=self.people[uid])
        data=self.client.post('/sovera/account/rooms',
            json={'name':'Duel room','seats':5},headers=self.people['alice']).json()
        self.room=data['room']['id']
        self.base='/sovera/account/rooms/'+self.room

    def heartbeat(self,uid):
        return self.client.put(self.base+'/presence',headers=self.people[uid])

    def test_turns_winner_replay_and_reset(self):
        uri=self.base+'/duel'
        self.assertEqual(self.client.get(uri).status_code,401)
        self.assertFalse(self.client.get(uri,headers=self.people['alice']).json()['ready'])
        self.assertEqual(self.client.post(uri+'/join',headers=self.people['alice']).status_code,409)
        self.heartbeat('alice')
        one=self.client.post(uri+'/join',headers=self.people['alice']).json()
        self.assertEqual(one['player_x'],'alice')
        self.assertFalse(one['ready'])
        self.heartbeat('bob')
        state=self.client.post(uri+'/join',headers=self.people['bob']).json()
        self.assertTrue(state['ready'])
        self.assertEqual(state['turn_uid'],'alice')
        bad=self.client.post(uri+'/move',json={'cell':0,'revision':state['revision']},
            headers=self.people['bob'])
        self.assertEqual(bad.status_code,409)
        for uid,cell in [('alice',0),('bob',3),('alice',1),('bob',4),('alice',2)]:
            previous=state['revision']
            response=self.client.post(uri+'/move',json={'cell':cell,'revision':previous},
                headers=self.people[uid])
            self.assertEqual(response.status_code,200)
            state=response.json()
            self.assertEqual(state['revision'],previous+1)
            self.assertEqual(self.client.post(uri+'/move',json={'cell':cell,'revision':previous},
                headers=self.people[uid]).status_code,409)
        self.assertEqual(state['winner'],'X')
        self.assertEqual(state['board'][0:3],['X','X','X'])
        self.assertEqual(self.client.post(uri+'/join',headers=self.people['alice']).status_code,200)
        self.assertEqual(self.client.post(uri+'/restart',headers=self.people['eve']).status_code,409)
        self.assertEqual(self.client.post(uri+'/restart',headers=self.people['bob']).status_code,409)
        self.heartbeat('bob')
        restarted=self.client.post(uri+'/restart',headers=self.people['bob']).json()
        self.assertIsNone(restarted['winner'])
        self.assertEqual(restarted['board'],list('.........'))

    def test_full_slots_prevent_spoofing_and_untrusted_coin_fields(self):
        uri=self.base+'/duel'
        self.heartbeat('alice')
        self.heartbeat('bob')
        self.heartbeat('eve')
        self.client.post(uri+'/join',headers=self.people['alice'])
        self.client.post(uri+'/join',headers=self.people['bob'])
        self.assertEqual(self.client.post(uri+'/join',headers=self.people['eve']).status_code,409)
        self.assertEqual(self.client.post(uri+'/move',json={
            'cell':0,'revision':2,'coins':1000000},headers=self.people['alice']).status_code,422)
        self.assertEqual(self.client.post(uri+'/move',json={
            'cell':9,'revision':2},headers=self.people['alice']).status_code,422)
        self.assertEqual(self.client.post(uri+'/move',json={
            'cell':0,'revision':2},headers=self.people['eve']).status_code,409)
        self.assertEqual(self.client.get(uri,headers=self.people['eve']).json()['board'],list('.........'))

if __name__=='__main__':
    unittest.main()
