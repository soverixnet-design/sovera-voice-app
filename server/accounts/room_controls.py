"""Room-scoped staff and persistent microphone locks; no global staff privileges."""
import asyncio
from fastapi import Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt

class SeatLock(BaseModel):
    model_config=ConfigDict(extra='forbid')
    locked: StrictBool
    seat: StrictInt | None=None

class RoomAdmin(BaseModel):
    model_config=ConfigDict(extra='forbid')
    uid: str=Field(min_length=1,max_length=128)
    enabled: StrictBool

class RoomControls:
    def __init__(self,rooms):
        self.rooms=rooms
        with rooms.db() as db:
            db.executescript('''CREATE TABLE IF NOT EXISTS account_room_admins(room TEXT NOT NULL,uid TEXT NOT NULL,PRIMARY KEY(room,uid));
            CREATE TABLE IF NOT EXISTS account_seat_locks(room TEXT NOT NULL,seat INTEGER NOT NULL,PRIMARY KEY(room,seat));''')
    def role(self,db,uid,room):
        row=db.execute('SELECT owner_uid,seats FROM account_rooms WHERE id=?',(room,)).fetchone()
        if row is None: raise HTTPException(404,'Room not found')
        role='owner' if row['owner_uid']==uid else 'admin' if db.execute('SELECT 1 FROM account_room_admins WHERE room=? AND uid=?',(room,uid)).fetchone() else 'member'
        return role,row['seats']
    def state(self,uid,room):
        with self.rooms.db() as db:
            role,count=self.role(db,uid,room)
            return {'room':dict(db.execute('SELECT name,seats,image_url FROM account_rooms WHERE id=?',(room,)).fetchone()),'role':role,'locked_seats':[r[0] for r in db.execute('SELECT seat FROM account_seat_locks WHERE room=? AND seat<? ORDER BY seat',(room,count))],
                    'admins':[dict(r) for r in db.execute('SELECT a.uid,p.display_name AS name FROM account_room_admins a JOIN account_profiles p ON p.firebase_uid=a.uid WHERE a.room=?',(room,))]}
    def lock(self,uid,room,data):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            role,count=self.role(db,uid,room)
            if role=='member': raise HTTPException(403,'Room staff only')
            if data.seat is not None and not 0<=data.seat<count: raise HTTPException(422,'Invalid seat')
            targets=range(count) if data.seat is None else [data.seat]
            for seat in targets:
                if data.locked: db.execute('INSERT OR IGNORE INTO account_seat_locks VALUES(?,?)',(room,seat))
                else: db.execute('DELETE FROM account_seat_locks WHERE room=? AND seat=?',(room,seat))
        return self.state(uid,room)
    def admin(self,uid,room,data):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            role,_=self.role(db,uid,room)
            if role!='owner': raise HTTPException(403,'Only the room owner can assign admins')
            self.rooms.profile(db,data.uid)
            owner=db.execute('SELECT owner_uid FROM account_rooms WHERE id=?',(room,)).fetchone()[0]
            if data.uid==owner: raise HTTPException(400,'Owner already has room permissions')
            if data.enabled: db.execute('INSERT OR IGNORE INTO account_room_admins VALUES(?,?)',(room,data.uid))
            else: db.execute('DELETE FROM account_room_admins WHERE room=? AND uid=?',(room,data.uid))
        return self.state(uid,room)
    def check_take(self,uid,room,seat):
        with self.rooms.db() as db:
            role,_=self.role(db,uid,room)
            if role=='member' and db.execute('SELECT 1 FROM account_seat_locks WHERE room=? AND seat=?',(room,seat)).fetchone():
                raise HTTPException(403,'This mic seat is locked')

def attach_room_controls(app,rooms,actor):
    service=RoomControls(rooms)
    @app.get('/sovera/account/rooms/{room}/controls')
    async def state(room:str,authorization:str | None=Header(default=None)):
        return await asyncio.to_thread(service.state,await actor(authorization),room)
    @app.put('/sovera/account/rooms/{room}/seat-lock')
    async def seat_lock(room:str,data:SeatLock,authorization:str | None=Header(default=None)):
        return await asyncio.to_thread(service.lock,await actor(authorization),room,data)
    @app.put('/sovera/account/rooms/{room}/admins')
    async def admin(room:str,data:RoomAdmin,authorization:str | None=Header(default=None)):
        return await asyncio.to_thread(service.admin,await actor(authorization),room,data)
    return service
