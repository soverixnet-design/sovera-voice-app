"""API tests for the room XO duel and authoritative turn validation."""
import sqlite3
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
        self.path=Path(temp.name)/'account.sqlite3'
        self.client=TestClient(create_app(Profiles(self.path),verify))
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
        self.assertEqual(self.client.post(uri+'/restart',headers=self.people['bob']).status_code,409)
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
        self.heartbeat('bob')
        self.assertEqual(self.client.post(uri+'/restart',headers=self.people['bob']).status_code,409)
        # Allow the winner to be visible for the five-second result window.
        with sqlite3.connect(self.path) as db:
            db.execute('UPDATE account_room_duels SET updated_at=updated_at-6 WHERE room_id=?',(self.room,))
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
        queued=self.client.post(uri+'/join',headers=self.people['eve'])
        self.assertEqual(queued.status_code,200)
        self.assertEqual(queued.json()['waiting_count'],1)
        self.assertEqual(queued.json()['my_waiting_position'],1)
        self.assertEqual(self.client.post(uri+'/move',json={
            'cell':0,'revision':2,'coins':1000000},headers=self.people['alice']).status_code,422)
        self.assertEqual(self.client.post(uri+'/move',json={
            'cell':9,'revision':2},headers=self.people['alice']).status_code,422)
        self.assertEqual(self.client.post(uri+'/move',json={
            'cell':0,'revision':2},headers=self.people['eve']).status_code,409)
        self.assertEqual(self.client.get(uri,headers=self.people['eve']).json()['board'],list('.........'))


    def test_any_user_can_queue_and_play_next_match(self):
        uri=self.base+'/duel'
        for uid in ('alice','bob','eve'):
            self.heartbeat(uid)
        self.client.post(uri+'/join',headers=self.people['alice'])
        self.client.post(uri+'/join',headers=self.people['bob'])
        queued=self.client.post(uri+'/join',headers=self.people['eve']).json()
        self.assertEqual(queued['my_waiting_position'],1)
        self.assertEqual(self.client.post(uri+'/join',headers=self.people['eve']).json()['waiting_count'],1)
        for uid,cell in [('alice',0),('bob',3),('alice',1),('bob',4),('alice',2)]:
            state=self.client.get(uri,headers=self.people[uid]).json()
            result=self.client.post(uri+'/move',
                json={'cell':cell,'revision':state['revision']},headers=self.people[uid])
            self.assertEqual(result.status_code,200)
        spectator=self.client.get(uri,headers=self.people['eve']).json()
        old=self.client.get(uri,headers=self.people['alice']).json()
        self.assertEqual(old['winner'],'X')
        self.assertEqual(spectator['winner'],old['winner'])
        self.assertEqual(spectator['board'],old['board'])
        self.assertEqual(self.client.post(uri+'/restart',headers=self.people['eve']).status_code,409)
        with sqlite3.connect(self.path) as db:
            db.execute('UPDATE account_room_duels SET updated_at=updated_at-6 WHERE room_id=?',(self.room,))
        next_game=self.client.post(uri+'/restart',headers=self.people['eve'])
        self.assertEqual(next_game.status_code,200)
        state=next_game.json()
        self.assertTrue(state['ready'])
        self.assertEqual(state['player_x'],'eve')
        self.assertEqual(state['player_o'],'alice')
        self.assertEqual(state['turn_uid'],'eve')
        self.assertEqual(state['waiting_count'],0)
        self.assertIsNone(state['winner'])
        self.assertEqual(self.client.get(uri,headers=self.people['bob']).json()['board'],list('.........'))
        self.assertEqual(self.client.post(uri+'/move',
            json={'cell':0,'revision':state['revision']},headers=self.people['bob']).status_code,409)
        self.assertEqual(self.client.post(uri+'/move',
            json={'cell':0,'revision':state['revision']},headers=self.people['eve']).status_code,200)

    def test_cancel_queue_does_not_disrupt_current_players(self):
        uri=self.base+'/duel'
        for uid in ('alice','bob','eve'):
            self.heartbeat(uid)
        self.client.post(uri+'/join',headers=self.people['alice'])
        self.client.post(uri+'/join',headers=self.people['bob'])
        self.client.post(uri+'/join',headers=self.people['eve'])
        canceled=self.client.post(uri+'/cancel',headers=self.people['eve'])
        self.assertEqual(canceled.status_code,200)
        self.assertEqual(canceled.json()['waiting_count'],0)
        self.assertIsNone(canceled.json()['my_waiting_position'])
        state=self.client.get(uri,headers=self.people['alice']).json()
        self.assertTrue(state['ready'])
        self.assertEqual(state['turn_uid'],'alice')
        self.assertEqual(self.client.post(uri+'/restart',headers=self.people['eve']).status_code,409)
        self.assertEqual(self.client.post(uri+'/cancel').status_code,401)

if __name__=='__main__':
    unittest.main()
