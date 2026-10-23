"""Gallery room covers, owned by rooms rather than member profile photos."""
import asyncio
import hashlib
from fastapi import HTTPException, Request
from fastapi.responses import Response
from .profile_media import sanitize, MAX_UPLOAD
PUBLIC='https://voice.soverixnet.com/sovera/account/room-photo/'
CHAT_PUBLIC='https://voice.soverixnet.com/sovera/account/chat-photo/'

def attach_room_photos(app,rooms,actor):
    with rooms.db() as db:
        db.execute('CREATE TABLE IF NOT EXISTS account_room_photos(room TEXT NOT NULL,key TEXT PRIMARY KEY,data BLOB NOT NULL)')
    def owner(uid,room):
        with rooms.db() as db:
            row=db.execute('SELECT owner_uid FROM account_rooms WHERE id=?',(room,)).fetchone()
            if row is None: raise HTTPException(404,'Room not found')
            if row[0]!=uid: raise HTTPException(403,'Only the room owner can change its picture')
    def save(uid,room,data):
        owner(uid,room)
        photo=sanitize(data);key=hashlib.sha256(room.encode()+photo).hexdigest()
        with rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            current=db.execute('SELECT image_url,background_url FROM account_rooms WHERE id=?',(room,)).fetchone()
            keep=current[0].removeprefix(PUBLIC) if current[0] else ''
            background=current[1].removeprefix(PUBLIC) if current[1] else ''
            total=db.execute('SELECT COALESCE(SUM(length(data)),0) FROM account_room_photos WHERE room<>?',(room,)).fetchone()[0]
            if total+len(photo)>256*1024*1024: raise HTTPException(507,'Photo storage is full')
            db.execute('DELETE FROM account_room_photos WHERE room=? AND key<>? AND key<>?',(room,keep,background))
            db.execute('INSERT OR IGNORE INTO account_room_photos VALUES(?,?,?)',(room,key,photo))
        return {'avatar_url':PUBLIC+key}
    @app.post('/sovera/account/rooms/{room}/photo')
    async def upload(room:str,request:Request):
        uid=await actor(request.headers.get('authorization'))
        await asyncio.to_thread(owner,uid,room)
        data=bytearray()
        async for chunk in request.stream():
            data.extend(chunk)
            if len(data)>MAX_UPLOAD: raise HTTPException(413,'Photo is too large')
        return await asyncio.to_thread(save,uid,room,bytes(data))
    @app.get('/sovera/account/room-photo/{key}')
    def photo(key:str):
        if len(key)!=64 or any(c not in '0123456789abcdef' for c in key):raise HTTPException(404)
        with rooms.db() as db: row=db.execute('SELECT data FROM account_room_photos WHERE key=?',(key,)).fetchone()
        if row is None:raise HTTPException(404)
        return Response(bytes(row[0]),media_type='image/webp',headers={'X-Content-Type-Options':'nosniff','Cache-Control':'public, max-age=3600'})

    def save_chat(uid,room,data):
        photo=sanitize(data);key=hashlib.sha256((room+uid).encode()+photo).hexdigest()
        with rooms.db() as db:
            db.execute('BEGIN IMMEDIATE');rooms.exists(db,room);rooms.profile(db,uid)
            active=db.execute('SELECT 1 FROM account_presence WHERE uid=? AND room_id=? AND seen_at>?',(uid,room,rooms.clock()-90)).fetchone()
            if not active:raise HTTPException(403,'Join this room before sharing photos')
            settings=db.execute('SELECT chat_enabled,photo_min_level FROM account_rooms WHERE id=?',(room,)).fetchone()
            sent=db.execute("SELECT COALESCE(SUM(COALESCE((SELECT counted_coins FROM account_gift_counts gc WHERE gc.reference=account_wallet_ledger.reference),-coin_delta)),0) FROM account_wallet_ledger WHERE firebase_uid=? AND kind='gift' AND coin_delta<0",(uid,)).fetchone()[0]
            if not settings['chat_enabled'] or sent//10000<settings['photo_min_level']:raise HTTPException(403,'Room chat or photo permission is unavailable')
            if db.execute('SELECT 1 FROM account_chat_photos WHERE key=?',(key,)).fetchone():return {'avatar_url':CHAT_PUBLIC+key}
            last=db.execute('SELECT MAX(created_at) FROM account_chat_photos WHERE uid=?',(uid,)).fetchone()[0]
            if last is not None and rooms.clock()-last<5:raise HTTPException(429,'Wait before uploading another photo')
            total=db.execute('SELECT COALESCE(SUM(length(data)),0) FROM account_chat_photos').fetchone()[0]
            if total+len(photo)>256*1024*1024:raise HTTPException(507,'Chat photo storage is full')
            db.execute('INSERT INTO account_chat_photos VALUES(?,?,?,?,?)',(key,room,uid,photo,int(rooms.clock())))
        return {'avatar_url':CHAT_PUBLIC+key}
    @app.post('/sovera/account/rooms/{room}/chat-photo')
    async def upload_chat(room:str,request:Request):
        uid=await actor(request.headers.get('authorization'))
        data=bytearray()
        async for chunk in request.stream():
            data.extend(chunk)
            if len(data)>MAX_UPLOAD:raise HTTPException(413,'Photo is too large')
        return await asyncio.to_thread(save_chat,uid,room,bytes(data))
    @app.get('/sovera/account/chat-photo/{key}')
    def chat_photo(key:str):
        if len(key)!=64 or any(c not in '0123456789abcdef' for c in key):raise HTTPException(404)
        with rooms.db() as db:row=db.execute('SELECT data FROM account_chat_photos WHERE key=?',(key,)).fetchone()
        if row is None:raise HTTPException(404)
        return Response(bytes(row[0]),media_type='image/webp',headers={'X-Content-Type-Options':'nosniff','Cache-Control':'public, max-age=3600'})
