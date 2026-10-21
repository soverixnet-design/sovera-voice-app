"""Private conversations, owner-approved sellers and official account receipts."""
import asyncio
import time
import uuid
from fastapi import Header, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
from .community import Community

class MessageInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    text: str = Field(min_length=1,max_length=1000)
    request_id: uuid.UUID

class NoticeInput(MessageInput):
    target_uid: str = Field(min_length=1,max_length=128)
    title: str = Field(min_length=1,max_length=100)

class SellerInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    target_uid: str = Field(min_length=1,max_length=128)
    enabled: bool = Field(strict=True)


def schema(db):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS account_coin_sellers(uid TEXT PRIMARY KEY,actor TEXT NOT NULL,created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_official_messages(id INTEGER PRIMARY KEY AUTOINCREMENT,event_key TEXT UNIQUE NOT NULL,target TEXT NOT NULL,title TEXT NOT NULL,text TEXT NOT NULL,created_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS account_official_target ON account_official_messages(target,id);
    CREATE TABLE IF NOT EXISTS account_direct_messages(id INTEGER PRIMARY KEY AUTOINCREMENT,sender TEXT NOT NULL,recipient TEXT NOT NULL,text TEXT NOT NULL,request_id TEXT NOT NULL,created_at INTEGER NOT NULL,UNIQUE(sender,request_id));
    CREATE INDEX IF NOT EXISTS account_dm_recipient ON account_direct_messages(recipient,id);
    CREATE INDEX IF NOT EXISTS account_dm_sender ON account_direct_messages(sender,id);
    ''')


def official(db,key,target,title,text):
    db.execute('INSERT OR IGNORE INTO account_official_messages(event_key,target,title,text,created_at) VALUES(?,?,?,?,?)',
               (key,target,title,text,int(time.time())))

class Messaging(Community):
    def __init__(self,path):
        super().__init__(path)
        with self.db() as db:schema(db)

    def sellers(self,uid):
        with self.db() as db:
            return [dict(r) for r in db.execute('''SELECT p.firebase_uid AS uid,p.display_name AS name,p.country,p.avatar_url,i.public_id,
              CAST((SELECT COALESCE(SUM(e.coin_delta),0) FROM account_wallet_ledger e WHERE e.firebase_uid=s.uid) AS TEXT) AS coins
              FROM account_coin_sellers s JOIN account_profiles p ON p.firebase_uid=s.uid
              JOIN account_wallet_links l ON l.firebase_uid=s.uid AND l.status='active'
              LEFT JOIN account_wallet_imports i ON i.firebase_uid=s.uid
              WHERE NOT EXISTS(SELECT 1 FROM account_blocks b WHERE (b.uid=? AND b.target=s.uid) OR (b.target=? AND b.uid=s.uid))
              ORDER BY p.display_name,s.uid LIMIT 200''',(uid,uid))]

    def seller_save(self,uid,data):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            role=db.execute('SELECT role FROM account_staff WHERE uid=?',(uid,)).fetchone()
            if not role or role['role']!='owner':raise HTTPException(403,'Only the owner manages coin sellers')
            if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(data.target_uid,)).fetchone():raise HTTPException(404,'User not found')
            if data.enabled:
                if not db.execute("SELECT 1 FROM account_wallet_links WHERE firebase_uid=? AND status='active'",(data.target_uid,)).fetchone():raise HTTPException(409,'Seller wallet must be verified and active')
                row=db.execute('INSERT OR IGNORE INTO account_coin_sellers VALUES(?,?,?)',(data.target_uid,uid,int(time.time())))
            else:row=db.execute('DELETE FROM account_coin_sellers WHERE uid=?',(data.target_uid,))
            if row.rowcount:
                official(db,'seller:'+str(uuid.uuid4()),data.target_uid,'Coin seller status',
                    'You are now an approved Sovera coin seller. Your profile and current Coin balance appear in the seller directory.' if data.enabled else 'Your coin seller listing has been removed.')
            return {'saved':True,'enabled':data.enabled}

    def notice(self,uid,data):
        self.require_staff(uid,publish=True)
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(data.target_uid,)).fetchone():raise HTTPException(404,'User not found')
            key='notice:'+uid+':'+str(data.request_id)
            prior=db.execute('SELECT * FROM account_official_messages WHERE event_key=?',(key,)).fetchone()
            if prior and (prior['target'],prior['title'],prior['text'])!=(data.target_uid,data.title,data.text):raise HTTPException(409,'Request already used')
            official(db,key,data.target_uid,data.title,data.text)
            return {'saved':True}

    def official_inbox(self,uid):
        with self.db() as db:
            return [dict(r) for r in db.execute('''SELECT 'private:'||id AS id,title,text,created_at FROM account_official_messages WHERE target=?
              UNION ALL SELECT 'publication:'||id,title,text,created_at FROM account_publications
              ORDER BY created_at DESC,id DESC LIMIT 100''',(uid,))]

    def thread(self,uid,target,after=0):
        with self.db() as db:
            person=db.execute('SELECT firebase_uid AS uid,display_name AS name,avatar_url,country FROM account_profiles WHERE firebase_uid=?',(target,)).fetchone()
            if not person:raise HTTPException(404,'User not found')
            blocked=bool(db.execute('SELECT 1 FROM account_blocks WHERE (uid=? AND target=?) OR (uid=? AND target=?)',(uid,target,target,uid)).fetchone())
            rows=[dict(r) for r in db.execute('''SELECT id,sender,text,created_at FROM account_direct_messages WHERE id>? AND ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) ORDER BY id LIMIT 100''',(after,uid,target,target,uid))]
            return {'person':dict(person),'blocked':blocked,'items':rows,'has_more':len(rows)==100}

    def send(self,uid,target,data):
        if uid==target:raise HTTPException(400,'Choose another member')
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            for person in (uid,target):
                if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(person,)).fetchone():raise HTTPException(404,'User not found')
            prior=db.execute('SELECT * FROM account_direct_messages WHERE sender=? AND request_id=?',(uid,str(data.request_id))).fetchone()
            if prior:
                if (prior['recipient'],prior['text'])!=(target,data.text):raise HTTPException(409,'Request already used')
                return {'saved':True,'id':prior['id']}
            if db.execute('SELECT 1 FROM account_blocks WHERE (uid=? AND target=?) OR (uid=? AND target=?)',(uid,target,target,uid)).fetchone():raise HTTPException(403,'Messaging unavailable for this member')
            now=int(time.time())
            if db.execute('SELECT COUNT(*) FROM account_direct_messages WHERE sender=? AND created_at>?',(uid,now-60)).fetchone()[0]>=30:raise HTTPException(429,'Please wait before sending again')
            row=db.execute('INSERT INTO account_direct_messages(sender,recipient,text,request_id,created_at) VALUES(?,?,?,?,?)',(uid,target,data.text,str(data.request_id),now))
            return {'saved':True,'id':row.lastrowid}

    def threads(self,uid):
        with self.db() as db:
            return [dict(r) for r in db.execute('''WITH latest AS (
              SELECT CASE WHEN sender=? THEN recipient ELSE sender END AS peer,MAX(id) AS last_id
              FROM account_direct_messages WHERE sender=? OR recipient=? GROUP BY peer)
              SELECT p.firebase_uid AS uid,p.display_name AS name,p.avatar_url,m.text,m.created_at
              FROM latest a JOIN account_profiles p ON p.firebase_uid=a.peer JOIN account_direct_messages m ON m.id=a.last_id
              ORDER BY m.id DESC LIMIT 100''',(uid,uid,uid))]


def attach_messaging(app,profiles,actor):
    service=Messaging(profiles.path)
    @app.get('/sovera/account/sellers')
    async def sellers(authorization:str|None=Header(default=None)):
        return {'items':await asyncio.to_thread(service.sellers,await actor(authorization))}
    @app.get('/sovera/account/official-inbox')
    async def inbox(authorization:str|None=Header(default=None)):
        return {'items':await asyncio.to_thread(service.official_inbox,await actor(authorization))}
    @app.get('/sovera/account/messages')
    async def threads(authorization:str|None=Header(default=None)):
        return {'items':await asyncio.to_thread(service.threads,await actor(authorization))}
    @app.get('/sovera/account/messages/{target}')
    async def thread(target:str,after:int=Query(default=0,ge=0,le=9007199254740991),authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.thread,await actor(authorization),target,after)
    @app.post('/sovera/account/messages/{target}')
    async def send(target:str,data:MessageInput,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.send,await actor(authorization),target,data)
