"""TOTP, single-use recovery codes and bounded admin session visibility."""
import asyncio
import base64
import hashlib
import hmac
import json
import secrets
import struct
import time
from urllib.parse import quote
from fastapi import HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field
from .control import Control, COOKIE, digest

class FactorInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    password:str=Field(min_length=1,max_length=128)
    otp:str=Field(default='',max_length=32)

class FactorConfirm(BaseModel):
    model_config=ConfigDict(extra='forbid')
    otp:str=Field(pattern=r'^\d{6}$')

def schema(db):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS account_control_factor_attempts(key TEXT NOT NULL,created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_control_totp(uid TEXT PRIMARY KEY,secret TEXT NOT NULL,active INTEGER NOT NULL,last_counter INTEGER NOT NULL DEFAULT -1,created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_control_recovery(uid TEXT NOT NULL,hash TEXT NOT NULL,PRIMARY KEY(uid,hash));
    CREATE TABLE IF NOT EXISTS account_control_session_meta(hash TEXT PRIMARY KEY,created_at INTEGER NOT NULL,last_seen INTEGER NOT NULL,user_agent TEXT NOT NULL,remote_ip TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS account_staff_policy(uid TEXT PRIMARY KEY,expires_at INTEGER NOT NULL DEFAULT 0,denied TEXT NOT NULL DEFAULT '[]');
    ''')

def totp(secret,counter):
    key=base64.b32decode(secret+'='*((-len(secret))%8))
    mac=hmac.new(key,struct.pack('>Q',counter),hashlib.sha1).digest();offset=mac[-1]&15
    return f'{(struct.unpack(">I",mac[offset:offset+4])[0]&0x7fffffff)%1000000:06d}'

def check_factor(db,uid,value):
    row=db.execute('SELECT * FROM account_control_totp WHERE uid=? AND active=1',(uid,)).fetchone()
    if not row:return
    value=value.strip();counter=int(time.time())//30
    for c in (counter-1,counter,counter+1):
        if c>row['last_counter'] and hmac.compare_digest(totp(row['secret'],c),value):
            db.execute('UPDATE account_control_totp SET last_counter=? WHERE uid=?',(c,uid));return
    if db.execute('DELETE FROM account_control_recovery WHERE uid=? AND hash=?',(uid,digest(value))).rowcount:return
    raise HTTPException(401,'Authenticator or unused recovery code required')

class Security:
    def __init__(self,path):
        self.control=Control(path)
        with self.control.db() as db:schema(db)
    def password(self,db,uid,value):
        from .control_password import password_hash
        row=db.execute('SELECT * FROM account_control_passwords WHERE uid=?',(uid,)).fetchone()
        if not row or not hmac.compare_digest(password_hash(value,row['salt']),row['password_hash']):raise HTTPException(403,'Current admin password required')
    def state(self,uid,current):
        with self.control.db() as db:
            row=db.execute('SELECT active FROM account_control_totp WHERE uid=?',(uid,)).fetchone()
            return {'enabled':bool(row and row[0]),'recovery_remaining':db.execute('SELECT COUNT(*) FROM account_control_recovery WHERE uid=?',(uid,)).fetchone()[0],
             'sessions':[dict(r)|{'current':r['id']==digest(current or '')} for r in db.execute('''SELECT s.hash AS id,s.expires,m.created_at,m.last_seen,m.user_agent,m.remote_ip
              FROM account_control_sessions s LEFT JOIN account_control_session_meta m ON m.hash=s.hash WHERE s.uid=? AND s.expires>? ORDER BY m.created_at DESC LIMIT 100''',(uid,int(time.time())))]}
    def enroll(self,uid,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.password(db,uid,data.password)
            if db.execute('SELECT 1 FROM account_control_totp WHERE uid=? AND active=1',(uid,)).fetchone():raise HTTPException(409,'2FA already active')
            secret=base64.b32encode(secrets.token_bytes(20)).decode().rstrip('=')
            db.execute('INSERT INTO account_control_totp VALUES(?,?,0,-1,?) ON CONFLICT(uid) DO UPDATE SET secret=excluded.secret,active=0,last_counter=-1,created_at=excluded.created_at',(uid,secret,int(time.time())))
            return {'secret':secret,'uri':f'otpauth://totp/Sovera:{quote(uid,safe="")}?secret={secret}&issuer=Sovera&digits=6&period=30'}
    def confirm(self,uid,otp,current):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT * FROM account_control_totp WHERE uid=? AND active=0',(uid,)).fetchone();counter=int(time.time())//30
            matched=next((c for c in (counter-1,counter,counter+1) if row and hmac.compare_digest(totp(row['secret'],c),otp)),None)
            if not row or int(time.time())-row['created_at']>600 or matched is None:raise HTTPException(400,'Enrollment code invalid or expired')
            db.execute('UPDATE account_control_totp SET active=1,last_counter=? WHERE uid=?',(matched,uid))
            db.execute('DELETE FROM account_control_recovery WHERE uid=?',(uid,))
            codes=[secrets.token_hex(8) for _ in range(10)]
            db.executemany('INSERT INTO account_control_recovery VALUES(?,?)',[(uid,digest(c)) for c in codes])
            db.execute('DELETE FROM account_control_sessions WHERE uid=? AND hash<>?',(uid,digest(current or '')))
            db.execute('DELETE FROM account_control_codes WHERE uid=?',(uid,))
            self.control.audit(db,uid,'security.2fa.enabled',uid,{})
            return {'saved':True,'recovery_codes':codes}
    def disable(self,uid,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.password(db,uid,data.password);check_factor(db,uid,data.otp)
            db.execute('DELETE FROM account_control_totp WHERE uid=?',(uid,));db.execute('DELETE FROM account_control_recovery WHERE uid=?',(uid,))
            self.control.audit(db,uid,'security.2fa.disabled',uid,{})
            return {'saved':True}
    def revoke(self,uid,key):
        with self.control.db() as db:
            db.execute('DELETE FROM account_control_sessions WHERE uid=? AND hash=?',(uid,key));self.control.audit(db,uid,'security.session.revoked',uid,{})
            return {'saved':True}
    def mark(self,token,agent,ip):
        if not token:return
        now=int(time.time());key=digest(token)
        with self.control.db() as db:
            if not db.execute('SELECT 1 FROM account_control_sessions WHERE hash=? AND expires>?',(key,now)).fetchone():return
            db.execute('''INSERT INTO account_control_session_meta VALUES(?,?,?,?,?) ON CONFLICT(hash) DO UPDATE SET last_seen=excluded.last_seen WHERE account_control_session_meta.last_seen<?''',(key,now,now,agent[:256],ip[:100],now-60))
            db.execute('DELETE FROM account_control_session_meta WHERE hash NOT IN (SELECT hash FROM account_control_sessions)')

CAPS=('users','wallet','catalog','publications','support','rooms','reports','programs')
def permit(db,uid,path):
    p=db.execute('SELECT * FROM account_staff_policy WHERE uid=?',(uid,)).fetchone()
    if not p:return
    if p['expires_at'] and p['expires_at']<=int(time.time()):raise HTTPException(403,'Staff access expired')
    prefix=path.removeprefix('/sovera/control/').split('/')[0]
    cap={'users':'users','recharge':'wallet','history':'wallet','catalog':'catalog','media':'catalog','publications':'publications','official-messages':'publications','support':'support','operations':'reports','rooms':'rooms','programs':'programs','payments':'wallet'}.get(prefix)
    if path.startswith('/sovera/control/operations/tickets'):cap='support'
    if path.startswith('/sovera/control/operations/schedules'):cap='publications'
    if path.startswith('/sovera/control/operations/members'):cap='users'
    denied=json.loads(p['denied'])
    if path.startswith('/sovera/control/users/') and path.endswith(('/adjust','/history')) and 'wallet' in denied:raise HTTPException(403,'Wallet capability disabled')
    if cap and cap in denied:raise HTTPException(403,'This action is disabled for your staff account')

def attach_security(app,profiles,staff):
    service=Security(profiles.path)
    @app.get('/sovera/control/security')
    async def state(request:Request):return await asyncio.to_thread(service.state,await staff(request),request.cookies.get(COOKIE))
    @app.post('/sovera/control/security/enroll')
    async def enroll(data:FactorInput,request:Request):return await asyncio.to_thread(service.enroll,await staff(request),data)
    @app.post('/sovera/control/security/confirm')
    async def confirm(data:FactorConfirm,request:Request):return await asyncio.to_thread(service.confirm,await staff(request),data.otp,request.cookies.get(COOKIE))
    @app.post('/sovera/control/security/disable')
    async def disable(data:FactorInput,request:Request):return await asyncio.to_thread(service.disable,await staff(request),data)
    @app.delete('/sovera/control/security/sessions/{key}')
    async def revoke(key:str,request:Request):return await asyncio.to_thread(service.revoke,await staff(request),key)
    return service
