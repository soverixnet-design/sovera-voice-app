import unittest
from fastapi import HTTPException
from .test_accounts import AccountTests
from .app import ProfileInput
from .room_controls import RoomControls, RoomAdmin, SeatLock

class RoomControlTests(unittest.TestCase):
    setUp=AccountTests.setUp
    def test_room_scope_owner_admin_and_persistent_locks(self):
        for uid in ('alice','bob','charlie'):
            self.store.save(uid,ProfileInput(display_name=uid,country='BD'))
        headers={'Authorization':'Bearer alice'}
        room=self.client.post('/sovera/account/rooms',json={'name':'Room','seats':15},headers=headers).json()['room']['id']
        from .rooms import Rooms
        controls=RoomControls(Rooms(self.path))
        with self.assertRaises(HTTPException): controls.admin('bob',room,RoomAdmin(uid='charlie',enabled=True))
        controls.admin('alice',room,RoomAdmin(uid='bob',enabled=True))
        self.assertEqual(controls.state('bob',room)['role'],'admin')
        controls.lock('bob',room,SeatLock(locked=True))
        self.assertEqual(len(RoomControls(Rooms(self.path)).state('charlie',room)['locked_seats']),15)
        with self.assertRaises(HTTPException): controls.check_take('charlie',room,0)
        controls.check_take('bob',room,0)
        with self.assertRaises(HTTPException): controls.lock('charlie',room,SeatLock(locked=False))
        controls.lock('bob',room,SeatLock(locked=False,seat=0))
        controls.check_take('charlie',room,0)
        controls.admin('alice',room,RoomAdmin(uid='bob',enabled=False))
        with self.assertRaises(HTTPException): controls.lock('bob',room,SeatLock(locked=False))
        self.assertEqual(self.client.put(f'/sovera/account/rooms/{room}/seat-lock',json={'locked':True,'seat':99},headers=headers).status_code,422)
        self.assertEqual(self.client.put(f'/sovera/account/rooms/{room}/admins',json={'uid':'bob','enabled':True},headers={'Authorization':'Bearer bob'}).status_code,403)
