import asyncio
import os
import types
import uuid
from unittest.mock import patch
from server.accounts.test_accounts import AccountTests
from server.accounts.app import create_app
from fastapi.testclient import TestClient
from server.voice import app as gateway

import unittest

class VoiceTests(unittest.TestCase):
    def setUp(self):
        AccountTests.setUp(self)
        previous=(gateway.authorize,gateway.ROOM_PREFIX,gateway.lk,gateway.lock)
        self.addCleanup(lambda: self.restore(previous))
        env=patch.dict(os.environ,{'SOVERA_VOICE_ROOM_PREFIX':'fb-','LIVEKIT_URL':'wss://voice.soverixnet.com','LIVEKIT_API_KEY':'test','LIVEKIT_API_SECRET':'test-secret-only-32-characters-long'})
        env.start();self.addCleanup(env.stop)
        async def verify(token):
            if token!='alice': raise ValueError()
            return token
        self.client=TestClient(create_app(self.store,verify,voice=True))
        self.headers={'Authorization':'Bearer alice'}
    def restore(self,old):
        gateway.authorize,gateway.ROOM_PREFIX,gateway.lk,gateway.lock=old
        gateway.seats.clear()
    def test_verified_profile_room_and_server_seat_count(self):
        path='/sovera/account/voice';room=str(uuid.uuid4())
        self.assertEqual(self.client.post(path,json={'room_id':room}).status_code,401)
        self.assertEqual(self.client.post(path,json={'room_id':room},headers=self.headers).status_code,409)
        self.client.put('/sovera/account',json=self.data,headers=self.headers)
        self.assertEqual(self.client.post(path,json={'room_id':room},headers=self.headers).status_code,404)
        room=self.client.post('/sovera/account/rooms',json={'name':'Room','seats':5},headers=self.headers).json()['room']['id']
        response=self.client.post(path,json={'room_id':room},headers=self.headers)
        import jwt
        claims=jwt.decode(response.json()['token'],os.environ['LIVEKIT_API_SECRET'],algorithms=['HS256'])
        self.assertEqual(claims['sub'],'alice')
        self.assertEqual(claims['video']['room'],'fb-'+room)
        self.assertFalse(claims['video']['canPublish'])
        self.assertEqual(self.client.post(path,json={'room_id':room,'uid':'owner'},headers=self.headers).status_code,422)
    def test_reconciler_ignores_legacy_rooms(self):
        calls=[]
        async def listed(request):
            return types.SimpleNamespace(rooms=[types.SimpleNamespace(name=str(uuid.uuid4()))])
        async def participants(request):
            calls.append(request.room)
            raise AssertionError('Legacy room inspected')
        gateway.lk=types.SimpleNamespace(room=types.SimpleNamespace(list_rooms=listed,list_participants=participants))
        gateway.lock=asyncio.Lock()
        asyncio.run(gateway.enforce())
        self.assertEqual(calls,[])
