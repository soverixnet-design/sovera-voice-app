"""Room-scoped staff and persistent microphone locks; no global staff privileges."""
import asyncio
import time
import uuid
from typing import Literal
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

class ReactionInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    emoji:Literal['😂','😍','😎','🔥','👏','🎉','😭','😡','🥳','😘','🤩','👍','🙏','💯','😴','💖']
    request_id:uuid.UUID

class ModerateInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    action:Literal['mute','unmute','down','kick','unban','mute_all','unmute_all']
    target_uid:str|None=Field(default=None,min_length=1,max_length=128)

class RoomControls:
    def __init__(self,rooms):
        self.rooms=rooms
        with rooms.db() as db:
            db.executescript('''CREATE TABLE IF NOT EXISTS account_room_reactions(id INTEGER PRIMARY KEY AUTOINCREMENT,room TEXT NOT NULL,uid TEXT NOT NULL,emoji TEXT NOT NULL,request_id TEXT NOT NULL,created_at INTEGER NOT NULL,UNIQUE(uid,request_id));
            CREATE TABLE IF NOT EXISTS account_room_bans(room TEXT NOT NULL,uid TEXT NOT NULL,PRIMARY KEY(room,uid));
            CREATE TABLE IF NOT EXISTS account_room_mutes(room TEXT NOT NULL,uid TEXT NOT NULL,PRIMARY KEY(room,uid));
            CREATE TABLE IF NOT EXISTS account_room_admins(room TEXT NOT NULL,uid TEXT NOT NULL,PRIMARY KEY(room,uid));
            CREATE TABLE IF NOT EXISTS account_seat_locks(room TEXT NOT NULL,seat INTEGER NOT NULL,PRIMARY KEY(room,seat));''')
    def role(self,db,uid,room):
        row=db.execute('SELECT owner_uid,seats FROM account_rooms WHERE id=?',(room,)).fetchone()
        if row is None: raise HTTPException(404,'Room not found')
        role='owner' if row['owner_uid']==uid else 'admin' if db.execute('SELECT 1 FROM account_room_admins WHERE room=? AND uid=?',(room,uid)).fetchone() else 'member'
        return role,row['seats']
    def state(self,uid,room):
        with self.rooms.db() as db:
            role,count=self.role(db,uid,room)
            self.rooms.check_member(db,uid,room)
            return {'room':dict(db.execute('SELECT name,seats,image_url,background_url,theme,chat_enabled,photo_min_level,seat_style FROM account_rooms WHERE id=?',(room,)).fetchone()),'role':role,'locked_seats':[r[0] for r in db.execute('SELECT seat FROM account_seat_locks WHERE room=? AND seat<? ORDER BY seat',(room,count))],
                    'reactions':[dict(r) for r in db.execute('SELECT id,uid,emoji,created_at FROM account_room_reactions WHERE room=? AND created_at>? ORDER BY id LIMIT 100',(room,int(time.time())-12))],'server_now':int(time.time()),
                    'muted_uids':[r[0] for r in db.execute('SELECT uid FROM account_room_mutes WHERE room=?',(room,))],
                    'banned':[dict(r) for r in db.execute('SELECT b.uid,p.display_name AS name FROM account_room_bans b JOIN account_profiles p ON p.firebase_uid=b.uid WHERE b.room=?',(room,))] if role!='member' else [],
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
    def react(self,uid,room,data):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE');self.rooms.exists(db,room);self.rooms.check_member(db,uid,room)
            if not db.execute('SELECT 1 FROM account_presence WHERE uid=? AND room_id=? AND seen_at>?',(uid,room,time.time()-90)).fetchone():raise HTTPException(403,'Join this room first')
            prior=db.execute('SELECT * FROM account_room_reactions WHERE uid=? AND request_id=?',(uid,str(data.request_id))).fetchone()
            if prior:
                if (prior['room'],prior['emoji'])!=(room,data.emoji):raise HTTPException(409,'Request already used')
                return {'saved':True,'id':prior['id']}
            now=int(time.time())
            if db.execute('SELECT 1 FROM account_room_reactions WHERE uid=? AND created_at>?',(uid,now-2)).fetchone():raise HTTPException(429,'Wait before another reaction')
            db.execute('DELETE FROM account_room_reactions WHERE created_at<?',(now-60,))
            row=db.execute('INSERT INTO account_room_reactions(room,uid,emoji,request_id,created_at) VALUES(?,?,?,?,?)',(room,uid,data.emoji,str(data.request_id),now))
            return {'saved':True,'id':row.lastrowid}
    def moderate(self,uid,room,data):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            role,_=self.role(db,uid,room)
            if role=='member':raise HTTPException(403,'Room staff only')
            targets=[data.target_uid] if data.target_uid else []
            if data.action.endswith('_all'):targets=[r[0] for r in db.execute('SELECT uid FROM account_presence WHERE room_id=?',(room,))]
            if not targets and not data.action.endswith('_all'):raise HTTPException(422,'Select a member')
            changed=[]
            for target in targets:
                target_role,_=self.role(db,target,room)
                if target==uid or target_role=='owner' or (target_role=='admin' and role!='owner'):
                    if data.action.endswith('_all'):continue
                    raise HTTPException(403,'Cannot moderate this room staff member')
                if data.action in ('mute','mute_all'):db.execute('INSERT OR IGNORE INTO account_room_mutes VALUES(?,?)',(room,target))
                elif data.action in ('unmute','unmute_all'):db.execute('DELETE FROM account_room_mutes WHERE room=? AND uid=?',(room,target))
                elif data.action=='kick':
                    db.execute('INSERT OR IGNORE INTO account_room_bans VALUES(?,?)',(room,target))
                    db.execute('DELETE FROM account_presence WHERE room_id=? AND uid=?',(room,target))
                elif data.action=='unban':db.execute('DELETE FROM account_room_bans WHERE room=? AND uid=?',(room,target))
                changed.append(target)
            return changed

    def can_publish(self,uid,room):
        with self.rooms.db() as db:
            return not bool(db.execute('SELECT 1 FROM account_room_mutes WHERE room=? AND uid=?',(room,uid)).fetchone())
    def check_take(self,uid,room,seat):
        with self.rooms.db() as db:
            role,_=self.role(db,uid,room)
            self.rooms.check_member(db,uid,room)
            if db.execute('SELECT 1 FROM account_room_mutes WHERE room=? AND uid=?',(room,uid)).fetchone():raise HTTPException(403,'Room staff muted your microphone')
            if role=='member' and db.execute('SELECT 1 FROM account_seat_locks WHERE room=? AND seat=?',(room,seat)).fetchone():
                raise HTTPException(403,'This mic seat is locked')

def attach_room_controls(app,rooms,actor):
    service=RoomControls(rooms)
    @app.post('/sovera/account/rooms/{room}/reaction')
    async def react(room:str,data:ReactionInput,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.react,await actor(authorization),room,data)
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
