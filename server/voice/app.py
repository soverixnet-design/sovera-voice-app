"""Single-worker voice gateway. Seats reset safely when the process restarts."""
import asyncio
import contextlib
import json
import os
import time
import uuid
from contextlib import asynccontextmanager
from typing import Literal

import httpx
import jwt
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, StrictInt
from livekit import api
from livekit.protocol import models

# Installer reads these public settings from the existing gateway.
BASE = os.environ.get('SOVERA_AUTH_URL', '')
APIKEY = os.environ.get('SOVERA_PUBLIC_KEY', '')
AUTH_PROVIDER = os.environ.get('SOVERA_AUTH_PROVIDER', 'supabase')
FIREBASE_PROJECT = os.environ.get('SOVERA_FIREBASE_PROJECT', '')
FIREBASE_KEY = os.environ.get('SOVERA_FIREBASE_PUBLIC_KEY', '')
ROOM_PREFIX = os.environ.get('SOVERA_VOICE_ROOM_PREFIX', '')
LEASE_SECONDS = 35
seats = {}
lock = asyncio.Lock()
lk = None
seat_policy = None
publish_policy = None


class Join(BaseModel):
    model_config = ConfigDict(extra="forbid")
    room_id: uuid.UUID
    action: Literal['join', 'state', 'take', 'leave', 'renew'] = 'join'
    seat: StrictInt | None = None


def permission(enabled):
    return models.ParticipantPermission(
        can_subscribe=True, can_publish=enabled, can_publish_data=False,
        can_update_metadata=False,
        can_publish_sources=[models.TrackSource.MICROPHONE] if enabled else [],
    )


async def publish(room, uid, enabled):
    return await lk.room.update_participant(api.UpdateParticipantRequest(
        room=room, identity=uid, permission=permission(enabled)))


async def enforce():
    # Reconcile server permissions with current leases, including stale replays.
    async with lock:
        rooms = await lk.room.list_rooms(api.ListRoomsRequest())
        for room in rooms.rooms:
            try:
                if not room.name.startswith(ROOM_PREFIX):
                    continue
                uuid.UUID(room.name[len(ROOM_PREFIX):])
            except ValueError:
                continue
            participants = await lk.room.list_participants(
                api.ListParticipantsRequest(room=room.name))
            live = {p.identity: p for p in participants.participants}
            for key, record in list(seats.items()):
                if key[0] != room.name:
                    continue
                participant = live.get(record['uid'])
                if record['until'] <= time.monotonic() or participant is None or participant.sid != record['sid']:
                    if participant is not None:
                        await publish(room.name, record['uid'], False)
                    del seats[key]
            allowed = {v['uid']: v['sid'] for k, v in seats.items() if k[0] == room.name}
            for participant in participants.participants:
                if participant.permission.can_publish and allowed.get(participant.identity) != participant.sid:
                    await publish(room.name, participant.identity, False)
        active = {r.name for r in rooms.rooms}
        for key in list(seats):
            if key[0] not in active:
                del seats[key]


async def guard_loop():
    while True:
        await asyncio.sleep(5)
        try:
            await enforce()
        except Exception:
            # Retain leases/records on API failure, so revocation is retried.
            pass


@asynccontextmanager
async def lifespan(app):
    global lk
    lk = api.LiveKitAPI('http://127.0.0.1:7880')
    try:
        await enforce()
        task = asyncio.create_task(guard_loop())
        try:
            yield
        finally:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task
            for record in seats.values():
                record['until'] = 0
            with contextlib.suppress(Exception):
                await enforce()
    finally:
        await lk.aclose()


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)


async def authorize_firebase(body, authorization):
    """Verify with Google's Auth service, then enforce Firestore document rules.

    The ID token is never decoded without verification. No service-account key
    is needed: reads use the caller's token and remain subject to Firestore RLS.
    Missing data and network failures fail closed before any LiveKit grant.
    """
    if not authorization.startswith('Bearer ') or not authorization[7:].strip():
        raise HTTPException(401, 'Sign in required')
    if not FIREBASE_PROJECT or not FIREBASE_KEY:
        raise HTTPException(503, 'Firebase authentication is not configured')
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            checked = await client.post(
                'https://identitytoolkit.googleapis.com/v1/accounts:lookup',
                params={'key': FIREBASE_KEY},
                json={'idToken': authorization[7:]})
            if checked.status_code in (400, 401, 403):
                raise HTTPException(401, 'Session expired')
            if checked.status_code != 200:
                raise HTTPException(503, 'Authentication unavailable')
            users = checked.json().get('users', [])
            if len(users) != 1 or users[0].get('disabled') is True:
                raise HTTPException(401, 'Account unavailable')
            uid = users[0]['localId']
            if not isinstance(uid, str) or not uid or len(uid) > 128 or '/' in uid:
                raise HTTPException(401, 'Invalid account')
            # A key from another project cannot be used to trust its identities:
            # the same bearer must also read documents in this fixed project.
            base = ('https://firestore.googleapis.com/v1/projects/' +
                    FIREBASE_PROJECT + '/databases/(default)/documents/')
            headers = {'Authorization': authorization}
            profile = await client.get(base + 'sovera_profiles/' + uid, headers=headers)
            room = await client.get(base + 'sovera_rooms/' + str(body.room_id), headers=headers)
            if profile.status_code in (403, 404) or room.status_code in (403, 404):
                raise HTTPException(403, 'Account or room unavailable')
            if profile.status_code != 200 or room.status_code != 200:
                raise HTTPException(503, 'Permission check unavailable')
            pfields = profile.json()['fields']
            rfields = room.json()['fields']
            if pfields.get('is_banned', {}).get('booleanValue') is not False:
                raise HTTPException(403, 'Account unavailable')
            if rfields.get('is_closed', {}).get('booleanValue') is not False:
                raise HTTPException(403, 'Room unavailable')
            count = int(rfields['seat_count']['integerValue'])
            if not 1 <= count <= 100:
                raise HTTPException(503, 'Seat configuration unavailable')
            return uid, count
    except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError):
        raise HTTPException(503, 'Authentication unavailable')


async def authorize(body, authorization):
    if AUTH_PROVIDER == 'firebase':
        return await authorize_firebase(body, authorization)
    if AUTH_PROVIDER != 'supabase':
        raise HTTPException(503, 'Authentication provider unavailable')
    if not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Sign in required')
    headers = {'apikey': APIKEY, 'Authorization': authorization}
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            user = await client.get(BASE + '/auth/v1/user', headers=headers)
            if user.status_code != 200:
                raise HTTPException(401, 'Session expired')
            uid = str(uuid.UUID(user.json()['id']))
            profile = await client.get(BASE + '/rest/v1/sovera_profiles', headers=headers,
                params={'id': 'eq.' + uid, 'select': 'id,is_banned'})
            room = await client.get(BASE + '/rest/v1/sovera_rooms', headers=headers,
                params={'id': 'eq.' + str(body.room_id), 'select': 'id,is_closed,seat_count'})
            if profile.status_code != 200 or room.status_code != 200:
                raise HTTPException(503, 'Permission check unavailable')
            profiles, rooms = profile.json(), room.json()
            if not profiles or profiles[0].get('is_banned') is not False:
                raise HTTPException(403, 'Account unavailable')
            if not rooms or rooms[0].get('is_closed') is not False:
                raise HTTPException(403, 'Room unavailable')
            count = rooms[0].get('seat_count')
            if type(count) is not int or not 1 <= count <= 100:
                raise HTTPException(503, 'Seat configuration unavailable')
            return uid, count
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Authentication unavailable')


def response(data):
    return JSONResponse(data, headers={'Cache-Control': 'no-store'})


@app.get('/sovera/health')
async def health():
    return {'ready': True, 'seats': True}


@app.post('/sovera/token')
async def token(body: Join, authorization: str = Header(default='')):
    uid, count = await authorize(body, authorization)
    room = ROOM_PREFIX + str(body.room_id)
    if body.action == 'join':
        now = int(time.time())
        claims = {'iss': os.environ['LIVEKIT_API_KEY'], 'sub': uid,
            'nbf': now - 5, 'exp': now + 120, 'jti': str(uuid.uuid4()),
            'video': {'roomJoin': True, 'room': room, 'canSubscribe': True,
                'canPublish': False, 'canPublishData': False}}
        signed = jwt.encode(claims, os.environ['LIVEKIT_API_SECRET'], algorithm='HS256')
        return response({'url': os.environ['LIVEKIT_URL'], 'token': signed})
    async with lock:
        try:
            current = await lk.room.list_participants(api.ListParticipantsRequest(room=room))
            participants = {p.identity: p for p in current.participants}
            for key, record in list(seats.items()):
                if key[0] != room:
                    continue
                participant = participants.get(record['uid'])
                if key[1] >= count or record['until'] <= time.monotonic() or participant is None or participant.sid != record['sid']:
                    if participant is not None:
                        await publish(room, record['uid'], False)
                    del seats[key]
            own = next((key for key, item in seats.items() if key[0] == room and item['uid'] == uid), None)
            participant = participants.get(uid)
            if body.action == 'leave':
                if participant is not None:
                    await publish(room, uid, False)
                if own is not None:
                    del seats[own]
            elif body.action == 'take':
                if participant is None:
                    raise HTTPException(409, 'Join live audio first')
                if body.seat is None or not 0 <= body.seat < count:
                    raise HTTPException(422, 'Invalid seat')
                if seat_policy is not None:
                    seat_policy(uid, str(body.room_id), body.seat)
                target = (room, body.seat)
                if target in seats and seats[target]['uid'] != uid:
                    raise HTTPException(409, 'Seat occupied')
                # Reserve before granting; revoke before making an old seat free.
                if own is not None and own != target:
                    await publish(room, uid, False)
                    del seats[own]
                record = {'uid': uid, 'sid': participant.sid, 'until': time.monotonic() + LEASE_SECONDS}
                seats[target] = record
                try:
                    await publish(room, uid, True)
                except Exception:
                    record['until'] = 0
                    raise
            elif body.action == 'renew':
                if own is None:
                    raise HTTPException(409, 'Seat expired')
                if publish_policy is not None and not publish_policy(uid,str(body.room_id)):
                    await publish(room,uid,False)
                    del seats[own]
                else:
                    await publish(room, uid, True)
                    seats[own]['until'] = time.monotonic() + LEASE_SECONDS
            return response({'seats': [{'seat': key[1], 'user_id': item['uid']}
                for key, item in seats.items() if key[0] == room], 'seat_count': count,
                'my_seat': next((key[1] for key, item in seats.items() if key[0] == room and item['uid'] == uid), None)})
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(503, 'Voice control unavailable')
