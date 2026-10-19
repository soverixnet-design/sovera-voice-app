"""Server-authoritative shared Food Wheel preview using the user's original 8 foods.

This is intentionally FREE/non-monetary until the production wallet and gift
ledgers can settle atomically. Never accept credits, money or diamond values.
The original Food HTML is rendered by the app and may only submit a food pick.
"""
import secrets
import time
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict
from typing import Literal
from .rooms import Rooms

FOODS=('chicken','fish','hotdog','steak','grapes','lettuce','pepper','melon')
SLOTS=FOODS+('salad','pizza')
WEIGHTS=(20,36,60,90,180,180,180,180,37,37) # exact 1000
PICK_SECONDS,SPIN_SECONDS,RESULT_SECONDS=20,5,5
ROUND_SECONDS=PICK_SECONDS+SPIN_SECONDS+RESULT_SECONDS
VEGETABLES=('grapes','lettuce','pepper','melon')
MEATS=('chicken','fish','hotdog','steak')

class FoodChoice(BaseModel):
    model_config=ConfigDict(extra='forbid')
    round:int
    item:Literal['chicken','fish','hotdog','steak','grapes','lettuce','pepper','melon']

class FoodWheel:
    def __init__(self,path,clock=time.time,draw=None,visual=None):
        self.rooms=Rooms(path,clock=clock)
        self.clock=clock
        self.draw=draw or (lambda:secrets.randbelow(sum(WEIGHTS)))
        self.visual=visual or secrets.choice
        with self.rooms.db() as db:
            db.executescript("""CREATE TABLE IF NOT EXISTS account_food_wheel_rounds(
                id INTEGER PRIMARY KEY,started_at REAL NOT NULL,
                result TEXT,visual_index INTEGER,settled_at REAL,
                CHECK(result IS NULL OR result IN ('chicken','fish','hotdog',
                'steak','grapes','lettuce','pepper','melon','salad','pizza')));
                CREATE TABLE IF NOT EXISTS account_food_wheel_picks(
                round_id INTEGER NOT NULL,user_id TEXT NOT NULL,item TEXT NOT NULL,
                picked_at REAL NOT NULL, PRIMARY KEY(round_id,user_id),
                CHECK(item IN ('chicken','fish','hotdog','steak',
                'grapes','lettuce','pepper','melon')));
                CREATE INDEX IF NOT EXISTS account_food_wheel_result_index
                ON account_food_wheel_picks(round_id,item);
            """)

    @staticmethod
    def qualifies(pick,result):
        return pick==result or (result=='salad' and pick in VEGETABLES) or (
            result=='pizza' and pick in MEATS)

    def _pick_result(self):
        number=self.draw()
        if type(number) is not int or not 0<=number<sum(WEIGHTS):
            raise ValueError('Invalid authoritative random draw')
        for item,weight in zip(SLOTS,WEIGHTS):
            if number<weight:return item
            number-=weight
        raise AssertionError('Weights must cover the draw')

    def _advance(self,db,now):
        row=db.execute('SELECT * FROM account_food_wheel_rounds ORDER BY id DESC LIMIT 1').fetchone()
        if row is None:
            db.execute('INSERT INTO account_food_wheel_rounds(id,started_at) VALUES(1,?)',(now,))
        else:
            if row['result'] is None and now>=row['started_at']+PICK_SECONDS:
                result=self._pick_result()
                allowed=VEGETABLES if result=='salad' else MEATS if result=='pizza' else (result,)
                visual=self.visual(allowed)
                if visual not in allowed:raise ValueError('Invalid wheel visual')
                db.execute("""UPDATE account_food_wheel_rounds SET result=?,visual_index=?,settled_at=?
                    WHERE id=? AND result IS NULL""",(result,FOODS.index(visual),now,row['id']))
            if now>=row['started_at']+ROUND_SECONDS:
                # After outages, resume with ONE new round; do not fabricate past results.
                db.execute("""INSERT INTO account_food_wheel_rounds(id,started_at)
                    VALUES(?,?)""",(row['id']+1,now))
        return db.execute('SELECT * FROM account_food_wheel_rounds ORDER BY id DESC LIMIT 1').fetchone()

    def _snapshot(self,db,uid,row,now):
        t=now-row['started_at']
        if t<PICK_SECONDS:
            phase='bet';end=row['started_at']+PICK_SECONDS
        elif t<PICK_SECONDS+SPIN_SECONDS:
            phase='spin';end=row['started_at']+PICK_SECONDS+SPIN_SECONDS
        else:
            phase='result';end=row['started_at']+ROUND_SECONDS
        mine=db.execute("""SELECT item FROM account_food_wheel_picks
            WHERE round_id=? AND user_id=?""",(row['id'],uid)).fetchone()
        total=db.execute('SELECT count(*) FROM account_food_wheel_picks WHERE round_id=?',
                         (row['id'],)).fetchone()[0]
        result=row['result'] if phase!='bet' else None
        winners=[]
        winner_count=0
        my_win=bool(mine and result and self.qualifies(mine['item'],result))
        if result is not None:
            selected=MEATS if result=='pizza' else VEGETABLES if result=='salad' else (result,)
            params=(row['id'],*selected)
            places=','.join('?' for _ in selected)
            winner_count=db.execute("""SELECT count(*) FROM account_food_wheel_picks
                WHERE round_id=? AND item IN ("""+places+')',params).fetchone()[0]
            for r in db.execute("""SELECT p.user_id,a.display_name,p.item FROM account_food_wheel_picks p
                JOIN account_profiles a ON a.firebase_uid=p.user_id
                WHERE p.round_id=? AND p.item IN ("""+places+""")
                ORDER BY p.picked_at,p.user_id LIMIT 3""",params).fetchall():
                winners.append({'uid':r['user_id'],'name':r['display_name'],'item':r['item']})
        completed=db.execute("""SELECT id,result,visual_index,settled_at FROM account_food_wheel_rounds
            WHERE result IS NOT NULL ORDER BY id DESC LIMIT 8""").fetchall()
        history=[{'round':r['id'],'result':r['result'],'visual_index':r['visual_index']}
                 for r in completed]
        return {'game':'food-wheel','round':row['id'],'phase':phase,
                'serverNow':int(now*1000),'endsAt':int(end*1000),
                'result':result,'visualIndex':row['visual_index'] if result else None,
                'winners':winners,'winnerCount':winner_count,
                'myPick':mine['item'] if mine else None,'myWin':my_win,
                'players':total,'history':history,
                'realCoinsEnabled':False,'diamondsEnabled':False,'isDemo':True,
                'cycleSeconds':ROUND_SECONDS}

    def state(self,uid):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.rooms.profile(db,uid)
            now=self.clock()
            row=self._advance(db,now)
            return self._snapshot(db,uid,row,now)

    def choose(self,uid,data):
        if type(data.round) is not int or data.round<1:
            raise HTTPException(422,'Invalid round')
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.rooms.profile(db,uid)
            now=self.clock()
            row=self._advance(db,now)
            previous=db.execute("""SELECT item FROM account_food_wheel_picks
                WHERE round_id=? AND user_id=?""",(data.round,uid)).fetchone()
            if previous is not None and previous['item']==data.item:
                return self._snapshot(db,uid,row,now)
            if row['id']!=data.round or now>=row['started_at']+PICK_SECONDS:
                raise HTTPException(409,'Round closed; refresh wheel')
            if previous is not None:
                raise HTTPException(409,'Selection already locked this round')
            db.execute("""INSERT INTO account_food_wheel_picks
                (round_id,user_id,item,picked_at) VALUES(?,?,?,?)""",
                (data.round,uid,data.item,now))
            return self._snapshot(db,uid,row,now)
