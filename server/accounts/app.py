"""Firebase-authenticated account profiles. No wallets or staff roles here."""
import asyncio
import os
import sqlite3
import time
from pathlib import Path
from datetime import date
from typing import Literal
from fastapi import FastAPI, Header, HTTPException, Query, Request
from .rooms import Rooms, RoomInput, MessageInput, RoomEffectInput
from .duel import RoomDuel, MoveInput
from .global_games import GlobalColors, ColorPick
from .food_wheel import FoodWheel, FoodChoice
from .greedy_access import greedy_access
from .wallet import WalletStore,ExchangeInput
from .greedy_wallet import attach_greedy_wallet
from .community import attach_community
from .control import attach_control
from .catalog import attach_catalog
from pydantic import BaseModel, ConfigDict, Field, field_validator

class ProfileInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    display_name: str = Field(min_length=1, max_length=40)
    country: str = Field(pattern=r'^[A-Z]{2}$')
    bio: str = Field(default='', max_length=150)
    avatar_url: str | None = Field(default=None, max_length=2000)

    gender: Literal['male', 'female', 'other'] | None = None
    birthday: date | None = None

    @field_validator('birthday')
    @classmethod
    def valid_birthday(cls, value):
        if value is not None and not date(1900, 1, 1) <= value <= date.today():
            raise ValueError('Invalid birthday')
        return value

    @field_validator('avatar_url')
    @classmethod
    def avatar(cls, value):
        if value is not None:
            from urllib.parse import urlsplit
            parsed = urlsplit(value)
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError('Avatar must use HTTPS without credentials')
        return value

class Profiles:
    def __init__(self, path):
        self.path = str(path)
        with sqlite3.connect(self.path) as db:
            db.execute('''CREATE TABLE IF NOT EXISTS account_profiles(
                firebase_uid TEXT PRIMARY KEY, display_name TEXT NOT NULL,
                country TEXT NOT NULL, bio TEXT NOT NULL, avatar_url TEXT,
                updated_at INTEGER NOT NULL)''')
            columns = {r[1] for r in db.execute('PRAGMA table_info(account_profiles)')}
            for column in ('gender', 'birthday'):
                if column not in columns:
                    db.execute(f'ALTER TABLE account_profiles ADD COLUMN {column} TEXT')

    def get(self, uid):
        with sqlite3.connect(self.path, timeout=10) as db:
            db.row_factory = sqlite3.Row
            row = db.execute('SELECT * FROM account_profiles WHERE firebase_uid=?', (uid,)).fetchone()
            if not row:return None
            from .catalog import equipped_assets
            from .wallet import legacy_identity
            return dict(row)|{'equipped':equipped_assets(db,uid)}|legacy_identity(db,uid)

    def save(self, uid, data):
        with sqlite3.connect(self.path, timeout=10) as db:
            db.execute('''INSERT INTO account_profiles(firebase_uid,display_name,country,bio,avatar_url,updated_at) VALUES(?,?,?,?,?,?)
                ON CONFLICT(firebase_uid) DO UPDATE SET display_name=excluded.display_name,
                country=excluded.country,bio=excluded.bio,avatar_url=excluded.avatar_url,
                updated_at=excluded.updated_at''', (uid, data.display_name, data.country,
                    data.bio, data.avatar_url, int(time.time())))
            for column in ('gender', 'birthday'):
                if column in getattr(data, 'model_fields_set', set()):
                    value = getattr(data, column)
                    if isinstance(value, date): value = value.isoformat()
                    db.execute(f'UPDATE account_profiles SET {column}=? WHERE firebase_uid=?', (value, uid))
        return self.get(uid)

def create_app(profiles, verify, *, voice=False):
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware('http')
    async def private_responses(request, call_next):
        if request.method in ('PUT', 'POST'):
            length = request.headers.get('content-length')
            if length is None or not length.isdecimal() or int(length)>(8*1024*1024 if (request.url.path in ('/sovera/control/media','/sovera/account/avatar') or (request.url.path.startswith('/sovera/account/rooms/') and request.url.path.endswith('/photo'))) else 8192):
                from fastapi.responses import JSONResponse
                return JSONResponse({'detail':'Invalid request size'}, status_code=413)
        response = await call_next(request)
        if not request.url.path.startswith(('/sovera/account/media/','/sovera/control/media/')) or 'cache-control' not in response.headers:
            response.headers['Cache-Control'] = 'no-store'
        return response

    async def actor(authorization):
        if not authorization or not authorization.startswith('Bearer '):
            raise HTTPException(401, 'Sign in required')
        token = authorization[7:]
        if not 1 <= len(token) <= 16000:
            raise HTTPException(401, 'Invalid session')
        try:
            uid = await verify(token)
            if not isinstance(uid, str) or not 1 <= len(uid) <= 128:
                raise ValueError()
            return uid
        except Exception:
            raise HTTPException(401, 'Invalid session') from None

    @app.get('/sovera/account/health')
    def health():
        return {'ready':True, 'profiles':True, 'rooms':True, 'chat':True, 'voice':voice, 'room_effects':True, 'catalog':True, 'managed_banners':True, 'animated_gifts':True, 'free_duel':True, 'global_color_game':True, 'food_wheel_preview':True, 'greedy_ready':False, 'wallet':wallets.has_verified_wallets(), 'server_wallet_read':True, 'games':False}

    @app.get('/sovera/account')
    async def get_profile(authorization: str | None = Header(default=None)):
        uid = await actor(authorization)
        return {'profile':await asyncio.to_thread(profiles.get, uid)}

    @app.put('/sovera/account')
    async def save_profile(data:ProfileInput, authorization: str | None = Header(default=None)):
        uid = await actor(authorization)
        return {'profile':await asyncio.to_thread(profiles.save, uid, data)}
    from .profile_media import attach_profile_media
    attach_profile_media(app, profiles, actor)
    rooms = Rooms(profiles.path)
    from .room_photos import attach_room_photos
    attach_room_photos(app, rooms, actor)
    from .room_controls import attach_room_controls
    attach_room_controls(app, rooms, actor)
    wallets = WalletStore(profiles.path)
    from .broadcasts import attach_broadcasts
    attach_broadcasts(app, profiles.path, actor)
    attach_greedy_wallet(app, wallets)
    duel = RoomDuel(profiles.path)
    colors = GlobalColors(profiles.path)
    food_wheel = FoodWheel(profiles.path)
    attach_community(app, profiles, actor)
    attach_control(app, profiles, actor)
    attach_catalog(app, profiles, actor)

    @app.get('/sovera/account/wallet')
    async def wallet_state(authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(wallets.state,uid)

    @app.post('/sovera/account/wallet/exchange')
    async def exchange(data:ExchangeInput,authorization:str | None=Header(default=None)):
        return await asyncio.to_thread(wallets.exchange,await actor(authorization),data)

    @app.get('/sovera/account/wallet/history')
    async def wallet_history(authorization: str | None = Header(default=None),
            limit:int=Query(default=30,ge=1,le=100),
            before_time:int | None=Query(default=None,ge=0),
            before_ref:str | None=Query(default=None,min_length=1,max_length=250)):
        uid=await actor(authorization)
        if (before_time is None)!=(before_ref is None):
            raise HTTPException(400,'Both history cursor fields are required')
        rows=await asyncio.to_thread(wallets.history,uid,limit+1,before_time,before_ref)
        return {'entries':rows[:limit],'has_more':len(rows)>limit}

    @app.get('/sovera/account/rooms')
    async def directory(authorization: str | None = Header(default=None)):
        await actor(authorization)
        return {'rooms':await asyncio.to_thread(rooms.directory)}

    @app.post('/sovera/account/rooms')
    async def create_room(data:RoomInput, authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return {'room':await asyncio.to_thread(rooms.save,uid,data)}

    @app.put('/sovera/account/rooms/{room}')
    async def edit_room(room:str,data:RoomInput,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return {'room':await asyncio.to_thread(rooms.save,uid,data,room)}

    @app.put('/sovera/account/rooms/{room}/presence')
    async def join(room:str,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(rooms.presence,uid,room)

    @app.delete('/sovera/account/rooms/{room}/presence')
    async def leave(room:str,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(rooms.presence,uid,room,True)

    @app.get('/sovera/account/rooms/{room}/messages')
    async def messages(room:str,after:int=Query(default=0,ge=0),authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return {'messages':await asyncio.to_thread(rooms.messages,room,after,uid)}

    @app.post('/sovera/account/rooms/{room}/messages')
    async def send(room:str,data:MessageInput,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(rooms.send,uid,room,data)
    @app.get('/sovera/account/rooms/{room}/people')
    async def active_people(room:str,authorization: str | None = Header(default=None)):
        await actor(authorization)
        return {'people':await asyncio.to_thread(rooms.people,room)}

    @app.get('/sovera/account/rooms/{room}/effects')
    async def recent_effects(room:str,authorization: str | None = Header(default=None)):
        await actor(authorization)
        return await asyncio.to_thread(rooms.effects,room)

    @app.post('/sovera/account/rooms/{room}/effects')
    async def send_effect(room:str,data:RoomEffectInput,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(rooms.send_effect,uid,room,data)

    @app.get('/sovera/account/rooms/{room}/duel')
    async def duel_state(room:str,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(duel.state,room,uid)

    @app.post('/sovera/account/rooms/{room}/duel/join')
    async def duel_join(room:str,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(duel.join,uid,room)

    @app.post('/sovera/account/rooms/{room}/duel/cancel')
    async def duel_cancel_wait(room:str,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(duel.cancel_wait,uid,room)

    @app.post('/sovera/account/rooms/{room}/duel/move')
    async def duel_move(room:str,data:MoveInput,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(duel.move,uid,room,data)

    @app.post('/sovera/account/rooms/{room}/duel/restart')
    async def duel_restart(room:str,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(duel.restart,uid,room)

    @app.get('/sovera/account/games/colors')
    async def global_color_state(authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(colors.state,uid)

    @app.post('/sovera/account/games/colors/pick')
    async def global_color_pick(data:ColorPick,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(colors.pick,uid,data)

    @app.get('/sovera/account/wheel/state')
    async def wheel_state(authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(food_wheel.state,uid)

    @app.post('/sovera/account/wheel/pick')
    async def wheel_pick(data:FoodChoice,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(food_wheel.choose,uid,data)

    @app.post('/sovera/account/greedy/access')
    async def greedy_token(authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        profile=await asyncio.to_thread(profiles.get,uid)
        if profile is None:
            raise HTTPException(409,'Save your profile first')
        verified=await asyncio.to_thread(wallets.state,uid)
        if verified['canSpend'] is not True:
            raise HTTPException(503,'Game wallet migration and settlement not verified')
        return greedy_access(uid,profile)

    if voice:
        from .voice import attach_voice
        attach_voice(app, rooms, actor)
    return app

def create():
    if os.environ.get('SOVERA_FIREBASE_PROJECT') != 'sovera-app-7d1d6':
        raise RuntimeError('Unexpected Firebase project')
    path = Path(os.environ['SOVERA_ACCOUNT_DATABASE'])
    if not path.is_absolute() or not path.parent.is_dir():
        raise RuntimeError('Persistent account directory required')
    import firebase_admin
    from firebase_admin import auth
    app = firebase_admin.initialize_app(options={
        'projectId':'sovera-app-7d1d6', 'httpTimeout':10}, name='sovera-account')
    async def verify(token):
        claims = await asyncio.to_thread(auth.verify_id_token, token, app=app, check_revoked=True)
        uid = claims['uid']
        account = await asyncio.to_thread(auth.get_user, uid, app=app)
        if account.disabled:
            raise ValueError('Account unavailable')
        return uid
    return create_app(Profiles(path), verify, voice=os.environ.get('SOVERA_ACCOUNT_VOICE') == '1')
