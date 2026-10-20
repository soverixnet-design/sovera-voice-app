"""Self-hosted staff control. Firebase identity, one ledger, no Supabase calls."""
import asyncio
import hashlib
import json
import secrets
import sqlite3
import time
import uuid
from fastapi import Header, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from .community import Community

ORIGIN='https://admin.soverixnet.com'
COOKIE='__Host-sovera-control'
LIMIT=9007199254740991

class CodeInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    code:str=Field(pattern=r'^[a-f0-9]{64}$')

class RechargeInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    target_uid:str=Field(min_length=1,max_length=128)
    amount:int=Field(strict=True,ge=1,le=1000000000)
    request_id:uuid.UUID
    note:str=Field(default='',max_length=300)

class StaffInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    target_uid:str=Field(min_length=1,max_length=128)
    role:str=Field(pattern=r'^(admin|support|agent|none)$')
    quota:int=Field(strict=True,ge=0,le=1000000000)

def digest(value):return hashlib.sha256(value.encode()).hexdigest()

class Control:
    def __init__(self,path):
        self.path=str(path)
        self.community=Community(path)
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS account_control_codes(hash TEXT PRIMARY KEY,uid TEXT NOT NULL,expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_control_sessions(hash TEXT PRIMARY KEY,uid TEXT NOT NULL,expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_control_agents(uid TEXT PRIMARY KEY,quota INTEGER NOT NULL DEFAULT 0,used INTEGER NOT NULL DEFAULT 0 CHECK(used>=0 AND used<=quota));
            CREATE TABLE IF NOT EXISTS account_control_audit(id INTEGER PRIMARY KEY AUTOINCREMENT,actor TEXT NOT NULL,action TEXT NOT NULL,target TEXT NOT NULL,payload TEXT NOT NULL,created_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_control_recharges(request_id TEXT PRIMARY KEY,actor TEXT NOT NULL,target TEXT NOT NULL,amount INTEGER NOT NULL,note TEXT NOT NULL,balance INTEGER NOT NULL,created_at INTEGER NOT NULL);
            ''')

    def db(self):
        # All writes use an explicit transaction under this context manager.
        from contextlib import contextmanager
        @contextmanager
        def connection():
            db=sqlite3.connect(self.path,timeout=10)
            db.row_factory=sqlite3.Row
            try:
                with db:yield db
            finally:db.close()
        return connection()

    def role(self,db,uid):
        staff=db.execute('SELECT role FROM account_staff WHERE uid=?',(uid,)).fetchone()
        if staff:return staff['role']
        if db.execute('SELECT 1 FROM account_control_agents WHERE uid=?',(uid,)).fetchone():return 'agent'
        raise HTTPException(403,'Staff permission required')

    def code(self,uid):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.role(db,uid)
            now=int(time.time())
            db.execute('DELETE FROM account_control_codes WHERE uid=? OR expires<=?',(uid,now))
            code=secrets.token_hex(32)
            db.execute('INSERT INTO account_control_codes VALUES(?,?,?)',(digest(code),uid,now+300))
            return {'code':code,'expires_at':now+300,'url':ORIGIN}

    def login(self,code):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            now=int(time.time())
            row=db.execute('SELECT uid FROM account_control_codes WHERE hash=? AND expires>?',(digest(code),now)).fetchone()
            if not row:raise HTTPException(401,'Invalid or expired code')
            self.role(db,row['uid'])
            db.execute('DELETE FROM account_control_codes WHERE hash=?',(digest(code),))
            db.execute('DELETE FROM account_control_sessions WHERE expires<=?',(now,))
            token=secrets.token_hex(32)
            db.execute('INSERT INTO account_control_sessions VALUES(?,?,?)',(digest(token),row['uid'],now+1800))
            return token

    def actor(self,token):
        if not token or len(token)!=64:raise HTTPException(401,'Sign in required')
        with self.db() as db:
            row=db.execute('SELECT uid FROM account_control_sessions WHERE hash=? AND expires>?',(digest(token),int(time.time()))).fetchone()
            if not row:raise HTTPException(401,'Session expired')
            self.role(db,row['uid'])
            return row['uid']

    def logout(self,token):
        with self.db() as db:db.execute('DELETE FROM account_control_sessions WHERE hash=?',(digest(token or ''),))

    def overview(self,uid):
        with self.db() as db:
            role=self.role(db,uid)
            profile=db.execute('SELECT display_name FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone()
            agent=db.execute('SELECT quota,used FROM account_control_agents WHERE uid=?',(uid,)).fetchone()
            return {'role':role,'name':profile['display_name'] if profile else 'Staff','uid':uid,
                'quota_remaining':agent['quota']-agent['used'] if agent else None,
                'users':db.execute('SELECT COUNT(*) FROM account_profiles').fetchone()[0],
                'rooms':db.execute('SELECT COUNT(*) FROM account_rooms').fetchone()[0],
                'open_tickets':db.execute("SELECT COUNT(*) FROM account_support WHERE reply='' ").fetchone()[0]}

    def users(self,uid):
        with self.db() as db:
            if self.role(db,uid)=='support':raise HTTPException(403,'User lookup permission required')
            return [dict(r) for r in db.execute('''SELECT p.firebase_uid AS uid,p.display_name AS name,p.country,
              l.status AS wallet_status,l.source_ref,
              (SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger e WHERE e.firebase_uid=p.firebase_uid) AS coins,
              (SELECT COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger e WHERE e.firebase_uid=p.firebase_uid) AS diamonds
              FROM account_profiles p LEFT JOIN account_wallet_links l ON l.firebase_uid=p.firebase_uid
              ORDER BY p.display_name,p.firebase_uid LIMIT 200''')]

    def recharge(self,uid,data):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            role=self.role(db,uid)
            if role not in ('owner','agent'):raise HTTPException(403,'Recharge permission required')
            request=str(data.request_id)
            prior=db.execute('SELECT * FROM account_control_recharges WHERE request_id=?',(request,)).fetchone()
            if prior:
                if (prior['actor'],prior['target'],prior['amount'],prior['note'])!=(uid,data.target_uid,data.amount,data.note):raise HTTPException(409,'Request already used')
                return dict(prior)
            link=db.execute('SELECT status FROM account_wallet_links WHERE firebase_uid=?',(data.target_uid,)).fetchone()
            if not link:raise HTTPException(409,'Original wallet must be verified before recharge')
            if link['status']!='active':raise HTTPException(409,'Wallet is frozen')
            balance=db.execute('SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(data.target_uid,)).fetchone()[0]
            if balance<0 or balance+data.amount>LIMIT:raise HTTPException(409,'Wallet reconciliation required')
            if role=='agent':
                updated=db.execute('UPDATE account_control_agents SET used=used+? WHERE uid=? AND quota-used>=?',(data.amount,uid,data.amount))
                if updated.rowcount!=1:raise HTTPException(409,'Recharge quota exceeded')
            now=int(time.time())
            db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',('recharge:'+request,data.target_uid,data.amount,0,'recharge',now))
            db.execute('INSERT INTO account_control_recharges VALUES(?,?,?,?,?,?,?)',(request,uid,data.target_uid,data.amount,data.note,balance+data.amount,now))
            self.audit(db,uid,'recharge',data.target_uid,{'amount':data.amount,'request_id':request})
            return dict(db.execute('SELECT * FROM account_control_recharges WHERE request_id=?',(request,)).fetchone())

    def audit(self,db,uid,action,target,payload):
        db.execute('INSERT INTO account_control_audit(actor,action,target,payload,created_at) VALUES(?,?,?,?,?)',(uid,action,target,json.dumps(payload),int(time.time())))

    def staff(self,uid,data=None):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.role(db,uid)!='owner':raise HTTPException(403,'Only the owner manages staff')
            if data:
                if data.target_uid==uid:raise HTTPException(409,'Cannot change your own owner access')
                if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(data.target_uid,)).fetchone():raise HTTPException(404,'User not found')
                current=db.execute('SELECT role FROM account_staff WHERE uid=?',(data.target_uid,)).fetchone()
                if current and current['role']=='owner':raise HTTPException(403,'Owner access is console-managed')
                used=db.execute('SELECT COALESCE(SUM(amount),0) FROM account_control_recharges WHERE actor=?',(data.target_uid,)).fetchone()[0]
                if data.role=='agent' and data.quota<used:raise HTTPException(409,'Quota is below coins already issued')
                db.execute('DELETE FROM account_staff WHERE uid=?',(data.target_uid,))
                # Retain spent-quota history when access is revoked.
                db.execute('DELETE FROM account_control_agents WHERE uid=?',(data.target_uid,))
                if data.role=='agent':db.execute('INSERT INTO account_control_agents VALUES(?,?,?)',(data.target_uid,data.quota,used))
                elif data.role!='none':db.execute('INSERT INTO account_staff VALUES(?,?)',(data.target_uid,data.role))
                db.execute('DELETE FROM account_control_codes WHERE uid=?',(data.target_uid,))
                db.execute('DELETE FROM account_control_sessions WHERE uid=?',(data.target_uid,))
                self.audit(db,uid,'staff.save',data.target_uid,{'role':data.role,'quota':data.quota,'previous_used':used})
            return [dict(r) for r in db.execute('''SELECT uid,role,NULL AS quota,NULL AS used FROM account_staff
              UNION ALL SELECT uid,'agent',quota,used FROM account_control_agents ORDER BY uid''')]

    def history(self,uid):
        with self.db() as db:
            role=self.role(db,uid)
            if role not in ('owner','agent'):raise HTTPException(403,'Finance permission required')
            return [dict(r) for r in db.execute('SELECT * FROM account_control_recharges WHERE ?=1 OR actor=? ORDER BY created_at DESC,request_id DESC LIMIT 100',(int(role=='owner'),uid))]

def attach_control(app,profiles,actor):
    service=Control(profiles.path)
    from .control_password import Passwords,PasswordInput
    passwords=Passwords(service)
    async def staff_actor(request):return await asyncio.to_thread(service.actor,request.cookies.get(COOKIE))

    @app.middleware('http')
    async def protect_control(request,call_next):
        if request.url.path.startswith('/sovera/control'):
            if request.headers.get('host','').split(':')[0]!='admin.soverixnet.com':
                return JSONResponse({'detail':'Admin domain required'},status_code=403)
            if request.method not in ('GET','HEAD') and request.headers.get('origin')!=ORIGIN:
                return JSONResponse({'detail':'Admin origin required'},status_code=403)
        return await call_next(request)

    @app.post('/sovera/account/staff/access-code')
    async def access_code(authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.code,await actor(authorization))

    @app.post('/sovera/control/login')
    async def login(data:CodeInput):
        token=await asyncio.to_thread(service.login,data.code)
        response=JSONResponse({'signed_in':True})
        response.set_cookie(COOKIE,token,max_age=1800,secure=True,httponly=True,samesite='strict',path='/')
        return response

    @app.post('/sovera/control/password-login')
    async def password_login(data:PasswordInput):
        token=await asyncio.to_thread(passwords.login,data.username,data.password)
        response=JSONResponse({'signed_in':True})
        response.set_cookie(COOKIE,token,max_age=1800,secure=True,httponly=True,samesite='strict',path='/')
        return response

    @app.post('/sovera/control/logout')
    async def logout(request:Request):
        await asyncio.to_thread(service.logout,request.cookies.get(COOKIE))
        response=JSONResponse({'signed_out':True})
        response.delete_cookie(COOKIE,path='/',secure=True,httponly=True,samesite='strict')
        return response

    @app.get('/sovera/control/session')
    async def session(request:Request):return await asyncio.to_thread(service.overview,await staff_actor(request))

    @app.get('/sovera/control/users')
    async def users(request:Request):return {'items':await asyncio.to_thread(service.users,await staff_actor(request))}

    @app.post('/sovera/control/recharge')
    async def recharge(data:RechargeInput,request:Request):return await asyncio.to_thread(service.recharge,await staff_actor(request),data)

    @app.get('/sovera/control/staff')
    async def staff(request:Request):return {'items':await asyncio.to_thread(service.staff,await staff_actor(request))}

    @app.post('/sovera/control/staff')
    async def staff_save(data:StaffInput,request:Request):return {'items':await asyncio.to_thread(service.staff,await staff_actor(request),data)}

    @app.get('/sovera/control/history')
    async def history(request:Request):return {'items':await asyncio.to_thread(service.history,await staff_actor(request))}

    @app.get('/sovera/control/support')
    async def support(request:Request):return {'items':await asyncio.to_thread(service.community.inbox,await staff_actor(request))}

    from .community import CommunityText,Publication
    @app.put('/sovera/control/support/{ticket}')
    async def reply(ticket:int,data:CommunityText,request:Request):return await asyncio.to_thread(service.community.reply,await staff_actor(request),ticket,data.text)

    @app.post('/sovera/control/publications')
    async def publish(data:Publication,request:Request):return await asyncio.to_thread(service.community.publish,await staff_actor(request),data)
