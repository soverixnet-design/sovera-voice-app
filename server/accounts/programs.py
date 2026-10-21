"""Owner-configured memberships, qualified referrals and verified manual recharge orders.

This module never treats an unverified payment reference as payment. External cash
collection/refunds require the owner's merchant/provider verification.
"""
import asyncio
import json
import time
import uuid
from datetime import datetime,timezone
from typing import Literal
from fastapi import HTTPException,Request,Query
from pydantic import BaseModel,ConfigDict,Field
from .control import Control,LIMIT
from .messaging import official

class Pack(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    id:uuid.UUID
    kind:Literal['vip','svip','recharge']
    title:str=Field(min_length=2,max_length=80)
    coins:int=Field(strict=True,ge=1,le=1000000000)
    days:int=Field(strict=True,ge=1,le=365,default=30)
    level:int=Field(strict=True,ge=1,le=20,default=1)
    item_ids:list[uuid.UUID]=Field(default_factory=list,max_length=5)
    currency:str=Field(default='USD',pattern=r'^[A-Z]{3}$')
    price_minor:int=Field(strict=True,ge=1,le=100000000,default=100)
    payment_method:str=Field(default='Manual verification',min_length=2,max_length=80)
    instructions:str=Field(default='',max_length=800)
    active:bool=True
class Buy(BaseModel):
    model_config=ConfigDict(extra='forbid')
    item_id:uuid.UUID
    request_id:uuid.UUID
    expected_coins:int=Field(strict=True,ge=1,le=1000000000)
class ReferralPolicy(BaseModel):
    model_config=ConfigDict(extra='forbid')
    enabled:bool=False
    recharge_target:int=Field(strict=True,ge=1,le=1000000000,default=1000)
    reward_coins:int=Field(strict=True,ge=1,le=1000000000,default=100)
    inviter_limit:int=Field(strict=True,ge=1,le=100000,default=10)
    join_days:int=Field(strict=True,ge=1,le=365,default=7)
class ReferralCode(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    public_id:str=Field(pattern=r'^\d{1,20}$')
class PaymentOrder(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    item_id:uuid.UUID
    request_id:uuid.UUID
    reference:str=Field(min_length=3,max_length=100)
class PaymentDecision(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    action:Literal['approve','reject','refund']
    note:str=Field(min_length=3,max_length=500)

def schema(db):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS account_program_packs(id TEXT PRIMARY KEY,payload TEXT NOT NULL,updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_program_policy(key TEXT PRIMARY KEY,payload TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS account_program_cancelled(id TEXT PRIMARY KEY,uid TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS account_program_purchases(id TEXT PRIMARY KEY,uid TEXT NOT NULL,payload TEXT NOT NULL,response TEXT NOT NULL,created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_memberships(uid TEXT PRIMARY KEY,kind TEXT NOT NULL,level INTEGER NOT NULL,title TEXT NOT NULL,expires_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_referrals(uid TEXT PRIMARY KEY,inviter TEXT NOT NULL,policy TEXT NOT NULL,joined_at INTEGER NOT NULL,claimed_at INTEGER);
    CREATE TABLE IF NOT EXISTS account_member_created(uid TEXT PRIMARY KEY,created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_payment_orders(id TEXT PRIMARY KEY,uid TEXT NOT NULL,pack TEXT NOT NULL,reference TEXT NOT NULL UNIQUE,status TEXT NOT NULL,note TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_agency_timeline(id INTEGER PRIMARY KEY AUTOINCREMENT,uid TEXT NOT NULL,agency TEXT NOT NULL,joined_at INTEGER NOT NULL,left_at INTEGER);
    CREATE TABLE IF NOT EXISTS account_agency_terms(id TEXT PRIMARY KEY,agency TEXT NOT NULL,manager TEXT NOT NULL,month TEXT NOT NULL,target INTEGER NOT NULL,salary INTEGER NOT NULL,rate INTEGER NOT NULL,paid_at INTEGER,UNIQUE(agency,month));
    ''')
    now=int(time.time())
    db.execute('INSERT OR IGNORE INTO account_member_created SELECT firebase_uid,? FROM account_profiles',(0,))
    db.execute("INSERT INTO account_agency_timeline(uid,agency,joined_at) SELECT m.uid,m.agency,? FROM account_agency_members m WHERE m.status='active' AND NOT EXISTS(SELECT 1 FROM account_agency_timeline t WHERE t.uid=m.uid AND t.left_at IS NULL)",(now,))

def membership(db,uid):
    if not db.execute("SELECT 1 FROM sqlite_master WHERE name='account_memberships'").fetchone():return None
    row=db.execute('SELECT kind,level,title,expires_at FROM account_memberships WHERE uid=? AND expires_at>?',(uid,int(time.time()))).fetchone()
    return dict(row) if row else None

def credit(db,uid,amount,key,kind='admin_adjust'):
    wallet=db.execute('SELECT status FROM account_wallet_links WHERE firebase_uid=?',(uid,)).fetchone()
    if not wallet or wallet[0]!='active':raise HTTPException(409,'Active wallet required')
    balance=db.execute('SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(uid,)).fetchone()[0]
    if not 0<=balance+amount<=LIMIT:raise HTTPException(409,'Insufficient Coins or wallet arithmetic limit reached')
    if amount:db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',(key,uid,amount,0,kind,int(time.time())))
    return balance+amount

class Programs:
    def __init__(self,path):
        self.control=Control(path)
        with self.control.db() as db:schema(db)
    def owner(self,db,uid):
        if self.control.role(db,uid)!='owner':raise HTTPException(403,'Owner required')
    def catalog(self,uid,admin=False):
        with self.control.db() as db:
            if admin:self.owner(db,uid)
            packs=[json.loads(r[0]) for r in db.execute('SELECT payload FROM account_program_packs ORDER BY updated_at DESC,id')]
            if not admin:packs=[p for p in packs if p['active']]
            from .wallet import legacy_identity
            row=db.execute("SELECT payload FROM account_program_policy WHERE key='referral'").fetchone();policy=json.loads(row[0]) if row else ReferralPolicy().model_dump()
            return {'items':packs,'membership':membership(db,uid),'referral_policy':policy,'public_id':legacy_identity(db,uid)['public_id'],
             'referral':dict(r) if (r:=db.execute('SELECT inviter,joined_at,claimed_at FROM account_referrals WHERE uid=?',(uid,)).fetchone()) else None,
             'invited':[dict(r) for r in db.execute('SELECT r.uid,p.display_name AS name,r.claimed_at,r.joined_at FROM account_referrals r JOIN account_profiles p ON p.firebase_uid=r.uid WHERE r.inviter=? ORDER BY joined_at DESC LIMIT 100',(uid,))]}
    def save_pack(self,uid,data):
        with self.control.db() as db:
            self.owner(db,uid)
            for key in data.item_ids:
                if not db.execute("SELECT 1 FROM account_catalog WHERE id=? AND kind IN ('frame','entry','medal','tag','room_frame') AND active=1",(str(key),)).fetchone():raise HTTPException(400,'Choose active wearable collection items')
            db.execute('INSERT INTO account_program_packs VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at',(str(data.id),data.model_dump_json(),int(time.time())))
            self.control.audit(db,uid,'program.pack',str(data.id),data.model_dump(mode='json'));return {'saved':True}
    def policy(self,uid,data):
        with self.control.db() as db:
            self.owner(db,uid);db.execute("INSERT INTO account_program_policy VALUES('referral',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload",(data.model_dump_json(),));self.control.audit(db,uid,'referral.policy','referral',data.model_dump());return {'saved':True}
    def buy(self,uid,data):
        key=str(data.request_id);payload=data.model_dump_json()
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');old=db.execute('SELECT * FROM account_program_purchases WHERE id=?',(key,)).fetchone()
            if old:
                if old['uid']!=uid or old['payload']!=payload:raise HTTPException(409,'Purchase ID already used')
                return json.loads(old['response'])
            if db.execute('SELECT 1 FROM account_program_cancelled WHERE id=?',(key,)).fetchone():raise HTTPException(409,'Request cancelled')
            pack=db.execute('SELECT payload FROM account_program_packs WHERE id=?',(str(data.item_id),)).fetchone();p=json.loads(pack[0]) if pack else {}
            if not p.get('active') or p.get('kind') not in ('vip','svip'):raise HTTPException(404,'Membership unavailable')
            if p['coins']!=data.expected_coins:raise HTTPException(409,'Price changed. Refresh membership offers')
            now=int(time.time());old_member=membership(db,uid)
            if old_member and (old_member['kind'],old_member['level'])!=(p['kind'],p['level']):raise HTTPException(409,'Your existing membership is active. Renew the same tier or wait for it to expire')
            balance=credit(db,uid,-p['coins'],'membership:'+key,'exchange');expires=max(now,old_member['expires_at'] if old_member else now)+p['days']*86400
            db.execute('INSERT INTO account_memberships VALUES(?,?,?,?,?) ON CONFLICT(uid) DO UPDATE SET kind=excluded.kind,level=excluded.level,title=excluded.title,expires_at=excluded.expires_at',(uid,p['kind'],p['level'],p['title'],expires))
            for item in p['item_ids']:
                own=db.execute('SELECT 1 FROM account_asset_ownership WHERE uid=? AND item_id=?',(uid,item)).fetchone();expiry=db.execute('SELECT expires_at FROM account_reward_asset_expiry WHERE uid=? AND item_id=?',(uid,item)).fetchone()
                if not own or expiry:
                    db.execute('INSERT OR IGNORE INTO account_asset_ownership VALUES(?,?,?)',(uid,item,now))
                    db.execute('INSERT INTO account_reward_asset_expiry VALUES(?,?,?) ON CONFLICT(uid,item_id) DO UPDATE SET expires_at=max(expires_at,excluded.expires_at)',(uid,item,expires))
            result={'saved':True,'coins':str(balance),'expires_at':expires}
            db.execute('INSERT INTO account_program_purchases VALUES(?,?,?,?,?)',(key,uid,payload,json.dumps(result),now));official(db,'membership:'+key,uid,'Membership activated',f"{p['title']} is active until {datetime.fromtimestamp(expires,timezone.utc).isoformat()}. Cost: {p['coins']:,} Coins.")
            self.control.audit(db,uid,'membership.buy',str(data.item_id),{'coins':p['coins'],'expires_at':expires});return result
    def refer(self,uid,code):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');row=db.execute("SELECT payload FROM account_program_policy WHERE key='referral'").fetchone();p=json.loads(row[0]) if row else {}
            if not p.get('enabled'):raise HTTPException(409,'Referral rewards are not enabled')
            if db.execute('SELECT 1 FROM account_referrals WHERE uid=?',(uid,)).fetchone():raise HTTPException(409,'An inviter is already linked')
            created=db.execute('SELECT created_at FROM account_member_created WHERE uid=?',(uid,)).fetchone()
            if not created or created[0]<time.time()-p['join_days']*86400:raise HTTPException(409,'Referral entry period ended')
            inviter=db.execute('''SELECT uid FROM account_public_ids WHERE public_id=? UNION SELECT firebase_uid FROM account_wallet_imports WHERE public_id=?''',(code,code)).fetchone()
            if not inviter or inviter[0]==uid or db.execute('SELECT 1 FROM account_bans WHERE uid=?',(inviter[0],)).fetchone():raise HTTPException(400,'Invalid inviter ID')
            if db.execute('SELECT COUNT(*) FROM account_referrals WHERE inviter=?',(inviter[0],)).fetchone()[0]>=p['inviter_limit']:raise HTTPException(409,'Inviter limit reached')
            db.execute('INSERT INTO account_referrals VALUES(?,?,?,?,NULL)',(uid,inviter[0],json.dumps(p),int(time.time())));return {'saved':True}
    def referral_claim(self,uid,target):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');r=db.execute('SELECT * FROM account_referrals WHERE uid=? AND inviter=?',(target,uid)).fetchone()
            if not r:raise HTTPException(404)
            if r['claimed_at']:return {'saved':True,'duplicate':True}
            p=json.loads(r['policy']);total=db.execute("SELECT COALESCE(SUM(amount),0) FROM account_control_recharges WHERE target=? AND created_at>=? AND NOT EXISTS(SELECT 1 FROM account_payment_orders o WHERE o.id=account_control_recharges.request_id AND o.status='refunded')",(target,r['joined_at'])).fetchone()[0]
            if total<p['recharge_target'] or db.execute('SELECT 1 FROM account_bans WHERE uid IN (?,?)',(uid,target)).fetchone():raise HTTPException(409,'Qualified verified recharge is required')
            credit(db,uid,p['reward_coins'],'referral:'+target);db.execute('UPDATE account_referrals SET claimed_at=? WHERE uid=?',(int(time.time()),target));official(db,'referral:'+target,uid,'Referral reward received',f"Your qualified referral earned {p['reward_coins']:,} Coins.");self.control.audit(db,'system','referral.reward',uid,{'invited':target,'coins':p['reward_coins']});return {'saved':True}
    def payment(self,uid,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');key=str(data.request_id);old=db.execute('SELECT * FROM account_payment_orders WHERE id=?',(key,)).fetchone()
            if old:
                if old['uid']!=uid or old['reference']!=data.reference or json.loads(old['pack'])['id']!=str(data.item_id):raise HTTPException(409,'Order ID already used')
                return {'saved':True,'status':old['status']}
            if db.execute('SELECT 1 FROM account_program_cancelled WHERE id=?',(key,)).fetchone():raise HTTPException(409,'Request cancelled')
            p=db.execute('SELECT payload FROM account_program_packs WHERE id=?',(str(data.item_id),)).fetchone();p=json.loads(p[0]) if p else {}
            if p.get('kind')!='recharge' or not p.get('active'):raise HTTPException(404,'Recharge offer unavailable')
            if db.execute('SELECT 1 FROM account_payment_orders WHERE reference=?',(data.reference,)).fetchone():raise HTTPException(409,'Payment reference already submitted')
            if db.execute("SELECT COUNT(*) FROM account_payment_orders WHERE uid=? AND status='pending'",(uid,)).fetchone()[0]>=3:raise HTTPException(429,'Wait for pending payment verification')
            now=int(time.time());db.execute('INSERT INTO account_payment_orders VALUES(?,?,?,?,?,?,?,?)',(key,uid,json.dumps(p),data.reference,'pending','',now,now));official(db,'payment:'+key,uid,'Payment verification pending','Your payment reference was submitted for manual verification. No Coins have been issued yet.');return {'saved':True,'status':'pending'}
    def cancel_request(self,uid,key):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            for table in ('account_program_purchases','account_payment_orders'):
                row=db.execute('SELECT uid FROM '+table+' WHERE id=?',(key,)).fetchone()
                if row:
                    if row[0]!=uid:raise HTTPException(403)
                    return {'saved':True,'applied':True}
            prior=db.execute('SELECT uid FROM account_program_cancelled WHERE id=?',(key,)).fetchone()
            if prior and prior[0]!=uid:raise HTTPException(403)
            db.execute('INSERT OR IGNORE INTO account_program_cancelled VALUES(?,?)',(key,uid));return {'saved':True,'applied':False}
    def payments(self,uid,admin=False):
        with self.control.db() as db:
            if admin:self.owner(db,uid)
            return [dict(r)|{'offer':json.loads(r['pack'])} for r in db.execute('SELECT * FROM account_payment_orders WHERE ?=1 OR uid=? ORDER BY created_at DESC LIMIT 200',(int(admin),uid))]
    def decide(self,uid,key,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.owner(db,uid);r=db.execute('SELECT * FROM account_payment_orders WHERE id=?',(key,)).fetchone()
            if not r:raise HTTPException(404)
            wanted={'approve':'approved','reject':'rejected','refund':'refunded'}[data.action]
            if r['status']==wanted:return {'saved':True,'duplicate':True}
            p=json.loads(r['pack']);now=int(time.time());target=r['uid']
            if data.action in ('approve','reject') and r['status']!='pending':raise HTTPException(409,'Order already reviewed')
            if data.action=='approve':
                balance=credit(db,target,p['coins'],'payment:'+key,'recharge')
                db.execute('INSERT INTO account_control_recharges VALUES(?,?,?,?,?,?,?)',(key,uid,target,p['coins'],'Verified manual payment: '+data.note,balance,now))
            if data.action=='refund':
                if r['status']!='approved':raise HTTPException(409,'Only approved orders can be reversed')
                credit(db,target,-p['coins'],'payment-refund:'+key)
            db.execute('UPDATE account_payment_orders SET status=?,note=?,updated_at=? WHERE id=?',(wanted,data.note,now,key));official(db,'payment-'+wanted+':'+key,target,'Payment '+wanted,f"{p['title']}: {wanted}. {data.note}"+(' Coin reversal recorded; the cash refund must be completed separately by the payment provider.' if wanted=='refunded' else ''))
            self.control.audit(db,uid,'payment.'+wanted,target,{'order':key,'coins':p['coins'],'note':data.note});return {'saved':True}

class AgencyTerms(BaseModel):
    model_config=ConfigDict(extra='forbid')
    id:uuid.UUID
    agency:uuid.UUID
    month:str=Field(pattern=r'^20\d\d-(0[1-9]|1[0-2])$')
    target:int=Field(strict=True,ge=1,le=1000000000000)
    salary:int=Field(strict=True,ge=0,le=1000000000)
    rate:int=Field(strict=True,ge=0,le=1000000000)

def month_bounds(value):
    start=datetime.strptime(value,'%Y-%m').replace(tzinfo=timezone.utc)
    end=start.replace(year=start.year+1,month=1) if start.month==12 else start.replace(month=start.month+1)
    return int(start.timestamp()),int(end.timestamp())

class AgencyFinance(Programs):
    def save_terms(self,uid,data):
        with self.control.db() as db:
            self.owner(db,uid);start,_=month_bounds(data.month)
            if start<=time.time():raise HTTPException(400,'Publish agency terms before the month starts')
            agency=db.execute('SELECT manager FROM account_agencies WHERE id=? AND active=1',(str(data.agency),)).fetchone()
            if not agency:raise HTTPException(404,'Active agency required')
            old=db.execute('SELECT * FROM account_agency_terms WHERE agency=? AND month=?',(str(data.agency),data.month)).fetchone()
            if old:
                if (old['target'],old['salary'],old['rate'])!=(data.target,data.salary,data.rate):raise HTTPException(409,'Published terms are immutable')
                return {'saved':True}
            db.execute('INSERT INTO account_agency_terms VALUES(?,?,?,?,?,?,?,NULL)',(str(data.id),str(data.agency),agency[0],data.month,data.target,data.salary,data.rate))
            self.control.audit(db,uid,'agency.terms',str(data.agency),data.model_dump(mode='json'));return {'saved':True}
    def income(self,uid,admin=False,key=""):
        with self.control.db() as db:
            if admin:self.owner(db,uid)
            items=[]
            for r in db.execute('SELECT t.*,a.name FROM account_agency_terms t JOIN account_agencies a ON a.id=t.agency WHERE (?=1 OR t.manager=?) AND (length(?)=0 OR t.id=?) ORDER BY month DESC LIMIT 100',(int(admin),uid,key,key)):
                start,end=month_bounds(r['month']);hosts=[dict(x) for x in db.execute('''SELECT l.firebase_uid AS uid,p.display_name AS name,SUM(l.diamond_delta) AS diamonds
                 FROM account_wallet_ledger l JOIN account_profiles p ON p.firebase_uid=l.firebase_uid WHERE l.kind='gift' AND l.diamond_delta>0 AND l.created_at>=? AND l.created_at<? AND EXISTS(SELECT 1 FROM account_agency_timeline m WHERE m.uid=l.firebase_uid AND m.agency=? AND m.joined_at<=l.created_at AND (m.left_at IS NULL OR m.left_at>l.created_at)) GROUP BY l.firebase_uid ORDER BY diamonds DESC''',(start,end,r['agency']))]
                for h in hosts:h['salary']=r['salary'] if h['diamonds']>=r['target'] else 0
                items.append(dict(r)|{'hosts':hosts,'commission':sum(h['diamonds'] for h in hosts)*r['rate']//10000,'closed':time.time()>=end})
            return {'items':items,'unit':'Coins. Rate is Coins per 10,000 qualifying gift Diamonds; not a cash salary or provider payout.'}
    def pay(self,uid,key):
        # Recalculate under the same write lock used for once-only settlement.
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.owner(db,uid);r=db.execute('SELECT * FROM account_agency_terms WHERE id=?',(key,)).fetchone()
            if not r:raise HTTPException(404)
            if r['paid_at']:return {'saved':True,'duplicate':True}
            report=next(x for x in self.income(uid,True,key)['items'] if x['id']==key)
            if not report['closed']:raise HTTPException(409,'Month has not ended')
            awards={r['manager']:report['commission']}
            for h in report['hosts']:awards[h['uid']]=awards.get(h['uid'],0)+h['salary']
            for target,amount in awards.items():
                if amount:
                    credit(db,target,amount,'agency:'+key+':'+target)
                    official(db,'agency:'+key+':'+target,target,'Agency Coins received',f"{r['month']} agency settlement: {amount:,} Coins.")
            db.execute('UPDATE account_agency_terms SET paid_at=? WHERE id=?',(int(time.time()),key));self.control.audit(db,uid,'agency.settle',r['agency'],{'terms':key,'awards':awards});return {'saved':True}

def attach_programs(app,profiles,actor,staff):
    service=Programs(profiles.path);agency=AgencyFinance(profiles.path)
    @app.get('/sovera/account/programs')
    async def catalog(request:Request):return await asyncio.to_thread(service.catalog,await actor(request.headers.get('authorization')))
    @app.post('/sovera/account/programs/buy')
    async def buy(data:Buy,request:Request):return await asyncio.to_thread(service.buy,await actor(request.headers.get('authorization')),data)
    @app.post('/sovera/account/programs/referral')
    async def refer(data:ReferralCode,request:Request):return await asyncio.to_thread(service.refer,await actor(request.headers.get('authorization')),data.public_id)
    @app.post('/sovera/account/programs/referral/{target}/claim')
    async def referral_claim(target:str,request:Request):return await asyncio.to_thread(service.referral_claim,await actor(request.headers.get('authorization')),target)
    @app.get('/sovera/account/programs/payments')
    async def payments(request:Request):return {'items':await asyncio.to_thread(service.payments,await actor(request.headers.get('authorization')))}
    @app.post('/sovera/account/programs/payments')
    async def payment(data:PaymentOrder,request:Request):return await asyncio.to_thread(service.payment,await actor(request.headers.get('authorization')),data)
    @app.get('/sovera/account/programs/agency-income')
    async def income(request:Request):return await asyncio.to_thread(agency.income,await actor(request.headers.get('authorization')))
    @app.get('/sovera/control/programs')
    async def settings(request:Request):return await asyncio.to_thread(service.catalog,await staff(request),True)
    @app.post('/sovera/control/programs/packs')
    async def pack(data:Pack,request:Request):return await asyncio.to_thread(service.save_pack,await staff(request),data)
    @app.post('/sovera/control/programs/referral')
    async def policy(data:ReferralPolicy,request:Request):return await asyncio.to_thread(service.policy,await staff(request),data)
    @app.get('/sovera/control/payments')
    async def orders(request:Request):return {'items':await asyncio.to_thread(service.payments,await staff(request),True)}
    @app.put('/sovera/control/payments/{key}')
    async def decide(key:uuid.UUID,data:PaymentDecision,request:Request):return await asyncio.to_thread(service.decide,await staff(request),str(key),data)
    @app.get('/sovera/control/programs/agency-income')
    async def agency_reports(request:Request):return await asyncio.to_thread(agency.income,await staff(request),True)
    @app.post('/sovera/control/programs/agency-terms')
    async def terms(data:AgencyTerms,request:Request):return await asyncio.to_thread(agency.save_terms,await staff(request),data)
    @app.post('/sovera/control/programs/agency-terms/{key}/settle')
    async def settle(key:uuid.UUID,request:Request):return await asyncio.to_thread(agency.pay,await staff(request),str(key))

    @app.post('/sovera/account/programs/cancel/{key}')
    async def cancel(key:uuid.UUID,request:Request):return await asyncio.to_thread(service.cancel_request,await actor(request.headers.get('authorization')),str(key))
