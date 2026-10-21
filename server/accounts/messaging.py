"""Private conversations, owner-approved sellers and official account receipts."""
import asyncio
import json
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


class SellerTransferInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    target_uid:str=Field(min_length=1,max_length=128)
    coins:int=Field(strict=True,ge=1,le=9007199254740991)
    request_id:uuid.UUID

class ReadInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    ids:list[str]=Field(max_length=100)

class SellerPackageInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    frame:str=''
    tag:str=''
    medal:str=''

def schema(db):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS account_seller_package(kind TEXT PRIMARY KEY,item_id TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS account_seller_transfers(sender TEXT NOT NULL,request_id TEXT NOT NULL,recipient TEXT NOT NULL,coins INTEGER NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(sender,request_id));
    CREATE TABLE IF NOT EXISTS account_message_reads(uid TEXT NOT NULL,event TEXT NOT NULL,PRIMARY KEY(uid,event));
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
            rows=[dict(r) for r in db.execute('''SELECT p.firebase_uid AS uid,p.display_name AS name,p.country,p.avatar_url,i.public_id,
              CAST((SELECT COALESCE(SUM(e.coin_delta),0) FROM account_wallet_ledger e WHERE e.firebase_uid=s.uid) AS TEXT) AS coins
              FROM account_coin_sellers s JOIN account_profiles p ON p.firebase_uid=s.uid
              JOIN account_wallet_links l ON l.firebase_uid=s.uid AND l.status='active'
              LEFT JOIN account_wallet_imports i ON i.firebase_uid=s.uid
              WHERE NOT EXISTS(SELECT 1 FROM account_blocks b WHERE (b.uid=? AND b.target=s.uid) OR (b.target=? AND b.uid=s.uid))
              ORDER BY p.display_name,s.uid LIMIT 200''',(uid,uid))]
            from .members import public_id
            for row in rows:row['public_id']=public_id(db,row['uid'])
            return rows

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
            if row.rowcount and data.enabled:
                for asset in db.execute("SELECT c.id,c.kind FROM account_seller_package p JOIN account_catalog c ON c.id=p.item_id WHERE c.active=1").fetchall():
                    db.execute('INSERT OR IGNORE INTO account_asset_ownership VALUES(?,?,?)',(data.target_uid,asset['id'],int(time.time())))
                    db.execute('DELETE FROM account_reward_asset_expiry WHERE uid=? AND item_id=?',(data.target_uid,asset['id']))
                    db.execute('INSERT OR REPLACE INTO account_asset_equipped VALUES(?,?,?)',(data.target_uid,asset['kind'],asset['id']))
            if row.rowcount:
                db.execute('INSERT INTO account_control_audit(actor,action,target,payload,created_at) VALUES(?,?,?,?,?)',(uid,'seller.approve' if data.enabled else 'seller.revoke',data.target_uid,'{}',int(time.time())))
                official(db,'seller:'+str(uuid.uuid4()),data.target_uid,'Coin seller status',
                    'You are now an approved Sovera coin seller. Your profile and current Coin balance appear in the seller directory.' if data.enabled else 'Your coin seller listing has been removed.')
            return {'saved':True,'enabled':data.enabled}


    def package(self,uid,data=None):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            role=db.execute('SELECT role FROM account_staff WHERE uid=?',(uid,)).fetchone()
            if not role or role['role']!='owner':raise HTTPException(403,'Owner required')
            if data is not None:
                for kind,item in data.model_dump().items():
                    if item and not db.execute('SELECT 1 FROM account_catalog WHERE id=? AND kind=? AND active=1',(item,kind)).fetchone():raise HTTPException(400,'Select an active '+kind)
                db.execute('DELETE FROM account_seller_package')
                for kind,item in data.model_dump().items():
                    if item:db.execute('INSERT INTO account_seller_package VALUES(?,?)',(kind,item))
                db.execute('INSERT INTO account_control_audit(actor,action,target,payload,created_at) VALUES(?,?,?,?,?)',(uid,'seller.package','sellers',json.dumps(data.model_dump()),int(time.time())))
            return dict(db.execute('SELECT kind,item_id FROM account_seller_package').fetchall())

    def transfer(self,uid,data):
        if uid==data.target_uid:raise HTTPException(400,'Choose another member')
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute('SELECT 1 FROM account_coin_sellers WHERE uid=?',(uid,)).fetchone():raise HTTPException(403,'Approved seller required')
            for person in (uid,data.target_uid):
                if db.execute('SELECT 1 FROM account_bans WHERE uid=?',(person,)).fetchone():raise HTTPException(403,'Account unavailable')
                if not db.execute("SELECT 1 FROM account_wallet_links WHERE firebase_uid=? AND status='active' AND verified_at>0",(person,)).fetchone():raise HTTPException(409,'Both wallets must be active and verified')
            prior=db.execute('SELECT * FROM account_seller_transfers WHERE sender=? AND request_id=?',(uid,str(data.request_id))).fetchone()
            if prior:
                if (prior['recipient'],prior['coins'])!=(data.target_uid,data.coins):raise HTTPException(409,'Request already used')
                return {'saved':True,'coins':str(prior['coins']),'replayed':True}
            if db.execute('SELECT 1 FROM account_blocks WHERE (uid=? AND target=?) OR (uid=? AND target=?)',(uid,data.target_uid,data.target_uid,uid)).fetchone():raise HTTPException(403,'Member unavailable')
            balances=[db.execute('SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(person,)).fetchone()[0] for person in (uid,data.target_uid)]
            if balances[0]<data.coins:raise HTTPException(409,'Insufficient Coins')
            if balances[1]+data.coins>9007199254740991:raise HTTPException(409,'Recipient balance exceeds supported precision')
            now=int(time.time());key='seller-transfer:'+uid+':'+str(data.request_id)
            db.execute('INSERT INTO account_seller_transfers VALUES(?,?,?,?,?)',(uid,str(data.request_id),data.target_uid,data.coins,now))
            for person,delta,side in ((uid,-data.coins,'out'),(data.target_uid,data.coins,'in')):
                db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',(key+':'+side,person,delta,0,'recharge',now))
                official(db,key+':'+side,person,'Coin transfer receipt',str(data.coins)+' Coins '+('sent to '+data.target_uid if side=='out' else 'received from seller '+uid)+'. Reference: '+key)
            db.execute('INSERT INTO account_control_audit(actor,action,target,payload,created_at) VALUES(?,?,?,?,?)',(uid,'seller.transfer',data.target_uid,json.dumps({'coins':str(data.coins),'reference':key}),now))
            return {'saved':True,'coins':str(data.coins),'balance':str(balances[0]-data.coins)}

    def mark_read(self,uid,data):
        with self.db() as db:
            for event in data.ids:
                prefix,_,number=event.partition(':')
                if not number.isdigit():raise HTTPException(400,'Invalid message')
                if prefix=='private':
                    visible=db.execute('SELECT 1 FROM account_official_messages WHERE id=? AND target=?',(number,uid)).fetchone()
                elif prefix=='publication':
                    visible=db.execute('SELECT 1 FROM account_publications WHERE id=?',(number,)).fetchone()
                elif prefix=='dm':
                    visible=db.execute('SELECT 1 FROM account_direct_messages WHERE id=? AND recipient=?',(number,uid)).fetchone()
                else:raise HTTPException(400,'Invalid message')
                if visible:db.execute('INSERT OR IGNORE INTO account_message_reads VALUES(?,?)',(uid,event))
            return {'saved':True}

    def unread(self,uid):
        with self.db() as db:
            dm=db.execute("""SELECT COUNT(*) FROM account_direct_messages m WHERE recipient=?
              AND NOT EXISTS(SELECT 1 FROM account_message_reads r WHERE r.uid=? AND r.event='dm:'||m.id)
              AND NOT EXISTS(SELECT 1 FROM account_blocks b WHERE (b.uid=? AND b.target=m.sender) OR (b.target=? AND b.uid=m.sender))""",(uid,uid,uid,uid)).fetchone()[0]
            official_count=db.execute("""SELECT COUNT(*) FROM (
              SELECT 'private:'||id AS event FROM account_official_messages WHERE target=?
              UNION ALL SELECT 'publication:'||id FROM account_publications) m
              WHERE NOT EXISTS(SELECT 1 FROM account_message_reads r WHERE r.uid=? AND r.event=m.event)""",(uid,uid)).fetchone()[0]
            return {'messages':dm,'official':official_count}

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
              SELECT p.firebase_uid AS uid,p.display_name AS name,p.avatar_url,m.text,m.created_at,
              (SELECT COUNT(*) FROM account_direct_messages d WHERE d.recipient=? AND d.sender=a.peer AND NOT EXISTS(SELECT 1 FROM account_message_reads r WHERE r.uid=? AND r.event='dm:'||d.id)) AS unread
              FROM latest a JOIN account_profiles p ON p.firebase_uid=a.peer JOIN account_direct_messages m ON m.id=a.last_id
              ORDER BY m.id DESC LIMIT 100''',(uid,uid,uid,uid,uid))]


def attach_messaging(app,profiles,actor):
    service=Messaging(profiles.path)
    @app.get('/sovera/account/unread')
    async def unread(authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.unread,await actor(authorization))
    @app.post('/sovera/account/message-read')
    async def read(data:ReadInput,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.mark_read,await actor(authorization),data)
    @app.post('/sovera/account/seller-transfer')
    async def transfer(data:SellerTransferInput,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.transfer,await actor(authorization),data)
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
