"""Server-scored campaigns and exactly-once reward claims on the real ledger."""
import asyncio
import json
import time
import uuid
from datetime import datetime, timezone, timedelta
from typing import Literal
from fastapi import HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from .control import Control, LIMIT

class Prize(BaseModel):
    model_config=ConfigDict(extra='forbid')
    rank:int=Field(strict=True,ge=1,le=10)
    coins:int=Field(strict=True,ge=0,le=1000000000)
    item_ids:list[uuid.UUID]=Field(default_factory=list,max_length=3)
    days:int=Field(strict=True,ge=1,le=365,default=7)
    @model_validator(mode='after')
    def valuable(self):
        if not self.coins and not self.item_ids:raise ValueError('Choose Coins or a collection item')
        return self

class CampaignInput(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    id:uuid.UUID
    title:str=Field(min_length=3,max_length=100)
    category:Literal['ranking','event','recharge']
    metric:Literal['rich','charm','recharge','play']
    starts_at:int=Field(strict=True,gt=0)
    ends_at:int=Field(strict=True,gt=0)
    threshold:int=Field(strict=True,ge=1,le=1000000000000,default=1)
    prizes:list[Prize]=Field(min_length=1,max_length=10)
    repeat:Literal['none','daily','weekly','monthly']='none'
    auto_claim:bool=False
    @model_validator(mode='after')
    def valid(self):
        if self.ends_at<=self.starts_at or self.ends_at-self.starts_at>366*86400:raise ValueError('Invalid campaign dates')
        if self.repeat in ('daily','weekly') and self.ends_at-self.starts_at!={'daily':86400,'weekly':604800}[self.repeat]:raise ValueError('Daily/weekly repeats require an exact one-day/seven-day UTC window')
        if self.repeat=='monthly' and next_month(self.starts_at)!=self.ends_at:raise ValueError('Monthly repeats require a calendar-month UTC window')
        ranks=[p.rank for p in self.prizes]
        if len(set(ranks))!=len(ranks):raise ValueError('Duplicate prize rank')
        if self.category=='recharge' and (self.metric!='recharge' or ranks!=[1]):raise ValueError('Recharge rewards need one threshold prize')
        return self

def next_month(seconds):
    import calendar
    d=datetime.fromtimestamp(seconds,timezone.utc);y=d.year+(d.month==12);m=1 if d.month==12 else d.month+1
    return int(d.replace(year=y,month=m,day=min(d.day,calendar.monthrange(y,m)[1])).timestamp())

def schema(db):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS account_reward_campaigns(id TEXT PRIMARY KEY,payload TEXT NOT NULL,status TEXT NOT NULL,actor TEXT NOT NULL,created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS account_reward_winners(campaign TEXT NOT NULL,uid TEXT NOT NULL,rank INTEGER NOT NULL,score INTEGER NOT NULL,claimed_at INTEGER,PRIMARY KEY(campaign,uid));
    CREATE TABLE IF NOT EXISTS account_reward_asset_expiry(uid TEXT NOT NULL,item_id TEXT NOT NULL,expires_at INTEGER NOT NULL,PRIMARY KEY(uid,item_id));
    ''')

def score_rows(db,metric,start,end):
    # Never count imported balances, owner adjustments, refunds or reward credits.
    if metric=='recharge':
        refunded=" AND NOT EXISTS(SELECT 1 FROM account_payment_orders o WHERE o.id=r.request_id AND o.status='refunded') " if db.execute("SELECT 1 FROM sqlite_master WHERE name='account_payment_orders'").fetchone() else ''
        return list(db.execute('''SELECT r.target AS uid,SUM(r.amount) AS score FROM account_control_recharges r
         WHERE r.created_at>=? AND r.created_at<? '''+refunded+' GROUP BY r.target ORDER BY score DESC,uid',(start,end)))
    expression={'rich':'-coin_delta','charm':'diamond_delta','play':'coin_delta'}[metric]
    kind='game_win' if metric=='play' else 'gift'
    positive='coin_delta<0' if metric=='rich' else 'diamond_delta>0' if metric=='charm' else 'coin_delta>0'
    return list(db.execute(f'''SELECT firebase_uid AS uid,SUM({expression}) AS score FROM account_wallet_ledger
     WHERE kind=? AND {positive} AND created_at>=? AND created_at<? GROUP BY firebase_uid ORDER BY score DESC,uid''',(kind,start,end)))

def visible(db,uid):
    return db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone() and not db.execute('SELECT 1 FROM account_bans WHERE uid=?',(uid,)).fetchone()

class Rewards:
    def __init__(self,path):
        self.control=Control(path)
        with self.control.db() as db:schema(db)
    def save(self,actor,data):
        payload=data.model_dump_json()
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.control.role(db,actor)!='owner':raise HTTPException(403,'Only owner can create funded reward campaigns')
            old=db.execute('SELECT payload FROM account_reward_campaigns WHERE id=?',(str(data.id),)).fetchone()
            if old:
                if old[0]!=payload:raise HTTPException(409,'Published reward rules are immutable. Create a new campaign')
                return {'saved':True}
            now=int(time.time())
            if data.starts_at<now-60:raise HTTPException(400,'New campaigns cannot reward historical activity')
            if db.execute("SELECT COUNT(*) FROM account_reward_campaigns WHERE status='active'").fetchone()[0]>=100:raise HTTPException(409,'Finish existing campaigns first')
            for prize in data.prizes:
                for key in prize.item_ids:
                    item=db.execute("SELECT kind FROM account_catalog WHERE id=? AND active=1",(str(key),)).fetchone()
                    if not item or item[0] not in ('frame','entry','medal','tag','room_frame'):raise HTTPException(400,'Choose active wearable catalog items')
            db.execute('INSERT INTO account_reward_campaigns VALUES(?,?,?,?,?)',(str(data.id),payload,'active',actor,now))
            self.control.audit(db,actor,'rewards.publish',str(data.id),data.model_dump(mode='json'))
            return {'saved':True}
    def cancel(self,actor,key):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.control.role(db,actor)!='owner':raise HTTPException(403,'Only owner can cancel scheduled rewards')
            row=db.execute('SELECT * FROM account_reward_campaigns WHERE id=?',(key,)).fetchone()
            if not row:raise HTTPException(404)
            if int(time.time())>=json.loads(row['payload'])['starts_at']:raise HTTPException(409,'Campaign already started; promised rewards cannot be cancelled')
            db.execute("UPDATE account_reward_campaigns SET status='cancelled' WHERE id=?",(key,))
            self.control.audit(db,actor,'rewards.cancel',key,{})
            return {'saved':True}
    def finalize(self,db,now):
        for row in db.execute("SELECT * FROM account_reward_campaigns WHERE status='active'").fetchall():
            p=json.loads(row['payload'])
            if p['ends_at']>now:continue
            if p['category']!='recharge':
                ranks={x['rank'] for x in p['prizes']}
                entries=[r for r in score_rows(db,p['metric'],p['starts_at'],p['ends_at']) if visible(db,r['uid'])]
                for rank,r in enumerate(entries[:10],1):
                    if rank in ranks and r['score']>=p['threshold']:db.execute('INSERT OR IGNORE INTO account_reward_winners VALUES(?,?,?,?,NULL)',(row['id'],r['uid'],rank,r['score']))
            db.execute("UPDATE account_reward_campaigns SET status='settled' WHERE id=?",(row['id'],))
            if p.get('repeat','none')!='none':
                following=dict(p);following['id']=str(uuid.uuid5(uuid.UUID(row['id']),str(p['ends_at'])));following['starts_at']=p['ends_at'];following['ends_at']=next_month(p['ends_at']) if p['repeat']=='monthly' else p['ends_at']+(86400 if p['repeat']=='daily' else 604800)
                db.execute("INSERT OR IGNORE INTO account_reward_campaigns VALUES(?,?,'active',?,?)",(following['id'],json.dumps(following),row['actor'],now))
    def person(self,db,uid):
        from .wallet import legacy_identity
        p=db.execute('SELECT display_name AS name,avatar_url,country FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone()
        from .catalog import equipped_assets
        return dict(p)|legacy_identity(db,uid)|{'uid':uid,'equipped':equipped_assets(db,uid)} if p else {'uid':uid,'name':'Member'}
    def listing(self,uid,admin=False):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');now=int(time.time());self.finalize(db,now)
            if admin and self.control.role(db,uid)!='owner':raise HTTPException(403,'Owner required')
            items=[]
            for r in db.execute('SELECT * FROM account_reward_campaigns ORDER BY created_at DESC,id DESC LIMIT 100'):
                p=json.loads(r['payload']);mine=db.execute('SELECT * FROM account_reward_winners WHERE campaign=? AND uid=?',(r['id'],uid)).fetchone()
                score=next((x['score'] for x in score_rows(db,p['metric'],p['starts_at'],min(now+1,p['ends_at'])) if x['uid']==uid),0) if p['category']=='recharge' else (mine['score'] if mine else 0)
                winners=[dict(w)|self.person(db,w['uid']) for w in db.execute('SELECT uid,rank,score,claimed_at FROM account_reward_winners WHERE campaign=? ORDER BY rank,uid LIMIT 10',(r['id'],))]
                prizes=[]
                for prize in p['prizes']:
                    art=[]
                    for key in prize['item_ids']:
                        c=db.execute('SELECT id,title,kind,media_id FROM account_catalog WHERE id=?',(key,)).fetchone()
                        if c:art.append(dict(c)|{'url':'https://voice.soverixnet.com/sovera/account/media/'+c['media_id']})
                    prizes.append(prize|{'items':art})
                items.append(p|{'prizes':prizes,'status':r['status'],'score':str(score),'claimed':bool(mine and mine['claimed_at']),'eligible':bool((mine and not mine['claimed_at']) or (p['category']=='recharge' and r['status']!='cancelled' and now>=p['starts_at'] and score>=p['threshold'] and not (mine and mine['claimed_at']))),'winners':winners})
            return {'items':items,'server_now':now}
    def claim(self,uid,key):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');now=int(time.time());self.finalize(db,now)
            row=db.execute('SELECT * FROM account_reward_campaigns WHERE id=?',(key,)).fetchone()
            if not row or row['status']=='cancelled':raise HTTPException(404,'Reward unavailable')
            p=json.loads(row['payload'])
            winner=db.execute('SELECT * FROM account_reward_winners WHERE campaign=? AND uid=?',(key,uid)).fetchone()
            if winner and winner['claimed_at']:return {'saved':True,'duplicate':True}
            if p['category']=='recharge' and now>=p['starts_at']:
                score=next((r['score'] for r in score_rows(db,'recharge',p['starts_at'],min(now+1,p['ends_at'])) if r['uid']==uid),0)
                if score<p['threshold']:raise HTTPException(409,'Recharge target not reached')
                db.execute('INSERT OR IGNORE INTO account_reward_winners VALUES(?,?,?,?,NULL)',(key,uid,1,score))
                winner=db.execute('SELECT * FROM account_reward_winners WHERE campaign=? AND uid=?',(key,uid)).fetchone()
            if not winner:raise HTTPException(409,'Final ranking reward not available yet')
            link=db.execute('SELECT status FROM account_wallet_links WHERE firebase_uid=?',(uid,)).fetchone()
            if not link or link['status']!='active' or not visible(db,uid):raise HTTPException(409,'An active account wallet is required')
            prize=next(x for x in p['prizes'] if x['rank']==winner['rank'])
            balance=db.execute('SELECT COALESCE(SUM(coin_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(uid,)).fetchone()[0]
            if balance+prize['coins']>LIMIT:raise HTTPException(409,'Wallet arithmetic limit reached')
            if prize['coins']:db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',('reward:'+key+':'+uid,uid,prize['coins'],0,'admin_adjust',now))
            for item in prize['item_ids']:
                own=db.execute('SELECT 1 FROM account_asset_ownership WHERE uid=? AND item_id=?',(uid,item)).fetchone()
                exp=db.execute('SELECT expires_at FROM account_reward_asset_expiry WHERE uid=? AND item_id=?',(uid,item)).fetchone()
                if not own or exp:
                    until=max(now,exp[0] if exp else now)+prize['days']*86400
                    db.execute('INSERT OR IGNORE INTO account_asset_ownership VALUES(?,?,?)',(uid,item,now))
                    db.execute('INSERT INTO account_reward_asset_expiry VALUES(?,?,?) ON CONFLICT(uid,item_id) DO UPDATE SET expires_at=excluded.expires_at',(uid,item,until))
            db.execute('UPDATE account_reward_winners SET claimed_at=? WHERE campaign=? AND uid=?',(now,key,uid))
            from .messaging import official
            official(db,'reward:'+key+':'+uid,uid,'Reward received',f"{p['title']}: {prize['coins']:,} Coins and {len(prize['item_ids'])} collection rewards ({prize['days']} days). Open Mall to equip your rewards.")
            self.control.audit(db,'system','rewards.claim',uid,{'campaign':key,'coins':prize['coins'],'rank':winner['rank']})
            return {'saved':True,'coins':str(prize['coins'])}
    def stop_repeat(self,uid,key):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if self.control.role(db,uid)!='owner':raise HTTPException(403,'Owner required')
            r=db.execute("SELECT payload FROM account_reward_campaigns WHERE id=? AND status='active'",(key,)).fetchone()
            if not r:raise HTTPException(409,'Only an active campaign can stop its next repeat')
            p=json.loads(r[0]);p['repeat']='none';db.execute('UPDATE account_reward_campaigns SET payload=? WHERE id=?',(json.dumps(p),key))
            self.control.audit(db,uid,'rewards.stop_repeat',key,{});return {'saved':True}
    def tick(self):
        with self.control.db() as db:
            db.execute('BEGIN IMMEDIATE');self.finalize(db,int(time.time()))
            campaigns=[dict(r) for r in db.execute("SELECT * FROM account_reward_campaigns WHERE status<>'cancelled' ORDER BY created_at DESC LIMIT 1000")]
        count=0
        for row in campaigns:
            p=json.loads(row['payload'])
            if not p.get('auto_claim'):continue
            with self.control.db() as db:
                if p['category']=='recharge':uids=[r['uid'] for r in score_rows(db,'recharge',p['starts_at'],min(int(time.time())+1,p['ends_at'])) if r['score']>=p['threshold']]
                else:uids=[r[0] for r in db.execute('SELECT uid FROM account_reward_winners WHERE campaign=? AND claimed_at IS NULL',(row['id'],))]
                eligible=[u for u in uids if db.execute("SELECT 1 FROM account_wallet_links WHERE firebase_uid=? AND status='active'",(u,)).fetchone() and visible(db,u)]
            for uid in eligible[:200]:
                if count>=500:return count
                try:
                    result=self.claim(uid,row['id']);count+=not result.get('duplicate',False)
                except HTTPException:continue
        return count

    def board(self,uid,metric,period):
        now=datetime.now(timezone.utc);start=now.replace(hour=0,minute=0,second=0,microsecond=0)
        if period=='weekly':start-=timedelta(days=start.weekday())
        if period=='monthly':start=start.replace(day=1)
        if period=='monthly':end=(start.replace(day=28)+timedelta(days=4)).replace(day=1)
        else:end=start+timedelta(days=7 if period=='weekly' else 1)
        with self.control.db() as db:
            if metric in ('room','cp'):
                bounds=(int(start.timestamp()),int(end.timestamp()))
                valid=""" FROM account_gift_receipts g
                    LEFT JOIN account_bans bs ON bs.uid=g.sender
                    LEFT JOIN account_bans br ON br.uid=g.recipient
                    WHERE g.created_at>=? AND g.created_at<? AND bs.uid IS NULL AND br.uid IS NULL """
                items=[]
                if metric=='room':
                    scores=db.execute('SELECT g.room,SUM(g.price) AS score'+valid+' GROUP BY g.room ORDER BY score DESC,g.room',bounds).fetchall()
                    for score in scores:
                        r=db.execute('SELECT * FROM account_rooms WHERE id=?',(score['room'],)).fetchone()
                        if r and visible(db,r['owner_uid']):
                            items.append(self.person(db,r['owner_uid'])|{'name':r['name'],'avatar_url':r['image_url'],'room':dict(r),'equipped':{},'public_id':r['id'],'score':str(score['score'])})
                else:
                    scores=db.execute('SELECT MIN(g.sender,g.recipient) AS first,MAX(g.sender,g.recipient) AS second,SUM(g.price) AS score'+valid+' AND g.sender<>g.recipient GROUP BY first,second ORDER BY score DESC,first,second',bounds).fetchall()
                    for score in scores:
                        if visible(db,score['first']) and visible(db,score['second']):
                            a=self.person(db,score['first']);b=self.person(db,score['second'])
                            items.append(a|{'name':a['name']+' & '+b['name'],'public_id':str(a.get('public_id','—'))+' / '+str(b.get('public_id','—')),'partner':b,'score':str(score['score'])})
                for rank,item in enumerate(items,1):item['rank']=rank
                mine=next(({'rank':r['rank'],'score':r['score']} for r in items if r['uid']==uid or r.get('partner',{}).get('uid')==uid),None)
                return {'items':items[:100],'mine':mine,'ends_at':int(end.timestamp()),'server_now':int(now.timestamp()),'timezone':'UTC'}
            rows=[r for r in score_rows(db,metric,int(start.timestamp()),int(end.timestamp())) if visible(db,r['uid'])]
            mine=next(({'rank':i,'score':str(r['score'])} for i,r in enumerate(rows,1) if r['uid']==uid),None)
            return {'items':[self.person(db,r['uid'])|{'rank':i,'score':str(r['score'])} for i,r in enumerate(rows[:100],1)],'mine':mine,'ends_at':int(end.timestamp()),'server_now':int(now.timestamp()),'timezone':'UTC'}

def attach_rewards(app,profiles,actor,staff):
    service=Rewards(profiles.path)
    @app.get('/sovera/account/rewards')
    async def listing(request:Request):return await asyncio.to_thread(service.listing,await actor(request.headers.get('authorization')))
    @app.get('/sovera/account/rankings')
    async def rankings(request:Request,metric:Literal['rich','charm','recharge','play','room','cp']='rich',period:Literal['daily','weekly','monthly']='weekly'):return await asyncio.to_thread(service.board,await actor(request.headers.get('authorization')),metric,period)
    @app.post('/sovera/account/rewards/{key}/claim')
    async def claim(key:uuid.UUID,request:Request):return await asyncio.to_thread(service.claim,await actor(request.headers.get('authorization')),str(key))
    @app.get('/sovera/control/rewards')
    async def management(request:Request):return await asyncio.to_thread(service.listing,await staff(request),True)
    @app.post('/sovera/control/rewards')
    async def create(data:CampaignInput,request:Request):return await asyncio.to_thread(service.save,await staff(request),data)
    @app.delete('/sovera/control/rewards/{key}')
    async def cancel(key:uuid.UUID,request:Request):return await asyncio.to_thread(service.cancel,await staff(request),str(key))

    @app.post('/sovera/control/rewards/{key}/stop-repeat')
    async def stop(key:uuid.UUID,request:Request):return await asyncio.to_thread(service.stop_repeat,await staff(request),str(key))
