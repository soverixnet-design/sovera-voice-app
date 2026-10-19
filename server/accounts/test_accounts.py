import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, create_app

class AccountTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'profiles.db'
        self.store = Profiles(self.path)
        async def verify(token):
            if token not in ('alice','bob'): raise ValueError('secret SDK error')
            return token
        self.client = TestClient(create_app(self.store, verify))
        self.data = {'display_name':'Shakil','country':'BD','bio':'Hello'}

    def test_private_and_persistent(self):
        self.assertEqual(self.client.get('/sovera/account').status_code,401)
        self.assertEqual(self.client.put('/sovera/account',json=self.data,headers={'Authorization':'Bearer alice'}).status_code,200)
        self.assertEqual(Profiles(self.path).get('alice')['display_name'],'Shakil')
        response=self.client.get('/sovera/account',headers={'Authorization':'Bearer bob'})
        self.assertIsNone(response.json()['profile'])
        self.assertEqual(response.headers['cache-control'],'no-store')

    def test_reject_spoofed_identity_and_wallet(self):
        for key in ('firebase_uid','is_banned','role','coins','uid'):
            r=self.client.put('/sovera/account',json={**self.data,key:'owner'},headers={'Authorization':'Bearer alice'})
            self.assertEqual(r.status_code,422)
        self.assertIsNone(self.store.get('alice'))

    def test_invalid_sessions_and_media(self):
        r=self.client.get('/sovera/account',headers={'Authorization':'Bearer revoked'})
        self.assertEqual(r.status_code,401)
        self.assertNotIn('secret',r.text)
        for url in ('javascript:alert(1)','http://example.com/a','https://u:p@example.com/a'):
            r=self.client.put('/sovera/account',json={**self.data,'avatar_url':url},headers={'Authorization':'Bearer alice'})
            self.assertEqual(r.status_code,422)
        self.assertEqual(self.client.get('/sovera/account/health').json()['wallet'],False)

class RoomTests(unittest.TestCase):
    setUp=AccountTests.setUp
    def make_room(self):
        self.client.put('/sovera/account',json=self.data,headers={'Authorization':'Bearer alice'})
        r=self.client.post('/sovera/account/rooms',json={'name':'My room','seats':9},headers={'Authorization':'Bearer alice'})
        self.assertEqual(r.status_code,200)
        return r.json()['room']['id']

    def test_owner_only_and_one_room(self):
        room=self.make_room()
        r=self.client.post('/sovera/account/rooms',json={'name':'Another room'},headers={'Authorization':'Bearer alice'})
        self.assertEqual(r.json()['room']['id'],room)
        self.client.put('/sovera/account',json=self.data,headers={'Authorization':'Bearer bob'})
        r=self.client.put('/sovera/account/rooms/'+room,json={'name':'Stolen room'},headers={'Authorization':'Bearer bob'})
        self.assertEqual(r.status_code,403)
        r=self.client.put('/sovera/account/rooms/'+room,json={'name':'Updated','seats':5},headers={'Authorization':'Bearer alice'})
        self.assertEqual(r.json()['room']['seats'],5)
        from server.accounts.rooms import Rooms
        self.assertEqual(Rooms(self.path).directory()[0]['name'],'Updated')

    def test_chat_replay_and_authoritative_identity(self):
        import uuid
        room=self.make_room(); path='/sovera/account/rooms/'+room+'/messages'
        body={'text':'Hello','request_id':str(uuid.uuid4())}
        a=self.client.post(path,json=body,headers={'Authorization':'Bearer alice'})
        b=self.client.post(path,json=body,headers={'Authorization':'Bearer alice'})
        self.assertEqual(a.json(),b.json())
        conflict=self.client.post(path,json={**body,'text':'Changed'},headers={'Authorization':'Bearer alice'})
        self.assertEqual(conflict.status_code,409)
        forged=self.client.post(path,json={**body,'name':'Owner'},headers={'Authorization':'Bearer alice'})
        self.assertEqual(forged.status_code,422)
        rows=self.client.get(path,headers={'Authorization':'Bearer bob'}).json()['messages']
        self.assertEqual(len(rows),1);self.assertEqual(rows[0]['name'],'Shakil')
        self.assertEqual(self.client.get(path).status_code,401)

    def test_room_visual_effects_are_verified_live_and_idempotent(self):
        import uuid
        from server.accounts.rooms import Rooms
        room=self.make_room()
        base='/sovera/account/rooms/'+room
        alice={'Authorization':'Bearer alice'}
        bob={'Authorization':'Bearer bob'}
        self.client.put('/sovera/account',json={**self.data,'display_name':'Friend'},headers=bob)
        self.assertEqual(self.client.post(base+'/effects',
            json={'recipient_uid':'bob','kind':'heart','request_id':str(uuid.uuid4())},
            headers=alice).status_code,409)
        self.client.put(base+'/presence',headers=alice)
        self.client.put(base+'/presence',headers=bob)
        people=self.client.get(base+'/people',headers=alice).json()['people']
        self.assertEqual({p['uid'] for p in people},{'alice','bob'})
        key=str(uuid.uuid4())
        request={'recipient_uid':'bob','kind':'heart','request_id':key}
        first=self.client.post(base+'/effects',json=request,headers=alice)
        self.assertEqual(first.status_code,200)
        self.assertTrue(first.json()['visual_only'])
        again=self.client.post(base+'/effects',json=request,headers=alice)
        self.assertEqual(first.json(),again.json())
        self.assertEqual(self.client.post(base+'/effects',
            json={**request,'kind':'rose'},headers=alice).status_code,409)
        events=self.client.get(base+'/effects',headers=bob).json()['effects']
        self.assertEqual(len(events),1)
        self.assertEqual(events[0]['sender_name'],'Shakil')
        self.assertEqual(events[0]['recipient_name'],'Friend')
        self.assertEqual(events[0]['kind'],'heart')
        self.assertEqual(self.client.get(base+'/effects').status_code,401)
        self.assertEqual(self.client.post(base+'/effects',
            json={**request,'request_id':str(uuid.uuid4()),'coins':100},
            headers=alice).status_code,422)
        self.assertEqual(self.client.post(base+'/effects',
            json={**request,'request_id':str(uuid.uuid4())},
            headers=alice).status_code,429)
        self.client.delete(base+'/presence',headers=bob)
        self.assertEqual(self.client.post(base+'/effects',
            json={**request,'request_id':str(uuid.uuid4())},
            headers=alice).status_code,409)
        self.assertEqual(self.client.get(base+'/people',headers=alice).json()['people'][0]['uid'],'alice')
        self.assertEqual(len(Rooms(self.path,clock=lambda:__import__('time').time()+20).effects(room)['effects']),0)

    def test_counts_expire_and_duplicate_heartbeats_do_not_inflate(self):
        from server.accounts.rooms import Rooms
        room=self.make_room(); now=[1000.]
        rooms=Rooms(self.path,clock=lambda:now[0])
        rooms.presence('alice',room);rooms.presence('alice',room)
        self.assertEqual(rooms.directory()[0]['occupants'],1)
        now[0]+=91
        self.assertEqual(rooms.directory()[0]['occupants'],0)
        rooms.presence('alice',room);rooms.presence('alice',room,True)
        self.assertEqual(rooms.directory()[0]['occupants'],0)

if __name__=='__main__': unittest.main()
