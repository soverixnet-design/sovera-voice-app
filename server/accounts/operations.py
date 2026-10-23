"""Owner reporting, central room moderation, ticket routing and audit exports."""
import asyncio
import csv
import io
import json
import os
import shutil
import time
import uuid
from datetime import datetime,timezone
from pathlib import Path
from typing import Literal
from fastapi import HTTPException, Request, Query
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict, Field
from .control import Control
from .control_security import CAPS

class RoomPresentation(BaseModel):
    model_config=ConfigDict(extra='forbid')
    theme:Literal['mid','gold','ocean','rose','forest','sunset']
    chat_enabled:bool
    photo_min_level:int=Field(strict=True,ge=0,le=10000)
    remove_background:bool=False
    remove_picture:bool=False
    appearance_locked:bool|None=None

class RoomModeration(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    status:Literal['open','closed','banned']
    reason:str=Field(min_length=3,max_length=300)
class TicketInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    status:Literal['open','in_progress','resolved']
    assignee:str=Field(default='',max_length=128)
    note:str=Field(default='',max_length=500)
class PolicyInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    expires_at:int=Field(strict=True,ge=0)
    denied:list[Literal['users','wallet','catalog','publications','support','rooms','reports','programs']]=Field(default_factory=list,max_length=8)
class ScheduledInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    id:uuid.UUID
    title:str=Field(min_length=1,max_length=100)
    text:str=Field(min_length=1,max_length=1000)
    section:Literal['notices','events']
    publish_at:int=Field(strict=True,gt=0)

def schema(db):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS account_room_moderation(room TEXT PRIMARY KEY,status TEXT NOT NULL,reason TEXT NOT NULL,actor TEXT NOT NULL,updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_ticket_state(ticket INTEGER PRIMARY KEY,status TEXT NOT NULL,assignee TEXT NOT NULL,note TEXT NOT NULL,updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_access_log(uid TEXT NOT NULL,device TEXT NOT NULL,user_agent TEXT NOT NULL,remote_ip TEXT NOT NULL,first_seen INTEGER NOT NULL,last_seen INTEGER NOT NULL,PRIMARY KEY(uid,device));
    CREATE TABLE IF NOT EXISTS account_publication_schedule(id TEXT PRIMARY KEY,payload TEXT NOT NULL,actor TEXT NOT NULL,publish_at INTEGER NOT NULL,published_at INTEGER);
    CREATE INDEX IF NOT EXISTS account_ledger_metric ON account_wallet_ledger(kind,created_at,firebase_uid);
    CREATE INDEX IF NOT EXISTS account_recharge_time ON account_control_recharges(created_at,target);
    ''')

def access(db,uid,agent,ip):
    import hashlib
    now=int(time.time());agent=agent[:256];ip=ip[:100];device=hashlib.sha256((agent+'|'+ip).encode()).hexdigest()[:24]
    db.execute('''INSERT INTO account_access_log VALUES(?,?,?,?,?,?) ON CONFLICT(uid,device) DO UPDATE SET last_seen=excluded.last_seen WHERE account_access_log.last_seen<?''',(uid,device,agent,ip,now,now,now-60))
    db.execute('DELETE FROM account_access_log WHERE last_seen<?',(now-90*86400,))

def csv_content(rows):
    out=io.StringIO();writer=csv.writer(out)
    if rows:
        writer.writerow(rows[0].keys())
        for r in rows:
            values=[]
            for x in r.values():
                v='' if x is None else str(x)
                if v.lstrip().startswith(('=','+','-','@','\t','\r')):v="'"+v
                values.append(v)
            writer.writerow(values)
    return '\ufeff'+out.getvalue()

class Operations:
    def __init__(self,path):
        self.control=Control(path)
        with self.control.db() as db:schema(db)
    def owner(self,db,uid):
        if self.control.role(db,uid)!='owner':raise HTTPException(403,'Owner permission required')
    def staff(self,db,uid):
        if self.control.role(db,uid) not in ('owner','admin','support'):raise HTTPException(403,'Moderation staff required')
    def overview(self,uid,days=30):
        with self.control.db() as db:
            self.owner(db,uid);now=int(time.time());start=now-days*86400
            activity=db.execute('SELECT COUNT(DISTINCT uid) FROM account_access_log WHERE last_seen>?',(now-86400,)).fetchone()[0]
            daily=[dict(r) for r in db.execute("""SELECT strftime('%Y-%m-%d',created_at,'unixepoch') AS day,COUNT(*) AS transactions,SUM(CASE WHEN kind='recharge' THEN coin_delta ELSE 0 END) AS recharged,SUM(CASE WHEN kind='gift' AND coin_delta<0 THEN -coin_delta ELSE 0 END) AS gifts,SUM(CASE WHEN kind='game_debit' THEN -coin_delta ELSE 0 END) AS stakes,SUM(CASE WHEN kind='game_win' THEN coin_delta ELSE 0 END) AS winnings FROM account_wallet_ledger WHERE created_at>=? GROUP BY day ORDER BY day""",(start,))]
            balances=db.execute('SELECT COALESCE(SUM(coin_delta),0),COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger').fetchone()
            disk=shutil.disk_usage(Path(self.control.path).parent)
            return {'daily':daily,'active_24h':activity,'online':db.execute('SELECT COUNT(*) FROM account_presence WHERE seen_at>?',(now-90,)).fetchone()[0],
             'coins_outstanding':str(balances[0]),'diamonds_outstanding':str(balances[1]),'disk_free':disk.free,'database_bytes':Path(self.control.path).stat().st_size,'load_average':list(os.getloadavg()) if hasattr(os,'getloadavg') else [],'server_now':now,
             'currency_note':'Virtual Coin/Diamond activity. This is not cash revenue or profit.',
             'large_adjustments':[dict(r) for r in db.execute("SELECT reference,firebase_uid,coin_delta,created_at FROM account_wallet_ledger WHERE kind='admin_adjust' AND abs(coin_delta)>=1000000 ORDER BY created_at DESC LIMIT 20")]}
    def maintenance_status(self,uid):
        with self.control.db() as db:
            self.owner(db,uid)
            jobs=[]
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='account_job_status'").fetchone():jobs=[dict(r) for r in db.execute('SELECT * FROM account_job_status')]
            snapshots=[]
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='account_backup_status'").fetchone():
                snapshots=[json.loads(r[0]) for r in db.execute('SELECT payload FROM account_backup_status ORDER BY created_at DESC LIMIT 14')]
                for row in snapshots:row['id']=datetime.fromtimestamp(row['created_at'],timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        return {'jobs':jobs,'backups':snapshots,'restore_note':'Integrity is checked on backup copies. No live restore is performed. Cross-database recovery requires coordinated operator review.'}
    def rooms(self,uid,q=''):
        with self.control.db() as db:
            self.staff(db,uid)
            return [dict(r) for r in db.execute('''SELECT r.id,r.name,r.owner_uid,p.display_name AS owner_name,r.seats,r.theme,r.chat_enabled,r.photo_min_level,r.image_url,r.background_url,r.appearance_locked,COALESCE(m.status,'open') AS status,m.reason,
             (SELECT COUNT(*) FROM account_presence a WHERE a.room_id=r.id AND a.seen_at>?) AS occupants
             FROM account_rooms r JOIN account_profiles p ON p.firebase_uid=r.owner_uid LEFT JOIN account_room_moderation m ON m.room=r.id
             WHERE r.name LIKE ? OR r.id LIKE ? ORDER BY r.created_at DESC LIMIT 200''',(time.time()-90,'%'+q+'%','%'+q+'%'))]
    def presentation(self,uid,room,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.control.role(db,uid) not in ('owner','admin'):raise HTTPException(403,'Room moderation permission required')
            row=db.execute('SELECT 1 FROM account_rooms WHERE id=?',(room,)).fetchone()
            if not row:raise HTTPException(404,'Room not found')
            db.execute('UPDATE account_rooms SET theme=?,chat_enabled=?,photo_min_level=? WHERE id=?',(data.theme,data.chat_enabled,data.photo_min_level,room))
            if data.remove_background:db.execute('UPDATE account_rooms SET background_url=NULL WHERE id=?',(room,))
            if data.remove_picture:db.execute('UPDATE account_rooms SET image_url=NULL WHERE id=?',(room,))
            if data.appearance_locked is not None:db.execute('UPDATE account_rooms SET appearance_locked=? WHERE id=?',(data.appearance_locked,room))
            self.control.audit(db,uid,'room.presentation',room,data.model_dump())
            return {'saved':True}
    def room_messages(self,uid,room):
        with self.control.db() as db:
            self.staff(db,uid)
            if not db.execute('SELECT 1 FROM account_rooms WHERE id=?',(room,)).fetchone():raise HTTPException(404,'Room not found')
            return [dict(r) for r in db.execute('SELECT id,name,sender_uid,text,image_url,created_at FROM account_messages WHERE room_id=? AND removed=0 ORDER BY id DESC LIMIT 100',(room,))]
    def remove_room_messages(self,uid,room,message_id=None):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.staff(db,uid)
            if not db.execute('SELECT 1 FROM account_rooms WHERE id=?',(room,)).fetchone():raise HTTPException(404,'Room not found')
            sql='UPDATE account_messages SET removed=1 WHERE room_id=? AND removed=0'
            args=[room]
            if message_id is not None:sql+=' AND id=?';args.append(message_id)
            count=db.execute(sql,args).rowcount
            self.control.audit(db,uid,'room.remove_messages',room,{'message_id':message_id,'count':count})
            return {'saved':True,'removed':count}
    def moderate(self,uid,room,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.control.role(db,uid) not in ('owner','admin'):raise HTTPException(403,'Room moderation permission required')
            if not db.execute('SELECT 1 FROM account_rooms WHERE id=?',(room,)).fetchone():raise HTTPException(404,'Room not found')
            db.execute('INSERT INTO account_room_moderation VALUES(?,?,?,?,?) ON CONFLICT(room) DO UPDATE SET status=excluded.status,reason=excluded.reason,actor=excluded.actor,updated_at=excluded.updated_at',(room,data.status,data.reason,uid,int(time.time())))
            if data.status!='open':db.execute('DELETE FROM account_presence WHERE room_id=?',(room,))
            self.control.audit(db,uid,'room.'+data.status,room,{'reason':data.reason})
            return {'saved':True,'voice_disconnect_pending':data.status!='open'}
    def tickets(self,uid,status='',offset=0):
        with self.control.db() as db:
            self.staff(db,uid)
            return [dict(r) for r in db.execute('''SELECT t.id,t.uid,p.display_name AS name,t.text,t.reply,t.created_at,
             COALESCE(s.status,CASE WHEN t.reply='' THEN 'open' ELSE 'resolved' END) AS status,COALESCE(s.assignee,'') AS assignee,s.note
             FROM account_support t JOIN account_profiles p ON p.firebase_uid=t.uid LEFT JOIN account_ticket_state s ON s.ticket=t.id
             WHERE ?='' OR COALESCE(s.status,CASE WHEN t.reply='' THEN 'open' ELSE 'resolved' END)=? ORDER BY t.id DESC LIMIT 100 OFFSET ?''',(status,status,offset))]
    def ticket(self,uid,ticket,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.staff(db,uid)
            if not db.execute('SELECT 1 FROM account_support WHERE id=?',(ticket,)).fetchone():raise HTTPException(404)
            if data.assignee and not db.execute("SELECT 1 FROM account_staff WHERE uid=? AND role IN ('owner','admin','support')",(data.assignee,)).fetchone():raise HTTPException(400,'Choose an existing support/admin staff member')
            db.execute('INSERT INTO account_ticket_state VALUES(?,?,?,?,?) ON CONFLICT(ticket) DO UPDATE SET status=excluded.status,assignee=excluded.assignee,note=excluded.note,updated_at=excluded.updated_at',(ticket,data.status,data.assignee,data.note,int(time.time())))
            self.control.audit(db,uid,'support.route',str(ticket),data.model_dump());return {'saved':True}
    def policy(self,uid,target,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.owner(db,uid)
            if target==uid or self.control.role(db,target)=='owner':raise HTTPException(403,'Owner access cannot be restricted here')
            db.execute('INSERT INTO account_staff_policy VALUES(?,?,?) ON CONFLICT(uid) DO UPDATE SET expires_at=excluded.expires_at,denied=excluded.denied',(target,data.expires_at,json.dumps(sorted(set(data.denied)))))
            db.execute('DELETE FROM account_control_sessions WHERE uid=?',(target,));self.control.audit(db,uid,'staff.policy',target,data.model_dump());return {'saved':True}
    def records(self,uid,kind,before=0,target='',start=0,end=4102444800):
        with self.control.db() as db:
            self.owner(db,uid)
            if kind=='audit':return [dict(r) for r in db.execute('SELECT * FROM account_control_audit WHERE (?=0 OR id<?) AND (?=\'\' OR target=?) AND created_at>=? AND created_at<? ORDER BY id DESC LIMIT 1000',(before,before,target,target,start,end))]
            if kind=='access':return [dict(r) for r in db.execute('SELECT uid,user_agent,remote_ip,first_seen,last_seen FROM account_access_log WHERE (?=\'\' OR uid=?) ORDER BY last_seen DESC LIMIT 1000',(target,target))]
            if kind=='ledger':return [dict(r) for r in db.execute('SELECT rowid AS id,* FROM account_wallet_ledger WHERE (?=0 OR rowid<?) AND (?=\'\' OR firebase_uid=?) AND created_at>=? AND created_at<? ORDER BY rowid DESC LIMIT 1000',(before,before,target,target,start,end))]
            if kind=='members':return self.control.users(uid,target)
            raise HTTPException(404)
    def members(self,uid,q='',country='',status='',minimum=0,offset=0):
        with self.control.db() as db:
            self.owner(db,uid)
            return [dict(r) for r in db.execute("""SELECT * FROM (
              SELECT p.firebase_uid AS uid,p.display_name AS name,p.country,
              COALESCE(i.public_id,n.public_id) AS public_id,
              CASE WHEN b.uid IS NOT NULL THEN 'banned' ELSE 'active' END AS status,
              COALESCE(s.role,'member') AS role,COALESCE(l.status,'unlinked') AS wallet_status,
              COALESCE(c.coins,0) AS coins,COALESCE(c.diamonds,0) AS diamonds,m.created_at
              FROM account_profiles p LEFT JOIN account_public_ids n ON n.uid=p.firebase_uid
              LEFT JOIN account_wallet_imports i ON i.firebase_uid=p.firebase_uid
              LEFT JOIN account_bans b ON b.uid=p.firebase_uid LEFT JOIN account_staff s ON s.uid=p.firebase_uid
              LEFT JOIN account_wallet_links l ON l.firebase_uid=p.firebase_uid
              LEFT JOIN account_member_created m ON m.uid=p.firebase_uid
              LEFT JOIN (SELECT firebase_uid,SUM(coin_delta) AS coins,SUM(diamond_delta) AS diamonds FROM account_wallet_ledger GROUP BY firebase_uid) c ON c.firebase_uid=p.firebase_uid
             ) WHERE (length(?)=0 OR name LIKE ? OR uid=? OR public_id=?)
              AND (length(?)=0 OR country=?) AND (length(?)=0 OR status=?) AND coins>=?
              ORDER BY name,uid LIMIT 100 OFFSET ?""",(q,'%'+q+'%',q,q,country,country,status,status,minimum,offset))]
    def schedules(self,uid,data=None):
        with self.control.db() as db:
            if self.control.role(db,uid) not in ('owner','admin'):raise HTTPException(403)
            if data:
                if data.publish_at<int(time.time()) or data.publish_at>int(time.time())+366*86400:raise HTTPException(400,'Choose a future time within one year')
                prior=db.execute('SELECT payload FROM account_publication_schedule WHERE id=?',(str(data.id),)).fetchone()
                if prior and prior[0]!=data.model_dump_json():raise HTTPException(409,'Schedule ID already used')
                db.execute('INSERT OR IGNORE INTO account_publication_schedule VALUES(?,?,?,?,NULL)',(str(data.id),data.model_dump_json(),uid,data.publish_at))
                self.control.audit(db,uid,'publication.schedule',str(data.id),{'publish_at':data.publish_at})
            return {'items':[dict(r)|{'details':json.loads(r['payload'])} for r in db.execute('SELECT * FROM account_publication_schedule ORDER BY publish_at DESC LIMIT 100')]}
    def scheduled_tick(self):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');now=int(time.time())
            for row in db.execute('SELECT * FROM account_publication_schedule WHERE published_at IS NULL AND publish_at<=? LIMIT 100',(now,)).fetchall():
                p=json.loads(row['payload'])
                try:
                    if self.control.role(db,row['actor']) not in ('owner','admin'):continue
                    from .control_security import permit
                    permit(db,row['actor'],'/sovera/control/publications')
                except HTTPException:continue
                db.execute('INSERT OR IGNORE INTO account_publications(section,title,text,uid,request_id,created_at) VALUES(?,?,?,?,?,?)',(p['section'],p['title'],p['text'],row['actor'],row['id'],now))
                db.execute('UPDATE account_publication_schedule SET published_at=? WHERE id=?',(now,row['id']))

def attach_operations(app,profiles,staff):
    service=Operations(profiles.path)
    @app.get('/sovera/control/operations')
    async def overview(request:Request,days:int=Query(default=30,ge=1,le=366)):return await asyncio.to_thread(service.overview,await staff(request),days)
    @app.get('/sovera/control/operations/maintenance')
    async def maintenance(request:Request):return await asyncio.to_thread(service.maintenance_status,await staff(request))
    @app.get('/sovera/control/rooms')
    async def rooms(request:Request,q:str=Query(default='',max_length=128)):return {'items':await asyncio.to_thread(service.rooms,await staff(request),q)}
    @app.get('/sovera/control/rooms/{room}/messages')
    async def room_messages(room:str,request:Request):return {'items':await asyncio.to_thread(service.room_messages,await staff(request),room)}
    @app.delete('/sovera/control/rooms/{room}/messages')
    async def clear_room_messages(room:str,request:Request):return await asyncio.to_thread(service.remove_room_messages,await staff(request),room)
    @app.delete('/sovera/control/rooms/{room}/messages/{message_id}')
    async def remove_room_message(room:str,message_id:int,request:Request):return await asyncio.to_thread(service.remove_room_messages,await staff(request),room,message_id)
    @app.put('/sovera/control/rooms/{room}/presentation')
    async def presentation(room:str,data:RoomPresentation,request:Request):return await asyncio.to_thread(service.presentation,await staff(request),room,data)
    @app.put('/sovera/control/rooms/{room}')
    async def moderate(room:str,data:RoomModeration,request:Request):
        result=await asyncio.to_thread(service.moderate,await staff(request),room,data)
        if data.status!='open':
            try:
                from server.voice import app as gateway
                from livekit import api as lkapi
                if gateway.lk:
                    await gateway.lk.room.delete_room(lkapi.DeleteRoomRequest(room=gateway.ROOM_PREFIX+room));result['voice_disconnect_pending']=False
            except Exception:pass
        return result
    @app.get('/sovera/control/operations/tickets')
    async def tickets(request:Request,status:str=Query(default='',max_length=20),offset:int=Query(default=0,ge=0,le=1000000)):return {'items':await asyncio.to_thread(service.tickets,await staff(request),status,offset)}
    @app.put('/sovera/control/operations/tickets/{ticket}')
    async def ticket(ticket:int,data:TicketInput,request:Request):return await asyncio.to_thread(service.ticket,await staff(request),ticket,data)
    @app.put('/sovera/control/operations/policy/{target}')
    async def policy(target:str,data:PolicyInput,request:Request):return await asyncio.to_thread(service.policy,await staff(request),target,data)
    @app.get('/sovera/control/operations/records/{kind}')
    async def records(kind:str,request:Request,before:int=Query(default=0,ge=0),target:str=Query(default='',max_length=128),start:int=Query(default=0,ge=0),end:int=Query(default=4102444800,ge=0),csv_export:bool=False):
        rows=await asyncio.to_thread(service.records,await staff(request),kind,before,target,start,end)
        if csv_export:return Response(csv_content(rows),media_type='text/csv',headers={'Content-Disposition':f'attachment; filename="sovera-{kind}.csv"','X-Content-Type-Options':'nosniff'})
        return {'items':rows}
    @app.get('/sovera/control/operations/members')
    async def members(request:Request,q:str=Query(default='',max_length=128),country:str=Query(default='',max_length=3),status:str=Query(default='',pattern='^(active|banned)?$'),minimum:int=Query(default=0,ge=0,le=9007199254740991),offset:int=Query(default=0,ge=0,le=1000000),csv_export:bool=False):
        rows=await asyncio.to_thread(service.members,await staff(request),q,country,status,minimum,offset)
        if csv_export:return Response(csv_content(rows),media_type='text/csv',headers={'Content-Disposition':'attachment; filename="sovera-members.csv"','X-Content-Type-Options':'nosniff'})
        return {'items':rows,'next_offset':offset+100 if len(rows)==100 else None}
    @app.get('/sovera/control/operations/schedules')
    async def schedules(request:Request):return await asyncio.to_thread(service.schedules,await staff(request))
    @app.post('/sovera/control/operations/schedules')
    async def schedule(data:ScheduledInput,request:Request):return await asyncio.to_thread(service.schedules,await staff(request),data)
    return service
