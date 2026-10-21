"""Gallery room covers, owned by rooms rather than member profile photos."""
import asyncio
import hashlib
from fastapi import HTTPException, Request
from fastapi.responses import Response
from .profile_media import sanitize, MAX_UPLOAD
PUBLIC='https://voice.soverixnet.com/sovera/account/room-photo/'

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
            current=db.execute('SELECT image_url FROM account_rooms WHERE id=?',(room,)).fetchone()[0]
            keep=current.removeprefix(PUBLIC) if current else ''
            total=db.execute('SELECT COALESCE(SUM(length(data)),0) FROM account_room_photos WHERE room<>?',(room,)).fetchone()[0]
            if total+len(photo)>256*1024*1024: raise HTTPException(507,'Photo storage is full')
            db.execute('DELETE FROM account_room_photos WHERE room=? AND key<>?',(room,keep))
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
