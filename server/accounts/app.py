"""Firebase-authenticated account profiles. No wallets or staff roles here."""
import asyncio
import os
import sqlite3
import time
from pathlib import Path
from fastapi import FastAPI, Header, HTTPException, Query
from .rooms import Rooms, RoomInput, MessageInput
from pydantic import BaseModel, ConfigDict, Field, field_validator

class ProfileInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    display_name: str = Field(min_length=1, max_length=40)
    country: str = Field(pattern=r'^[A-Z]{2}$')
    bio: str = Field(default='', max_length=150)
    avatar_url: str | None = Field(default=None, max_length=2000)

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

    def get(self, uid):
        with sqlite3.connect(self.path, timeout=10) as db:
            db.row_factory = sqlite3.Row
            row = db.execute('SELECT * FROM account_profiles WHERE firebase_uid=?', (uid,)).fetchone()
            return dict(row) if row else None

    def save(self, uid, data):
        with sqlite3.connect(self.path, timeout=10) as db:
            db.execute('''INSERT INTO account_profiles VALUES(?,?,?,?,?,?)
                ON CONFLICT(firebase_uid) DO UPDATE SET display_name=excluded.display_name,
                country=excluded.country,bio=excluded.bio,avatar_url=excluded.avatar_url,
                updated_at=excluded.updated_at''', (uid, data.display_name, data.country,
                    data.bio, data.avatar_url, int(time.time())))
        return self.get(uid)

def create_app(profiles, verify, *, voice=False):
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware('http')
    async def private_responses(request, call_next):
        if request.method in ('PUT', 'POST'):
            length = request.headers.get('content-length')
            if length is None or not length.isdecimal() or int(length)>8192:
                from fastapi.responses import JSONResponse
                return JSONResponse({'detail':'Invalid request size'}, status_code=413)
        response = await call_next(request)
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
        return {'ready':True, 'profiles':True, 'rooms':True, 'chat':True, 'voice':voice, 'wallet':False, 'games':False}

    @app.get('/sovera/account')
    async def get_profile(authorization: str | None = Header(default=None)):
        uid = await actor(authorization)
        return {'profile':await asyncio.to_thread(profiles.get, uid)}

    @app.put('/sovera/account')
    async def save_profile(data:ProfileInput, authorization: str | None = Header(default=None)):
        uid = await actor(authorization)
        return {'profile':await asyncio.to_thread(profiles.save, uid, data)}
    rooms = Rooms(profiles.path)

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
        await actor(authorization)
        return {'messages':await asyncio.to_thread(rooms.messages,room,after)}

    @app.post('/sovera/account/rooms/{room}/messages')
    async def send(room:str,data:MessageInput,authorization: str | None = Header(default=None)):
        uid=await actor(authorization)
        return await asyncio.to_thread(rooms.send,uid,room,data)
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
