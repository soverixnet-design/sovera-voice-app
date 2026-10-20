"""Persistent public room directory and chat, without voice or coin claims."""
from contextlib import contextmanager
import sqlite3
import time
import uuid
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field
from typing import Literal

class RoomInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    name:str=Field(min_length=1,max_length=40)
    seats:int=Field(default=9,strict=True)
    room_frame:Literal["none","coins_seller","official"]|None=None

class MessageInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    text:str=Field(min_length=1,max_length=500)
    request_id:uuid.UUID

class RoomEffectInput(BaseModel):
    """Cosmetic only. This API never debits Coins or awards Diamonds."""
    model_config=ConfigDict(extra='forbid')
    recipient_uid:str=Field(min_length=1,max_length=128)
    kind:Literal['rose','heart','sparkle','crown']
    request_id:uuid.UUID

class Rooms:
    def __init__(self,path,clock=time.time):
        self.path,self.clock=str(path),clock
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS account_blocks(uid TEXT NOT NULL,target TEXT NOT NULL,
              created_at INTEGER NOT NULL,PRIMARY KEY(uid,target));
            CREATE TABLE IF NOT EXISTS account_rooms(
              id TEXT PRIMARY KEY,owner_uid TEXT NOT NULL UNIQUE,name TEXT NOT NULL,
              seats INTEGER NOT NULL,created_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS account_presence(
              uid TEXT PRIMARY KEY,room_id TEXT NOT NULL,seen_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS account_messages(
              id INTEGER PRIMARY KEY AUTOINCREMENT,room_id TEXT NOT NULL,
              sender_uid TEXT NOT NULL,request_id TEXT NOT NULL,text TEXT NOT NULL,
              name TEXT NOT NULL,country TEXT NOT NULL,created_at REAL NOT NULL,
              UNIQUE(sender_uid,request_id));
            CREATE INDEX IF NOT EXISTS account_message_room ON account_messages(room_id,id);
            CREATE INDEX IF NOT EXISTS account_presence_room ON account_presence(room_id,seen_at);
            CREATE TABLE IF NOT EXISTS account_room_effects(
              id INTEGER PRIMARY KEY AUTOINCREMENT,room_id TEXT NOT NULL,
              sender_uid TEXT NOT NULL,recipient_uid TEXT NOT NULL,
              request_id TEXT NOT NULL,kind TEXT NOT NULL,
              sender_name TEXT NOT NULL,recipient_name TEXT NOT NULL,
              created_at REAL NOT NULL,UNIQUE(sender_uid,request_id));
            CREATE INDEX IF NOT EXISTS account_effect_room_time
              ON account_room_effects(room_id,created_at DESC,id DESC);
            ''')
            columns={r['name'] for r in db.execute('PRAGMA table_info(account_rooms)')}
            if 'room_frame' not in columns:
                db.execute("ALTER TABLE account_rooms ADD COLUMN room_frame TEXT NOT NULL DEFAULT 'none'")
    @contextmanager
    def db(self):
        db=sqlite3.connect(self.path,timeout=10)
        db.row_factory=sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()
    def profile(self,db,uid):
        p=db.execute('SELECT * FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone()
        if not p: raise HTTPException(409,'Save your profile first')
        return p
    def exists(self,db,room):
        if not db.execute('SELECT 1 FROM account_rooms WHERE id=?',(room,)).fetchone():
            raise HTTPException(404,'Room not found')
    def directory(self):
        with self.db() as db:
            from .catalog import equipped_assets
            return [dict(r)|{'equipped':equipped_assets(db,r['owner_uid'])} for r in db.execute('''SELECT r.*,p.display_name AS owner_name,
                p.country,p.avatar_url,(SELECT count(*) FROM account_presence a
                WHERE a.room_id=r.id AND a.seen_at>?) AS occupants
                FROM account_rooms r JOIN account_profiles p ON p.firebase_uid=r.owner_uid
                ORDER BY r.created_at DESC LIMIT 100''',(self.clock()-90,)).fetchall()]
    def save(self,uid,data,room=None):
        if data.seats not in (5,6,9,12,15): raise HTTPException(422,'Choose 5, 6, 9, 12 or 15 seats')
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.profile(db,uid)
            existing=db.execute('SELECT * FROM account_rooms WHERE owner_uid=?',(uid,)).fetchone()
            if room:
                self.exists(db,room)
                if not existing or existing['id']!=room: raise HTTPException(403,'Only the room owner can edit it')
                db.execute('UPDATE account_rooms SET name=?,seats=?,room_frame=? WHERE id=?',(data.name,data.seats,data.room_frame if data.room_frame is not None else existing['room_frame'],room))
            elif existing:
                return dict(existing)
            else:
                room=str(uuid.uuid4())
                db.execute('INSERT INTO account_rooms(id,owner_uid,name,seats,created_at,room_frame) VALUES(?,?,?,?,?,?)',(room,uid,data.name,data.seats,self.clock(),data.room_frame or 'none'))
            return dict(db.execute('SELECT * FROM account_rooms WHERE id=?',(room,)).fetchone())
    def presence(self,uid,room,leave=False):
        with self.db() as db:
            self.exists(db,room)
            if leave: db.execute('DELETE FROM account_presence WHERE uid=? AND room_id=?',(uid,room))
            else:
                self.profile(db,uid)
                before=db.execute('SELECT room_id,seen_at FROM account_presence WHERE uid=?',(uid,)).fetchone()
                db.execute('INSERT INTO account_presence VALUES(?,?,?) ON CONFLICT(uid) DO UPDATE SET room_id=excluded.room_id,seen_at=excluded.seen_at',(uid,room,self.clock()))
                if not before or before['room_id']!=room or before['seen_at']<=self.clock()-90:
                    from .catalog import equipped_assets
                    entry=equipped_assets(db,uid).get('entry')
                    if entry:db.execute('INSERT INTO account_catalog_events(room_id,sender_uid,recipient_uid,item_id,created_at) VALUES(?,?,?,?,?)',(room,uid,uid,entry['id'],int(self.clock())))
            return {'saved':True}
    def messages(self,room,after=0,viewer=None):
        with self.db() as db:
            self.exists(db,room)
            sql='''SELECT id,text,name,country,created_at,sender_uid AS uid
                FROM account_messages m WHERE room_id=? AND NOT EXISTS(
                SELECT 1 FROM account_blocks b WHERE b.uid=? AND b.target=m.sender_uid)'''
            if after:
                rows=db.execute(sql+' AND id>? ORDER BY id LIMIT 50',(room,viewer,after)).fetchall()
            else:
                rows=list(reversed(db.execute(sql+' ORDER BY id DESC LIMIT 50',(room,viewer)).fetchall()))
            return [dict(r) for r in rows]
    def people(self,room):
        """Only heartbeat-confirmed participants, with server-owned names/UIDs."""
        with self.db() as db:
            self.exists(db,room)
            from .catalog import equipped_assets
            from .wallet import legacy_identity
            return [dict(r)|legacy_identity(db,r['uid'])|{'equipped':equipped_assets(db,r['uid'])} for r in db.execute('''SELECT p.firebase_uid AS uid,
                p.display_name AS name,p.country,p.avatar_url FROM account_presence a
                JOIN account_profiles p ON p.firebase_uid=a.uid
                WHERE a.room_id=? AND a.seen_at>? ORDER BY p.display_name,p.firebase_uid
                LIMIT 100''',(room,self.clock()-90)).fetchall()]

    def effects(self,room):
        """Short-lived public room animation history; always use server time."""
        with self.db() as db:
            self.exists(db,room)
            now=self.clock()
            rows=db.execute('''SELECT id,kind,sender_uid,recipient_uid,sender_name,
                recipient_name,created_at FROM account_room_effects
                WHERE room_id=? AND created_at>? ORDER BY id DESC LIMIT 20''',
                (room,now-15)).fetchall()
            return {'effects':[dict(r) for r in reversed(rows)],'server_now':now}

    def send_effect(self,uid,room,data):
        """Idempotent, rate-limited and authenticated. No wallet writes whatsoever."""
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.exists(db,room)
            sender=self.profile(db,uid)
            key=str(data.request_id)
            prior=db.execute('''SELECT * FROM account_room_effects
                WHERE sender_uid=? AND request_id=?''',(uid,key)).fetchone()
            if prior:
                if (prior['room_id'],prior['recipient_uid'],prior['kind']) != (room,data.recipient_uid,data.kind):
                    raise HTTPException(409,'Effect request was already used')
                return {'id':prior['id'],'saved':True,'visual_only':True}
            now=self.clock()
            for participant in (uid,data.recipient_uid):
                active=db.execute('''SELECT 1 FROM account_presence
                    WHERE uid=? AND room_id=? AND seen_at>?''',(participant,room,now-90)).fetchone()
                if active is None:
                    raise HTTPException(409,'Both members must be in this room')
            recipient=self.profile(db,data.recipient_uid)
            last=db.execute('''SELECT max(created_at) FROM account_room_effects
                WHERE sender_uid=?''',(uid,)).fetchone()[0]
            if last is not None and now-last<3:
                raise HTTPException(429,'Wait before sending another effect')
            cur=db.execute('''INSERT INTO account_room_effects
                (room_id,sender_uid,recipient_uid,request_id,kind,
                sender_name,recipient_name,created_at) VALUES (?,?,?,?,?,?,?,?)''',
                (room,uid,data.recipient_uid,key,data.kind,
                 sender['display_name'],recipient['display_name'],now))
            return {'id':cur.lastrowid,'saved':True,'visual_only':True}

    def send(self,uid,room,data):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.exists(db,room);p=self.profile(db,uid)
            old=db.execute('SELECT * FROM account_messages WHERE sender_uid=? AND request_id=?',(uid,str(data.request_id))).fetchone()
            if old:
                if old['text']!=data.text or old['room_id']!=room: raise HTTPException(409,'Request ID already used')
                return {'id':old['id']}
            last=db.execute('SELECT max(created_at) FROM account_messages WHERE sender_uid=?',(uid,)).fetchone()[0]
            if last is not None and self.clock()-last<1: raise HTTPException(429,'Wait before sending another message')
            cur=db.execute('INSERT INTO account_messages(room_id,sender_uid,request_id,text,name,country,created_at) VALUES(?,?,?,?,?,?,?)',(room,uid,str(data.request_id),data.text,p['display_name'],p['country'],self.clock()))
            return {'id':cur.lastrowid}
