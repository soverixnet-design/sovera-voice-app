"""Self-hosted staff control. Firebase identity, one ledger, no Supabase calls."""
import asyncio
import hashlib
import json
import secrets
import sqlite3
import time
import uuid
from fastapi import Header, HTTPException, Request, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from .community import Community

ORIGIN='https://admin.soverixnet.com'
COOKIE='__Host-sovera-control'
LIMIT=9007199254740991

class CodeInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    code:str=Field(pattern=r'^[a-f0-9]{64}$')
    otp:str=Field(default='',max_length=32)

class RechargeInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    target_uid:str=Field(min_length=1,max_length=128)
    amount:int=Field(strict=True,ge=1,le=LIMIT)
    request_id:uuid.UUID
    note:str=Field(default='',max_length=300)

class ExchangePolicyInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    coins_per_100:int=Field(strict=True,ge=1,le=100)

class StaffInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    target_uid:str=Field(min_length=1,max_length=128)
    role:str=Field(pattern=r'^(admin|support|agent|none)$')
    quota:int=Field(strict=True,ge=0,le=LIMIT)

def digest(value):return hashlib.sha256(value.encode()).hexdigest()

class Control:
    def __init__(self,path):
        self.path=str(path)
        self.community=Community(path)
        from .messaging import Messaging
        self.messaging=Messaging(path)
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS account_control_codes(hash TEXT PRIMARY KEY,uid TEXT NOT NULL,expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_control_sessions(hash TEXT PRIMARY KEY,uid TEXT NOT NULL,expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_control_agents(uid TEXT PRIMARY KEY,quota INTEGER NOT NULL DEFAULT 0,used INTEGER NOT NULL DEFAULT 0 CHECK(used>=0 AND used<=quota));
            CREATE TABLE IF NOT EXISTS account_control_audit(id INTEGER PRIMARY KEY AUTOINCREMENT,actor TEXT NOT NULL,action TEXT NOT NULL,target TEXT NOT NULL,payload TEXT NOT NULL,created_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS account_control_recharges(request_id TEXT PRIMARY KEY,actor TEXT NOT NULL,target TEXT NOT NULL,amount INTEGER NOT NULL,note TEXT NOT NULL,balance INTEGER NOT NULL,created_at INTEGER NOT NULL);
            ''')
            from .control_security import schema
            schema(db)

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
        if db.execute("SELECT 1 FROM sqlite_master WHERE name='account_staff_policy'").fetchone():
            expiry=db.execute('SELECT expires_at FROM account_staff_policy WHERE uid=?',(uid,)).fetchone()
            if expiry and expiry[0] and expiry[0]<=int(time.time()):raise HTTPException(403,'Staff access expired')
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

    def login(self,code,otp=''):
        with self.db() as throttle:
            now=int(time.time());throttle.execute('DELETE FROM account_control_factor_attempts WHERE created_at<?',(now-900,))
            key=digest(code)
            if throttle.execute('SELECT COUNT(*) FROM account_control_factor_attempts WHERE key=?',(key,)).fetchone()[0]>=8:raise HTTPException(429,'Too many code attempts. Request a new access code')
            throttle.execute('INSERT INTO account_control_factor_attempts VALUES(?,?)',(key,now))
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            now=int(time.time())
            row=db.execute('SELECT uid FROM account_control_codes WHERE hash=? AND expires>?',(digest(code),now)).fetchone()
            if not row:raise HTTPException(401,'Invalid or expired code')
            self.role(db,row['uid'])
            from .control_security import check_factor
            check_factor(db,row['uid'],otp)
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
            policy=db.execute('SELECT expires_at FROM account_staff_policy WHERE uid=?',(row['uid'],)).fetchone()
            if policy and policy[0] and policy[0]<=int(time.time()):raise HTTPException(403,'Staff access expired')
            if db.execute('SELECT 1 FROM account_bans WHERE uid=?',(row['uid'],)).fetchone():raise HTTPException(403,'Account banned')
            return row['uid']

    def logout(self,token):
        with self.db() as db:db.execute('DELETE FROM account_control_sessions WHERE hash=?',(digest(token or ''),))

    def overview(self,uid):
        with self.db() as db:
            role=self.role(db,uid)
            profile=db.execute('SELECT display_name FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone()
            agent=db.execute('SELECT quota,used FROM account_control_agents WHERE uid=?',(uid,)).fetchone()
            open_tickets=db.execute("SELECT COUNT(*) FROM account_support WHERE reply=''").fetchone()[0]
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='account_ticket_state'").fetchone():
                open_tickets=db.execute("SELECT COUNT(*) FROM account_support t LEFT JOIN account_ticket_state s ON s.ticket=t.id WHERE COALESCE(s.status,CASE WHEN t.reply='' THEN 'open' ELSE 'resolved' END)<>'resolved'").fetchone()[0]
            return {'role':role,'name':profile['display_name'] if profile else 'Staff','uid':uid,
                'quota_remaining':agent['quota']-agent['used'] if agent else None,
                'users':db.execute('SELECT COUNT(*) FROM account_profiles').fetchone()[0],
                'rooms':db.execute('SELECT COUNT(*) FROM account_rooms').fetchone()[0],
                'open_tickets':open_tickets}

    def users(self,uid,q='',offset=0):
        with self.db() as db:
            if self.role(db,uid)=='support':raise HTTPException(403,'User lookup permission required')
            return [dict(r) for r in db.execute('''SELECT p.firebase_uid AS uid,p.display_name AS name,p.country,COALESCE(i.public_id,n.public_id) AS public_id,p.bio,p.avatar_url,p.updated_at,
              (SELECT seen_at FROM account_presence WHERE uid=p.firebase_uid) AS last_seen,
              (SELECT r.name FROM account_presence a JOIN account_rooms r ON r.id=a.room_id WHERE a.uid=p.firebase_uid AND a.seen_at>strftime('%s','now')-90) AS current_room,
              (SELECT role FROM account_staff WHERE uid=p.firebase_uid) AS role,
              l.status AS wallet_status,l.source_ref,
              (SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger e WHERE e.firebase_uid=p.firebase_uid) AS coins,
              (SELECT COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger e WHERE e.firebase_uid=p.firebase_uid) AS diamonds
              FROM account_profiles p LEFT JOIN account_wallet_links l ON l.firebase_uid=p.firebase_uid
              LEFT JOIN account_wallet_imports i ON i.firebase_uid=p.firebase_uid LEFT JOIN account_public_ids n ON n.uid=p.firebase_uid
              WHERE (?='' OR p.display_name LIKE ? OR p.firebase_uid LIKE ? OR COALESCE(l.source_ref,'') LIKE ? OR p.country LIKE ? OR COALESCE(i.public_id,n.public_id,'') LIKE ?)
              ORDER BY p.display_name,p.firebase_uid LIMIT 200 OFFSET ?''',(q,'%'+q+'%','%'+q+'%','%'+q+'%','%'+q+'%','%'+q+'%',offset))]

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
            from .messaging import official
            official(db,'recharge:'+request,data.target_uid,'Coins received',f'You received {data.amount:,} Coins. Balance after recharge: {balance+data.amount:,} Coins.' + (' Note: '+data.note if data.note else ''))
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
                if data.role=='none' and db.execute("SELECT 1 FROM sqlite_master WHERE name='account_control_passwords'").fetchone():
                    db.execute('DELETE FROM account_control_passwords WHERE uid=?',(data.target_uid,))
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
        if request.url.path.startswith('/sovera/control/') and request.url.path not in ('/sovera/control/login','/sovera/control/password-login'):
            try:
                uid=await asyncio.to_thread(service.actor,request.cookies.get(COOKIE))
                from .control_security import permit
                with service.db() as db:permit(db,uid,request.url.path)
            except HTTPException as e:return JSONResponse({'detail':e.detail},status_code=e.status_code)
        response=await call_next(request)
        await asyncio.to_thread(security.mark,request.cookies.get(COOKIE),request.headers.get('user-agent',''),request.client.host if request.client else '')
        return response

    @app.post('/sovera/account/staff/access-code')
    async def access_code(authorization:str|None=Header(default=None)):
        return await asyncio.to_thread(service.code,await actor(authorization))

    @app.post('/sovera/control/login')
    async def login(data:CodeInput):
        token=await asyncio.to_thread(service.login,data.code,data.otp)
        response=JSONResponse({'signed_in':True})
        response.set_cookie(COOKIE,token,max_age=1800,secure=True,httponly=True,samesite='strict',path='/')
        return response

    @app.post('/sovera/control/password-login')
    async def password_login(data:PasswordInput):
        token=await asyncio.to_thread(passwords.login,data.username,data.password,data.otp)
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
    async def users(request:Request,q:str=Query(default='',max_length=128),offset:int=Query(default=0,ge=0,le=1000000)):return {'items':await asyncio.to_thread(service.users,await staff_actor(request),q,offset)}

    @app.get('/sovera/control/exchange-policy')
    async def exchange_policy(request:Request):
        uid=await staff_actor(request)
        with service.db() as db:
            if service.role(db,uid)!='owner':raise HTTPException(403,'Owner required')
            return {'coins_per_100':db.execute('SELECT coins_per_100 FROM account_exchange_policy WHERE id=1').fetchone()[0]}

    @app.put('/sovera/control/exchange-policy')
    async def set_exchange_policy(data:ExchangePolicyInput,request:Request):
        uid=await staff_actor(request)
        with service.db() as db:
            if service.role(db,uid)!='owner':raise HTTPException(403,'Owner required')
            db.execute('UPDATE account_exchange_policy SET coins_per_100=? WHERE id=1',(data.coins_per_100,))
            service.audit(db,uid,'exchange.policy',uid,{'coins_per_100':data.coins_per_100})
            return {'saved':True}

    @app.post('/sovera/control/recharge')
    async def recharge(data:RechargeInput,request:Request):return await asyncio.to_thread(service.recharge,await staff_actor(request),data)

    @app.get('/sovera/control/staff')
    async def staff(request:Request):return {'items':await asyncio.to_thread(service.staff,await staff_actor(request))}

    from .control_password import StaffPasswordInput
    @app.get('/sovera/control/staff/credentials')
    async def staff_credentials(request:Request):return {'items':await asyncio.to_thread(passwords.credentials,await staff_actor(request))}
    @app.post('/sovera/control/staff/credentials')
    async def staff_password(data:StaffPasswordInput,request:Request):return await asyncio.to_thread(passwords.provision,await staff_actor(request),data)

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

    from .messaging import SellerInput,NoticeInput,SellerPackageInput
    @app.get('/sovera/control/sellers/package')
    async def seller_package(request:Request):
        return await asyncio.to_thread(service.messaging.package,await staff_actor(request))
    @app.post('/sovera/control/sellers/package')
    async def seller_package_save(data:SellerPackageInput,request:Request):
        return await asyncio.to_thread(service.messaging.package,await staff_actor(request),data)
    @app.get('/sovera/control/sellers')
    async def sellers(request:Request):
        uid=await staff_actor(request)
        return {'items':await asyncio.to_thread(service.messaging.sellers,uid)}
    @app.post('/sovera/control/sellers')
    async def seller_save(data:SellerInput,request:Request):
        return await asyncio.to_thread(service.messaging.seller_save,await staff_actor(request),data)
    @app.post('/sovera/control/official-messages')
    async def official_message(data:NoticeInput,request:Request):
        return await asyncio.to_thread(service.messaging.notice,await staff_actor(request),data)

    from .members import attach_members
    attach_members(app,profiles,actor,staff_actor)

    from .rewards import attach_rewards
    attach_rewards(app,profiles,actor,staff_actor)

    from .control_security import attach_security
    security=attach_security(app,profiles,staff_actor)

    from .operations import attach_operations
    attach_operations(app,profiles,staff_actor)

    from .programs import attach_programs
    attach_programs(app,profiles,actor,staff_actor)
