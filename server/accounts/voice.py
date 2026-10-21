"""Firebase identity and persistent room authorization for the voice gateway."""
import asyncio
import os
from fastapi import HTTPException
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
    from .room_controls import RoomControls
    gateway.seat_policy = RoomControls(rooms).check_take

    def allowed(uid, room):
        with rooms.db() as db:
            rooms.profile(db, uid)
            rooms.exists(db,room)
            if db.execute('SELECT 1 FROM account_bans WHERE uid=?',(uid,)).fetchone():raise HTTPException(403,'Account banned')
            row = db.execute('SELECT seats FROM account_rooms WHERE id=?', (room,)).fetchone()
            if row is None:
                raise HTTPException(404, 'Room not found')
            if row['seats'] not in (5, 6, 9, 12, 15):
                raise HTTPException(503, 'Invalid seat configuration')
            return row['seats']

    async def authorize(body, authorization):
        uid = await actor(authorization)
        count = await asyncio.to_thread(allowed, uid, str(body.room_id))
        return uid, count

    gateway.authorize = authorize
    app.router.lifespan_context = gateway.lifespan
    app.add_api_route('/sovera/account/voice', gateway.token, methods=['POST'])
