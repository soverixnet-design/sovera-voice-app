"""Persistent community features using the same verified Firebase identity."""
import asyncio
import sqlite3
import time
import uuid
from contextlib import contextmanager
from typing import Literal
from fastapi import Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field

class CommunityText(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    text: str = Field(min_length=1, max_length=1000)
    request_id: uuid.UUID

class Publication(CommunityText):
    title: str = Field(min_length=1, max_length=100)
    section: Literal['notices', 'events']

class Community:
    def __init__(self, path):
        self.path = str(path)
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS account_follows(uid TEXT NOT NULL, room TEXT NOT NULL,
              PRIMARY KEY(uid,room));
            CREATE TABLE IF NOT EXISTS account_moments(id INTEGER PRIMARY KEY AUTOINCREMENT,
              uid TEXT NOT NULL,text TEXT NOT NULL,request_id TEXT NOT NULL,created_at INTEGER NOT NULL,
              UNIQUE(uid,request_id));
            CREATE TABLE IF NOT EXISTS account_support(id INTEGER PRIMARY KEY AUTOINCREMENT,
              uid TEXT NOT NULL,text TEXT NOT NULL,request_id TEXT NOT NULL,created_at INTEGER NOT NULL,
              reply TEXT NOT NULL DEFAULT '',UNIQUE(uid,request_id));
            CREATE TABLE IF NOT EXISTS account_staff(uid TEXT PRIMARY KEY,
              role TEXT NOT NULL CHECK(role IN ('owner','admin','support')));
            CREATE TABLE IF NOT EXISTS account_publications(id INTEGER PRIMARY KEY AUTOINCREMENT,
              section TEXT NOT NULL,title TEXT NOT NULL,text TEXT NOT NULL,uid TEXT NOT NULL,
              request_id TEXT NOT NULL,created_at INTEGER NOT NULL,UNIQUE(uid,request_id));
            CREATE INDEX IF NOT EXISTS account_support_owner ON account_support(uid,id);
            ''')

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def role(self, uid):
        with self.db() as db:
            row = db.execute('SELECT role FROM account_staff WHERE uid=?', (uid,)).fetchone()
            return row['role'] if row else None

    def require_staff(self, uid, publish=False):
        role = self.role(uid)
        if role not in (('owner','admin') if publish else ('owner','admin','support')):
            raise HTTPException(403, 'Staff permission required')

    def list(self, uid, section):
        with self.db() as db:
            if section == 'follows':
                return [dict(r) for r in db.execute('SELECT room FROM account_follows WHERE uid=? ORDER BY room', (uid,))]
            if section == 'members':
                return [dict(r) for r in db.execute('SELECT firebase_uid AS uid,display_name AS name,country,avatar_url FROM account_profiles ORDER BY display_name,firebase_uid LIMIT 100')]
            if section == 'moments':
                return [dict(r) for r in db.execute('''SELECT m.id,m.uid,m.text,m.created_at,p.display_name AS name
                  FROM account_moments m JOIN account_profiles p ON p.firebase_uid=m.uid
                  ORDER BY m.id DESC LIMIT 50''')]
            if section == 'support':
                return [dict(r) for r in db.execute('SELECT id,text,reply,created_at FROM account_support WHERE uid=? ORDER BY id DESC LIMIT 50', (uid,))]
            if section in ('notices','events'):
                return [dict(r) for r in db.execute('SELECT id,title,text,created_at FROM account_publications WHERE section=? ORDER BY id DESC LIMIT 50', (section,))]
            raise HTTPException(404)

    def write(self, uid, section, data):
        table = {'moments':'account_moments','support':'account_support'}[section]
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?', (uid,)).fetchone():
                raise HTTPException(409, 'Save your profile first')
            prev = db.execute(f'SELECT id,text FROM {table} WHERE uid=? AND request_id=?', (uid,str(data.request_id))).fetchone()
            if prev:
                if prev['text'] != data.text:
                    raise HTTPException(409, 'Request already used')
                return {'saved':True,'id':prev['id']}
            now = int(time.time())
            last = db.execute(f'SELECT MAX(created_at) FROM {table} WHERE uid=?', (uid,)).fetchone()[0]
            if last is not None and now-last < 5:
                raise HTTPException(429, 'Please wait before posting again')
            row = db.execute(f'INSERT INTO {table}(uid,text,request_id,created_at) VALUES(?,?,?,?)', (uid,data.text,str(data.request_id),now))
            return {'saved':True,'id':row.lastrowid}

    def follow(self, uid, room, enabled):
        with self.db() as db:
            if not db.execute('SELECT 1 FROM account_rooms WHERE id=?', (room,)).fetchone():
                raise HTTPException(404, 'Room not found')
            if enabled:
                db.execute('INSERT OR IGNORE INTO account_follows VALUES(?,?)', (uid,room))
            else:
                db.execute('DELETE FROM account_follows WHERE uid=? AND room=?', (uid,room))
        return {'saved':True,'following':enabled}

    def publish(self, uid, data):
        self.require_staff(uid, publish=True)
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            prev = db.execute('SELECT * FROM account_publications WHERE uid=? AND request_id=?', (uid,str(data.request_id))).fetchone()
            if prev:
                if (prev['title'],prev['text'],prev['section']) != (data.title,data.text,data.section):
                    raise HTTPException(409, 'Request already used')
                return {'saved':True,'id':prev['id']}
            row = db.execute('INSERT INTO account_publications(section,title,text,uid,request_id,created_at) VALUES(?,?,?,?,?,?)', (data.section,data.title,data.text,uid,str(data.request_id),int(time.time())))
            return {'saved':True,'id':row.lastrowid}

    def inbox(self, uid):
        self.require_staff(uid)
        with self.db() as db:
            return [dict(r) for r in db.execute('''SELECT t.id,t.text,t.reply,t.created_at,p.display_name AS name
              FROM account_support t JOIN account_profiles p ON p.firebase_uid=t.uid
              ORDER BY t.id DESC LIMIT 100''')]

    def reply(self, uid, ticket, text):
        self.require_staff(uid)
        with self.db() as db:
            row = db.execute('UPDATE account_support SET reply=? WHERE id=?', (text,ticket))
            if row.rowcount != 1:
                raise HTTPException(404, 'Ticket not found')
        return {'saved':True}

def attach_community(app, profiles, actor):
    service = Community(profiles.path)

    @app.get('/sovera/account/community/{section}')
    async def listing(section: str, authorization: str | None = Header(default=None)):
        uid = await actor(authorization)
        return {'items':await asyncio.to_thread(service.list,uid,section)}

    @app.post('/sovera/account/community/{section}')
    async def posting(section: str, data: CommunityText, authorization: str | None = Header(default=None)):
        uid = await actor(authorization)
        if section not in ('moments','support'):
            raise HTTPException(404)
        return await asyncio.to_thread(service.write,uid,section,data)

    @app.put('/sovera/account/community/follows/{room}')
    async def follow(room: str, authorization: str | None = Header(default=None)):
        return await asyncio.to_thread(service.follow,await actor(authorization),room,True)

    @app.delete('/sovera/account/community/follows/{room}')
    async def unfollow(room: str, authorization: str | None = Header(default=None)):
        return await asyncio.to_thread(service.follow,await actor(authorization),room,False)

    @app.get('/sovera/account/staff')
    async def permissions(authorization: str | None = Header(default=None)):
        return {'role':await asyncio.to_thread(service.role,await actor(authorization))}

    @app.post('/sovera/account/staff/publications')
    async def publication(data: Publication, authorization: str | None = Header(default=None)):
        return await asyncio.to_thread(service.publish,await actor(authorization),data)

    @app.get('/sovera/account/staff/support')
    async def inbox(authorization: str | None = Header(default=None)):
        return {'items':await asyncio.to_thread(service.inbox,await actor(authorization))}

    @app.put('/sovera/account/staff/support/{ticket}')
    async def reply(ticket: int, data: CommunityText, authorization: str | None = Header(default=None)):
        return await asyncio.to_thread(service.reply,await actor(authorization),ticket,data.text)
