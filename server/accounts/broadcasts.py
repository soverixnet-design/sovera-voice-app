"""Public celebrations are written inside successful wallet transactions only."""
import asyncio
import json
import sqlite3
import time
from fastapi import Header, Query

SCHEMA='''CREATE TABLE IF NOT EXISTS account_broadcasts(
 id INTEGER PRIMARY KEY AUTOINCREMENT,event_key TEXT NOT NULL UNIQUE,
 kind TEXT NOT NULL,payload TEXT NOT NULL,created_at INTEGER NOT NULL);
 CREATE INDEX IF NOT EXISTS account_broadcast_time ON account_broadcasts(created_at,id);'''

def initialize(db): db.executescript(SCHEMA)

def person(db,uid):
    row=db.execute('SELECT display_name,avatar_url FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone()
    if row is None: return None
    from .wallet import legacy_identity
    return {'name':row[0],'avatar_url':row[1]}|legacy_identity(db,uid)

def emit(db,key,kind,payload):
    now=int(time.time())
    db.execute('INSERT OR IGNORE INTO account_broadcasts(event_key,kind,payload,created_at) VALUES(?,?,?,?)',(key,kind,json.dumps(payload),now))
    db.execute('DELETE FROM account_broadcasts WHERE created_at<?',(now-600,))

class Broadcasts:
    def __init__(self,path):
        self.path=str(path)
        with sqlite3.connect(self.path) as db: initialize(db)
    def read(self,after=None):
        now=int(time.time())
        with sqlite3.connect(self.path) as db:
            rows=db.execute('SELECT id,kind,payload,created_at FROM account_broadcasts WHERE id>? AND created_at>=? ORDER BY id LIMIT 30',(after or 0,now-(10 if after is None else 120))).fetchall()
            cursor=rows[-1][0] if rows else max(after or 0,db.execute('SELECT COALESCE(MAX(id),0) FROM account_broadcasts').fetchone()[0])
        return {'cursor':cursor,'server_now':now,'items':[{'id':r[0],'kind':r[1],'created_at':r[3],**json.loads(r[2])} for r in rows]}

def attach_broadcasts(app,path,actor):
    service=Broadcasts(path)
    @app.get('/sovera/account/broadcasts')
    async def feed(after:int | None=Query(default=None,ge=0,le=9007199254740991),authorization:str | None=Header(default=None)):
        await actor(authorization)
        return await asyncio.to_thread(service.read,after)
