import unittest
from fastapi import HTTPException
from .test_accounts import AccountTests
from .app import ProfileInput
from .room_controls import RoomControls, RoomAdmin, SeatLock

class RoomControlTests(unittest.TestCase):
    setUp=AccountTests.setUp
    def test_invitation_is_private_permission_checked_and_retry_safe(self):
        import uuid
        from .room_controls import InviteInput
        from .rooms import Rooms,RoomInput
        for uid in ('alice','bob','charlie'):self.store.save(uid,ProfileInput(display_name=uid,country='BD'))
        rooms=Rooms(self.path);room=rooms.save('alice',RoomInput(name='Room'))['id']
        controls=RoomControls(rooms)
        rooms.presence('alice',room);rooms.presence('bob',room)
        data=InviteInput(target_uid='bob',seat=2,request_id=uuid.uuid4())
        with self.assertRaises(HTTPException):controls.invite('charlie',room,data)
        first=controls.invite('alice',room,data)
        self.assertEqual(first,controls.invite('alice',room,data))
        self.assertEqual(controls.state('charlie',room)['invites'],[])
        self.assertEqual(controls.state('bob',room)['invites'][0]['seat'],2)
        with self.assertRaises(HTTPException):controls.invite('alice',room,data.model_copy(update={'seat':3}))
        with self.assertRaises(HTTPException):controls.invite('alice',room,data.model_copy(update={'target_uid':'charlie','request_id':uuid.uuid4()}))
        controls.moderate('alice',room,__import__('server.accounts.room_controls',fromlist=['ModerateInput']).ModerateInput(action='kick',target_uid='bob'))
        with self.assertRaises(HTTPException):controls.invite('alice',room,data.model_copy(update={'request_id':uuid.uuid4()}))
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

    def test_reactions_are_private_identity_bound_retry_safe_and_rate_limited(self):
        import uuid
        from .room_controls import ReactionInput
        from .rooms import Rooms,RoomInput
        self.store.save('alice',ProfileInput(display_name='Alice',country='BD'))
        self.store.save('bob',ProfileInput(display_name='Bob',country='BD'))
        rooms=Rooms(self.path);room=rooms.save('alice',RoomInput(name='Real room',seats=21,seat_style='neon'))['id']
        controls=RoomControls(rooms)
        data=ReactionInput(emoji='😂',request_id=uuid.uuid4())
        with self.assertRaises(HTTPException):controls.react('bob',room,data)
        rooms.presence('alice',room)
        first=controls.react('alice',room,data)
        self.assertEqual(first,controls.react('alice',room,data))
        self.assertEqual(controls.state('alice',room)['reactions'][0]['uid'],'alice')
        self.assertEqual(controls.state('alice',room)['room']['seat_style'],'neon')
        with self.assertRaises(HTTPException):controls.react('alice',room,data.model_copy(update={'emoji':'🔥'}))
        with self.assertRaises(HTTPException):controls.react('alice',room,data.model_copy(update={'request_id':uuid.uuid4()}))

    def test_room_moderation_does_not_grant_global_power_or_force_unmute(self):
        from .room_controls import ModerateInput
        from .rooms import Rooms,RoomInput,MessageInput
        import uuid
        for uid in ('alice','bob','charlie'):self.store.save(uid,ProfileInput(display_name=uid,country='BD'))
        rooms=Rooms(self.path);room=rooms.save('alice',RoomInput(name='Room'))['id']
        controls=RoomControls(rooms)
        for uid in ('alice','bob','charlie'):rooms.presence(uid,room)
        controls.admin('alice',room,RoomAdmin(uid='bob',enabled=True))
        with self.assertRaises(HTTPException):controls.moderate('charlie',room,ModerateInput(action='kick',target_uid='bob'))
        with self.assertRaises(HTTPException):controls.moderate('bob',room,ModerateInput(action='kick',target_uid='alice'))
        controls.moderate('bob',room,ModerateInput(action='mute',target_uid='charlie'))
        self.assertFalse(controls.can_publish('charlie',room))
        with self.assertRaises(HTTPException):controls.check_take('charlie',room,2)
        controls.moderate('bob',room,ModerateInput(action='unmute',target_uid='charlie'))
        self.assertTrue(controls.can_publish('charlie',room))
        controls.moderate('bob',room,ModerateInput(action='kick',target_uid='charlie'))
        with self.assertRaises(HTTPException):rooms.presence('charlie',room)
        with self.assertRaises(HTTPException):rooms.send('charlie',room,MessageInput(text='Blocked',request_id=uuid.uuid4()))
        controls.moderate('alice',room,ModerateInput(action='unban',target_uid='charlie'))
        rooms.presence('charlie',room)
