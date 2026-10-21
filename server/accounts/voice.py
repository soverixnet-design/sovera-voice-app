"""Firebase identity and persistent room authorization for the voice gateway."""
import asyncio
import os
from fastapi import HTTPException,Header
from livekit import api
from server.voice import app as gateway


def attach_voice(app, rooms, actor):
    # A separate namespace prevents the legacy gateway's seat reconciler from
    # revoking Firebase participants (and vice versa).
    if os.environ.get('SOVERA_VOICE_ROOM_PREFIX') != 'fb-':
        raise RuntimeError('Firebase voice requires its isolated room namespace')
    if os.environ.get('LIVEKIT_URL') != 'wss://voice.soverixnet.com':
        raise RuntimeError('Unexpected voice endpoint')
    if not os.environ.get('LIVEKIT_API_KEY') or not os.environ.get('LIVEKIT_API_SECRET'):
        raise RuntimeError('Voice credentials required')
    gateway.ROOM_PREFIX = 'fb-'
    from .room_controls import RoomControls,ModerateInput
    controls=RoomControls(rooms)
    gateway.seat_policy = controls.check_take
    gateway.publish_policy = controls.can_publish

    def allowed(uid, room):
        with rooms.db() as db:
            rooms.profile(db, uid)
            rooms.exists(db,room)
            if db.execute('SELECT 1 FROM account_bans WHERE uid=?',(uid,)).fetchone():raise HTTPException(403,'Account banned')
            row = db.execute('SELECT seats FROM account_rooms WHERE id=?', (room,)).fetchone()
            if row is None:
                raise HTTPException(404, 'Room not found')
            rooms.check_member(db,uid,room)
            if not 5 <= row['seats'] <= 21:
                raise HTTPException(503, 'Invalid seat configuration')
            return row['seats']

    async def authorize(body, authorization):
        uid = await actor(authorization)
        count = await asyncio.to_thread(allowed, uid, str(body.room_id))
        return uid, count

    gateway.authorize = authorize
    app.router.lifespan_context = gateway.lifespan
    app.add_api_route('/sovera/account/voice', gateway.token, methods=['POST'])

    @app.post('/sovera/account/rooms/{room}/moderate')
    async def moderate(room:str,data:ModerateInput,authorization:str|None=Header(default=None)):
        uid=await actor(authorization)
        targets=await asyncio.to_thread(controls.moderate,uid,room,data)
        if data.action in ('mute','mute_all','down','kick'):
            async with gateway.lock:
                try:
                    current=await gateway.lk.room.list_participants(api.ListParticipantsRequest(room='fb-'+room))
                    online={p.identity for p in current.participants}
                    for target in targets:
                        if target in online:await gateway.publish('fb-'+room,target,False)
                        for key,record in list(gateway.seats.items()):
                            if key[0]=='fb-'+room and record['uid']==target:del gateway.seats[key]
                        if data.action=='kick' and target in online:
                            await gateway.lk.room.remove_participant(api.RoomParticipantIdentity(room='fb-'+room,identity=target))
                except Exception:raise HTTPException(503,'Moderation saved; voice update pending. Retry to confirm.')
        return {'saved':True}
