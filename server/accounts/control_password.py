"""Console-provisioned passwords for existing staff; no public registration."""
import hashlib
import hmac
import re
import secrets
import time
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field

class PasswordInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    username:str=Field(min_length=3,max_length=64)
    password:str=Field(min_length=1,max_length=128)
    otp:str=Field(default='',max_length=32)

class StaffPasswordInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    target_uid:str=Field(min_length=1,max_length=128)
    username:str=Field(min_length=3,max_length=64)
    password:str=Field(min_length=12,max_length=128,repr=False)

def username_key(value):
    value=value.strip().lower()
    if not re.fullmatch(r'[a-z0-9_.-]{3,64}',value):
        raise ValueError('Username: use 3–64 English letters, numbers, dot, underscore or dash')
    return value

def password_hash(password,salt):
    return hashlib.scrypt(password.encode(),salt=bytes.fromhex(salt),n=16384,r=8,p=1,dklen=32,maxmem=64*1024*1024).hex()

class Passwords:
    def __init__(self,control):
        self.control=control
        with control.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS account_control_passwords(username TEXT PRIMARY KEY,uid TEXT UNIQUE NOT NULL,salt TEXT NOT NULL,password_hash TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS account_control_login_attempts(id INTEGER PRIMARY KEY AUTOINCREMENT,username TEXT NOT NULL,created_at INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS control_login_attempt_time ON account_control_login_attempts(created_at);
            ''')

    def set(self,uid,username,password,actor=None):
        username=username_key(username)
        if len(password)<12 or len(password)>128:
            raise ValueError('Password must contain 12–128 characters')
        salt=secrets.token_hex(16)
        hashed=password_hash(password,salt)
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            target_role=self.control.role(db,uid)
            if actor is not None:
                if self.control.role(db,actor)!='owner':raise HTTPException(403,'Only the owner can manage staff passwords')
                if target_role=='owner' or actor==uid:raise HTTPException(403,'Owner credentials require the existing console recovery process')
            other=db.execute('SELECT uid FROM account_control_passwords WHERE username=?',(username,)).fetchone()
            if other and other['uid']!=uid:raise ValueError('Username already assigned')
            db.execute('DELETE FROM account_control_passwords WHERE uid=?',(uid,))
            db.execute('INSERT INTO account_control_passwords VALUES(?,?,?,?)',(username,uid,salt,hashed))
            db.execute('DELETE FROM account_control_sessions WHERE uid=?',(uid,))
            db.execute('DELETE FROM account_control_codes WHERE uid=?',(uid,))
            db.execute('DELETE FROM account_control_login_attempts WHERE username=?',(username,))
            self.control.audit(db,actor or uid,'password.set',uid,{'username':username})

    def credentials(self,actor):
        with self.control.db() as db:
            if self.control.role(db,actor)!='owner':raise HTTPException(403,'Owner required')
            return [dict(r) for r in db.execute("SELECT s.uid,s.role,p.username FROM (SELECT uid,role FROM account_staff UNION ALL SELECT uid,'agent' AS role FROM account_control_agents) s LEFT JOIN account_control_passwords p ON p.uid=s.uid WHERE s.role<>'owner' ORDER BY s.uid")]

    def provision(self,actor,data):
        try:self.set(data.target_uid,data.username,data.password,actor=actor)
        except ValueError as error:raise HTTPException(422,str(error)) from None
        return {'saved':True,'sessions_revoked':True}

    def login(self,username,password,otp=''):
        try:username=username_key(username)
        except ValueError:username='invalid'
        now=int(time.time())
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('DELETE FROM account_control_login_attempts WHERE created_at<=?',(now-900,))
            count=db.execute('SELECT COUNT(*) FROM account_control_login_attempts').fetchone()[0]
            personal=db.execute('SELECT COUNT(*) FROM account_control_login_attempts WHERE username=?',(username,)).fetchone()[0]
            if count>=60 or personal>=8:raise HTTPException(429,'Too many sign-in attempts. Try again in 15 minutes.')
            # Commit the attempt even when authentication fails; parallel requests share this limit.
            db.execute('INSERT INTO account_control_login_attempts(username,created_at) VALUES(?,?)',(username,now))
            row=db.execute('SELECT * FROM account_control_passwords WHERE username=?',(username,)).fetchone()
        actual=password_hash(password,row['salt'] if row else '00'*16)
        if not hmac.compare_digest(actual,row['password_hash'] if row else '00'*32):
            raise HTTPException(401,'Username or password is incorrect')
        if not row:raise HTTPException(401,'Username or password is incorrect')
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            current=db.execute('SELECT * FROM account_control_passwords WHERE username=?',(username,)).fetchone()
            if not current or current['password_hash']!=row['password_hash']:raise HTTPException(401,'Sign in again')
            self.control.role(db,row['uid'])
            from .control_security import check_factor
            check_factor(db,row['uid'],otp)
            token=secrets.token_hex(32)
            db.execute('DELETE FROM account_control_sessions WHERE expires<=?',(now,))
            db.execute('INSERT INTO account_control_sessions VALUES(?,?,?)',(hashlib.sha256(token.encode()).hexdigest(),row['uid'],now+1800))
            self.control.audit(db,row['uid'],'password.login',row['uid'],{})
            return token
