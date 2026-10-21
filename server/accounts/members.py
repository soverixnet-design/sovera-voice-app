"""Server identities, social relationships, agency rosters and owner moderation."""
import asyncio
import json
import sqlite3
import time
import uuid
from fastapi import Header,HTTPException,Query,Request
from pydantic import BaseModel,ConfigDict,Field
from .community import Community

SCHEMA='''
CREATE TABLE IF NOT EXISTS account_public_ids(seq INTEGER PRIMARY KEY AUTOINCREMENT,uid TEXT UNIQUE NOT NULL,public_id TEXT UNIQUE);
CREATE TABLE IF NOT EXISTS account_gift_receipts(request_id TEXT NOT NULL,sender TEXT NOT NULL,recipient TEXT NOT NULL,item TEXT NOT NULL,title TEXT NOT NULL,price INTEGER NOT NULL,room TEXT NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(request_id,recipient));
CREATE TABLE IF NOT EXISTS account_user_follows(uid TEXT NOT NULL,target TEXT NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(uid,target));
CREATE TABLE IF NOT EXISTS account_profile_visits(target TEXT NOT NULL,visitor TEXT NOT NULL,day INTEGER NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(target,visitor,day));
CREATE TABLE IF NOT EXISTS account_bans(uid TEXT PRIMARY KEY,actor TEXT NOT NULL,reason TEXT NOT NULL,created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS account_adjustments(request_id TEXT PRIMARY KEY,actor TEXT NOT NULL,target TEXT NOT NULL,amount INTEGER NOT NULL,note TEXT NOT NULL,balance INTEGER NOT NULL,created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS account_agencies(id TEXT PRIMARY KEY,name TEXT NOT NULL,manager TEXT NOT NULL,active INTEGER NOT NULL DEFAULT 1);
CREATE TABLE IF NOT EXISTS account_agency_members(uid TEXT PRIMARY KEY,agency TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('pending','active')),created_at INTEGER NOT NULL);
'''

def initialize(db):db.executescript(SCHEMA)
def public_id(db,uid):
    old=db.execute("SELECT 1 FROM sqlite_master WHERE name='account_wallet_imports'").fetchone()
    if old:
        found=db.execute('SELECT public_id FROM account_wallet_imports WHERE firebase_uid=?',(uid,)).fetchone()
        if found:return str(found[0])
    found=db.execute('SELECT public_id FROM account_public_ids WHERE uid=?',(uid,)).fetchone()
    if found and found[0]:return str(found[0])
    row=db.execute('INSERT OR IGNORE INTO account_public_ids(uid) VALUES(?)',(uid,))
    seq=db.execute('SELECT seq FROM account_public_ids WHERE uid=?',(uid,)).fetchone()[0]
    candidate=str(100000000+seq)
    while old and db.execute('SELECT 1 FROM account_wallet_imports WHERE public_id=?',(candidate,)).fetchone():candidate=str(int(candidate)+1000000000)
    db.execute('UPDATE account_public_ids SET public_id=? WHERE uid=?',(candidate,uid))
    return candidate

class Toggle(BaseModel):
    model_config=ConfigDict(extra='forbid')
    enabled:bool=Field(strict=True)
class BanInput(Toggle):
    reason:str=Field(default='',max_length=300)
class Adjustment(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    amount:int=Field(strict=True,ge=-1000000000,le=1000000000)
    note:str=Field(min_length=3,max_length=300)
    request_id:uuid.UUID
class AgencyInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    id:uuid.UUID
    name:str=Field(min_length=2,max_length=60)
    manager:str=Field(min_length=1,max_length=128)
    active:bool=True

class Members(Community):
    def __init__(self,path):
        super().__init__(path)
        with self.db() as db:initialize(db)
    def owner(self,db,uid):
        row=db.execute('SELECT role FROM account_staff WHERE uid=?',(uid,)).fetchone()
        if not row or row[0]!='owner':raise HTTPException(403,'Owner permission required')
    def profile(self,viewer,target,visit=False):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            p=db.execute('SELECT firebase_uid AS uid,display_name,country,bio,avatar_url,gender FROM account_profiles WHERE firebase_uid=?',(target,)).fetchone()
            if not p:raise HTTPException(404,'Member not found')
            if db.execute('SELECT 1 FROM account_bans WHERE uid=?',(target,)).fetchone():raise HTTPException(403,'This account is unavailable')
            if db.execute('SELECT 1 FROM account_blocks WHERE (uid=? AND target=?) OR (uid=? AND target=?)',(viewer,target,target,viewer)).fetchone():raise HTTPException(403,'Member unavailable')
            if visit and target!=viewer:db.execute('INSERT OR IGNORE INTO account_profile_visits VALUES(?,?,?,?)',(target,viewer,int(time.time())//86400,int(time.time())))
            from .catalog import equipped_assets
            followers=db.execute('SELECT count(*) FROM account_user_follows WHERE target=?',(target,)).fetchone()[0]
            following=db.execute('SELECT count(*) FROM account_user_follows WHERE uid=?',(target,)).fetchone()[0]
            friends=db.execute('SELECT count(*) FROM account_user_follows f JOIN account_user_follows g ON f.uid=g.target AND f.target=g.uid WHERE f.uid=?',(target,)).fetchone()[0]
            visitors=db.execute('SELECT count(DISTINCT visitor) FROM account_profile_visits WHERE target=?',(target,)).fetchone()[0]
            sent,received=db.execute("SELECT COALESCE(SUM(CASE WHEN coin_delta<0 THEN -coin_delta ELSE 0 END),0),COALESCE(SUM(CASE WHEN diamond_delta>0 THEN diamond_delta ELSE 0 END),0) FROM account_wallet_ledger WHERE firebase_uid=? AND kind='gift'",(target,)).fetchone()
            return dict(p)|{'public_id':public_id(db,target),'equipped':equipped_assets(db,target),'followers':followers,'following':following,'friends':friends,'visitors':visitors,'is_following':bool(db.execute('SELECT 1 FROM account_user_follows WHERE uid=? AND target=?',(viewer,target)).fetchone()),'gift_coins_sent':str(sent),'gift_diamonds_received':str(received),'wealth_level':sent//10000,'charm_level':received//10000}
    def follow_user(self,uid,target,enabled):
        if uid==target:raise HTTPException(400,'Cannot follow yourself')
        self.profile(uid,target)
        with self.db() as db:
            if enabled:db.execute('INSERT OR IGNORE INTO account_user_follows VALUES(?,?,?)',(uid,target,int(time.time())))
            else:db.execute('DELETE FROM account_user_follows WHERE uid=? AND target=?',(uid,target))
        return {'saved':True,'following':enabled}
    def people(self,uid,q='',section=None,offset=0):
        filters={
            'followers':"EXISTS(SELECT 1 FROM account_user_follows f WHERE f.uid=p.firebase_uid AND f.target=?)",
            'following':"EXISTS(SELECT 1 FROM account_user_follows f WHERE f.target=p.firebase_uid AND f.uid=?)",
            'friends':"EXISTS(SELECT 1 FROM account_user_follows f JOIN account_user_follows g ON f.uid=g.target AND f.target=g.uid WHERE f.uid=? AND f.target=p.firebase_uid)",
            'visitors':"EXISTS(SELECT 1 FROM account_profile_visits v WHERE v.target=? AND v.visitor=p.firebase_uid)"}
        if section and section not in filters:raise HTTPException(404)
        with self.db() as db:
            sql="""SELECT p.firebase_uid AS uid,p.display_name AS name,p.avatar_url,p.country,COALESCE(i.public_id,n.public_id) AS public_id FROM account_profiles p
              LEFT JOIN account_wallet_imports i ON i.firebase_uid=p.firebase_uid LEFT JOIN account_public_ids n ON n.uid=p.firebase_uid
              WHERE NOT EXISTS(SELECT 1 FROM account_bans WHERE uid=p.firebase_uid) AND (?='' OR p.display_name LIKE ? OR COALESCE(i.public_id,n.public_id)=?)
              AND NOT EXISTS(SELECT 1 FROM account_blocks b WHERE (b.uid=? AND b.target=p.firebase_uid) OR (b.target=? AND b.uid=p.firebase_uid))"""
            args=[q,'%'+q+'%',q,uid,uid]
            if section:sql+=' AND '+filters[section];args.append(uid)
            sql+=' ORDER BY p.display_name,p.firebase_uid LIMIT 100 OFFSET ?';args.append(offset)
            return [dict(r) for r in db.execute(sql,args)]
    def ban(self,actor,target,data):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE');self.owner(db,actor)
            self.protect_owner(db,actor,target)
            presence=db.execute('SELECT room_id FROM account_presence WHERE uid=?',(target,)).fetchone()
            if data.enabled:
                db.execute('INSERT INTO account_bans VALUES(?,?,?,?) ON CONFLICT(uid) DO UPDATE SET actor=excluded.actor,reason=excluded.reason,created_at=excluded.created_at',(target,actor,data.reason,int(time.time())))
                db.execute('DELETE FROM account_presence WHERE uid=?',(target,))
                db.execute('DELETE FROM account_control_sessions WHERE uid=?',(target,))
            else:db.execute('DELETE FROM account_bans WHERE uid=?',(target,))
            self.audit(db,actor,'user.ban' if data.enabled else 'user.unban',target,{'reason':data.reason})
        return {'saved':True,'banned':data.enabled,'room_id':presence[0] if presence else None}
    def protect_owner(self,db,actor,target):
        row=db.execute('SELECT role FROM account_staff WHERE uid=?',(target,)).fetchone()
        if target==actor or row and row[0]=='owner':raise HTTPException(403,'Owner access cannot be changed here')
        if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(target,)).fetchone():raise HTTPException(404,'Member not found')
    def audit(self,db,actor,action,target,data):
        db.execute('INSERT INTO account_control_audit(actor,action,target,payload,created_at) VALUES(?,?,?,?,?)',(actor,action,target,json.dumps(data),int(time.time())))
    def adjust(self,actor,target,data):
        if data.amount==0:raise HTTPException(400,'Enter a nonzero Coin adjustment')
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE');self.owner(db,actor)
            key=str(data.request_id)
            prior=db.execute('SELECT * FROM account_adjustments WHERE request_id=?',(key,)).fetchone()
            if prior:
                if (prior['actor'],prior['target'],prior['amount'],prior['note'])!=(actor,target,data.amount,data.note):raise HTTPException(409,'Request already used')
                return dict(prior)
            if not db.execute('SELECT 1 FROM account_wallet_links WHERE firebase_uid=?',(target,)).fetchone():raise HTTPException(409,'Wallet not ready')
            balance=db.execute('SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(target,)).fetchone()[0]+data.amount
            if not 0<=balance<=9007199254740991:raise HTTPException(409,'Adjustment exceeds available Coins or supported balance')
            now=int(time.time())
            db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',('adjust:'+key,target,data.amount,0,'admin_adjust',now))
            db.execute('INSERT INTO account_adjustments VALUES(?,?,?,?,?,?,?)',(key,actor,target,data.amount,data.note,balance,now))
            self.audit(db,actor,'wallet.adjust',target,{'amount':data.amount,'note':data.note,'request_id':key})
            from .messaging import official
            official(db,'adjust:'+key,target,'Wallet adjustment',f'Coins: {data.amount:+,}. New balance: {balance:,}. Reason: {data.note}')
            return {'saved':True,'balance':str(balance)}
    def history(self,actor,target,before=9223372036854775807):
        with self.db() as db:
            role=db.execute('SELECT role FROM account_staff WHERE uid=?',(actor,)).fetchone()
            if not role or role[0] not in ('owner','admin'):raise HTTPException(403,'Staff permission required')
            rows=[dict(r) for r in db.execute('SELECT rowid AS cursor,* FROM account_wallet_ledger WHERE firebase_uid=? AND rowid<? ORDER BY rowid DESC LIMIT 100',(target,before))]
            gifts=[dict(r) for r in db.execute('''SELECT e.id,e.sender_uid,e.recipient_uid,e.room_id,e.created_at,COALESCE((SELECT g.title FROM account_gift_receipts g WHERE g.sender=e.sender_uid AND g.recipient=e.recipient_uid AND g.item=e.item_id AND g.created_at=e.created_at LIMIT 1),c.title) AS title,(SELECT g.price FROM account_gift_receipts g WHERE g.sender=e.sender_uid AND g.recipient=e.recipient_uid AND g.item=e.item_id AND g.created_at=e.created_at LIMIT 1) AS price,s.display_name AS sender_name,r.display_name AS recipient_name FROM account_catalog_events e JOIN account_catalog c ON c.id=e.item_id JOIN account_profiles s ON s.firebase_uid=e.sender_uid JOIN account_profiles r ON r.firebase_uid=e.recipient_uid WHERE (e.sender_uid=? OR e.recipient_uid=?) AND c.kind='gift' AND e.id<? ORDER BY e.id DESC LIMIT 100''',(target,target,before))]
            return {'ledger':rows,'gifts':gifts,'has_more':len(rows)==100,'gift_has_more':len(gifts)==100}
    def agencies(self,uid):
        with self.db() as db:
            return [dict(r) for r in db.execute('''SELECT a.*,p.display_name AS manager_name,(SELECT count(*) FROM account_agency_members m WHERE m.agency=a.id AND m.status='active') AS members,(SELECT status FROM account_agency_members WHERE uid=? AND agency=a.id) AS membership FROM account_agencies a JOIN account_profiles p ON p.firebase_uid=a.manager WHERE a.active=1 ORDER BY a.name''',(uid,))]
    def agency_save(self,actor,data):
        with self.db() as db:
            self.owner(db,actor)
            manager=data.manager
            if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(manager,)).fetchone():
                found=db.execute('SELECT p.firebase_uid FROM account_profiles p LEFT JOIN account_public_ids n ON n.uid=p.firebase_uid LEFT JOIN account_wallet_imports i ON i.firebase_uid=p.firebase_uid WHERE COALESCE(i.public_id,n.public_id)=?',(manager,)).fetchone()
                if not found:raise HTTPException(404,'Manager not found')
                manager=found[0]
            db.execute('INSERT INTO account_agencies VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,manager=excluded.manager,active=excluded.active',(str(data.id),data.name,manager,int(data.active)))
            self.audit(db,actor,'agency.save',str(data.id),data.model_dump(mode='json'))
        return {'saved':True}
    def agency_roster(self,uid,agency):
        with self.db() as db:
            row=db.execute('SELECT * FROM account_agencies WHERE id=?',(agency,)).fetchone()
            if not row:raise HTTPException(404)
            self.manager(db,uid,row)
            return [dict(r) for r in db.execute('SELECT m.uid,m.status,p.display_name AS name FROM account_agency_members m JOIN account_profiles p ON p.firebase_uid=m.uid WHERE agency=? ORDER BY m.created_at',(agency,))]
    def manager(self,db,uid,row):
        role=db.execute('SELECT role FROM account_staff WHERE uid=?',(uid,)).fetchone()
        if row['manager']!=uid and (not role or role[0]!='owner'):raise HTTPException(403,'Agency manager permission required')
    def agency_join(self,uid,agency,target=None,enabled=True):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT * FROM account_agencies WHERE id=? AND active=1',(agency,)).fetchone()
            if not row:raise HTTPException(404,'Agency unavailable')
            if target:
                self.manager(db,uid,row)
                if enabled:
                    result=db.execute("UPDATE account_agency_members SET status='active' WHERE uid=? AND agency=?",(target,agency))
                    if not result.rowcount:raise HTTPException(409,'Member must request to join first')
                else:db.execute('DELETE FROM account_agency_members WHERE uid=? AND agency=?',(target,agency))
            else:
                if enabled:
                    old=db.execute('SELECT agency FROM account_agency_members WHERE uid=?',(uid,)).fetchone()
                    if old and old[0]!=agency:raise HTTPException(409,'Leave your current agency first')
                    db.execute("INSERT OR IGNORE INTO account_agency_members VALUES(?,?,'pending',?)",(uid,agency,int(time.time())))
                else:db.execute('DELETE FROM account_agency_members WHERE uid=? AND agency=?',(uid,agency))
        return {'saved':True}

def attach_members(app,profiles,actor,staff_actor):
    service=Members(profiles.path)
    @app.get('/sovera/account/members')
    async def people(q:str=Query(default='',max_length=128),section:str|None=None,offset:int=Query(default=0,ge=0,le=1000000),authorization:str|None=Header(default=None)):
        return {'items':await asyncio.to_thread(service.people,await actor(authorization),q,section,offset)}
    @app.get('/sovera/account/members/{target}')
    async def profile(target:str,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.profile,await actor(authorization),target,True)
    @app.put('/sovera/account/members/{target}/follow')
    async def follow(target:str,data:Toggle,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.follow_user,await actor(authorization),target,data.enabled)
    @app.get('/sovera/account/agencies')
    async def agencies(authorization:str|None=Header(default=None)):
        return {'items':await asyncio.to_thread(service.agencies,await actor(authorization))}
    @app.post('/sovera/account/agencies/{agency}/join')
    async def join(agency:str,data:Toggle,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.agency_join,await actor(authorization),agency,None,data.enabled)
    @app.get('/sovera/account/agencies/{agency}/members')
    async def roster(agency:str,authorization:str|None=Header(default=None)):
        return {'items':await asyncio.to_thread(service.agency_roster,await actor(authorization),agency)}
    @app.put('/sovera/account/agencies/{agency}/members/{target}')
    async def approve(agency:str,target:str,data:Toggle,authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.agency_join,await actor(authorization),agency,target,data.enabled)
    @app.post('/sovera/control/users/{target}/ban')
    async def ban(target:str,data:BanInput,request:Request):
        result=await asyncio.to_thread(service.ban,await staff_actor(request),target,data)
        if data.enabled and result['room_id']:
            try:
                from server.voice import app as gateway
                if gateway.lk is not None:await gateway.lk.room.remove_participant(gateway.api.RoomParticipantIdentity(room=gateway.ROOM_PREFIX+result['room_id'],identity=target))
            except Exception:result['voice_disconnect_pending']=True
        return result
    @app.post('/sovera/control/users/{target}/adjust')
    async def adjust(target:str,data:Adjustment,request:Request):
        return await asyncio.to_thread(service.adjust,await staff_actor(request),target,data)
    @app.get('/sovera/control/users/{target}/history')
    async def history(target:str,request:Request,before:int=Query(default=9223372036854775807,ge=1)):
        return await asyncio.to_thread(service.history,await staff_actor(request),target,before)
    @app.get('/sovera/control/agencies')
    async def agencies_admin(request:Request):
        uid=await staff_actor(request)
        service.require_staff(uid,publish=True)
        return {'items':await asyncio.to_thread(service.agencies,uid)}
    @app.post('/sovera/control/agencies')
    async def agency_save(data:AgencyInput,request:Request):
        return await asyncio.to_thread(service.agency_save,await staff_actor(request),data)

    from .app import ProfileInput
    @app.put('/sovera/control/users/{target}/profile')
    async def edit_profile(target:str,data:ProfileInput,request:Request):
        uid=await staff_actor(request)
        with service.db() as db:
            service.owner(db,uid)
            if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(target,)).fetchone():raise HTTPException(404,'Member not found')
        result=await asyncio.to_thread(profiles.save,target,data)
        with service.db() as db:service.audit(db,uid,'profile.edit',target,data.model_dump(mode='json'))
        return {'profile':result}

    @app.get('/sovera/control/agencies/{agency}/members')
    async def admin_roster(agency:str,request:Request):
        uid=await staff_actor(request)
        with service.db() as db:service.owner(db,uid)
        return {'items':await asyncio.to_thread(service.agency_roster,uid,agency)}
    @app.put('/sovera/control/agencies/{agency}/members/{target}')
    async def admin_approve(agency:str,target:str,data:Toggle,request:Request):
        uid=await staff_actor(request)
        with service.db() as db:service.owner(db,uid)
        return await asyncio.to_thread(service.agency_join,uid,agency,target,data.enabled)
