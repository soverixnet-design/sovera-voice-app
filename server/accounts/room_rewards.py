"""Weekly room gift rewards, immutable rules and exactly-once wallet payouts."""
import asyncio
import json
import time
from fastapi import HTTPException, Header, Request
from pydantic import BaseModel, ConfigDict, Field
from .control import Control, LIMIT
from .messaging import official

WEEK=604800
MONDAY=345600  # 1970-01-05 00:00 UTC

def week_start(now):return (int(now)-MONDAY)//WEEK*WEEK+MONDAY

class Policy(BaseModel):
    model_config=ConfigDict(extra='forbid')
    enabled:bool=True
    percent:int=Field(default=10,strict=True,ge=0,le=100)

class RoomRewards:
    def __init__(self,path):
        self.control=Control(path)
        with self.control.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS account_room_reward_policy(effective_at INTEGER PRIMARY KEY,payload TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS account_room_reward_weeks(room TEXT NOT NULL,starts_at INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(room,starts_at));
            CREATE TABLE IF NOT EXISTS account_room_reward_payouts(room TEXT NOT NULL,starts_at INTEGER NOT NULL,uid TEXT NOT NULL,coins INTEGER NOT NULL,paid_at INTEGER,PRIMARY KEY(room,starts_at,uid));
            CREATE INDEX IF NOT EXISTS account_room_gift_week ON account_gift_receipts(created_at,room,sender);
            ''')
            db.execute('INSERT OR IGNORE INTO account_room_reward_policy VALUES(?,?)',(int(time.time()),Policy().model_dump_json())) if not db.execute('SELECT 1 FROM account_room_reward_policy LIMIT 1').fetchone() else None
    def policy_at(self,db,now):
        row=db.execute('SELECT * FROM account_room_reward_policy WHERE effective_at<=? ORDER BY effective_at DESC LIMIT 1',(now,)).fetchone()
        return ({**json.loads(row['payload']),'effective_at':row['effective_at']} if row else {'enabled':False,'percent':0,'effective_at':0})
    def policies(self,uid):
        with self.control.db() as db:
            if self.control.role(db,uid)!='owner':raise HTTPException(403,'Owner required')
            now=int(time.time())
            return {'current':self.policy_at(db,now),'scheduled':[dict(r)|{'rules':json.loads(r['payload'])} for r in db.execute('SELECT * FROM account_room_reward_policy WHERE effective_at>? ORDER BY effective_at',(now,))],'next_week':week_start(now)+WEEK}
    def save(self,uid,data):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.control.role(db,uid)!='owner':raise HTTPException(403,'Owner required')
            effective=week_start(time.time())+WEEK
            db.execute('INSERT INTO account_room_reward_policy VALUES(?,?) ON CONFLICT(effective_at) DO UPDATE SET payload=excluded.payload',(effective,data.model_dump_json()))
            self.control.audit(db,uid,'room_rewards.policy','global',{'effective_at':effective,**data.model_dump()})
            return {'saved':True,'effective_at':effective}
    def summary(self,db,room,start):
        end=start+WEEK
        policy=self.policy_at(db,start)
        if not policy['effective_at']:
            first=db.execute('SELECT effective_at FROM account_room_reward_policy ORDER BY effective_at LIMIT 1').fetchone()[0]
            if first<end:policy=self.policy_at(db,first)
        owner=db.execute('SELECT owner_uid FROM account_rooms WHERE id=?',(room,)).fetchone()
        if not owner:raise HTTPException(404,'Room not found')
        rows=[dict(r) for r in db.execute('''SELECT g.sender AS uid,SUM(g.price) AS score FROM account_gift_receipts g
          JOIN account_wallet_ledger l ON l.reference='catalog:'||g.request_id AND l.firebase_uid=g.sender AND l.kind='gift' AND l.coin_delta<0
          WHERE g.room=? AND g.created_at>=? AND g.created_at<? GROUP BY g.sender ORDER BY score DESC,g.sender''',(room,max(start,policy['effective_at']),end))]
        total=sum(r['score'] for r in rows)
        pool=total*policy['percent']//100 if policy['enabled'] else 0
        owner_coins=pool//2;shared=pool-owner_coins
        top=[r for r in rows if r['uid']!=owner[0]][:5]
        allocations=[{'uid':owner[0],'coins':owner_coins,'role':'owner'}] if owner_coins else []
        for index,r in enumerate(top):
            coins=shared//5+(1 if index<shared%5 else 0)
            if coins:allocations.append({'uid':r['uid'],'coins':coins,'role':'top_gifter','rank':index+1})
        return {'starts_at':start,'ends_at':end,'percent':policy['percent'],'enabled':policy['enabled'],'gift_coins':str(total),'reward_coins':str(pool),'unallocated_coins':str(pool-sum(a['coins'] for a in allocations)),'allocations':allocations,'contributors':rows}
    def person(self,db,uid):
        row=db.execute('''SELECT p.display_name AS name,p.avatar_url,p.country,COALESCE(i.public_id,n.public_id) AS public_id FROM account_profiles p LEFT JOIN account_wallet_imports i ON i.firebase_uid=p.firebase_uid LEFT JOIN account_public_ids n ON n.uid=p.firebase_uid WHERE p.firebase_uid=?''',(uid,)).fetchone()
        return {'uid':uid,**(dict(row) if row else {'name':'Unavailable member','public_id':'—'})}
    def detail(self,uid,room):
        with self.control.db() as db:
            if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone():raise HTTPException(403)
            current=self.summary(db,room,week_start(time.time()))
            current['contributors']=[{**r,**self.person(db,r['uid']),'score':str(r['score'])} for r in current['contributors'][:100]]
            current['allocations']=[{**a,**self.person(db,a['uid']),'coins':str(a['coins'])} for a in current['allocations']]
            history=[]
            for r in db.execute('SELECT * FROM account_room_reward_weeks WHERE room=? ORDER BY starts_at DESC LIMIT 12',(room,)):
                p=json.loads(r['payload']);p['payouts']=[{**dict(a),**self.person(db,a['uid']),'coins':str(a['coins'])} for a in db.execute('SELECT uid,coins,paid_at FROM account_room_reward_payouts WHERE room=? AND starts_at=?',(room,r['starts_at']))];history.append(p)
            return {'current':current,'history':history,'server_now':int(time.time()),'rule':'Monday 00:00 UTC weekly reset. Owner gets half. Remaining half is five equal slots for the top five other gift senders. Empty slots are not issued. Rules change next week.'}
    def tick(self):
        now=int(time.time());paid=0
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            first=db.execute('SELECT MIN(effective_at) FROM account_room_reward_policy').fetchone()[0]
            candidates=list(db.execute('SELECT DISTINCT room,CAST((created_at-?)/? AS INTEGER)*?+? AS starts_at FROM account_gift_receipts WHERE created_at>=? AND created_at<?',(MONDAY,WEEK,WEEK,MONDAY,first,week_start(now))))
            for row in candidates:
                if db.execute('SELECT 1 FROM account_room_reward_weeks WHERE room=? AND starts_at=?',(row['room'],row['starts_at'])).fetchone():continue
                summary=self.summary(db,row['room'],row['starts_at'])
                db.execute('INSERT INTO account_room_reward_weeks VALUES(?,?,?)',(row['room'],row['starts_at'],json.dumps(summary)))
                for a in summary['allocations']:db.execute('INSERT INTO account_room_reward_payouts VALUES(?,?,?,?,NULL)',(row['room'],row['starts_at'],a['uid'],a['coins']))
            for row in db.execute('SELECT * FROM account_room_reward_payouts WHERE paid_at IS NULL').fetchall():
                uid=row['uid'];coins=row['coins']
                link=db.execute('SELECT status FROM account_wallet_links WHERE firebase_uid=?',(uid,)).fetchone()
                if not link or link[0]!='active' or db.execute('SELECT 1 FROM account_bans WHERE uid=?',(uid,)).fetchone():continue
                balance=db.execute('SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(uid,)).fetchone()[0]
                if balance+coins>LIMIT:continue
                ref=f"room-reward:{row['room']}:{row['starts_at']}:{uid}"
                db.execute("INSERT OR IGNORE INTO account_wallet_ledger VALUES(?,?,?,0,'admin_adjust',?)",(ref,uid,coins,now))
                official(db,ref,uid,'Weekly room reward',f"Your weekly room reward: {coins:,} Coins. Room {row['room']}. The Coins have been added to your wallet.")
                db.execute('UPDATE account_room_reward_payouts SET paid_at=? WHERE room=? AND starts_at=? AND uid=?',(now,row['room'],row['starts_at'],uid))
                self.control.audit(db,'system','room_rewards.pay',uid,{'room':row['room'],'week':row['starts_at'],'coins':coins});paid+=1
        return paid

def attach_room_rewards(app,profiles,actor,staff):
    service=RoomRewards(profiles.path)
    @app.get('/sovera/account/rooms/{room}/rewards')
    async def detail(room:str,authorization:str|None=Header(default=None)):return await asyncio.to_thread(service.detail,await actor(authorization),room)
    @app.get('/sovera/control/room-rewards')
    async def policy(request:Request):return await asyncio.to_thread(service.policies,await staff(request))
    @app.put('/sovera/control/room-rewards')
    async def save(data:Policy,request:Request):return await asyncio.to_thread(service.save,await staff(request),data)
    @app.get('/sovera/control/room-rewards/{room}')
    async def inspect(room:str,request:Request):
        uid=await staff(request);await asyncio.to_thread(service.policies,uid)
        return await asyncio.to_thread(service.detail,uid,room)
