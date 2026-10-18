import asyncio
import importlib.util
import os
from pathlib import Path
import types
import unittest
import uuid

os.environ.update(SOVERA_AUTH_URL='https://example.invalid',SOVERA_PUBLIC_KEY='public-fixture',LIVEKIT_API_KEY='fixture',LIVEKIT_API_SECRET='fixture-secret-for-tests-only-32-bytes-long',LIVEKIT_URL='wss://voice.soverixnet.com')
spec=importlib.util.spec_from_file_location('voice_gateway',Path(__file__).with_name('app.py'))
g=importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
ROOM=str(uuid.uuid4())

class FakeRoom:
    def __init__(self):
        self.participants={uid:types.SimpleNamespace(identity=uid,sid='sid-'+uid,permission=types.SimpleNamespace(can_publish=False)) for uid in ['alice','bob']}
        self.fail=False
    async def list_participants(self,request):
        return types.SimpleNamespace(participants=list(self.participants.values()))
    async def list_rooms(self,request):
        return types.SimpleNamespace(rooms=[types.SimpleNamespace(name=ROOM)])
    async def update_participant(self,request):
        if self.fail:
            raise RuntimeError('unavailable')
        self.participants[request.identity].permission=request.permission

class Seats(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.old_auth=g.authorize
        async def auth(body,authorization):
            if authorization not in ['alice','bob']:
                raise g.HTTPException(401)
            return authorization, 2
        g.authorize=auth
        g.seats.clear()
        g.lock=asyncio.Lock()
        self.room=FakeRoom()
        g.lk=types.SimpleNamespace(room=self.room)
    async def asyncTearDown(self):
        g.authorize=self.old_auth
    async def call(self,action,seat=None,uid='alice'):
        return await g.token(g.Join(room_id=ROOM,action=action,seat=seat),uid)
    async def test_collision_does_not_grant_second_user(self):
        await self.call('take',0)
        with self.assertRaises(g.HTTPException) as raised:
            await self.call('take',0,'bob')
        self.assertEqual(raised.exception.status_code,409)
        self.assertFalse(self.room.participants['bob'].permission.can_publish)
    async def test_leave_revokes_before_release(self):
        await self.call('take',0)
        self.assertTrue(self.room.participants['alice'].permission.can_publish)
        self.room.fail=True
        with self.assertRaises(g.HTTPException):
            await self.call('leave')
        self.assertIn((ROOM,0),g.seats)
        self.room.fail=False
        await self.call('leave')
        self.assertFalse(self.room.participants['alice'].permission.can_publish)
        self.assertNotIn((ROOM,0),g.seats)
    async def test_expiry_and_session_replacement_revoke(self):
        await self.call('take',0)
        g.seats[(ROOM,0)]['until']=0
        await g.enforce()
        self.assertFalse(self.room.participants['alice'].permission.can_publish)
        await self.call('take',0)
        self.room.participants['alice'].sid='replacement'
        await g.enforce()
        self.assertFalse(self.room.participants['alice'].permission.can_publish)
        self.assertFalse(g.seats)
    async def test_invalid_seat_and_unauthenticated_rejected(self):
        for seat in [-1,2,100]:
            with self.assertRaises(g.HTTPException):
                await self.call('take',seat)
        with self.assertRaises(g.HTTPException):
            await self.call('take',0,'unknown')
        self.assertFalse(g.seats)
    async def test_stale_publish_permission_reconciled(self):
        self.room.participants['bob'].permission.can_publish=True
        await g.enforce()
        self.assertFalse(self.room.participants['bob'].permission.can_publish)
    async def test_join_token_is_always_listen_only(self):
        import json,jwt
        await self.call('take',0)
        result=await self.call('join')
        claims=jwt.decode(json.loads(result.body)['token'],'fixture-secret-for-tests-only-32-bytes-long',algorithms=['HS256'])
        self.assertFalse(claims['video']['canPublish'])
        self.assertNotIn('roomAdmin',claims['video'])

if __name__=='__main__':
    unittest.main()
