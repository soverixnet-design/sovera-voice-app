"""Owner-managed image catalog, grants, purchases and room gift settlement."""
import asyncio
import hashlib
import io
import json
import sqlite3
import time
import uuid
import warnings
from typing import Literal
from fastapi import Header, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict, Field
from .control import Control,COOKIE

KINDS=('banner','frame','entry','gift','medal','tag','room_frame')
MAX_UPLOAD=8*1024*1024
PUBLIC='https://voice.soverixnet.com/sovera/account/media/'
class ItemInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    id:uuid.UUID
    kind:Literal['banner','frame','entry','gift','medal','tag','room_frame']
    title:str=Field(min_length=1,max_length=80)
    media_id:str=Field(pattern=r'^[a-f0-9]{64}$')
    price:int=Field(strict=True,ge=0,le=1000000000)
    active:bool=True
    position:int=Field(strict=True,default=0,ge=0,le=10000)
    avatar_scale:float=Field(default=.46,ge=.25,le=.8)
    avatar_x:float=Field(default=.5,ge=.2,le=.8)
    avatar_y:float=Field(default=.5,ge=.2,le=.8)
class GrantInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    target_uid:str=Field(min_length=1,max_length=128)
    item_id:uuid.UUID
    equip:bool=True
    revoke:bool=False
class SelectInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    kind:Literal['frame','entry','medal','tag','room_frame']
    item_id:uuid.UUID|None=None
class BuyInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    item_id:uuid.UUID
    request_id:uuid.UUID
    expected_price:int=Field(strict=True,ge=0,le=1000000000)
class GiftInput(BuyInput):
    recipient_uids:list[str]=Field(min_length=1,max_length=100)

def equipped_assets(db,uid):
    if not db.execute("SELECT 1 FROM sqlite_master WHERE name='account_asset_equipped'").fetchone():return {}
    return {r['kind']:dict(r)|{'url':PUBLIC+r['media_id']} for r in db.execute('SELECT c.* FROM account_asset_equipped e JOIN account_catalog c ON c.id=e.item_id WHERE e.uid=? AND c.active=1',(uid,))}

class Catalog:
    def __init__(self,path):
        self.control=Control(path)
        with self.control.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS account_media(id TEXT PRIMARY KEY,mime TEXT NOT NULL,data BLOB NOT NULL,width INTEGER NOT NULL,height INTEGER NOT NULL,frames INTEGER NOT NULL,created_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_catalog(id TEXT PRIMARY KEY,kind TEXT NOT NULL,title TEXT NOT NULL,media_id TEXT NOT NULL,price INTEGER NOT NULL,active INTEGER NOT NULL,position INTEGER NOT NULL,avatar_scale REAL NOT NULL,avatar_x REAL NOT NULL,avatar_y REAL NOT NULL,updated_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_asset_ownership(uid TEXT NOT NULL,item_id TEXT NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(uid,item_id));
            CREATE TABLE IF NOT EXISTS account_asset_equipped(uid TEXT NOT NULL,kind TEXT NOT NULL,item_id TEXT NOT NULL,PRIMARY KEY(uid,kind));
            CREATE TABLE IF NOT EXISTS account_catalog_requests(id TEXT PRIMARY KEY,actor TEXT NOT NULL,payload TEXT NOT NULL,response TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS account_catalog_events(id INTEGER PRIMARY KEY AUTOINCREMENT,room_id TEXT NOT NULL,sender_uid TEXT NOT NULL,recipient_uid TEXT NOT NULL,item_id TEXT NOT NULL,created_at INTEGER NOT NULL);
            ''')
    def manage(self,db,uid):
        if self.control.role(db,uid) not in ('owner','admin'):raise HTTPException(403,'Catalog management permission required')
    def row(self,db,item_id,active=True):
        row=db.execute('SELECT * FROM account_catalog WHERE id=?'+(' AND active=1' if active else ''),(str(item_id),)).fetchone()
        if not row:raise HTTPException(404,'Catalog item not available')
        return row
    def public(self,row):
        data=dict(row);data['url']=PUBLIC+data['media_id'];data['active']=bool(data['active']);return data
    def upload(self,uid,data):
        with self.control.db() as db:self.manage(db,uid)
        if not data or len(data)>MAX_UPLOAD:raise HTTPException(413,'Image must be no larger than 8 MB')
        from PIL import Image,UnidentifiedImageError
        try:
            with warnings.catch_warnings():
                warnings.simplefilter('error',Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(data)) as im:
                    mime={'PNG':'image/png','JPEG':'image/jpeg','GIF':'image/gif','WEBP':'image/webp'}.get(im.format)
                    width,height=im.size;frames=getattr(im,'n_frames',1)
                    if not mime or min(width,height)<16 or max(width,height)>4096 or width*height>16000000 or frames>300:raise ValueError()
                    im.verify()
        except (ValueError,OSError,UnidentifiedImageError,Image.DecompressionBombError,Image.DecompressionBombWarning,EOFError):raise HTTPException(400,'Use a valid PNG, JPG, GIF or WebP image, up to 4096 px and 300 frames') from None
        key=hashlib.sha256(data).hexdigest()
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.manage(db,uid)
            if not db.execute('SELECT 1 FROM account_media WHERE id=?',(key,)).fetchone():
                size=db.execute('SELECT COALESCE(SUM(length(data)),0) FROM account_media').fetchone()[0]
                if size+len(data)>200*1024*1024:raise HTTPException(409,'Media storage limit reached (200 MB)')
                db.execute('INSERT INTO account_media VALUES(?,?,?,?,?,?,?)',(key,mime,data,width,height,frames,int(time.time())))
            return {'id':key,'url':PUBLIC+key,'width':width,'height':height,'frames':frames,'mime':mime}
    def media(self,key):
        with self.control.db() as db:
            row=db.execute('SELECT mime,data FROM account_media WHERE id=?',(key,)).fetchone()
            if not row:raise HTTPException(404,'Image not found')
            return Response(bytes(row['data']),media_type=row['mime'],headers={'X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; sandbox"})
    def save(self,uid,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.manage(db,uid)
            if not db.execute('SELECT 1 FROM account_media WHERE id=?',(data.media_id,)).fetchone():raise HTTPException(400,'Upload the image first')
            old=db.execute('SELECT kind FROM account_catalog WHERE id=?',(str(data.id),)).fetchone()
            if old and old['kind']!=data.kind:raise HTTPException(409,'An existing item cannot change category')
            if not old and db.execute('SELECT COUNT(*) FROM account_catalog').fetchone()[0]>=1000:raise HTTPException(409,'Catalog limit reached')
            db.execute('''INSERT INTO account_catalog VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
             title=excluded.title,media_id=excluded.media_id,price=excluded.price,active=excluded.active,position=excluded.position,
             avatar_scale=excluded.avatar_scale,avatar_x=excluded.avatar_x,avatar_y=excluded.avatar_y,updated_at=excluded.updated_at''',
             (str(data.id),data.kind,data.title,data.media_id,data.price,int(data.active),data.position,data.avatar_scale,data.avatar_x,data.avatar_y,int(time.time())))
            self.control.audit(db,uid,'catalog.save',str(data.id),{'kind':data.kind,'price':data.price,'active':data.active})
            return self.public(self.row(db,data.id,False))
    def listing(self,uid,admin=False):
        with self.control.db() as db:
            if admin:self.manage(db,uid)
            items=[self.public(r) for r in db.execute('SELECT * FROM account_catalog'+('' if admin else ' WHERE active=1')+' ORDER BY position,title,id LIMIT 1000')]
            owned=[r[0] for r in db.execute('SELECT item_id FROM account_asset_ownership WHERE uid=?',(uid,))]
            equipped=self.equipped(db,uid)
            return {'items':items,'owned':owned,'equipped':equipped}
    def equipped(self,db,uid):
        return equipped_assets(db,uid)
    def grant(self,uid,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.control.role(db,uid)!='owner':raise HTTPException(403,'Only owner can grant or revoke assets')
            if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(data.target_uid,)).fetchone():raise HTTPException(404,'User not found')
            item=self.row(db,data.item_id,False)
            if item['kind'] in ('banner','gift'):raise HTTPException(400,'Only wearable assets can be assigned')
            if data.revoke:
                db.execute('DELETE FROM account_asset_ownership WHERE uid=? AND item_id=?',(data.target_uid,str(data.item_id)))
                db.execute('DELETE FROM account_asset_equipped WHERE uid=? AND item_id=?',(data.target_uid,str(data.item_id)))
            else:
                db.execute('INSERT OR IGNORE INTO account_asset_ownership VALUES(?,?,?)',(data.target_uid,str(data.item_id),int(time.time())))
                if data.equip:db.execute('INSERT INTO account_asset_equipped VALUES(?,?,?) ON CONFLICT(uid,kind) DO UPDATE SET item_id=excluded.item_id',(data.target_uid,item['kind'],str(data.item_id)))
            self.control.audit(db,uid,'catalog.revoke' if data.revoke else 'catalog.grant',data.target_uid,{'item':str(data.item_id)})
            return {'saved':True}
    def select(self,uid,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if data.item_id is None:db.execute('DELETE FROM account_asset_equipped WHERE uid=? AND kind=?',(uid,data.kind))
            else:
                item=self.row(db,data.item_id)
                if item['kind']!=data.kind:raise HTTPException(400,'Wrong category')
                owned=db.execute('SELECT 1 FROM account_asset_ownership WHERE uid=? AND item_id=?',(uid,str(data.item_id))).fetchone()
                if item['price']>0 and not owned:raise HTTPException(403,'Purchase or owner grant required')
                db.execute('INSERT INTO account_asset_equipped VALUES(?,?,?) ON CONFLICT(uid,kind) DO UPDATE SET item_id=excluded.item_id',(uid,data.kind,str(data.item_id)))
            return {'equipped':self.equipped(db,uid)}
    def verified(self,db,uid):
        row=db.execute('SELECT status,verified_at FROM account_wallet_links WHERE firebase_uid=?',(uid,)).fetchone()
        if not row or row['status']!='active' or row['verified_at']<=0:raise HTTPException(409,'Wallet verification required before spending or receiving gifts')
    def transact(self,uid,data,room=None):
        payload=json.dumps({'item':str(data.item_id),'expected_price':data.expected_price,'room':room,'recipients':sorted(set(data.recipient_uids)) if room else []},sort_keys=True)
        request=str(data.request_id)
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            prior=db.execute('SELECT * FROM account_catalog_requests WHERE id=?',(request,)).fetchone()
            if prior:
                if prior['actor']!=uid or prior['payload']!=payload:raise HTTPException(409,'Request ID already used')
                return json.loads(prior['response'])
            item=self.row(db,data.item_id);now=int(time.time())
            if item['price']!=data.expected_price:raise HTTPException(409,'Price changed. Refresh the catalog before confirming again')
            recipients=sorted(set(data.recipient_uids)) if room else []
            if room:
                if item['kind']!='gift':raise HTTPException(400,'Select a gift')
                last=db.execute('SELECT MAX(created_at) FROM account_catalog_events WHERE sender_uid=?',(uid,)).fetchone()[0]
                if last is not None and now-last<3:raise HTTPException(429,'Wait before sending another gift')
                for person in [uid]+recipients:
                    if not db.execute('SELECT 1 FROM account_presence WHERE uid=? AND room_id=? AND seen_at>?',(person,room,now-90)).fetchone():raise HTTPException(409,'All recipients must be online in this room')
            else:
                if item['kind'] in ('banner','gift'):raise HTTPException(400,'Select a wearable item')
                if db.execute('SELECT 1 FROM account_asset_ownership WHERE uid=? AND item_id=?',(uid,str(data.item_id))).fetchone():
                    result={'saved':True,'coins_spent':0,'already_owned':True}
                    db.execute('INSERT INTO account_catalog_requests VALUES(?,?,?,?)',(request,uid,payload,json.dumps(result)));return result
            cost=item['price']*(len(recipients) if room else 1)
            if cost:
                self.verified(db,uid)
                balance=db.execute('SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(uid,)).fetchone()[0]
                if balance<cost:raise HTTPException(409,'Insufficient Coins')
                for person in recipients:
                    self.verified(db,person)
                    diamonds=db.execute('SELECT COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(person,)).fetchone()[0]
                    if diamonds<0 or diamonds+item['price']>9007199254740991:raise HTTPException(409,'Recipient wallet reconciliation required')
                db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',('catalog:'+request,uid,-cost,0,'gift' if room else 'exchange',now))
                for index,person in enumerate(recipients):db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',('catalog:'+request+':'+str(index),person,0,item['price'],'gift',now))
            if room:
                for person in recipients:db.execute('INSERT INTO account_catalog_events(room_id,sender_uid,recipient_uid,item_id,created_at) VALUES(?,?,?,?,?)',(room,uid,person,str(data.item_id),now))
            else:db.execute('INSERT OR IGNORE INTO account_asset_ownership VALUES(?,?,?)',(uid,str(data.item_id),now))
            result={'saved':True,'coins_spent':cost,'diamond_each':item['price'] if room else 0,'request_id':request}
            db.execute('INSERT INTO account_catalog_requests VALUES(?,?,?,?)',(request,uid,payload,json.dumps(result)))
            return result
    def events(self,uid,room):
        with self.control.db() as db:
            if not db.execute('SELECT 1 FROM account_presence WHERE uid=? AND room_id=? AND seen_at>?',(uid,room,int(time.time())-90)).fetchone():raise HTTPException(403,'Join the room first')
            return {'server_now':int(time.time()),'items':[dict(r)|{'asset':self.public(r)} for r in db.execute('''SELECT c.*,e.id AS event_id,e.sender_uid,e.recipient_uid,e.created_at,p.display_name AS recipient_name,s.display_name AS sender_name,p.avatar_url FROM account_catalog_events e JOIN account_catalog c ON c.id=e.item_id JOIN account_profiles p ON p.firebase_uid=e.recipient_uid JOIN account_profiles s ON s.firebase_uid=e.sender_uid WHERE e.room_id=? AND e.created_at>? AND c.active=1 ORDER BY e.id DESC LIMIT 100''',(room,int(time.time())-15))]}
    def details(self,uid,target):
        with self.control.db() as db:
            if self.control.role(db,uid)=='support':raise HTTPException(403,'User lookup permission required')
            profile=db.execute('SELECT * FROM account_profiles WHERE firebase_uid=?',(target,)).fetchone()
            if not profile:raise HTTPException(404,'User not found')
            presence=db.execute('''SELECT a.seen_at,a.room_id,r.name AS room_name FROM account_presence a LEFT JOIN account_rooms r ON r.id=a.room_id WHERE a.uid=?''',(target,)).fetchone()
            wallet=db.execute('SELECT status,source_ref,verified_at FROM account_wallet_links WHERE firebase_uid=?',(target,)).fetchone()
            return {'profile':dict(profile),'presence':dict(presence) if presence else None,'online':bool(presence and presence['seen_at']>time.time()-90),'wallet':dict(wallet) if wallet else None,
             'equipped':self.equipped(db,target),'owned':[r[0] for r in db.execute('SELECT item_id FROM account_asset_ownership WHERE uid=?',(target,))],
             'rooms':[dict(r) for r in db.execute('SELECT id,name,seats FROM account_rooms WHERE owner_uid=?',(target,))]}

def attach_catalog(app,profiles,actor):
    service=Catalog(profiles.path)
    async def staff(request):return await asyncio.to_thread(service.control.actor,request.cookies.get(COOKIE))
    @app.post('/sovera/control/media')
    async def upload(request:Request):
        uid=await staff(request)
        data=bytearray()
        async for chunk in request.stream():
            data.extend(chunk)
            if len(data)>MAX_UPLOAD:raise HTTPException(413,'Image must be no larger than 8 MB')
        return await asyncio.to_thread(service.upload,uid,bytes(data))
    @app.get('/sovera/control/media/{key}')
    @app.get('/sovera/account/media/{key}')
    async def media(key:str):return await asyncio.to_thread(service.media,key)
    @app.get('/sovera/control/catalog')
    async def control_items(request:Request):return await asyncio.to_thread(service.listing,await staff(request),True)
    @app.post('/sovera/control/catalog')
    async def save(data:ItemInput,request:Request):return await asyncio.to_thread(service.save,await staff(request),data)
    @app.post('/sovera/control/catalog/grant')
    async def grant(data:GrantInput,request:Request):return await asyncio.to_thread(service.grant,await staff(request),data)
    @app.get('/sovera/control/users/{uid}')
    async def details(uid:str,request:Request):return await asyncio.to_thread(service.details,await staff(request),uid)
    @app.get('/sovera/account/catalog')
    async def items(authorization:str|None=Header(default=None)):return await asyncio.to_thread(service.listing,await actor(authorization))
    @app.put('/sovera/account/catalog/equip')
    async def equip(data:SelectInput,authorization:str|None=Header(default=None)):return await asyncio.to_thread(service.select,await actor(authorization),data)
    @app.post('/sovera/account/catalog/purchase')
    async def purchase(data:BuyInput,authorization:str|None=Header(default=None)):return await asyncio.to_thread(service.transact,await actor(authorization),data)
    @app.get('/sovera/account/rooms/{room}/catalog-events')
    async def events(room:str,authorization:str|None=Header(default=None)):return await asyncio.to_thread(service.events,await actor(authorization),room)
    @app.post('/sovera/account/rooms/{room}/gifts')
    async def gift(room:str,data:GiftInput,authorization:str|None=Header(default=None)):return await asyncio.to_thread(service.transact,await actor(authorization),data,room)
